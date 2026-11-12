-- BreakApp 28: one payer per full group line, transactional Stripe claims.
begin;
create table public.group_line_payment_claims(
 group_cart_item_id uuid primary key references public.group_cart_items(id) on delete restrict,
 payment_id uuid not null references public.payment_attempts(id) on delete restrict,
 payer_id uuid not null references auth.users(id) on delete restrict,
 beneficiary_id uuid not null references auth.users(id) on delete restrict,
 amount_cents bigint not null check(amount_cents>0),
 state text not null check(state in ('pending','paid','refund_pending','refunded')),
 created_at timestamptz not null default now(),
 paid_at timestamptz,
 unique(group_cart_item_id,payment_id)
);
create index group_claims_payment on public.group_line_payment_claims(payment_id);
create index group_claims_payer on public.group_line_payment_claims(payer_id);
create index group_claims_beneficiary on public.group_line_payment_claims(beneficiary_id);
alter table public.group_line_payment_claims enable row level security;
revoke all on public.group_line_payment_claims from public,anon,authenticated;

create or replace function public.group_payable_lines(p_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $payables$
declare v_group public.group_drafts%rowtype;v_user uuid:=auth.uid();
 v_lines jsonb;
begin
 if v_user is null then raise exception 'Accedi per vedere le righe pagabili';end if;
 select * into v_group from public.group_drafts where id=p_group_id;
 if not found or v_group.status not in ('draft','confirmed') or
  not exists(select 1 from public.group_members where group_id=p_group_id
   and user_id=v_user and status='accepted')
 then raise exception 'Gruppo non accessibile';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'line_id',i.id,'product_name',i.product_name,'quantity',i.quantity,
  'unit_cents',i.unit_price_cents,
  'amount_cents',i.quantity::bigint*i.unit_price_cents,
  'beneficiary_id',case when v_user=v_group.coordinator_id then i.user_id else null end,
  'payment_state',coalesce(cl.state,'available'))
  order by i.product_name,i.id),'[]'::jsonb) into v_lines
 from public.group_cart_items i join public.group_members m
 on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 left join public.group_line_payment_claims cl on cl.group_cart_item_id=i.id
 where i.group_id=p_group_id;
 return v_lines;
end;$payables$;

create or replace function public.begin_group_stripe_checkout(
 p_group_id uuid,p_line_ids uuid[],p_request_key uuid
) returns jsonb language plpgsql security definer set search_path=''
as $group_checkout$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_merchant public.school_stripe_merchants%rowtype;
 v_attempt public.payment_attempts%rowtype;v_line record;v_amount bigint:=0;
 v_id uuid;v_ids uuid[];v_order public.group_orders%rowtype;v_count integer:=0;
begin
 if v_user is null or p_group_id is null or p_request_key is null or
   p_line_ids is null or cardinality(p_line_ids) not between 1 and 50 or
   exists(select 1 from unnest(p_line_ids) x where x is null) or
   (select count(distinct x) from unnest(p_line_ids) x)<>cardinality(p_line_ids)
 then raise exception 'Righe e idempotenza pagamento non validi';end if;
 if exists(select 1 from app_private.platform_admins where user_id=v_user)
 then raise exception 'Super Admin escluso dai pagamenti';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status not in ('draft','confirmed') or
  (v_group.status='draft' and v_group.updated_at<now()-interval '24 hours') or
  not exists(select 1 from public.group_members where group_id=p_group_id
   and user_id=v_user and status='accepted')
 then raise exception 'Non puoi pagare questo gruppo';end if;
 if v_group.status='confirmed' then
  select * into v_order from public.group_orders where group_id=p_group_id for update;
  if not found or v_order.status not in ('confirmed','preparing','ready')
   or v_order.pickup_lease_until>now()
   or exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)
  then raise exception 'Pagamento online bloccato durante il ritiro';end if;
 end if;
 select * into v_merchant from public.school_stripe_merchants
 where school_id=v_group.school_id and charges_enabled;
 if not found then raise exception 'Merchant scolastico Stripe non abilitato';end if;

 select * into v_attempt from public.payment_attempts
 where payer_id=v_user and request_key=p_request_key for update;
 if found then
  select coalesce(array_agg(a.group_cart_item_id order by a.group_cart_item_id),
    '{}'::uuid[]) into v_ids from public.payment_item_allocations a where a.payment_id=v_attempt.id;
  if v_attempt.group_id<>p_group_id or v_attempt.stripe_account_id<>v_merchant.stripe_account_id
   or v_ids<>(select array_agg(x order by x) from unnest(p_line_ids) x)
  then raise exception 'Chiave idempotenza riutilizzata per altro pagamento';end if;
  return jsonb_build_object('attempt_id',v_attempt.id,
   'amount_cents',v_attempt.amount_cents,'currency','eur',
   'stripe_account_id',v_attempt.stripe_account_id,
   'existing_session',v_attempt.stripe_checkout_session_id);
 end if;

 -- Group row serializes cart mutation, confirmation and all simultaneous claims.
 for v_line in
  select i.id,i.user_id,i.quantity,i.unit_price_cents,i.product_id,
   p.price_cents as current_price
  from public.group_cart_items i
  join public.group_members m on m.group_id=i.group_id and m.user_id=i.user_id
    and m.status='accepted'
  join public.products p on p.id=i.product_id and p.school_id=v_group.school_id
   and p.bar_id=v_group.bar_id and p.is_active
  where i.group_id=p_group_id and i.id=any(p_line_ids)
  order by i.id for update of i for share of p
 loop
  v_count:=v_count+1;
  if exists(select 1 from public.group_line_payment_claims where group_cart_item_id=v_line.id)
  then raise exception 'Riga già pagata o con checkout in corso';end if;
  if v_group.status='draft' and v_line.unit_price_cents<>v_line.current_price
  then raise exception 'Prezzo aggiornato: il proprietario deve verificare il carrello';end if;
  v_amount:=v_amount+v_line.quantity::bigint*v_line.unit_price_cents;
 end loop;
 if v_count<>cardinality(p_line_ids)
  or v_amount<=0 or v_amount>999999999
 then raise exception 'Righe non valide o non pagabili';end if;
 insert into public.payment_attempts(school_id,payer_id,group_id,request_key,
  stripe_account_id,amount_cents,status,expires_at)
 values(v_group.school_id,v_user,p_group_id,p_request_key,
  v_merchant.stripe_account_id,v_amount,'initiated',now()+interval '40 minutes')
 returning id into v_id;
 insert into public.payment_item_allocations(payment_id,group_cart_item_id,
  beneficiary_id,amount_cents)
 select v_id,i.id,i.user_id,i.quantity::bigint*i.unit_price_cents
 from public.group_cart_items i where i.group_id=p_group_id and i.id=any(p_line_ids);
 insert into public.group_line_payment_claims(group_cart_item_id,payment_id,
  payer_id,beneficiary_id,amount_cents,state)
 select i.id,v_id,v_user,i.user_id,i.quantity::bigint*i.unit_price_cents,'pending'
 from public.group_cart_items i where i.group_id=p_group_id and i.id=any(p_line_ids);
 return jsonb_build_object('attempt_id',v_id,'amount_cents',v_amount,'currency','eur',
  'stripe_account_id',v_merchant.stripe_account_id,'existing_session',null);
end;$group_checkout$;

-- Signature must be checked by the Stripe webhook Edge Function first.
create or replace function public.finalize_verified_group_checkout(
 p_event_id text,p_account text,p_session text,p_intent text,
 p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb
) returns text language plpgsql security definer set search_path=''
as $group_paid$
declare v_attempt public.payment_attempts%rowtype;v_group public.group_drafts%rowtype;
 v_order public.group_orders%rowtype;v_claims bigint;v_sum bigint;v_decision text;
 v_processed boolean;v_group_id uuid;
begin
 if auth.jwt()->>'role'<>'service_role'
 then raise exception 'Solo webhook server può certificare denaro';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$' or
    p_account !~ '^acct_[A-Za-z0-9]+$' or
    p_session !~ '^cs_(test|live)_[A-Za-z0-9]+$' or
    p_intent !~ '^pi_[A-Za-z0-9]+$' or p_attempt is null or
    p_currency<>'eur' or not p_paid or p_amount<=0
 then raise exception 'Dati webhook gruppo non validi';end if;
 select processed_at is not null into v_processed from app_private.stripe_webhook_inbox
 where event_id=p_event_id;
 if found and v_processed then return 'duplicate';end if;
 -- Keep the same serialized group lock order as checkout and confirmation.
 select group_id into v_group_id from public.payment_attempts where id=p_attempt;
 if v_group_id is null then raise exception 'Tentativo gruppo non trovato';end if;
 select * into v_group from public.group_drafts where id=v_group_id for update;
 select * into v_order from public.group_orders where group_id=v_group.id for update;
 select * into v_attempt from public.payment_attempts where id=p_attempt for update;
 if not found or v_attempt.group_id<>v_group.id or
  v_attempt.stripe_account_id<>p_account or
  v_attempt.stripe_checkout_session_id<>p_session or
  v_attempt.amount_cents<>p_amount or v_attempt.currency<>p_currency
 then raise exception 'Checkout gruppo non coerente con il ledger';end if;
 if not exists(select 1 from public.school_stripe_merchants
  where school_id=v_group.school_id and stripe_account_id=p_account)
 then raise exception 'Merchant del gruppo non valido';end if;
 select count(*),coalesce(sum(amount_cents),0) into v_claims,v_sum
 from public.group_line_payment_claims where payment_id=p_attempt and state='pending';
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload)
 values(p_event_id,p_account,'checkout.session.completed',p_payload)
 on conflict(event_id) do nothing;
 if v_attempt.status='succeeded' then v_decision:='duplicate_payment';
 elsif v_attempt.status='cancelled' or v_group.status not in ('draft','confirmed') or
   (v_order.id is not null and (v_order.status in ('cancelled','delivered','no_show')
    or v_order.pickup_lease_until>now()
    or exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)))
   or v_claims=0 or v_sum<>v_attempt.amount_cents
 then v_decision:='review';
 else v_decision:='succeeded';end if;
 if v_decision<>'duplicate_payment' then
  update public.payment_attempts set
   stripe_payment_intent_id=p_intent,
   status=case when v_decision='succeeded' then 'succeeded' else 'review' end,
   updated_at=now() where id=p_attempt;
 end if;
 if v_decision='succeeded' then
  update public.group_line_payment_claims set state='paid',paid_at=now()
   where payment_id=p_attempt and state='pending';
 end if;
 update app_private.stripe_webhook_inbox set processed_at=now() where event_id=p_event_id;
 return v_decision;
end;$group_paid$;

create or replace function public.reconcile_signed_group_checkout_expiry(
 p_event_id text,p_account text,p_session text,p_attempt uuid
) returns text language plpgsql security definer set search_path=''
as $group_expire$
declare v_group public.group_drafts%rowtype;v_attempt public.payment_attempts%rowtype;
begin
 if auth.jwt()->>'role'<>'service_role' or
  p_event_id !~ '^evt_[A-Za-z0-9]+$' or
  p_account !~ '^acct_[A-Za-z0-9]+$' or
  p_session !~ '^cs_(test|live)_[A-Za-z0-9]+$'
 then raise exception 'Scadenza Stripe non firmata';end if;
 select group_id into v_group.id from public.payment_attempts where id=p_attempt;
 if v_group.id is null then raise exception 'Tentativo gruppo assente';end if;
 select * into v_group from public.group_drafts where id=v_group.id for update;
 select * into v_attempt from public.payment_attempts where id=p_attempt for update;
 if not found or v_attempt.group_id<>v_group.id or
  v_attempt.stripe_checkout_session_id<>p_session or
  v_attempt.stripe_account_id<>p_account
 then raise exception 'Scadenza checkout incoerente';end if;
 if v_attempt.status in ('cancelled','succeeded','review') then return 'duplicate';end if;
 if v_attempt.status not in ('initiated','requires_action','processing')
 then raise exception 'Checkout non riconciliabile';end if;
 delete from public.group_line_payment_claims
 where payment_id=p_attempt and state='pending';
 update public.payment_attempts set status='cancelled',updated_at=now()
 where id=p_attempt;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event_id,p_account,'checkout.session.expired','{}'::jsonb,now())
 on conflict(event_id) do nothing;
 return 'cancelled';
end;$group_expire$;

create or replace function public.confirm_group_order(
 p_group_id uuid,p_request_key uuid,p_accept_unready boolean,
 p_latitude double precision,p_longitude double precision,
 p_accuracy_m double precision,p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $group_confirm$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_school public.schools%rowtype;v_window public.pickup_windows%rowtype;
 v_bar public.bars%rowtype;v_order uuid;v_item record;v_product record;
 v_stock public.daily_stock%rowtype;v_total bigint:=0;v_units integer:=0;
 v_distance double precision;v_count integer:=0;v_not_ready integer;
begin
 if not app_private.is_registered_group_user(v_user)
   or p_group_id is null or p_request_key is null or p_accept_unready is null
 then raise exception 'Conferma gruppo non valida';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>v_user
 then raise exception 'Solo il coordinatore può confermare';end if;
 select id into v_order from public.group_orders
 where group_id=p_group_id;
 if found then
  if v_group.status='confirmed' and exists(select 1 from public.group_orders
   where id=v_order and request_key=p_request_key)
  then return v_order;end if;
  raise exception 'Gruppo già confermato con altra richiesta';
 end if;
 if v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Bozza gruppo non più confermabile';end if;
 if exists(select 1 from public.group_members where group_id=p_group_id and status='pending')
 then raise exception 'Risolvi prima le richieste di ingresso pendenti';end if;
 select count(*) into v_not_ready from public.group_members
 where group_id=p_group_id and status='accepted' and not ready;
 if v_not_ready>0 and not p_accept_unready
 then raise exception 'Alcuni partecipanti non hanno terminato: richiedi conferma esplicita';end if;

 select * into v_window from public.pickup_windows where id=v_group.pickup_window_id
 and school_id=v_group.school_id and bar_id=v_group.bar_id and is_active for share;
 if not found then raise exception 'La fascia è scaduta: scegline una nuova';end if;
 select * into v_school from public.schools where id=v_group.school_id and is_active for share;
 select * into v_bar from public.bars where id=v_group.bar_id
  and school_id=v_group.school_id and is_active for share;
 if v_school.id is null or v_bar.id is null
 then raise exception 'Scuola o bar non attivi';end if;
 if v_window.service_date<(now() at time zone v_school.timezone)::date
  or v_window.service_date>(now() at time zone v_school.timezone)::date+v_school.booking_horizon_days
  or (v_window.service_date+v_window.starts_at) at time zone v_school.timezone<=now()
 then raise exception 'La fascia non è più prenotabile: scegline una nuova';end if;
 -- GPS is mandatory again at final coordinator confirmation.
 if v_school.latitude is null or v_school.longitude is null
  or p_latitude is null or p_longitude is null
  or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
  or p_accuracy_m is null or p_accuracy_m<0 or p_accuracy_m>100
  or p_observed_at is null or p_observed_at<now()-interval '2 minutes'
  or p_observed_at>now()+interval '15 seconds'
 then raise exception 'Posizione del coordinatore non verificabile';end if;
 v_distance:=6371000*2*pg_catalog.asin(least(1.0::double precision,
  pg_catalog.sqrt(pg_catalog.power(pg_catalog.sin(
    pg_catalog.radians(p_latitude-v_school.latitude)/2),2)
   +pg_catalog.cos(pg_catalog.radians(v_school.latitude))
    *pg_catalog.cos(pg_catalog.radians(p_latitude))
    *pg_catalog.power(pg_catalog.sin(
      pg_catalog.radians(p_longitude-v_school.longitude)/2),2))));
 if v_distance+p_accuracy_m>v_school.pickup_radius_m
 then raise exception 'Coordinatore fuori dal raggio consentito';end if;

 -- All product/stock rows are checked and locked in UUID order.
 for v_item in
  select i.product_id,sum(i.quantity)::integer as quantity
  from public.group_cart_items i
   join public.group_members m on m.group_id=i.group_id and m.user_id=i.user_id
  where i.group_id=p_group_id and m.status='accepted'
  group by i.product_id order by i.product_id
 loop
  v_count:=v_count+1;
  if v_item.quantity>1000 then raise exception 'Quantità prodotto troppo elevata';end if;
  select p.id,p.name,p.price_cents into v_product
  from public.products p join public.categories c
   on c.id=p.category_id and c.school_id=p.school_id and c.bar_id=p.bar_id
  where p.id=v_item.product_id and p.school_id=v_group.school_id
   and p.bar_id=v_group.bar_id and p.is_active and c.is_active for share of p;
  if not found then raise exception 'Prodotto % non più disponibile',v_item.product_id;end if;
  select * into v_stock from public.daily_stock
   where school_id=v_group.school_id and bar_id=v_group.bar_id
    and product_id=v_item.product_id and service_date=v_window.service_date for update;
  if not found then raise exception 'Scorte non configurate per %',v_product.name;end if;
  if v_stock.capacity is not null and v_stock.allocated+v_item.quantity>v_stock.capacity
  then raise exception 'Scorte insufficienti per %',v_product.name;end if;
  v_units:=v_units+v_item.quantity;
 end loop;
 if v_count=0 then raise exception 'Il gruppo non contiene prodotti';end if;
 -- Online-paid lines retain their contractual quote; unpaid lines take the
 -- current catalog price. Pending signed checkout claims retain their quote.
 select coalesce(sum(i.quantity::bigint*
   case when cl.state in ('pending','paid','refund_pending') then i.unit_price_cents
   else p.price_cents end),0)
 into v_total
 from public.group_cart_items i
 join public.group_members m on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 join public.products p on p.id=i.product_id
 left join public.group_line_payment_claims cl on cl.group_cart_item_id=i.id
 where i.group_id=p_group_id;
 if v_total>999999999 then raise exception 'Importo del gruppo troppo elevato';end if;
 if (v_school.approval_product_threshold is not null
  and v_units>v_school.approval_product_threshold)
  or (v_school.approval_amount_threshold_cents is not null
   and v_total>v_school.approval_amount_threshold_cents)
 then raise exception 'Ordine grande: in attesa del workflow di approvazione Barista';end if;

 insert into public.group_orders(group_id,school_id,bar_id,pickup_window_id,
  coordinator_id,request_key,status,total_cents)
 values(p_group_id,v_group.school_id,v_group.bar_id,v_group.pickup_window_id,
  v_user,p_request_key,
  case when v_bar.preparation_mode='ready_made' then 'ready' else 'confirmed' end,
  v_total) returning id into v_order;
 -- Snapshot per person, with latest unpaid price, after product locks.
 insert into public.group_order_lines(group_order_id,group_cart_item_id,
  beneficiary_id,product_id,name,quantity,unit_cents)
 select v_order,i.id,i.user_id,i.product_id,p.name,i.quantity,
   case when cl.state in ('pending','paid','refund_pending') then i.unit_price_cents
     else p.price_cents end
 from public.group_cart_items i join public.group_members m
  on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 join public.products p on p.id=i.product_id
 left join public.group_line_payment_claims cl on cl.group_cart_item_id=i.id
 where i.group_id=p_group_id;
 update public.group_cart_items i set unit_price_cents=l.unit_cents
 from public.group_order_lines l
 where l.group_order_id=v_order and l.group_cart_item_id=i.id;
 for v_item in select product_id,sum(quantity)::integer quantity
   from public.group_order_lines where group_order_id=v_order
   group by product_id order by product_id loop
  update public.daily_stock set allocated=allocated+v_item.quantity,updated_at=now()
  where school_id=v_group.school_id and bar_id=v_group.bar_id
   and product_id=v_item.product_id and service_date=v_window.service_date;
 end loop;
 update public.group_drafts set status='confirmed',accepting_members=false,updated_at=now()
 where id=p_group_id;
 insert into public.group_order_audit(group_order_id,actor_id,action,details)
 values(v_order,v_user,'confirmed',jsonb_build_object('units',v_units,'total_cents',v_total));
 return v_order;
end;$group_confirm$;

create or replace function public.stripe_payment_attempt_kind(p_attempt uuid)
returns text language plpgsql stable security definer set search_path=''
as $kind$
declare v_kind text;
begin
 if auth.jwt()->>'role'<>'service_role' then raise exception 'Service role';end if;
 select case when group_id is not null then 'group'
  when order_id is not null then 'individual' end into v_kind
 from public.payment_attempts where id=p_attempt;
 return v_kind;
end;$kind$;

revoke all on function public.stripe_payment_attempt_kind(uuid) from public,anon,authenticated;
grant execute on function public.stripe_payment_attempt_kind(uuid) to service_role;
revoke all on function public.group_payable_lines(uuid),
 public.begin_group_stripe_checkout(uuid,uuid[],uuid),
 public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb),
 public.reconcile_signed_group_checkout_expiry(text,text,text,uuid)
 from public,anon,authenticated;
grant execute on function public.group_payable_lines(uuid),
 public.begin_group_stripe_checkout(uuid,uuid[],uuid) to authenticated;
grant execute on function public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb),
 public.reconcile_signed_group_checkout_expiry(text,text,text,uuid) to service_role;
commit;
