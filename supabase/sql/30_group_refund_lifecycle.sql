-- BreakApp 30: Preserve group paid lines and refund original payer (partial Stripe refunds).
begin;
alter table public.group_cart_items add column removed_at timestamptz;
alter table public.group_cart_items drop constraint group_cart_items_group_id_user_id_product_id_key;
create unique index group_cart_active_product_unique on public.group_cart_items(group_id,user_id,product_id) where removed_at is null;
alter table public.group_members drop constraint group_members_status_check;
alter table public.group_members add constraint group_members_status_check check(status in ('pending','accepted','rejected','left'));
create table public.group_line_refunds(
 group_cart_item_id uuid primary key references public.group_cart_items(id) on delete restrict,
 refund_id uuid not null unique references public.payment_refunds(id) on delete restrict,
 original_payer_id uuid not null references auth.users(id) on delete restrict,
 amount_cents bigint not null check(amount_cents>0),
 created_at timestamptz not null default now()
);
create index group_line_refunds_payer on public.group_line_refunds(original_payer_id);
alter table public.group_line_refunds enable row level security;
revoke all on public.group_line_refunds from public,anon,authenticated;

create or replace function app_private.queue_group_line_refund(p_item_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=''
as $queue_group_refund$
declare v_claim public.group_line_payment_claims%rowtype;
 v_attempt public.payment_attempts%rowtype;v_refund uuid;
begin
 select * into v_claim from public.group_line_payment_claims
 where group_cart_item_id=p_item_id for update;
 if not found or v_claim.state in ('pending','refunded') then return;end if;
 select * into v_attempt from public.payment_attempts
 where id=v_claim.payment_id for update;
 if v_attempt.status<>'succeeded' or v_attempt.stripe_payment_intent_id is null
 then raise exception 'Pagamento non certificato per il rimborso';end if;
 if exists(select 1 from public.group_line_refunds where group_cart_item_id=p_item_id) then return;end if;
 insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason)
 values(v_attempt.id,p_item_id,v_claim.amount_cents,'pending',left(p_reason,300))
 on conflict(payment_id,request_key) do update
  set request_key=excluded.request_key returning id into v_refund;
 insert into public.group_line_refunds(group_cart_item_id,refund_id,original_payer_id,amount_cents)
 values(p_item_id,v_refund,v_attempt.payer_id,v_claim.amount_cents);
 update public.group_line_payment_claims set state='refund_pending'
 where group_cart_item_id=p_item_id and state='paid';
end;$queue_group_refund$;

create or replace function app_private.archive_group_line(p_item_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=''
as $archive_group_line$
declare v_claim text;
begin
 select state into v_claim from public.group_line_payment_claims where group_cart_item_id=p_item_id for update;
 if v_claim in ('pending','paid','refund_pending','refunded') then
  update public.group_cart_items set removed_at=coalesce(removed_at,now()) where id=p_item_id;
  if v_claim='paid' then perform app_private.queue_group_line_refund(p_item_id,p_reason);end if;
 else
  delete from public.group_cart_items where id=p_item_id;
 end if;
end;$archive_group_line$;

create or replace function app_private.queue_unwanted_paid_group_line()
returns trigger language plpgsql security definer set search_path=''
as $queue_unwanted_group_payment$
declare v_status text;v_removed timestamptz;
begin
 if new.state='paid' and old.state is distinct from 'paid' then
  select g.status,i.removed_at into v_status,v_removed
  from public.group_drafts g join public.group_cart_items i on i.group_id=g.id
  where i.id=new.group_cart_item_id;
  if v_removed is not null or v_status in ('cancelled','expired') then
   perform app_private.queue_group_line_refund(new.group_cart_item_id,'Riga rimossa o gruppo annullato');
  end if;
 end if;
 return new;
end;$queue_unwanted_group_payment$;
create trigger group_paid_line_refund after update of state on public.group_line_payment_claims
for each row execute function app_private.queue_unwanted_paid_group_line();



create or replace function public.join_group_draft(
 p_invite_token uuid,p_latitude double precision,p_longitude double precision,
 p_accuracy_m double precision,p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $join_group$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_school public.schools%rowtype;v_status text;v_distance double precision;
begin
 if v_user is null or p_invite_token is null then
  raise exception 'Accedi come partecipante per aprire l''invito';end if;
 select * into v_group from public.group_drafts where invite_token=p_invite_token for update;
 if not found then raise exception 'Invito non valido';end if;
 if v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
   or not v_group.accepting_members then
  raise exception 'Il gruppo non accetta nuovi ingressi';end if;
 select status into v_status from public.group_members
  where group_id=v_group.id and user_id=v_user;
 if found and v_status<>'left' then
  if v_status='rejected' then raise exception 'Ingresso rifiutato';end if;
  return v_group.id;
 end if;
 if v_group.max_members is not null and
  (select count(*) from public.group_members where group_id=v_group.id
   and status in ('accepted','pending'))>=v_group.max_members
 then raise exception 'Gruppo al completo';end if;
 select * into v_school from public.schools where id=v_group.school_id and is_active;
 if not found or v_school.latitude is null or v_school.longitude is null
 then raise exception 'Posizione scuola non configurata';end if;
 if p_latitude is null or p_longitude is null or
   p_latitude not between -90 and 90 or p_longitude not between -180 and 180
   or p_accuracy_m is null or p_accuracy_m<0 or p_accuracy_m>100
   or p_observed_at is null or p_observed_at<now()-interval '2 minutes'
   or p_observed_at>now()+interval '15 seconds'
 then raise exception 'Posizione non verificabile';end if;
 v_distance:=6371000 * 2 * pg_catalog.asin(least(1.0::double precision,
   pg_catalog.sqrt(
   pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_latitude-v_school.latitude)/2),2)
   +pg_catalog.cos(pg_catalog.radians(v_school.latitude))*pg_catalog.cos(pg_catalog.radians(p_latitude))
   *pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_longitude-v_school.longitude)/2),2))));
 if v_distance+p_accuracy_m>v_school.pickup_radius_m then
   raise exception 'Per partecipare devi essere entro il raggio scolastico';end if;
 insert into public.group_members(group_id,user_id,status)
 values(v_group.id,v_user,case when v_group.requires_approval then 'pending' else 'accepted' end)
 on conflict(group_id,user_id) do update
 set status=excluded.status,ready=false,approved_at=null,joined_at=now()
 where public.group_members.status='left';
 update public.group_drafts set updated_at=now() where id=v_group.id;
 return v_group.id;
end;
$join_group$;

create or replace function public.replace_group_personal_cart(
 p_group_id uuid,p_items jsonb
) returns void language plpgsql security definer set search_path=''
as $cart_group$
declare v_group public.group_drafts%rowtype;v_user uuid:=auth.uid();
 v_item record;v_product record;
begin
 if v_user is null or p_group_id is null or p_items is null or
  jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100
 then raise exception 'Carrello non valido';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Bozza gruppo non modificabile';end if;
 if not exists(select 1 from public.group_members
  where group_id=p_group_id and user_id=v_user and status='accepted' and not ready)
 then raise exception 'Non sei autorizzato a modificare questo carrello';end if;
 if exists(select 1 from jsonb_to_recordset(p_items)
   as x(product_id uuid,quantity integer)
   where x.product_id is null or x.quantity is null or x.quantity not between 1 and 1000)
 then raise exception 'Quantità non valide';end if;
 if (select count(distinct x.product_id) from jsonb_to_recordset(p_items)
    as x(product_id uuid,quantity integer))<>(select count(*) from jsonb_array_elements(p_items))
 then raise exception 'Non duplicare righe prodotto';end if;
 -- Draft lines have no stock reservation; settled group claims must remain immutable.
 for v_item in select x.product_id,x.quantity from jsonb_to_recordset(p_items)
 as x(product_id uuid,quantity integer) order by x.product_id loop
  select p.name,p.price_cents into v_product from public.products p
   join public.categories c on c.id=p.category_id and c.is_active
    and c.school_id=p.school_id and c.bar_id=p.bar_id
   where p.id=v_item.product_id and p.bar_id=v_group.bar_id
      and p.school_id=v_group.school_id and p.is_active;
  if not found then raise exception 'Prodotto non disponibile in questo bar';end if;
 end loop;
 for v_item in select i.id,i.product_id,i.quantity from public.group_cart_items i
  where i.group_id=p_group_id and i.user_id=v_user and i.removed_at is null loop
  if not exists(select 1 from jsonb_to_recordset(p_items)
   as x(product_id uuid,quantity integer)
   where x.product_id=v_item.product_id and x.quantity=v_item.quantity)
  then
   if exists(select 1 from public.group_line_payment_claims cl
    where cl.group_cart_item_id=v_item.id and cl.state='pending')
   then raise exception 'Checkout in corso: attendi la conferma o scadenza';end if;
   perform app_private.archive_group_line(v_item.id,'Riga rimossa dal carrello');
  end if;
 end loop;
 insert into public.group_cart_items(group_id,user_id,product_id,product_name,unit_price_cents,quantity)
 select p_group_id,v_user,p.id,p.name,p.price_cents,x.quantity
 from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
 join public.products p on p.id=x.product_id
 where not exists(select 1 from public.group_cart_items i where i.group_id=p_group_id
  and i.user_id=v_user and i.product_id=x.product_id and i.quantity=x.quantity
  and i.removed_at is null);
 update public.group_drafts set updated_at=now() where id=p_group_id;
end;
$cart_group$;

create or replace function public.leave_group_draft(p_group_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_leave$
declare v_group public.group_drafts%rowtype; v_members integer;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status<>'draft'
   or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Gruppo non modificabile'; end if;
 if not exists(select 1 from public.group_members where group_id=p_group_id
   and user_id=auth.uid() and status in ('pending','accepted'))
 then raise exception 'Non fai parte di questo gruppo'; end if;
 if v_group.coordinator_id=auth.uid() then
  select count(*) into v_members from public.group_members
    where group_id=p_group_id and status in ('pending','accepted');
  if v_members>1 then
   raise exception 'Trasferisci il coordinamento prima di uscire';
  end if;
  update public.group_drafts set status='cancelled',accepting_members=false,
    updated_at=now() where id=p_group_id;
  perform app_private.archive_group_line(i.id,'Gruppo sciolto')
   from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null;
 else
  perform app_private.archive_group_line(i.id,'Beneficiario uscito')
   from public.group_cart_items i where i.group_id=p_group_id
    and i.user_id=auth.uid() and i.removed_at is null;
  update public.group_members set status='left',ready=false
   where group_id=p_group_id and user_id=auth.uid();
  update public.group_drafts set updated_at=now() where id=p_group_id;
 end if;
end;$group_leave$;

create or replace function public.cancel_group_draft(p_group_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_cancel$
declare v_group public.group_drafts%rowtype;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>auth.uid() or v_group.status<>'draft'
 then raise exception 'Solo il coordinatore può annullare questa bozza'; end if;
 update public.group_drafts set status='cancelled',accepting_members=false,
  updated_at=now() where id=p_group_id;
 perform app_private.archive_group_line(i.id,'Bozza gruppo annullata')
  from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null;
end;$group_cancel$;

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
 where i.group_id=p_group_id and i.removed_at is null;
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
  where i.group_id=p_group_id and i.removed_at is null and i.id=any(p_line_ids)
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
 from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null and i.id=any(p_line_ids);
 insert into public.group_line_payment_claims(group_cart_item_id,payment_id,
  payer_id,beneficiary_id,amount_cents,state)
 select i.id,v_id,v_user,i.user_id,i.quantity::bigint*i.unit_price_cents,'pending'
 from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null and i.id=any(p_line_ids);
 return jsonb_build_object('attempt_id',v_id,'amount_cents',v_amount,'currency','eur',
  'stripe_account_id',v_merchant.stripe_account_id,'existing_session',null);
end;$group_checkout$;

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
  where i.group_id=p_group_id and i.removed_at is null and m.status='accepted'
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
 where i.group_id=p_group_id and i.removed_at is null;
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
 where i.group_id=p_group_id and i.removed_at is null;
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

create or replace function public.group_draft_details(p_group_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $details$
declare v_group public.group_drafts%rowtype;v_user uuid:=auth.uid();
 v_role text;v_ready boolean;v_totals jsonb;v_my_lines jsonb;v_members jsonb;
begin
 if v_user is null then raise exception 'Accesso richiesto';end if;
 select * into v_group from public.group_drafts where id=p_group_id;
 if not found then raise exception 'Gruppo non trovato';end if;
 select status,ready into v_role,v_ready from public.group_members
   where group_id=p_group_id and user_id=v_user;
 if v_role is null or v_role='left' then raise exception 'Non fai parte di questo gruppo';end if;
 select jsonb_build_object('count',coalesce(sum(i.quantity),0),
    'total_cents',coalesce(sum(i.quantity::bigint*i.unit_price_cents),0))
 into v_totals from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null;
 select coalesce(jsonb_agg(jsonb_build_object('product_id',i.product_id,
   'name',i.product_name,'quantity',i.quantity,
   'unit_price_cents',i.unit_price_cents) order by i.product_name),'[]'::jsonb)
 into v_my_lines from public.group_cart_items i where i.group_id=p_group_id
   and i.user_id=v_user and i.removed_at is null;
 if v_group.coordinator_id=v_user then
  select coalesce(jsonb_agg(jsonb_build_object(
    'member_id',m.user_id,'status',m.status,'ready',m.ready,
    'line_count',(select coalesce(sum(i.quantity),0) from public.group_cart_items i
      where i.group_id=m.group_id and i.user_id=m.user_id and i.removed_at is null)
  ) order by m.joined_at),'[]'::jsonb)
  into v_members from public.group_members m where m.group_id=p_group_id;
 else
  select jsonb_build_object('accepted',(select count(*) from public.group_members
   where group_id=p_group_id and status='accepted'),
   'ready',(select count(*) from public.group_members
   where group_id=p_group_id and status='accepted' and ready))
   into v_members;
 end if;
 return jsonb_build_object('id',v_group.id,'title',v_group.title,
 'school_id',v_group.school_id,'bar_id',v_group.bar_id,
 'pickup_window_id',v_group.pickup_window_id,'status',v_group.status,
 'my_status',v_role,'my_ready',v_ready,'coordinator',v_group.coordinator_id=v_user,
 'invite_token',case when v_group.coordinator_id=v_user then v_group.invite_token else null end,
 'requires_approval',v_group.requires_approval,'accepting_members',v_group.accepting_members,
 'max_members',v_group.max_members,'expires_at',v_group.updated_at+interval '24 hours',
 'totals',v_totals,'my_items',v_my_lines,'members',v_members);
end;
$details$;

create or replace function public.group_order_details(p_group_order_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $group_details$
declare v_order public.group_orders%rowtype;v_user uuid:=auth.uid();
 v_member boolean;v_lines jsonb;v_payments bigint;v_cash bigint;
begin
 if v_user is null then raise exception 'Accedi per visualizzare ordine';end if;
 select * into v_order from public.group_orders where id=p_group_order_id;
 if not found then raise exception 'Ordine non trovato';end if;
 select exists(select 1 from public.group_members m join public.group_drafts g on g.id=m.group_id
  where m.group_id=v_order.group_id and m.user_id=v_user and m.status='accepted')
 into v_member;
 if not v_member and not app_private.can_serve_group_bar(v_order.school_id)
 then raise exception 'Non autorizzato a questo ordine';end if;
 select coalesce(jsonb_agg(jsonb_build_object('name',l.name,'quantity',l.quantity,
  'unit_cents',l.unit_cents,'subtotal_cents',l.subtotal_cents,
  'beneficiary_id',case when v_order.coordinator_id=v_user or
   app_private.can_serve_group_bar(v_order.school_id) then l.beneficiary_id else null end)
  order by l.name),'[]'::jsonb) into v_lines
 from public.group_order_lines l where l.group_order_id=v_order.id;
 select coalesce(sum(cl.amount_cents),0) into v_payments
 from public.group_line_payment_claims cl
 join public.group_order_lines l on l.group_cart_item_id=cl.group_cart_item_id
 where l.group_order_id=v_order.id and cl.state='paid';
 select coalesce(sum(amount_cents),0) into v_cash
 from public.group_counter_payments where group_order_id=v_order.id;
 return jsonb_build_object('id',v_order.id,'group_id',v_order.group_id,
  'school_id',v_order.school_id,'bar_id',v_order.bar_id,
  'coordinator',v_order.coordinator_id=v_user,'status',v_order.status,
  'total_cents',v_order.total_cents,'paid_cents',v_payments+v_cash,
  'due_cents',greatest(0,v_order.total_cents-v_payments-v_cash),
  'pickup_window_id',v_order.pickup_window_id,
  'pickup_token',case when v_order.coordinator_id=v_user then v_order.pickup_token else null end,
  'pickup_lease_until',case when v_order.coordinator_id=v_user or
    app_private.can_serve_group_bar(v_order.school_id) then v_order.pickup_lease_until else null end,
  'lines',v_lines);
end;$group_details$;

create or replace function public.record_group_counter_payment(
 p_group_order_id uuid,p_method text,p_request_key uuid
) returns jsonb language plpgsql security definer set search_path=''
as $group_cash$
declare v_order public.group_orders%rowtype;v_paid bigint;v_cash bigint;v_due bigint;
begin
 if p_method not in ('cash','external_pos') or p_request_key is null
 then raise exception 'Incasso gruppo non valido';end if;
 select * into v_order from public.group_orders where id=p_group_order_id for update;
 if not found or not app_private.can_serve_group_bar(v_order.school_id)
 then raise exception 'Incasso non autorizzato';end if;
 if v_order.status not in ('confirmed','preparing','ready') or
    v_order.pickup_lease_actor<>auth.uid() or v_order.pickup_lease_until<=now()
 then raise exception 'Scansiona il QR prima di incassare';end if;
 select amount_cents into v_cash from public.group_counter_payments
  where group_order_id=v_order.id;
 if found then
  if exists(select 1 from public.group_counter_payments
   where group_order_id=v_order.id and request_key=p_request_key and method=p_method)
  then return jsonb_build_object('status','duplicate','amount_cents',v_cash);end if;
  raise exception 'Incasso gruppo già registrato';end if;
 if exists(select 1 from public.payment_attempts p
    where p.group_id=v_order.group_id
    and p.status in ('initiated','requires_action','processing')
    and (p.expires_at is null or p.expires_at>now()))
 then raise exception 'Checkout online in corso: attendere webhook firmato';end if;
 select coalesce(sum(cl.amount_cents),0) into v_paid
  from public.group_line_payment_claims cl
 join public.group_order_lines l on l.group_cart_item_id=cl.group_cart_item_id
 where l.group_order_id=v_order.id and cl.state='paid';
 v_due:=v_order.total_cents-v_paid;
 if v_due<=0 then raise exception 'Gruppo già saldato';end if;
 insert into public.group_counter_payments(group_order_id,school_id,bar_id,
  actor_id,request_key,method,amount_cents)
 values(v_order.id,v_order.school_id,v_order.bar_id,auth.uid(),p_request_key,p_method,v_due);
 insert into public.group_order_audit(group_order_id,actor_id,action,details)
 values(v_order.id,auth.uid(),'counter_payment:'||p_method,jsonb_build_object('amount_cents',v_due));
 return jsonb_build_object('status','recorded','amount_cents',v_due);
end;$group_cash$;

create or replace function public.deliver_group_order(p_group_order_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_deliver$
declare v_order public.group_orders%rowtype;v_paid bigint;
begin
 select * into v_order from public.group_orders where id=p_group_order_id for update;
 if not found or not app_private.can_serve_group_bar(v_order.school_id)
 then raise exception 'Consegna non autorizzata';end if;
 if v_order.status<>'ready' or v_order.pickup_lease_actor<>auth.uid()
  or v_order.pickup_lease_until<=now()
 then raise exception 'Gruppo non pronto o scansione QR scaduta';end if;
 select coalesce(sum(cl.amount_cents),0) into v_paid
  from public.group_line_payment_claims cl
 join public.group_order_lines l on l.group_cart_item_id=cl.group_cart_item_id
 where l.group_order_id=v_order.id and cl.state='paid';
 v_paid:=v_paid+coalesce((select sum(amount_cents) from public.group_counter_payments
  where group_order_id=v_order.id),0);
 if v_paid<>v_order.total_cents
 then raise exception 'Non è possibile consegnare: saldo residuo o importo incoerente';end if;
 update public.group_orders set status='delivered',
  pickup_lease_actor=null,pickup_lease_until=null,updated_at=now()
 where id=v_order.id;
 insert into public.group_order_audit(group_order_id,actor_id,action)
 values(v_order.id,auth.uid(),'delivered');
end;$group_deliver$;



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
 elsif v_attempt.status='cancelled' or v_claims=0 or v_sum<>v_attempt.amount_cents
 then v_decision:='review';
 elsif v_group.status not in ('draft','confirmed') or
   exists(select 1 from public.group_line_payment_claims cl
     join public.group_cart_items i on i.id=cl.group_cart_item_id
     where cl.payment_id=p_attempt and i.removed_at is not null) or
   (v_order.id is not null and (v_order.status in ('cancelled','delivered','no_show')
    or v_order.pickup_lease_until>now()
    or exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)))
 then v_decision:='refund_required';
 else v_decision:='succeeded';end if;
 if v_decision<>'duplicate_payment' then
  update public.payment_attempts set
   stripe_payment_intent_id=p_intent,
   status=case when v_decision in ('succeeded','refund_required') then 'succeeded' else 'review' end,
   updated_at=now() where id=p_attempt;
 end if;
 if v_decision in ('succeeded','refund_required') then
  update public.group_line_payment_claims set state='paid',paid_at=now()
   where payment_id=p_attempt and state='pending';
 end if;
 if v_decision='refund_required' then
  perform app_private.queue_group_line_refund(cl.group_cart_item_id,'Pagamento tardivo dopo chiusura finestra')
  from public.group_line_payment_claims cl
  where cl.payment_id=p_attempt and cl.state='paid';
 end if;
 update app_private.stripe_webhook_inbox set processed_at=now() where event_id=p_event_id;
 return v_decision;
end;$group_paid$;

create or replace function public.cancel_confirmed_group_order(p_group_order_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_cancel_confirmed$
declare v_order public.group_orders%rowtype;v_school public.schools%rowtype;
 v_window public.pickup_windows%rowtype;v_item record;v_paid bigint;
begin
 select * into v_order from public.group_orders where id=p_group_order_id for update;
 if not found or v_order.coordinator_id<>auth.uid()
 then raise exception 'Solo il coordinatore può cancellare il gruppo';end if;
 if v_order.status not in ('confirmed','ready')
 then raise exception 'Ordine non cancellabile in questo stato';end if;
 select * into v_school from public.schools where id=v_order.school_id;
 select * into v_window from public.pickup_windows where id=v_order.pickup_window_id;
 if (v_window.service_date+v_window.starts_at) at time zone v_school.timezone
    <=now()+make_interval(mins=>v_school.cancel_cutoff_minutes)
 then raise exception 'È stato superato il limite per annullare';end if;
 if exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)
    or exists(select 1 from public.payment_attempts
     where group_id=v_order.group_id and status in
      ('initiated','requires_action','processing','review'))
 then raise exception 'Pagamento al banco o checkout pendente: attendere riconciliazione';end if;
 for v_item in select product_id,sum(quantity)::integer quantity
  from public.group_order_lines where group_order_id=v_order.id
  group by product_id order by product_id loop
  update public.daily_stock set allocated=allocated-v_item.quantity,updated_at=now()
  where school_id=v_order.school_id and bar_id=v_order.bar_id
   and product_id=v_item.product_id and service_date=v_window.service_date
   and allocated>=v_item.quantity;
  if not found then raise exception 'Riconciliazione stock necessaria per cancellare';end if;
 end loop;
 update public.group_orders set status='cancelled',pickup_lease_actor=null,
  pickup_lease_until=null,updated_at=now() where id=v_order.id;
 update public.group_drafts set status='cancelled',updated_at=now()
  where id=v_order.group_id;
 perform app_private.archive_group_line(i.id,'Ordine confermato cancellato')
 from public.group_cart_items i
 where i.group_id=v_order.group_id and i.removed_at is null;
 insert into public.group_order_audit(group_order_id,actor_id,action)
 values(v_order.id,auth.uid(),'cancelled');
end;$group_cancel_confirmed$;

create or replace function public.expire_group_drafts(p_limit integer default 40)
returns integer language plpgsql security definer set search_path=''
as $group_expire_maintenance$
declare v_group record;v_count integer:=0;
begin
 if auth.jwt()->>'role'<>'service_role' then raise exception 'Solo manutenzione server';end if;
 if p_limit is null or p_limit not between 1 and 200 then raise exception 'Limite non valido';end if;
 for v_group in
  select id from public.group_drafts
  where status='draft' and updated_at <= now()-interval '24 hours'
  order by updated_at,id for update skip locked limit p_limit
 loop
  update public.group_drafts set status='expired',accepting_members=false where id=v_group.id;
  perform app_private.archive_group_line(i.id,'Bozza gruppo scaduta')
   from public.group_cart_items i where i.group_id=v_group.id and i.removed_at is null;
  v_count:=v_count+1;
 end loop;
 return v_count;
end;$group_expire_maintenance$;

create or replace function public.list_group_refunds_for_dispatch(p_limit integer default 15)
returns table(refund_id uuid,account text,payment_intent text,amount_cents bigint)
language plpgsql security definer set search_path=''
as $dispatch_group_refunds$
begin
 if auth.jwt()->>'role'<>'service_role' then raise exception 'Solo server';end if;
 if p_limit is null or p_limit not between 1 and 30 then raise exception 'Limite non valido';end if;
 return query select r.id,a.stripe_account_id,a.stripe_payment_intent_id,r.amount_cents
  from public.group_line_refunds l
  join public.payment_refunds r on r.id=l.refund_id
  join public.payment_attempts a on a.id=r.payment_id
  where r.status in ('pending','processing') and a.status='succeeded'
  and a.stripe_payment_intent_id is not null
  order by r.created_at,r.id limit p_limit;
end;$dispatch_group_refunds$;

create or replace function public.stripe_refund_kind(p_refund_id uuid)
returns text language plpgsql stable security definer set search_path=''
as $stripe_refund_kind$
begin
 if auth.jwt()->>'role'<>'service_role' then raise exception 'Solo webhook';end if;
 return case when exists(select 1 from public.group_line_refunds where refund_id=p_refund_id)
  then 'group' when exists(select 1 from public.payment_refunds r
   join public.payment_attempts a on a.id=r.payment_id
   where r.id=p_refund_id and a.order_id is not null) then 'individual'
   else null end;
end;$stripe_refund_kind$;

create or replace function public.finalize_verified_group_refund(
 p_event_id text,p_stripe_account text,p_refund_id uuid,p_stripe_refund text,
 p_payment_intent text,p_amount bigint,p_currency text,p_status text
) returns text language plpgsql security definer set search_path=''
as $group_refund_signed$
declare v_line public.group_line_refunds%rowtype;
 v_refund public.payment_refunds%rowtype;v_attempt public.payment_attempts%rowtype;
begin
 if auth.jwt()->>'role'<>'service_role'
 or p_event_id !~ '^evt_[A-Za-z0-9]+$'
 or p_stripe_account !~ '^acct_[A-Za-z0-9]+$'
 or p_stripe_refund !~ '^re_[A-Za-z0-9]+$'
 or p_payment_intent !~ '^pi_[A-Za-z0-9]+$'
 or p_amount is null or p_amount<=0 or p_currency<>'eur'
 or p_status not in ('succeeded','failed') then
  raise exception 'Firma o parametri refund invalidi';end if;
 select * into v_line from public.group_line_refunds
 where refund_id=p_refund_id for update;
 if not found or v_line.amount_cents<>p_amount then raise exception 'Riga refund non trovata';end if;
 select * into v_refund from public.payment_refunds where id=p_refund_id for update;
 select * into v_attempt from public.payment_attempts where id=v_refund.payment_id for update;
 if v_refund.amount_cents<>p_amount or v_attempt.stripe_account_id<>p_stripe_account
 or v_attempt.stripe_payment_intent_id<>p_payment_intent
 or v_attempt.payer_id<>v_line.original_payer_id or v_attempt.status<>'succeeded'
 or (v_refund.stripe_refund_id is not null and v_refund.stripe_refund_id<>p_stripe_refund)
 then raise exception 'Rimborso Stripe non coerente con ledger pagatore';end if;
 if v_refund.status='succeeded' then return 'duplicate';end if;
 if v_refund.status=p_status and v_refund.stripe_refund_id=p_stripe_refund
 then return 'duplicate';end if;
 update public.payment_refunds set status=p_status,
 stripe_refund_id=p_stripe_refund,updated_at=now() where id=p_refund_id;
 if p_status='succeeded' then
  update public.group_line_payment_claims set state='refunded'
   where group_cart_item_id=v_line.group_cart_item_id and state='refund_pending';
 end if;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event_id,p_stripe_account,'refund.updated',
  jsonb_build_object('refund_id',p_refund_id,'status',p_status),now())
 on conflict(event_id) do nothing;
 return p_status;
end;$group_refund_signed$;

revoke all on function public.expire_group_drafts(integer),
 public.list_group_refunds_for_dispatch(integer),
 public.stripe_refund_kind(uuid),
 public.finalize_verified_group_refund(text,text,uuid,text,text,bigint,text,text)
 from public,anon,authenticated;
grant execute on function public.expire_group_drafts(integer),
 public.list_group_refunds_for_dispatch(integer),
 public.stripe_refund_kind(uuid),
 public.finalize_verified_group_refund(text,text,uuid,text,text,bigint,text,text)
 to service_role;


revoke all on function app_private.queue_group_line_refund(uuid,text),
 app_private.archive_group_line(uuid,text),
 app_private.queue_unwanted_paid_group_line()
 from public,anon,authenticated;
revoke all on function public.join_group_draft(uuid,double precision,double precision,double precision,timestamptz),
 public.replace_group_personal_cart(uuid,jsonb),
 public.leave_group_draft(uuid),public.cancel_group_draft(uuid),
 public.group_payable_lines(uuid),public.begin_group_stripe_checkout(uuid,uuid[],uuid),
 public.group_draft_details(uuid),
 public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz),
 public.group_order_details(uuid),public.record_group_counter_payment(uuid,text,uuid),
 public.deliver_group_order(uuid),public.cancel_confirmed_group_order(uuid),
 public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb)
 from public,anon,authenticated;
grant execute on function public.join_group_draft(uuid,double precision,double precision,double precision,timestamptz),
 public.replace_group_personal_cart(uuid,jsonb),
 public.leave_group_draft(uuid),public.cancel_group_draft(uuid),
 public.group_payable_lines(uuid),public.begin_group_stripe_checkout(uuid,uuid[],uuid),
 public.group_draft_details(uuid),
 public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz),
 public.group_order_details(uuid),public.record_group_counter_payment(uuid,text,uuid),
 public.deliver_group_order(uuid),public.cancel_confirmed_group_order(uuid)
 to authenticated;
grant execute on function public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb)
 to service_role;
alter table public.customer_notifications
 drop constraint customer_notifications_event_type_check;
alter table public.customer_notifications
 add constraint customer_notifications_event_type_check check(event_type in
 ('closure_order_cancelled','order_status','group_join_requested','group_join_approved',
 'group_join_rejected','support_reply','group_draft_expiry'));

create table app_private.group_expiry_warnings(
 group_id uuid not null references public.group_drafts(id) on delete restrict,
 deadline_at timestamptz not null,
 created_at timestamptz not null default now(),
 primary key(group_id,deadline_at)
);

create or replace function public.warn_group_drafts_before_expiry(p_limit integer default 50)
returns integer language plpgsql security definer set search_path=''
as $warn_group_expiry$
declare v_group public.group_drafts%rowtype;v_id uuid;v_count integer:=0;
begin
 if auth.jwt()->>'role'<>'service_role' then raise exception 'Solo dispatcher server';end if;
 if p_limit is null or p_limit not between 1 and 200 then raise exception 'Limite non valido';end if;
 for v_group in select * from public.group_drafts
  where status='draft' and updated_at<=now()-interval '23 hours'
   and updated_at>now()-interval '24 hours'
  order by updated_at,id for update skip locked limit p_limit
 loop
  v_id:=null;
  insert into app_private.group_expiry_warnings(group_id,deadline_at)
   values(v_group.id,v_group.updated_at+interval '24 hours')
   on conflict do nothing returning group_id into v_id;
  if v_id is not null then
   insert into public.customer_notifications(school_id,user_id,group_id,event_type,message)
   values(v_group.school_id,v_group.coordinator_id,v_group.id,'group_draft_expiry',
    'La bozza gruppo "'||left(v_group.title,90)||'" scade tra circa un''ora. Confermala o modifica i dati necessari.');
   v_count:=v_count+1;
  end if;
 end loop;
 return v_count;
end;$warn_group_expiry$;
revoke all on function public.warn_group_drafts_before_expiry(integer) from public,anon,authenticated;
grant execute on function public.warn_group_drafts_before_expiry(integer) to service_role;
commit;
