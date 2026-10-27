begin;
alter table public.payment_attempts add column workflow_v2 boolean not null default false;
alter table public.payment_refunds add column workflow_context jsonb;
alter table public.order_items add column removed_at timestamptz;
alter table public.order_items drop constraint order_items_order_id_product_id_key;
create unique index current_individual_product on public.order_items(order_id,product_id) where removed_at is null;
create view app_private.current_order_items with(security_invoker=true) as select * from public.order_items where removed_at is null;
revoke all on app_private.current_order_items from public,anon,authenticated,service_role;
drop policy order_items_customer_and_staff_read on public.order_items;
create policy order_items_customer_and_staff_read on public.order_items for select to authenticated
 using(removed_at is null and exists(select 1 from public.orders o where o.id=order_items.order_id));
create table public.order_supplements(
 id uuid primary key default gen_random_uuid(),group_order_id uuid not null references public.group_orders(id),
 group_line_id uuid not null references public.group_order_lines(id),beneficiary_id uuid not null references auth.users(id),
 description text not null,amount_cents bigint not null check(amount_cents>0),
 state text not null default 'available' check(state in ('available','pending','paid','cancelled')),
 payment_id uuid references public.payment_attempts(id),created_at timestamptz not null default now()
);
create index supplements_group on public.order_supplements(group_order_id);
create index supplements_line on public.order_supplements(group_line_id);
create index supplements_beneficiary on public.order_supplements(beneficiary_id);
create index supplements_payment on public.order_supplements(payment_id);
alter table public.payment_item_allocations add column supplement_id uuid references public.order_supplements(id);
alter table public.payment_item_allocations drop constraint payment_item_allocations_check;
alter table public.payment_item_allocations add constraint payment_item_allocations_check
 check(num_nonnulls(order_item_id,group_cart_item_id,supplement_id)=1);
create index payment_allocation_supplement on public.payment_item_allocations(supplement_id);
create unique index supplement_one_payment on public.payment_item_allocations(supplement_id) where supplement_id is not null;
create table public.order_additional_receipts(
 id uuid primary key default gen_random_uuid(),order_id uuid references public.orders(id),group_order_id uuid references public.group_orders(id),
 school_id uuid not null references public.schools(id),bar_id uuid not null references public.bars(id),
 actor_id uuid not null references auth.users(id),request_key uuid not null,
 method text not null check(method in ('cash','external_pos')),amount_cents bigint not null check(amount_cents>0),
 created_at timestamptz not null default now(),unique(actor_id,request_key),check(num_nonnulls(order_id,group_order_id)=1)
);
create index additional_receipts_order on public.order_additional_receipts(order_id);
create index additional_receipts_group on public.order_additional_receipts(group_order_id);
create index additional_receipts_school on public.order_additional_receipts(school_id);
create index additional_receipts_bar on public.order_additional_receipts(bar_id);
create table public.cash_refund_obligations(
 id uuid primary key default gen_random_uuid(),school_id uuid not null references public.schools(id),
 owner_id uuid not null references auth.users(id),order_id uuid references public.orders(id),group_order_id uuid references public.group_orders(id),
 request_key uuid not null,amount_cents bigint not null check(amount_cents>0),
 status text not null default 'pending' check(status in ('pending','returned')),reason text not null,
 returned_by uuid references auth.users(id),returned_at timestamptz,
 unique(request_key),check(num_nonnulls(order_id,group_order_id)=1)
);
create index cash_refund_school on public.cash_refund_obligations(school_id);
create index cash_refund_owner on public.cash_refund_obligations(owner_id);
create index cash_refund_order on public.cash_refund_obligations(order_id);
create index cash_refund_group on public.cash_refund_obligations(group_order_id);
create index cash_refund_actor on public.cash_refund_obligations(returned_by);
do $$declare t text;begin foreach t in array array['order_supplements','order_additional_receipts','cash_refund_obligations'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;end;$$;

create function app_private.order_paid_cents(p_kind text,p_id uuid)
returns bigint language sql stable set search_path='' as $$
 with scope as(select group_id from public.group_orders where p_kind='group' and id=p_id),
 online as(select a.amount_cents-coalesce((select sum(r.amount_cents) from public.payment_refunds r where r.payment_id=a.id),0) cents
  from public.payment_attempts a where a.status='succeeded' and
   ((p_kind='individual' and a.order_id=p_id) or (p_kind='group' and a.group_id=(select group_id from scope)))),
 receipts as(select amount_cents cents from public.counter_payments where p_kind='individual' and order_id=p_id
  union all select amount_cents from public.group_counter_payments where p_kind='group' and group_order_id=p_id
  union all select amount_cents from public.order_additional_receipts where
   (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)),
 cash_refunds as(select amount_cents cents from public.cash_refund_obligations where
  (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id))
 select greatest(0,coalesce((select sum(cents) from online),0)+coalesce((select sum(cents) from receipts),0)-coalesce((select sum(cents) from cash_refunds),0))::bigint;
$$;
revoke all on function app_private.order_paid_cents(text,uuid) from public,anon,authenticated,service_role;
create function app_private.refresh_individual_balance(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.orders set payment_status=case when app_private.order_paid_cents('individual',id)>=total_cents then 'paid' else 'due' end,
  updated_at=now() where id=p_id and status not in ('cancelled','no_show');
end;$$;
revoke all on function app_private.refresh_individual_balance(uuid) from public,anon,authenticated,service_role;
create function app_private.assert_no_pending_checkout(p_kind text,p_id uuid)
returns void language plpgsql stable set search_path='' as $$
begin
 if exists(select 1 from public.payment_attempts a where
  ((p_kind='individual' and a.order_id=p_id) or (p_kind='group' and a.group_id=(select group_id from public.group_orders where id=p_id)))
  and a.status in ('initiated','requires_action','processing','review'))
 then raise exception 'Checkout in corso: attendi il risultato firmato prima di modificare o incassare';end if;
end;$$;
revoke all on function app_private.assert_no_pending_checkout(text,uuid) from public,anon,authenticated,service_role;

create function app_private.refund_order_credit(p_kind text,p_id uuid,p_line uuid,p_amount bigint,p_key uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare x record;j jsonb;v_left bigint:=p_amount;v_available bigint;v_piece bigint;v_cash bigint;
begin
 if p_amount<=0 then return;end if;
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if exists(select 1 from public.payment_refunds where request_key=p_key) or exists(select 1 from public.cash_refund_obligations where request_key=p_key) then return;end if;
 for x in select a.* from public.payment_attempts a where a.status='succeeded' and
  ((p_kind='individual' and a.order_id=p_id) or (p_kind='group' and a.group_id=(j->>'group_id')::uuid and
   (p_line is null or exists(select 1 from public.payment_item_allocations al
    left join public.order_supplements sp on sp.id=al.supplement_id
    where al.payment_id=a.id and (al.group_cart_item_id=(select group_cart_item_id from public.group_order_lines where id=p_line)
      or sp.group_line_id=p_line))))) order by a.created_at desc,a.id for update loop
  select greatest(0,x.amount_cents-coalesce(sum(amount_cents),0)) into v_available from public.payment_refunds where payment_id=x.id;
  if p_kind='group' and p_line is not null then
   select least(v_available,coalesce(sum(al.amount_cents),0)) into v_available from public.payment_item_allocations al
   left join public.order_supplements sp on sp.id=al.supplement_id where al.payment_id=x.id and
    (al.group_cart_item_id=(select group_cart_item_id from public.group_order_lines where id=p_line) or sp.group_line_id=p_line);
  end if;
  v_piece:=least(v_left,v_available);
  if v_piece>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
   values(x.id,p_key,v_piece,'pending',left(p_reason,300),jsonb_build_object('kind',p_kind,'order_id',p_id,'line_id',p_line));v_left:=v_left-v_piece;end if;
  exit when v_left=0;
 end loop;
 if v_left>0 then
  select coalesce(sum(cents),0) into v_cash from(
   select amount_cents cents from public.counter_payments where p_kind='individual' and order_id=p_id
   union all select amount_cents from public.group_counter_payments where p_kind='group' and group_order_id=p_id
   union all select amount_cents from public.order_additional_receipts where (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)) q;
  v_cash:=v_cash-coalesce((select sum(amount_cents) from public.cash_refund_obligations where
   (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)),0);
  if v_cash>=v_left then insert into public.cash_refund_obligations(school_id,owner_id,order_id,group_order_id,request_key,amount_cents,reason)
   values((j->>'school_id')::uuid,(j->>'owner_id')::uuid,case when p_kind='individual' then p_id end,
    case when p_kind='group' then p_id end,p_key,v_left,left(p_reason,300));
  else raise exception 'Credito da riconciliare: nessuna modifica economica applicata';end if;
 end if;
end;$$;
revoke all on function app_private.refund_order_credit(text,uuid,uuid,bigint,uuid,text) from public,anon,authenticated,service_role;

alter function public.finalize_verified_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb) rename to finalize_legacy_individual;
alter function public.finalize_legacy_individual(text,text,text,text,uuid,bigint,text,boolean,jsonb) set schema app_private;
revoke all on function app_private.finalize_legacy_individual(text,text,text,text,uuid,bigint,text,boolean,jsonb) from public,anon,authenticated,service_role;
alter function public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb) rename to finalize_legacy_group;
alter function public.finalize_legacy_group(text,text,text,text,uuid,bigint,text,boolean,jsonb) set schema app_private;
revoke all on function app_private.finalize_legacy_group(text,text,text,text,uuid,bigint,text,boolean,jsonb) from public,anon,authenticated,service_role;

create function app_private.finalize_workflow_checkout(p_event text,p_account text,p_session text,p_intent text,p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb)
returns text language plpgsql security definer set search_path='' as $$
declare a public.payment_attempts%rowtype;j jsonb;k text;v_id uuid;v_due bigint;v_refund bigint;v_terminal boolean;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' or p_event!~'^evt_[A-Za-z0-9]+$' or p_intent!~'^pi_[A-Za-z0-9]+$'
  or p_session!~'^cs_(test|live)_[A-Za-z0-9]+$' or p_currency<>'eur' or not p_paid or p_amount<=0 then raise exception 'Webhook non valido';end if;
 select * into a from public.payment_attempts where id=p_attempt;
 if not found or a.stripe_account_id<>p_account or a.amount_cents<>p_amount or a.stripe_checkout_session_id<>p_session then raise exception 'Webhook incoerente';end if;
 if a.status='succeeded' then return 'duplicate_payment';end if;
 k:=case when a.order_id is null then 'group' else 'individual' end;
 if k='group' then
  perform id from public.group_drafts where id=a.group_id for update;
  select id into v_id from public.group_orders where group_id=a.group_id;
  if v_id is null then
   select jsonb_build_object('status',status,'group_id',id) into j from public.group_drafts where id=a.group_id for update;
   v_terminal:=j->>'status' in ('cancelled','expired');v_due:=p_amount;
  else j:=app_private.order_scope(k,v_id,'internal');v_terminal:=j->>'status' in ('cancelled','delivered','no_show');
   v_due:=greatest(0,(j->>'total_cents')::bigint-app_private.order_paid_cents(k,v_id));end if;
 else v_id:=a.order_id;j:=app_private.order_scope(k,v_id,'internal');
  if (j->>'owner_id')::uuid<>a.payer_id then raise exception 'Pagatore non coerente';end if;
  v_terminal:=j->>'status' in ('cancelled','delivered','no_show');v_due:=greatest(0,(j->>'total_cents')::bigint-app_private.order_paid_cents(k,v_id));
 end if;
 select * into a from public.payment_attempts where id=p_attempt for update;
 if a.status='succeeded' then return 'duplicate_payment';end if;
 v_terminal:=v_terminal or a.status in ('cancelled','failed');
 update public.payment_attempts set status='succeeded',stripe_payment_intent_id=p_intent,updated_at=now() where id=a.id;
 update public.group_line_payment_claims set state='paid' where payment_id=a.id and state='pending';
 update public.order_supplements set state='paid' where payment_id=a.id and state='pending';
 v_refund:=case when v_terminal then p_amount else greatest(0,p_amount-v_due) end;
 select greatest(0,v_refund-coalesce(sum(amount_cents),0)) into v_refund from public.payment_refunds where payment_id=a.id;
 if v_refund>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
  values(a.id,a.id,v_refund,'pending','Incasso tardivo o quota già saldata',jsonb_build_object('kind',k,'order_id',v_id)) on conflict(payment_id,request_key) do nothing;end if;
 if k='individual' then perform app_private.refresh_individual_balance(v_id);end if;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event,p_account,'checkout.session.completed',p_payload,now()) on conflict(event_id) do nothing;
 return case when v_refund>0 then 'refund_required' else 'succeeded' end;
end;$$;
revoke all on function app_private.finalize_workflow_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb) from public,anon,authenticated,service_role;
create function public.finalize_verified_checkout(p_event_id text,p_event_account text,p_session text,p_intent text,p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb)
returns text language plpgsql security definer set search_path='' as $$begin
 if (select workflow_v2 from public.payment_attempts where id=p_attempt) then
 return app_private.finalize_workflow_checkout(p_event_id,p_event_account,p_session,p_intent,p_attempt,p_amount,p_currency,p_paid,p_payload);end if;
 return app_private.finalize_legacy_individual(p_event_id,p_event_account,p_session,p_intent,p_attempt,p_amount,p_currency,p_paid,p_payload);
end;$$;
create function public.finalize_verified_group_checkout(p_event_id text,p_account text,p_session text,p_intent text,p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb)
returns text language plpgsql security definer set search_path='' as $$begin
 if (select workflow_v2 from public.payment_attempts where id=p_attempt) then
 return app_private.finalize_workflow_checkout(p_event_id,p_account,p_session,p_intent,p_attempt,p_amount,p_currency,p_paid,p_payload);end if;
 return app_private.finalize_legacy_group(p_event_id,p_account,p_session,p_intent,p_attempt,p_amount,p_currency,p_paid,p_payload);
end;$$;
revoke all on function public.finalize_verified_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb),public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.finalize_verified_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb),public.finalize_verified_group_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb) to service_role;

create or replace function public.begin_individual_stripe_checkout(p_order_id uuid,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;a public.payment_attempts%rowtype;m public.school_stripe_merchants%rowtype;v_amount bigint;
begin
 j:=app_private.order_scope('individual',p_order_id,'owner');
 if exists(select 1 from app_private.platform_admins where user_id=auth.uid()) then raise exception 'Super Admin escluso dai pagamenti cliente';end if;
 if p_request_key is null or j->>'status' in ('cancelled','delivered','no_show') then raise exception 'Ordine non pagabile';end if;
 select * into a from public.payment_attempts where payer_id=auth.uid() and request_key=p_request_key;
 if found then if a.order_id<>p_order_id then raise exception 'Idempotenza incoerente';end if;
 else
  perform app_private.assert_no_pending_checkout('individual',p_order_id);
  select * into m from public.school_stripe_merchants where school_id=(j->>'school_id')::uuid and charges_enabled;
  if not found then raise exception 'Merchant Stripe non abilitato';end if;
  v_amount:=greatest(0,(j->>'total_cents')::bigint-app_private.order_paid_cents('individual',p_order_id));
  if v_amount<=0 then raise exception 'Ordine già saldato';end if;
  insert into public.payment_attempts(school_id,payer_id,order_id,stripe_account_id,request_key,amount_cents,expires_at,workflow_v2)
  values((j->>'school_id')::uuid,auth.uid(),p_order_id,m.stripe_account_id,p_request_key,v_amount,now()+interval '40 minutes',true) returning * into a;
 end if;
 return jsonb_build_object('attempt_id',a.id,'amount_cents',a.amount_cents,'currency','eur','stripe_account_id',a.stripe_account_id,'existing_session',a.stripe_checkout_session_id);
end;$$;

create or replace function public.begin_group_stripe_checkout(p_group_id uuid,p_line_ids uuid[],p_request_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g public.group_drafts%rowtype;o public.group_orders%rowtype;m public.school_stripe_merchants%rowtype;
 a public.payment_attempts%rowtype;x record;v_sum bigint;v_n integer;v_ids uuid[];
begin
 if p_request_key is null or cardinality(p_line_ids) not between 1 and 50 or p_line_ids is null or exists(select 1 from unnest(p_line_ids) v where v is null)
  or (select count(distinct v) from unnest(p_line_ids) v)<>cardinality(p_line_ids) then raise exception 'Selezione righe non valida';end if;
 select * into g from public.group_drafts where id=p_group_id for update;
 if not found or g.status not in ('draft','confirmed','approval_pending') or (g.status='draft' and g.updated_at<now()-interval '24 hours')
  or not exists(select 1 from public.group_members where group_id=g.id and user_id=auth.uid() and status='accepted')
  or exists(select 1 from app_private.platform_admins where user_id=auth.uid()) then raise exception 'Gruppo non pagabile';end if;
 select * into o from public.group_orders where group_id=g.id for update;
 if found and (o.status in ('cancelled','delivered','no_show') or o.pickup_lease_until>now()
  or exists(select 1 from public.group_counter_payments where group_order_id=o.id)) then raise exception 'Pagamenti chiusi durante il ritiro';end if;
 select * into a from public.payment_attempts where payer_id=auth.uid() and request_key=p_request_key;
 if found then
  select array_agg(coalesce(group_cart_item_id,supplement_id) order by coalesce(group_cart_item_id,supplement_id)) into v_ids from public.payment_item_allocations where payment_id=a.id;
  if a.group_id<>g.id or v_ids<>(select array_agg(v order by v) from unnest(p_line_ids) v) then raise exception 'Idempotenza incoerente';end if;
 else
  select * into m from public.school_stripe_merchants where school_id=g.school_id and charges_enabled;
  if not found then raise exception 'Merchant Stripe non abilitato';end if;
  select coalesce(sum(cents),0),count(*) into v_sum,v_n from(
   select i.quantity::bigint*i.unit_price_cents cents from public.group_cart_items i join public.group_members gm on gm.group_id=i.group_id and gm.user_id=i.user_id
    where i.group_id=g.id and i.removed_at is null and gm.status='accepted' and i.id=any(p_line_ids)
    and not exists(select 1 from public.group_line_payment_claims cl where cl.group_cart_item_id=i.id)
   union all select sp.amount_cents from public.order_supplements sp where sp.group_order_id=o.id and sp.id=any(p_line_ids) and sp.state='available') q;
  if v_n<>cardinality(p_line_ids) or v_sum<=0 then raise exception 'Una riga è già pagata o non è disponibile';end if;
  if g.status='draft' and exists(select 1 from public.group_cart_items i join public.products p on p.id=i.product_id
   where i.id=any(p_line_ids) and i.unit_price_cents<>p.price_cents) then raise exception 'Prezzo aggiornato: ricontrolla il carrello';end if;
  insert into public.payment_attempts(school_id,payer_id,group_id,stripe_account_id,request_key,amount_cents,expires_at,workflow_v2)
   values(g.school_id,auth.uid(),g.id,m.stripe_account_id,p_request_key,v_sum,now()+interval '40 minutes',true) returning * into a;
  insert into public.payment_item_allocations(payment_id,group_cart_item_id,beneficiary_id,amount_cents)
   select a.id,i.id,i.user_id,i.quantity::bigint*i.unit_price_cents from public.group_cart_items i where i.group_id=g.id and i.id=any(p_line_ids);
  insert into public.group_line_payment_claims(group_cart_item_id,payment_id,payer_id,beneficiary_id,amount_cents,state)
   select al.group_cart_item_id,a.id,auth.uid(),al.beneficiary_id,al.amount_cents,'pending' from public.payment_item_allocations al where al.payment_id=a.id and al.group_cart_item_id is not null;
  insert into public.payment_item_allocations(payment_id,supplement_id,beneficiary_id,amount_cents)
   select a.id,sp.id,sp.beneficiary_id,sp.amount_cents from public.order_supplements sp where sp.group_order_id=o.id and sp.id=any(p_line_ids);
  update public.order_supplements set state='pending',payment_id=a.id where group_order_id=o.id and id=any(p_line_ids);
 end if;
 return jsonb_build_object('attempt_id',a.id,'amount_cents',a.amount_cents,'currency','eur','stripe_account_id',a.stripe_account_id,'existing_session',a.stripe_checkout_session_id);
end;$$;

create or replace function public.stripe_refund_kind(p_refund_id uuid)
returns text language plpgsql stable security definer set search_path='' as $$begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo webhook';end if;
 return case when exists(select 1 from public.group_line_refunds where refund_id=p_refund_id) then 'group'
  when exists(select 1 from public.payment_refunds where id=p_refund_id) then 'individual' end;
end;$$;
create or replace function public.finalize_verified_stripe_refund(p_event_id text,p_stripe_account text,p_refund_id uuid,p_stripe_refund text,p_payment_intent text,p_amount bigint,p_currency text,p_status text)
returns text language plpgsql security definer set search_path='' as $$
declare r public.payment_refunds%rowtype;a public.payment_attempts%rowtype;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' or p_event_id!~'^evt_[A-Za-z0-9]+$' or p_stripe_refund!~'^re_[A-Za-z0-9]+$'
  or p_status not in ('succeeded','failed') or p_currency<>'eur' then raise exception 'Evento refund non valido';end if;
 select * into r from public.payment_refunds where id=p_refund_id for update;
 select * into a from public.payment_attempts where id=r.payment_id for update;
 if r.id is null or r.amount_cents<>p_amount or a.status<>'succeeded' or a.stripe_account_id<>p_stripe_account or a.stripe_payment_intent_id<>p_payment_intent
  or (r.stripe_refund_id is not null and r.stripe_refund_id<>p_stripe_refund) then raise exception 'Refund non coerente con il pagatore originale';end if;
 if r.status='succeeded' then return 'duplicate';end if;
 update public.payment_refunds set status=p_status,stripe_refund_id=p_stripe_refund,updated_at=now() where id=r.id;
 if a.order_id is not null then
  perform app_private.refresh_individual_balance(a.order_id);
  if p_status='succeeded' and (select coalesce(sum(amount_cents),0) from public.payment_refunds where payment_id=a.id and status='succeeded')>=a.amount_cents
  and (select count(*) from public.payment_attempts where order_id=a.order_id and status='succeeded')=1
  and app_private.order_paid_cents('individual',a.order_id)=0
  then update public.orders set payment_status='refunded' where id=a.order_id;end if;
 end if;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event_id,p_stripe_account,'refund.updated',jsonb_build_object('refund_id',r.id,'status',p_status),now()) on conflict(event_id) do nothing;
 return p_status;
end;$$;
-- Amendments and customer-consented exceptions follow below.
create table public.order_change_requests(
 id uuid primary key default gen_random_uuid(),school_id uuid not null references public.schools(id),
 order_id uuid references public.orders(id),group_order_id uuid references public.group_orders(id),
 actor_id uuid not null references auth.users(id),owner_id uuid not null references auth.users(id),
 kind text not null check(kind in ('amendment','substitution','delay')),
 state text not null check(state in ('staff_pending','customer_pending','applied','rejected','expired')),
 payload jsonb not null,request_key uuid not null,expires_at timestamptz not null,
 created_at timestamptz not null default now(),resolved_at timestamptz,
 unique(actor_id,request_key),check(num_nonnulls(order_id,group_order_id)=1)
);
create index changes_school on public.order_change_requests(school_id,state);
create index changes_owner on public.order_change_requests(owner_id);
create index changes_order on public.order_change_requests(order_id);
create index changes_group on public.order_change_requests(group_order_id);
create table public.order_versions(
 id bigint generated always as identity primary key,order_id uuid references public.orders(id),group_order_id uuid references public.group_orders(id),
 actor_id uuid not null references auth.users(id),change_id uuid references public.order_change_requests(id),
 snapshot jsonb not null,created_at timestamptz not null default now(),check(num_nonnulls(order_id,group_order_id)=1)
);
create index versions_order on public.order_versions(order_id);
create index versions_group on public.order_versions(group_order_id);
create index versions_actor on public.order_versions(actor_id);
create index versions_change on public.order_versions(change_id);
do $$declare t text;begin foreach t in array array['order_change_requests','order_versions'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;end;$$;
create function app_private.quote_order_items(p_bar uuid,p_items jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare j jsonb;n integer;
begin
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100
 then raise exception 'Carrello non valido';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer) where product_id is null or quantity not between 1 and 1000 or quantity is null)
 then raise exception 'Quantità non valida';end if;
 select count(*) into n from(select product_id from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer) group by product_id) x;
 select jsonb_agg(jsonb_build_object('product_id',p.id,'quantity',x.quantity,'unit_cents',p.price_cents,
  'name',p.name,'ingredients',p.ingredients,'allergens',p.allergens) order by p.id) into j
 from(select product_id,sum(quantity)::integer quantity from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer) group by product_id) x
 join public.products p on p.id=x.product_id and p.bar_id=p_bar and p.is_active
 join public.categories c on c.id=p.category_id and c.is_active;
 if coalesce(jsonb_array_length(j),0)<>n or exists(select 1 from jsonb_to_recordset(j) x(quantity integer) where quantity>1000)
 then raise exception 'Prodotto non disponibile o quantità troppo elevata';end if;
 return j;
end;$$;
revoke all on function app_private.quote_order_items(uuid,jsonb) from public,anon,authenticated,service_role;
create function app_private.notify_order_change(p_kind text,p_id uuid,p_message text)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if p_kind='individual' then insert into public.customer_notifications(school_id,user_id,order_id,event_type,message)
 values((j->>'school_id')::uuid,(j->>'owner_id')::uuid,p_id,'order_status',left(p_message,1000));
 else insert into public.customer_notifications(school_id,user_id,group_id,event_type,message)
 select (j->>'school_id')::uuid,user_id,(j->>'group_id')::uuid,'group_confirmed',left(p_message,1000)
 from public.group_members where group_id=(j->>'group_id')::uuid and status='accepted';end if;
end;$$;
revoke all on function app_private.notify_order_change(text,uuid,text) from public,anon,authenticated,service_role;
create function app_private.cancel_workflow_order(p_kind text,p_id uuid,p_reason text,p_key uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;v_paid bigint;
begin
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if j->>'status' in ('cancelled','no_show') then return;end if;
 if j->>'status'='delivered' then raise exception 'Ordine già consegnato';end if;
 v_paid:=app_private.order_paid_cents(p_kind,p_id);
 perform app_private.release_order_stock(p_kind,p_id,true);
 if p_kind='individual' then update public.orders set status='cancelled',updated_at=now() where id=p_id;
 else update public.group_orders set status='cancelled',pickup_lease_until=null,pickup_lease_actor=null,updated_at=now() where id=p_id;
  update public.group_drafts set status='cancelled',updated_at=now() where id=(j->>'group_id')::uuid;
  update public.order_supplements set state='cancelled' where group_order_id=p_id and state='available';end if;
 perform app_private.refund_order_credit(p_kind,p_id,null,v_paid,p_id,p_reason);
 update public.order_approvals set state='cancelled',reason=p_reason,lease_until=null where
  (order_id=p_id or group_order_id=p_id) and state in ('queued','active','awaiting_reschedule');
 perform app_private.notify_order_change(p_kind,p_id,'Ordine annullato: '||p_reason||'. Eventuali rimborsi sono in elaborazione verso i pagatori originali.');
end;$$;
revoke all on function app_private.cancel_workflow_order(text,uuid,text,uuid) from public,anon,authenticated,service_role;

create function app_private.apply_individual_amendment(p_change uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.order_change_requests%rowtype;j jsonb;w public.pickup_windows%rowtype;x record;s public.daily_stock%rowtype;
 v_total bigint;v_paid bigint;v_preserve boolean;
begin
 select * into c from public.order_change_requests where id=p_change for update;
 if c.state='applied' then return;end if;
 j:=app_private.order_scope('individual',c.order_id,'internal');
 if j->>'status' not in ('confirmed','preparing','ready') then raise exception 'Ordine non modificabile';end if;
 perform app_private.assert_no_pending_checkout('individual',c.order_id);
 select * into w from public.pickup_windows where id=(j->>'window_id')::uuid;
 select preparation_mode='active' and j->>'status' in ('preparing','ready') into v_preserve from public.bars where id=(j->>'bar_id')::uuid;
 select sum(quantity::bigint*unit_cents) into v_total from jsonb_to_recordset(c.payload->'items') x(quantity integer,unit_cents integer);
 if v_total is null or v_total>999999999 then raise exception 'Importo non valido';end if;
 v_paid:=app_private.order_paid_cents('individual',c.order_id);
 if exists(select 1 from jsonb_to_recordset(c.payload->'items') q(product_id uuid)
  where not exists(select 1 from public.products where id=q.product_id and bar_id=(j->>'bar_id')::uuid and is_active))
 then raise exception 'Prodotto non più disponibile: l’ordine originale rimane invariato';end if;
 insert into public.order_versions(order_id,actor_id,change_id,snapshot)
 values(c.order_id,coalesce(auth.uid(),c.owner_id),c.id,jsonb_build_object('scope',j,'items',
  (select jsonb_agg(to_jsonb(i)) from public.order_items i where order_id=c.order_id and removed_at is null)));
 for x in with old as(select product_id,quantity from public.order_items where order_id=c.order_id and removed_at is null),
  new as(select * from jsonb_to_recordset(c.payload->'items') n(product_id uuid,quantity integer))
  select coalesce(o.product_id,n.product_id) product_id,coalesce(n.quantity,0)-coalesce(o.quantity,0) delta
  from old o full join new n on n.product_id=o.product_id order by 1 loop
  select * into s from public.daily_stock where bar_id=(j->>'bar_id')::uuid and product_id=x.product_id and service_date=w.service_date for update;
  if not found then raise exception 'Scorte non configurate';end if;
  if x.delta<0 and v_preserve then continue;end if;
  if s.capacity is not null and s.allocated+x.delta>s.capacity then raise exception 'Scorte insufficienti: l’ordine precedente rimane invariato';end if;
  update public.daily_stock set allocated=allocated+x.delta,updated_at=now() where id=s.id;
 end loop;
 update public.order_items set removed_at=now() where order_id=c.order_id and removed_at is null;
 insert into public.order_items(school_id,bar_id,order_id,product_id,product_name,quantity,unit_cents)
 select (j->>'school_id')::uuid,(j->>'bar_id')::uuid,c.order_id,product_id,name,quantity,unit_cents
 from jsonb_to_recordset(c.payload->'items') n(product_id uuid,name text,quantity integer,unit_cents integer);
 update public.orders set total_cents=v_total,updated_at=now() where id=c.order_id;
 perform app_private.refund_order_credit('individual',c.order_id,null,greatest(0,v_paid-v_total),c.id,'Riduzione ordine');
 perform app_private.refresh_individual_balance(c.order_id);
 update public.order_change_requests set state='applied',resolved_at=now() where id=c.id;
 perform app_private.notify_order_change('individual',c.order_id,'Modifica applicata. Controlla in app prodotti, saldo e rimborsi in elaborazione.');
end;$$;
revoke all on function app_private.apply_individual_amendment(uuid) from public,anon,authenticated,service_role;
create function public.request_order_amendment(p_order uuid,p_items jsonb,p_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare j jsonb;c uuid;v_items jsonb;v_needs_staff boolean;v_at timestamptz;
begin
 j:=app_private.order_scope('individual',p_order,'owner');
 select id into c from public.order_change_requests where actor_id=auth.uid() and request_key=p_key;
 if found then return c;end if;
 select (w.service_date+w.starts_at) at time zone s.timezone-make_interval(mins=>s.cancel_cutoff_minutes) into v_at
 from public.pickup_windows w join public.schools s on s.id=w.school_id where w.id=(j->>'window_id')::uuid;
 if p_key is null or v_at<=now() or j->>'status' not in ('confirmed','preparing','ready') then raise exception 'Limite di modifica superato';end if;
 perform app_private.assert_no_pending_checkout('individual',p_order);
 v_items:=app_private.quote_order_items((j->>'bar_id')::uuid,p_items);
 select preparation_mode='active' and j->>'status' in ('preparing','ready') into v_needs_staff from public.bars where id=(j->>'bar_id')::uuid;
 insert into public.order_change_requests(school_id,order_id,actor_id,owner_id,kind,state,payload,request_key,expires_at)
 values((j->>'school_id')::uuid,p_order,auth.uid(),auth.uid(),'amendment','staff_pending',jsonb_build_object('items',v_items),p_key,v_at) returning id into c;
 if not v_needs_staff then perform app_private.apply_individual_amendment(c);end if;
 return c;
end;$$;
create function public.decide_order_amendment(p_change uuid,p_accept boolean)
returns void language plpgsql security definer set search_path='' as $$
declare c public.order_change_requests%rowtype;
begin
 select * into c from public.order_change_requests where id=p_change for update;
 if not found or c.kind<>'amendment' or c.state<>'staff_pending' or c.expires_at<=now() or not app_private.can_serve_group_bar(c.school_id)
 then raise exception 'Richiesta non approvabile';end if;
 if p_accept then perform app_private.apply_individual_amendment(c.id);
 else update public.order_change_requests set state='rejected',resolved_at=now() where id=c.id;end if;
end;$$;

create function public.propose_order_exception(p_kind text,p_order uuid,p_type text,p_line uuid,p_product uuid,p_window uuid,p_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare j jsonb;v_payload jsonb;v_expires timestamptz;v_id uuid;p public.products%rowtype;x record;
begin
 j:=app_private.order_scope(p_kind,p_order,'staff');
 if j->>'status' not in ('confirmed','preparing','ready') or p_type not in ('substitution','delay') or p_key is null
 then raise exception 'Proposta non valida';end if;
 perform app_private.assert_no_pending_checkout(p_kind,p_order);
 select id into v_id from public.order_change_requests where actor_id=auth.uid() and request_key=p_key;if found then return v_id;end if;
 if p_type='substitution' then
  select * into x from app_private.order_lines(p_kind,p_order) where line_id=p_line;
  select * into p from public.products where id=p_product and bar_id=(j->>'bar_id')::uuid and is_active;
  if x.line_id is null or p.id is null then raise exception 'Prodotto o riga non validi';end if;
  v_payload:=jsonb_build_object('line_id',p_line,'product_id',p.id,'name',p.name,'unit_cents',p.price_cents,
   'quantity',x.quantity,'ingredients',p.ingredients,'allergens',p.allergens);
 else
  if not app_private.window_bookable(p_window,(j->>'bar_id')::uuid,now()) then raise exception 'Fascia non valida';end if;
  v_payload:=jsonb_build_object('window_id',p_window);
 end if;
 select greatest(now(),(w.service_date+w.starts_at) at time zone s.timezone) into v_expires
 from public.pickup_windows w join public.schools s on s.id=w.school_id where w.id=(j->>'window_id')::uuid;
 insert into public.order_change_requests(school_id,order_id,group_order_id,actor_id,owner_id,kind,state,payload,request_key,expires_at)
 values((j->>'school_id')::uuid,case when p_kind='individual' then p_order end,case when p_kind='group' then p_order end,
 auth.uid(),(j->>'owner_id')::uuid,p_type,'customer_pending',v_payload,p_key,v_expires) returning id into v_id;
 insert into public.customer_notifications(school_id,user_id,order_id,group_id,event_type,message)
 values((j->>'school_id')::uuid,(j->>'owner_id')::uuid,case when p_kind='individual' then p_order end,(j->>'group_id')::uuid,'order_status',
 'Il Barista propone una '||case when p_type='substitution' then 'sostituzione: controlla ingredienti e allergeni e accetta o rifiuta.' else 'nuova fascia: puoi accettare, scegliere un’alternativa o annullare.' end);
 return v_id;
end;$$;

create function app_private.apply_order_substitution(p_change uuid,p_remove boolean)
returns void language plpgsql security definer set search_path='' as $$
declare c public.order_change_requests%rowtype;j jsonb;k text;v_id uuid;x record;v_old bigint;v_new bigint;v_delta bigint;
 v_window public.pickup_windows%rowtype;v_paid bigint;v_remaining bigint;sp record;
begin
 select * into c from public.order_change_requests where id=p_change for update;
 if c.state='applied' then return;end if;
 k:=case when c.order_id is null then 'group' else 'individual' end;v_id:=coalesce(c.order_id,c.group_order_id);
 j:=app_private.order_scope(k,v_id,'internal');perform app_private.assert_no_pending_checkout(k,v_id);
 select * into x from app_private.order_lines(k,v_id) where line_id=(c.payload->>'line_id')::uuid;
 if not found then raise exception 'Riga non più disponibile';end if;
 v_old:=x.quantity::bigint*x.unit_cents;v_new:=case when p_remove then 0 else (c.payload->>'quantity')::bigint*(c.payload->>'unit_cents')::bigint end;
 select * into v_window from public.pickup_windows where id=(j->>'window_id')::uuid;
 insert into public.order_versions(order_id,group_order_id,actor_id,change_id,snapshot)
 values(c.order_id,c.group_order_id,coalesce(auth.uid(),c.owner_id),c.id,jsonb_build_object('scope',j,'line',to_jsonb(x)));
 if not p_remove then
  if not exists(select 1 from public.products where id=(c.payload->>'product_id')::uuid and bar_id=(j->>'bar_id')::uuid and is_active) then raise exception 'Sostituto non più disponibile';end if;
  update public.daily_stock set allocated=allocated+x.quantity,updated_at=now()
   where bar_id=(j->>'bar_id')::uuid and product_id=(c.payload->>'product_id')::uuid and service_date=v_window.service_date;
  if not found then raise exception 'Scorte sostituto non configurate';end if;
 end if;
 -- Prepared product stock is not automatically returned to inventory.
 if j->>'status'='confirmed' or (select preparation_mode from public.bars where id=(j->>'bar_id')::uuid)='ready_made' then
  update public.daily_stock set allocated=allocated-x.quantity,updated_at=now() where bar_id=(j->>'bar_id')::uuid and product_id=x.product_id and service_date=v_window.service_date;end if;
 if k='individual' then
  v_paid:=app_private.order_paid_cents(k,v_id);
  update public.order_items set removed_at=now() where id=x.line_id;
  if not p_remove then insert into public.order_items(school_id,bar_id,order_id,product_id,product_name,quantity,unit_cents)
   values((j->>'school_id')::uuid,(j->>'bar_id')::uuid,v_id,(c.payload->>'product_id')::uuid,c.payload->>'name',x.quantity,(c.payload->>'unit_cents')::int);end if;
  update public.orders set total_cents=total_cents+v_new-v_old,updated_at=now() where id=v_id;
  perform app_private.refund_order_credit(k,v_id,x.line_id,greatest(0,v_paid-((j->>'total_cents')::bigint+v_new-v_old)),c.id,'Sostituzione/rimozione articolo');
  perform app_private.refresh_individual_balance(v_id);
 else
  if p_remove then update public.group_order_lines set quantity=0 where id=x.line_id;
  else update public.group_order_lines set product_id=(c.payload->>'product_id')::uuid,name=c.payload->>'name',unit_cents=(c.payload->>'unit_cents')::int where id=x.line_id;end if;
  if not exists(select 1 from public.group_line_payment_claims where group_cart_item_id=x.cart_id) then
   if p_remove then update public.group_cart_items set removed_at=now() where id=x.cart_id;
   else update public.group_cart_items set product_id=(c.payload->>'product_id')::uuid,product_name=c.payload->>'name',unit_price_cents=(c.payload->>'unit_cents')::int where id=x.cart_id;end if;
  elsif v_new>v_old then
   insert into public.order_supplements(group_order_id,group_line_id,beneficiary_id,description,amount_cents)
   values(v_id,x.line_id,x.beneficiary_id,'Differenza sostituzione: '||(c.payload->>'name'),v_new-v_old);
  else
   v_remaining:=v_old-v_new;
   for sp in select * from public.order_supplements where group_line_id=x.line_id and state='available' order by created_at desc for update loop
    if sp.amount_cents<=v_remaining then update public.order_supplements set state='cancelled' where id=sp.id;v_remaining:=v_remaining-sp.amount_cents;
    else update public.order_supplements set amount_cents=amount_cents-v_remaining where id=sp.id;v_remaining:=0;end if;exit when v_remaining=0;end loop;
   perform app_private.refund_order_credit(k,v_id,x.line_id,v_remaining,c.id,'Riduzione prezzo articolo di gruppo');
  end if;
  update public.group_orders set total_cents=total_cents+v_new-v_old,updated_at=now() where id=v_id;
 end if;
 update public.order_change_requests set state='applied',resolved_at=now() where id=c.id;
 if not exists(select 1 from app_private.order_lines(k,v_id) where quantity>0) then
  perform app_private.cancel_workflow_order(k,v_id,'Nessun articolo rimasto dopo la sostituzione',v_id);end if;
 perform app_private.notify_order_change(k,v_id,'Sostituzione/rimozione applicata con consenso o per mancata risposta al ritiro. Controlla prodotti, saldo e rimborsi.');
end;$$;
alter table public.group_order_lines drop constraint group_order_lines_quantity_check;
alter table public.group_order_lines add constraint group_order_lines_quantity_check check(quantity between 0 and 1000);
revoke all on function app_private.apply_order_substitution(uuid,boolean) from public,anon,authenticated,service_role;

create function app_private.move_order_window(p_kind text,p_id uuid,p_window uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;oldw public.pickup_windows%rowtype;neww public.pickup_windows%rowtype;x record;
begin
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if not app_private.window_bookable(p_window,(j->>'bar_id')::uuid,now()) then raise exception 'Nuova fascia non prenotabile';end if;
 select * into oldw from public.pickup_windows where id=(j->>'window_id')::uuid;
 select * into neww from public.pickup_windows where id=p_window;
 if oldw.service_date<>neww.service_date and (j->>'stock_reserved')::boolean then
  for x in select product_id,sum(quantity)::integer quantity from app_private.order_lines(p_kind,p_id) group by product_id order by product_id loop
   update public.daily_stock set allocated=allocated+x.quantity,updated_at=now() where bar_id=(j->>'bar_id')::uuid and product_id=x.product_id and service_date=neww.service_date;
   if not found then raise exception 'Scorte non configurate per la nuova data';end if;
   if j->>'status'='confirmed' then update public.daily_stock set allocated=allocated-x.quantity,updated_at=now()
    where bar_id=(j->>'bar_id')::uuid and product_id=x.product_id and service_date=oldw.service_date;end if;
  end loop;
 end if;
 if p_kind='individual' then update public.orders set pickup_window_id=p_window,updated_at=now() where id=p_id;
 else update public.group_orders set pickup_window_id=p_window,updated_at=now() where id=p_id;
  update public.group_drafts set pickup_window_id=p_window where id=(j->>'group_id')::uuid;end if;
end;$$;
revoke all on function app_private.move_order_window(text,uuid,uuid) from public,anon,authenticated,service_role;
create function public.respond_order_exception(p_change uuid,p_action text,p_window uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare c public.order_change_requests%rowtype;k text;v_id uuid;j jsonb;
begin
 select * into c from public.order_change_requests where id=p_change for update;
 if not found or c.owner_id<>auth.uid() or c.state<>'customer_pending' or c.expires_at<now() or p_action not in ('accept','reject','cancel','alternative')
 then raise exception 'Proposta non disponibile';end if;
 k:=case when c.order_id is null then 'group' else 'individual' end;v_id:=coalesce(c.order_id,c.group_order_id);
 j:=app_private.order_scope(k,v_id,'owner');
 if p_action='cancel' then perform app_private.cancel_workflow_order(k,v_id,'Annullamento dopo proposta del personale',c.id);
 elsif c.kind='substitution' then perform app_private.apply_order_substitution(c.id,p_action='reject');return;
 elsif p_action in ('accept','alternative') then perform app_private.move_order_window(k,v_id,coalesce(p_window,(c.payload->>'window_id')::uuid));
 end if;
 update public.order_change_requests set state=case when p_action='reject' then 'rejected' else 'applied' end,resolved_at=now() where id=c.id;
 perform app_private.notify_order_change(k,v_id,'Risposta alla proposta di orario registrata. La fascia originale rimane finché non accetti una modifica.');
end;$$;
create function public.cancel_workflow_order(p_kind text,p_order uuid,p_key uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;v_at timestamptz;
begin
 j:=app_private.order_scope(p_kind,p_order,'owner');
 select (w.service_date+w.starts_at) at time zone s.timezone-make_interval(mins=>s.cancel_cutoff_minutes) into v_at
 from public.pickup_windows w join public.schools s on s.id=w.school_id where w.id=(j->>'window_id')::uuid;
 if p_key is null or v_at<=now() then raise exception 'Termine di annullamento superato';end if;
 perform app_private.assert_no_pending_checkout(p_kind,p_order);
 perform app_private.cancel_workflow_order(p_kind,p_order,'Annullato dal cliente entro il termine',p_key);
end;$$;
create function public.list_order_changes(p_school uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if auth.uid() is null or (p_school is not null and not app_private.can_serve_group_bar(p_school)) then raise exception 'Accesso non autorizzato';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into j from(select * from public.order_change_requests
 where (p_school is null and owner_id=auth.uid()) or school_id=p_school order by created_at desc limit 200) x;return j;
end;$$;
create function public.maintain_order_changes()
returns integer language plpgsql security definer set search_path='' as $$
declare c public.order_change_requests%rowtype;n integer:=0;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo backend';end if;
 for c in select * from public.order_change_requests where state in ('customer_pending','staff_pending') and expires_at<=now()
 order by expires_at for update skip locked limit 100 loop
  if c.kind='substitution' then perform app_private.apply_order_substitution(c.id,true);
  else update public.order_change_requests set state='expired',resolved_at=now() where id=c.id;
   insert into public.customer_notifications(school_id,user_id,order_id,event_type,message)
   values(c.school_id,c.owner_id,c.order_id,'order_status','Proposta scaduta senza modifica dell’orario originale. Contatta il personale.');end if;n:=n+1;
 end loop;return n;
end;$$;
revoke all on function public.request_order_amendment(uuid,jsonb,uuid),public.decide_order_amendment(uuid,boolean),
 public.propose_order_exception(text,uuid,text,uuid,uuid,uuid,uuid),public.respond_order_exception(uuid,text,uuid),
 public.cancel_workflow_order(text,uuid,uuid),public.list_order_changes(uuid) from public,anon,authenticated;
grant execute on function public.request_order_amendment(uuid,jsonb,uuid),public.decide_order_amendment(uuid,boolean),
 public.propose_order_exception(text,uuid,text,uuid,uuid,uuid,uuid),public.respond_order_exception(uuid,text,uuid),
 public.cancel_workflow_order(text,uuid,uuid),public.list_order_changes(uuid) to authenticated;
revoke all on function public.maintain_order_changes() from public,anon,authenticated;
grant execute on function public.maintain_order_changes() to service_role;
-- All existing readers use current lines; archived versions keep payment FKs intact.
do $$declare f record;d text;begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','app_private') and p.prokind='f' and p.proname not in ('apply_individual_amendment','apply_order_substitution') loop
  d:=pg_get_functiondef(f.oid);
  if d ~* '(from|join)\s+public\.order_items' then
   d:=regexp_replace(d,'\m(from|join)\s+public\.order_items\M','\1 app_private.current_order_items','gi');execute d;
  end if;
 end loop;
end;$$;
create trigger additional_cash_ledger after insert on public.order_additional_receipts
 for each row execute function app_private.capture_cash_receipt();
create function public.collect_workflow_balance(p_kind text,p_order uuid,p_method text,p_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;v_due bigint;v_existing public.order_additional_receipts%rowtype;o public.group_orders%rowtype;
begin
 j:=app_private.order_scope(p_kind,p_order,'staff');
 if p_method is null or p_method not in ('cash','external_pos') or p_key is null or j->>'status' not in ('confirmed','preparing','ready') then raise exception 'Incasso non valido';end if;
 select * into v_existing from public.order_additional_receipts where actor_id=auth.uid() and request_key=p_key;
 if found then if coalesce(v_existing.order_id,v_existing.group_order_id)<>p_order or v_existing.method<>p_method then raise exception 'Idempotenza incoerente';end if;
  return jsonb_build_object('status','duplicate','id',v_existing.id,'amount_cents',v_existing.amount_cents);end if;
 if p_kind='group' then select * into o from public.group_orders where id=p_order;
  if o.pickup_lease_actor is distinct from auth.uid() or o.pickup_lease_until is null or o.pickup_lease_until<=now() then raise exception 'Scansiona il QR del coordinatore prima di incassare';end if;end if;
 perform app_private.assert_no_pending_checkout(p_kind,p_order);
 v_due:=(j->>'total_cents')::bigint-app_private.order_paid_cents(p_kind,p_order);
 if v_due<=0 then raise exception 'Ordine già saldato';end if;
 insert into public.order_additional_receipts(order_id,group_order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
 values(case when p_kind='individual' then p_order end,case when p_kind='group' then p_order end,
 (j->>'school_id')::uuid,(j->>'bar_id')::uuid,auth.uid(),p_key,p_method,v_due) returning * into v_existing;
 if p_kind='individual' then perform app_private.refresh_individual_balance(p_order);end if;
 return jsonb_build_object('status','recorded','id',v_existing.id,'amount_cents',v_due);
end;$$;
revoke all on function public.collect_workflow_balance(text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.collect_workflow_balance(text,uuid,text,uuid) to authenticated;
create or replace function public.record_individual_counter_payment(p_order_id uuid,p_method text,p_request_key uuid)
returns uuid language sql security definer set search_path='' as $$select (public.collect_workflow_balance('individual',p_order_id,p_method,p_request_key)->>'id')::uuid;$$;
create or replace function public.record_group_counter_payment(p_group_order_id uuid,p_method text,p_request_key uuid)
returns jsonb language sql security definer set search_path='' as $$select public.collect_workflow_balance('group',p_group_order_id,p_method,p_request_key);$$;
create or replace function public.cancel_individual_order(p_order_id uuid)
returns void language sql security definer set search_path='' as $$select public.cancel_workflow_order('individual',p_order_id,p_order_id);$$;
create or replace function public.cancel_confirmed_group_order(p_group_order_id uuid)
returns void language sql security definer set search_path='' as $$select public.cancel_workflow_order('group',p_group_order_id,p_group_order_id);$$;
create function public.confirm_cash_refund_return(p_refund uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare r public.cash_refund_obligations%rowtype;j jsonb;v_session uuid;
begin
 select * into r from public.cash_refund_obligations where id=p_refund for update;
 if not found or not app_private.can_serve_group_bar(r.school_id) or length(btrim(coalesce(p_reason,'')))<8 then raise exception 'Personale e motivazione richiesti';end if;
 if r.status='returned' then return;end if;
 j:=app_private.order_scope(case when r.order_id is null then 'group' else 'individual' end,coalesce(r.order_id,r.group_order_id),'internal');
 select id into v_session from public.cash_sessions where bar_id=(j->>'bar_id')::uuid and actor_id=auth.uid() and closed_at is null for update;
 if v_session is null then raise exception 'Apri il turno di cassa per registrare la restituzione fisica';end if;
 insert into public.cash_entries(session_id,school_id,bar_id,actor_id,kind,amount_cents,source_key,reason)
 values(v_session,r.school_id,(j->>'bar_id')::uuid,auth.uid(),'withdrawal',-r.amount_cents,'cash_refund:'||r.id,left(p_reason,500));
 update public.cash_refund_obligations set status='returned',returned_by=auth.uid(),returned_at=now() where id=r.id;
end;$$;
revoke all on function public.confirm_cash_refund_return(uuid,text) from public,anon,authenticated;
grant execute on function public.confirm_cash_refund_return(uuid,text) to authenticated;
create function public.list_cash_refund_obligations(p_school uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb;begin
 if auth.uid() is null or (p_school is not null and not app_private.can_serve_group_bar(p_school)) then raise exception 'Accesso non autorizzato';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into j from(select * from public.cash_refund_obligations
 where (p_school is null and owner_id=auth.uid()) or school_id=p_school order by id limit 200) x;return j;
end;$$;
revoke all on function public.list_cash_refund_obligations(uuid) from public,anon,authenticated;
grant execute on function public.list_cash_refund_obligations(uuid) to authenticated;
-- Paid/cancelled Checkout supplements may be replayed only after signed provider expiry.
create function app_private.release_expired_supplements()
returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status in ('cancelled','failed') and old.status<>'succeeded' then
  update public.order_supplements sp set state=case when o.status in ('cancelled','no_show','delivered') then 'cancelled' else 'available' end,payment_id=null
  from public.group_orders o where o.id=sp.group_order_id and sp.payment_id=new.id and sp.state='pending';
  delete from public.payment_item_allocations where payment_id=new.id and supplement_id is not null;
 end if;return new;
end;$$;
revoke all on function app_private.release_expired_supplements() from public,anon,authenticated;
create trigger checkout_supplement_expiry after update of status on public.payment_attempts for each row execute function app_private.release_expired_supplements();
-- Small extensions to the legacy response shape keep every client and report on the same net ledger.
do $$declare d text;begin
 d:=pg_get_functiondef('public.group_order_details(uuid)'::regprocedure);
 d:=replace(d,$snippet$'paid_cents',v_payments+v_cash$snippet$,$snippet$'paid_cents',app_private.order_paid_cents('group',v_order.id)$snippet$);
 d:=replace(d,'greatest(0,v_order.total_cents-v_payments-v_cash)',$snippet$greatest(0,v_order.total_cents-app_private.order_paid_cents('group',v_order.id))$snippet$);execute d;
 d:=pg_get_functiondef('public.deliver_group_order(uuid)'::regprocedure);
 d:=replace(d,' if v_paid<>v_order.total_cents',$snippet$ v_paid:=app_private.order_paid_cents('group',v_order.id);
 if v_paid<>v_order.total_cents$snippet$);execute d;
 d:=pg_get_functiondef('public.group_payable_lines(uuid)'::regprocedure);
 d:=replace(d,$snippet$('draft','confirmed')$snippet$,$snippet$('draft','confirmed','approval_pending')$snippet$);
 d:=replace(d,' return v_lines;',$snippet$ return v_lines||coalesce((select jsonb_agg(jsonb_build_object('line_id',sp.id,'product_name',sp.description,'quantity',1,'unit_cents',sp.amount_cents,'amount_cents',sp.amount_cents,'payment_state',sp.state)) from public.order_supplements sp join public.group_orders o on o.id=sp.group_order_id where o.group_id=p_group_id and sp.state<>'cancelled'),'[]'::jsonb);$snippet$);execute d;
end;$$;
create function public.workflow_order_details(p_kind text,p_order uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;v_lines jsonb;begin
 j:=app_private.order_scope(p_kind,p_order,'either');
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('name',case when p_kind='individual'
  then (select product_name from public.order_items where id=x.line_id) else (select name from public.group_order_lines where id=x.line_id) end)),'[]'::jsonb)
 into v_lines from app_private.order_lines(p_kind,p_order) x where quantity>0;
 return j||jsonb_build_object('lines',v_lines,'paid_cents',app_private.order_paid_cents(p_kind,p_order),'due_cents',greatest(0,(j->>'total_cents')::bigint-app_private.order_paid_cents(p_kind,p_order)));
end;$$;
create function public.my_payment_documents()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb;begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into j from(select a.id,a.order_id,a.group_id,a.amount_cents,a.currency,a.status,a.created_at,
  (select coalesce(jsonb_agg(jsonb_build_object('amount_cents',r.amount_cents,'status',r.status,'created_at',r.created_at)),'[]'::jsonb) from public.payment_refunds r where r.payment_id=a.id) refunds
  from public.payment_attempts a where payer_id=auth.uid() order by created_at desc limit 100) x;return j;
end;$$;
revoke all on function public.workflow_order_details(text,uuid),public.my_payment_documents() from public,anon,authenticated;
grant execute on function public.workflow_order_details(text,uuid),public.my_payment_documents() to authenticated;
create or replace function public.preview_bar_closure(p_bar_id uuid,p_date date,p_start time,p_end time)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_school uuid;j jsonb;n integer;v_paid bigint;begin
 select school_id into v_school from public.bars where id=p_bar_id;
 if not app_private.can_operate_bar(v_school,false) then raise exception 'Personale non autorizzato';end if;
 with affected as(select o.id,'individual'::text kind,app_private.order_paid_cents('individual',o.id) paid from public.orders o join public.pickup_windows w on w.id=o.pickup_window_id
  where o.bar_id=p_bar_id and w.service_date=p_date and w.starts_at<p_end and w.ends_at>p_start and o.status not in ('cancelled','delivered','no_show')
  union all select o.id,'group',app_private.order_paid_cents('group',o.id) from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id
  where o.bar_id=p_bar_id and w.service_date=p_date and w.starts_at<p_end and w.ends_at>p_start and o.status not in ('cancelled','delivered','no_show'))
 select count(*),coalesce(sum(paid),0),coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'paid_cents',paid)),'[]'::jsonb) into n,v_paid,j from affected;
 return jsonb_build_object('active_orders',n,'paid_cents',v_paid,'orders',j);
end;$$;
create or replace function public.close_bar_interval(p_bar_id uuid,p_date date,p_start time,p_end time,p_kind text,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_id uuid;v_tz text;x record;begin
 select b.school_id,s.timezone into v_school,v_tz from public.bars b join public.schools s on s.id=b.school_id where b.id=p_bar_id and b.is_active for update of b;
 if not app_private.can_operate_bar(v_school,p_kind='planned') or p_kind not in ('planned','extraordinary') or p_kind is null
  or p_date is null or p_date<(now() at time zone v_tz)::date or p_date>(now() at time zone v_tz)::date+365
  or p_start is null or p_end is null or p_start>=p_end or length(btrim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Chiusura non valida o non autorizzata';end if;
 if exists(select 1 from public.bar_closures where bar_id=p_bar_id and service_date=p_date and reopened_at is null and starts_at<p_end and ends_at>p_start) then raise exception 'Chiusura già presente';end if;
 if p_kind='planned' and (public.preview_bar_closure(p_bar_id,p_date,p_start,p_end)->>'active_orders')::int>0 then raise exception 'Usa chiusura straordinaria per ordini attivi';end if;
 insert into public.bar_closures(school_id,bar_id,service_date,starts_at,ends_at,closure_type,reason,created_by)
 values(v_school,p_bar_id,p_date,p_start,p_end,p_kind,p_reason,auth.uid()) returning id into v_id;
 if p_kind='extraordinary' then
  for x in select o.id,'individual'::text kind from public.orders o join public.pickup_windows w on w.id=o.pickup_window_id
   where o.bar_id=p_bar_id and w.service_date=p_date and w.starts_at<p_end and w.ends_at>p_start and o.status not in ('cancelled','delivered','no_show')
   union all select o.id,'group' from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id
   where o.bar_id=p_bar_id and w.service_date=p_date and w.starts_at<p_end and w.ends_at>p_start and o.status not in ('cancelled','delivered','no_show') order by 1 loop
   perform app_private.cancel_workflow_order(x.kind,x.id,'Chiusura straordinaria: '||p_reason,v_id);
  end loop;
 end if;
 insert into public.bar_service_events(school_id,bar_id,actor_id,action,details) values(v_school,p_bar_id,auth.uid(),'closure_created',jsonb_build_object('closure_id',v_id,'kind',p_kind));return v_id;
end;$$;
create table public.customer_favorites(user_id uuid not null references auth.users(id) on delete cascade,product_id uuid not null references public.products(id),primary key(user_id,product_id));
create index favorite_product on public.customer_favorites(product_id);
alter table public.customer_favorites enable row level security;
revoke all on public.customer_favorites from public,anon,authenticated;
grant select,insert,delete on public.customer_favorites to authenticated;
create policy favorite_own on public.customer_favorites for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
commit;
