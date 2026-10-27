-- BreakApp 31: verified same-day offline individual pickup, cash recovery, Stripe double-charge refunds.
begin;
create table public.offline_order_pickups(
 offline_event_id uuid primary key references public.offline_events_inbox(id) on delete restrict,
 order_id uuid not null unique references public.orders(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 collected_cents bigint not null check(collected_cents>=0),
 stripe_refund_id uuid references public.payment_refunds(id) on delete restrict,
 posted_at timestamptz not null default now()
);
create index offline_order_pickups_order on public.offline_order_pickups(order_id);
create index offline_order_pickups_school on public.offline_order_pickups(school_id);
create index offline_order_pickups_actor on public.offline_order_pickups(actor_id);
create index offline_order_pickups_refund on public.offline_order_pickups(stripe_refund_id);
alter table public.offline_order_pickups enable row level security;
revoke all on public.offline_order_pickups from public,anon,authenticated;

create or replace function public.offline_ready_order_manifest(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $ready_offline_manifest$
declare v_today date;v_orders jsonb;
begin
 if not app_private.has_barista_role(p_school,auth.uid()) then
  raise exception 'Manifest consegne accessibile solo al Barista';end if;
 select (now() at time zone timezone)::date into v_today
 from public.schools where id=p_school and is_active;
 if v_today is null then raise exception 'Scuola non disponibile';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',o.id,'bar_id',o.bar_id,'display_no',o.display_no,
  'pickup_token',o.pickup_token,'total_cents',o.total_cents,
  'payment_status',o.payment_status,'payment_method',o.payment_method,
  'server_updated_at',o.updated_at) order by o.display_no),'[]'::jsonb)
 into v_orders
 from (select o.* from public.orders o
  join public.pickup_windows w on w.id=o.pickup_window_id
  where o.school_id=p_school and w.service_date=v_today
    and o.status='ready' and o.payment_status in ('paid','due')
  order by o.created_at desc limit 500) o;
 return jsonb_build_object('school_id',p_school,'service_date',v_today,
  'synced_at',now(),'orders',v_orders);
end;$ready_offline_manifest$;

create or replace function app_private.post_offline_order_pickup(p_event uuid,p_force_review boolean)
returns jsonb language plpgsql security definer set search_path=''
as $post_offline_pickup$
declare v_event public.offline_events_inbox%rowtype;
 v_lease public.staff_offline_leases%rowtype;
 v_order public.orders%rowtype;v_window public.pickup_windows%rowtype;
 v_method text;v_amount bigint;v_token uuid;v_order_id uuid;
 v_attempt public.payment_attempts%rowtype;v_refund uuid;
begin
 select * into v_event from public.offline_events_inbox where id=p_event for update;
 if not found then raise exception 'Evento non trovato';end if;
 if exists(select 1 from public.offline_order_pickups where offline_event_id=p_event)
 then return jsonb_build_object('status','duplicate');end if;
 if v_event.event_kind<>'cash_pickup' or v_event.status='rejected'
 then raise exception 'Evento non consegnabile';end if;
 if p_force_review then
  if v_event.status<>'approved' or
   not app_private.can_review_school_offline(v_event.school_id)
  then raise exception 'Approvazione Admin 2FA richiesta';end if;
 else
  if v_event.status<>'quarantined' or v_event.barista_id<>auth.uid()
   or not app_private.has_barista_role(v_event.school_id,auth.uid())
  then raise exception 'Barista autore richiesto';end if;
  select * into v_lease from public.staff_offline_leases
   where barista_id=v_event.barista_id for update;
  if not found or v_lease.device_id<>v_event.device_id
   or v_lease.generation<>v_event.lease_generation
   or v_lease.expires_at<=now() or v_lease.revoked_at is not null
   or v_event.local_recorded_at is null
   or v_event.local_recorded_at<v_lease.issued_at
   or v_event.local_recorded_at>v_lease.expires_at
   or v_event.local_recorded_at>v_event.received_at+interval '2 minutes'
  then return jsonb_build_object('status','quarantined',
   'reason','Lease revocato, scaduto o data dubbia');end if;
 end if;
 if v_event.payload->>'order_id' is null
  or v_event.payload->>'pickup_token' is null
  or v_event.payload->>'bar_id' is null
  or (v_event.payload->>'collected_cents')!~ '^[0-9]{1,9}$'
 then return jsonb_build_object('status','quarantined',
  'reason','Riferimenti ordine o denaro invalidi');end if;
 v_order_id:=(v_event.payload->>'order_id')::uuid;
 v_token:=(v_event.payload->>'pickup_token')::uuid;
 v_amount:=(v_event.payload->>'collected_cents')::bigint;
 select * into v_order from public.orders where id=v_order_id for update;
 if not found or v_order.school_id<>v_event.school_id
  or v_order.pickup_token<>v_token or v_order.bar_id<>(v_event.payload->>'bar_id')::uuid
 then raise exception 'Ordine non appartenente al tenant o QR non verificato';end if;
 if v_order.status<>'ready' or exists(select 1 from public.offline_order_pickups
  where order_id=v_order.id)
 then return jsonb_build_object('status','quarantined',
  'reason','Ordine già gestito o non più pronto');end if;
 select * into v_window from public.pickup_windows where id=v_order.pickup_window_id;
 if v_window.service_date<>(v_event.local_recorded_at at time zone
     (select timezone from public.schools where id=v_order.school_id))::date
 then return jsonb_build_object('status','quarantined',
  'reason','Manifest di data differente');end if;
 if v_amount=0 then
  if v_order.payment_status<>'paid'
   then return jsonb_build_object('status','quarantined',
    'reason','Il pagamento non risulta completo');end if;
 elsif v_amount=v_order.total_cents and v_amount>0 then
  if exists(select 1 from public.counter_payments where order_id=v_order.id)
  then return jsonb_build_object('status','quarantined',
    'reason','Altro incasso al banco già contabilizzato');end if;
  if exists(select 1 from public.payment_attempts a
     where a.order_id=v_order.id and a.status in ('initiated','requires_action','processing'))
   then return jsonb_build_object('status','quarantined',
     'reason','Checkout Stripe ancora aperto: attendere webhook firmato');end if;
  if v_order.payment_status='paid' then
   -- Cash physically accepted offline + Stripe settled online: preserve cash;
   -- refund the actual original Stripe payer, not the order beneficiary.
   select * into v_attempt from public.payment_attempts
   where order_id=v_order.id and status='succeeded' for update;
   if not found or v_attempt.stripe_payment_intent_id is null
     or v_attempt.amount_cents<>v_amount
   then return jsonb_build_object('status','quarantined',
    'reason','Pagamento preesistente senza riferimento Stripe univoco');end if;
   if exists(select 1 from public.payment_refunds where payment_id=v_attempt.id
    and status in ('pending','processing','succeeded','review'))
   then return jsonb_build_object('status','quarantined',
    'reason','Rimborso precedente: necessaria verifica amministrativa');end if;
   insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason)
   values(v_attempt.id,p_event,v_amount,'pending',
     'Doppio incasso: contanti ricevuti offline e checkout Stripe online')
   returning id into v_refund;
  elsif v_order.payment_status<>'due' then
   return jsonb_build_object('status','quarantined',
    'reason','Stato del pagamento non conciliabile');end if;
  insert into public.counter_payments(school_id,bar_id,order_id,
   actor_id,method,amount_cents,request_key)
  values(v_order.school_id,v_order.bar_id,v_order.id,
   v_event.barista_id,'cash',v_amount,p_event);
 else
  return jsonb_build_object('status','quarantined',
   'reason','Contanti non corrispondenti al totale della ricevuta');end if;
 insert into public.offline_order_pickups(offline_event_id,order_id,school_id,
  actor_id,collected_cents,stripe_refund_id)
 values(p_event,v_order.id,v_order.school_id,v_event.barista_id,v_amount,v_refund);
 update public.orders set status='delivered',payment_status='paid',
  updated_at=now() where id=v_order.id;
 insert into public.order_audit(order_id,school_id,actor_id,action)
 values(v_order.id,v_order.school_id,v_event.barista_id,
  case when v_amount=0 then 'offline:delivered_paid'
   else 'offline:cash_paid_and_delivered' end);
 update public.offline_events_inbox set status='applied',
  review_reason=case when v_refund is not null
   then 'Cash contabilizzato; rimborso Stripe in elaborazione' else 'Consegna sincronizzata' end,
  reviewed_at=case when p_force_review then reviewed_at else now() end,
  reviewed_by=case when p_force_review then reviewed_by else auth.uid() end
 where id=p_event;
 return jsonb_build_object('status','applied','order_id',v_order.id,
  'cash_cents',v_amount,'refund_pending',v_refund is not null);
end;$post_offline_pickup$;

create or replace function public.reconcile_my_offline_pickup_event(p_event uuid)
returns jsonb language plpgsql security definer set search_path=''
as $reconcile_pickup$
begin
 if auth.uid() is null then raise exception 'Utente richiesto';end if;
 return app_private.post_offline_order_pickup(p_event,false);
end;$reconcile_pickup$;
create or replace function public.apply_approved_offline_pickup_event(p_event uuid)
returns jsonb language plpgsql security definer set search_path=''
as $approved_pickup$
begin
 if auth.uid() is null then raise exception 'Admin richiesto';end if;
 return app_private.post_offline_order_pickup(p_event,true);
end;$approved_pickup$;

-- Also dispatch individual manual/collision refunds, not just group line refunds.
create or replace function public.list_group_refunds_for_dispatch(p_limit integer default 15)
returns table(refund_id uuid,account text,payment_intent text,amount_cents bigint)
language plpgsql security definer set search_path=''
as $dispatch_group_refunds$
begin
 if auth.jwt()->>'role'<>'service_role' then raise exception 'Solo server';end if;
 if p_limit is null or p_limit not between 1 and 30 then raise exception 'Limite non valido';end if;
 return query select r.id,a.stripe_account_id,a.stripe_payment_intent_id,r.amount_cents
  from public.payment_refunds r
  join public.payment_attempts a on a.id=r.payment_id
  where r.status in ('pending','processing') and r.stripe_refund_id is null
    and r.created_at>=now()-interval '23 hours'
    and a.status='succeeded' and a.stripe_payment_intent_id is not null
  order by r.created_at,r.id limit p_limit;
end;$dispatch_group_refunds$;

revoke all on function app_private.post_offline_order_pickup(uuid,boolean) from public,anon,authenticated;
revoke all on function public.offline_ready_order_manifest(uuid),
 public.reconcile_my_offline_pickup_event(uuid),
 public.apply_approved_offline_pickup_event(uuid) from public,anon,authenticated;
grant execute on function public.offline_ready_order_manifest(uuid),
 public.reconcile_my_offline_pickup_event(uuid),
 public.apply_approved_offline_pickup_event(uuid) to authenticated;
commit;
