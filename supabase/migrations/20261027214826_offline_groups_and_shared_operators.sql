begin;
alter table public.offline_events_inbox drop constraint offline_events_inbox_event_kind_check;
alter table public.offline_events_inbox add constraint offline_events_inbox_event_kind_check check(event_kind in ('counter_sale','cash_pickup','shift_change','group_pickup'));
create table app_private.offline_manifests(
 id uuid primary key default gen_random_uuid(),barista_id uuid not null references auth.users(id),school_id uuid not null references public.schools(id),
 device_id uuid not null,generation bigint not null,payload jsonb not null,issued_at timestamptz not null default now()
);
create index manifest_barista on app_private.offline_manifests(barista_id,issued_at);
create index manifest_school on app_private.offline_manifests(school_id);
alter table app_private.offline_manifests enable row level security;
revoke all on app_private.offline_manifests from public,anon,authenticated,service_role;
create table public.offline_group_pickups(
 offline_event_id uuid primary key references public.offline_events_inbox(id),group_order_id uuid not null unique references public.group_orders(id),
 manifest_id uuid not null references app_private.offline_manifests(id),actor_id uuid not null references auth.users(id),
 collected_cents bigint not null check(collected_cents>=0),posted_at timestamptz not null default now()
);
create index offline_group_manifest on public.offline_group_pickups(manifest_id);
create index offline_group_actor on public.offline_group_pickups(actor_id);
alter table public.offline_group_pickups enable row level security;
revoke all on public.offline_group_pickups from public,anon,authenticated;
alter function public.offline_ready_order_manifest(uuid) rename to legacy_individual_manifest;
alter function public.legacy_individual_manifest(uuid) set schema app_private;
revoke all on function app_private.legacy_individual_manifest(uuid) from public,anon,authenticated,service_role;
create function public.offline_ready_order_manifest(p_school uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;groups jsonb;l public.staff_offline_leases%rowtype;v_id uuid;begin
 if not app_private.has_barista_role(p_school,auth.uid()) then raise exception 'Barista richiesto';end if;
 select * into l from public.staff_offline_leases where barista_id=auth.uid() and school_id=p_school and revoked_at is null and expires_at>now();
 if not found then raise exception 'Autorizza il dispositivo prima del manifest';end if;
 j:=app_private.legacy_individual_manifest(p_school);
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'kind','group','bar_id',o.bar_id,'display_no','G-'||left(o.id::text,8),
 'pickup_token',o.pickup_token,'total_cents',o.total_cents,'due_cents',greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id)),
 'payment_status',case when app_private.order_paid_cents('group',o.id)>=o.total_cents then 'paid' else 'due' end,
 'server_updated_at',o.updated_at,'can_pickup_at',case when b.preparation_mode='ready_made' then (w.service_date+w.starts_at) at time zone s.timezone else now() end)), '[]'::jsonb)
 into groups from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id join public.bars b on b.id=o.bar_id
 where o.school_id=p_school and o.status='ready' and w.service_date=(now() at time zone s.timezone)::date;
 j:=jsonb_set(j,'{orders}',coalesce((select jsonb_agg(x||jsonb_build_object('kind','individual','due_cents',greatest(0,(x->>'total_cents')::bigint-app_private.order_paid_cents('individual',(x->>'id')::uuid)),
 'can_pickup_at',(select case when b.preparation_mode='ready_made' then (w.service_date+w.starts_at) at time zone s.timezone else now() end from public.orders o join public.bars b on b.id=o.bar_id join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id where o.id=(x->>'id')::uuid))) from jsonb_array_elements(j->'orders') x),'[]'::jsonb)||groups);
 insert into app_private.offline_manifests(barista_id,school_id,device_id,generation,payload) values(auth.uid(),p_school,l.device_id,l.generation,j) returning id into v_id;
 return j||jsonb_build_object('snapshot_id',v_id);
end;$$;
revoke all on function public.offline_ready_order_manifest(uuid) from public,anon,authenticated;
grant execute on function public.offline_ready_order_manifest(uuid) to authenticated;

create function app_private.post_offline_group_pickup(p_event uuid,p_force boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.offline_events_inbox%rowtype;l public.staff_offline_leases%rowtype;m app_private.offline_manifests%rowtype;
 o public.group_orders%rowtype;snap jsonb;v_amount bigint;v_due bigint;v_excess bigint;v_piece bigint;v_available bigint;a record;
begin
 select * into e from public.offline_events_inbox where id=p_event for update;
 if e.event_kind<>'group_pickup' then raise exception 'Tipo evento non valido';end if;
 if e.status='applied' then return jsonb_build_object('status','duplicate');end if;
 if p_force then
  if e.status<>'approved' or not app_private.can_review_school_offline(e.school_id) then raise exception 'Revisione Admin con 2FA richiesta';end if;
 else
  if e.barista_id<>auth.uid() or not app_private.has_barista_role(e.school_id,auth.uid()) then raise exception 'Autore richiesto';end if;
  select * into l from public.staff_offline_leases where barista_id=e.barista_id for update;
  if l.device_id is distinct from e.device_id or l.generation<>e.lease_generation or l.revoked_at is not null or l.expires_at<=now()
   or e.local_recorded_at is null or e.local_recorded_at<l.issued_at or e.local_recorded_at>least(l.expires_at,e.received_at+interval '2 minutes')
  then return jsonb_build_object('status','quarantined','reason','Lease revocato/scaduto o tempo non verificabile');end if;
 end if;
 select * into m from app_private.offline_manifests where id=(e.payload->>'snapshot_id')::uuid and barista_id=e.barista_id and school_id=e.school_id
  and device_id=e.device_id and generation=e.lease_generation;
 if not found then return jsonb_build_object('status','quarantined','reason','Manifest server non verificabile');end if;
 select x into snap from jsonb_array_elements(m.payload->'orders') x where x->>'id'=e.payload->>'order_id' and x->>'kind'='group';
 select * into o from public.group_orders where id=(e.payload->>'order_id')::uuid for update;
 v_amount:=(e.payload->>'collected_cents')::bigint;
 if snap is null or o.school_id<>e.school_id or o.pickup_token::text<>e.payload->>'pickup_token' or o.status<>'ready'
  or o.total_cents<>(snap->>'total_cents')::bigint or v_amount<>(snap->>'due_cents')::bigint
  or (not p_force and e.local_recorded_at<(snap->>'can_pickup_at')::timestamptz)
 then return jsonb_build_object('status','quarantined','reason','QR, fascia, importo o stato diverso dal manifest');end if;
 perform app_private.assert_no_pending_checkout('group',o.id);
 v_due:=greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id));v_excess:=greatest(0,v_amount-v_due);
 if v_amount=0 and v_due>0 then return jsonb_build_object('status','quarantined','reason','Saldo non completo');end if;
 if v_amount>0 then
  if v_excess>0 and not p_force and (select coalesce(sum(pa.amount_cents),0) from public.payment_attempts pa where pa.group_id=o.group_id and pa.status='succeeded' and pa.updated_at>=m.issued_at)<v_excess
   then return jsonb_build_object('status','quarantined','reason','Eccedenza non attribuibile con certezza ai pagatori successivi al manifest');end if;
  insert into public.order_additional_receipts(group_order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
  values(o.id,o.school_id,o.bar_id,e.barista_id,e.id,'cash',v_amount);
  for a in select * from public.payment_attempts where group_id=o.group_id and status='succeeded'
   and (p_force or updated_at>=m.issued_at) order by updated_at desc,id for update loop
   exit when v_excess=0;
   select greatest(0,a.amount_cents-coalesce(sum(amount_cents),0)) into v_available from public.payment_refunds where payment_id=a.id;
   v_piece:=least(v_excess,v_available);
   if v_piece>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
    values(a.id,e.id,v_piece,'pending','Doppio incasso gruppo: contanti offline e Stripe',jsonb_build_object('kind','group','order_id',o.id));v_excess:=v_excess-v_piece;end if;
  end loop;
  if v_excess>0 then raise exception 'Eccedenza non riconciliata: revisione necessaria';end if;
 end if;
 insert into public.offline_group_pickups(offline_event_id,group_order_id,manifest_id,actor_id,collected_cents) values(e.id,o.id,m.id,e.barista_id,v_amount);
 update public.group_orders set status='delivered',pickup_lease_until=null,pickup_lease_actor=null,updated_at=now() where id=o.id;
 insert into public.group_order_audit(group_order_id,actor_id,action,details) values(o.id,e.barista_id,'offline:delivered',jsonb_build_object('event_id',e.id,'cash_cents',v_amount));
 update public.offline_events_inbox set status='applied',review_reason='Consegna gruppo riconciliata',reviewed_at=now() where id=e.id;
 return jsonb_build_object('status','applied','group_order_id',o.id,'refund_pending',v_amount>v_due);
end;$$;
revoke all on function app_private.post_offline_group_pickup(uuid,boolean) from public,anon,authenticated,service_role;
create function public.reconcile_my_offline_group_pickup(p_event uuid)
returns jsonb language sql security definer set search_path='' as $$select app_private.post_offline_group_pickup(p_event,false);$$;
create function public.apply_approved_offline_group_pickup(p_event uuid)
returns jsonb language sql security definer set search_path='' as $$select app_private.post_offline_group_pickup(p_event,true);$$;
revoke all on function public.reconcile_my_offline_group_pickup(uuid),public.apply_approved_offline_group_pickup(uuid) from public,anon,authenticated;
grant execute on function public.reconcile_my_offline_group_pickup(uuid),public.apply_approved_offline_group_pickup(uuid) to authenticated;
do $$declare d text;begin
 d:=pg_get_functiondef('public.stage_my_offline_event(uuid,bigint,uuid,text,timestamptz,jsonb)'::regprocedure);
 d:=replace(d,$fragment$('counter_sale','cash_pickup','shift_change')$fragment$,$fragment$('counter_sale','cash_pickup','shift_change','group_pickup')$fragment$);execute d;
 d:=pg_get_functiondef('app_private.capture_cash_receipt()'::regprocedure);
 d:=replace(d,$fragment$tg_table_name='counter_payments'$fragment$,$fragment$tg_table_name in ('counter_payments','order_additional_receipts')$fragment$);execute d;
end;$$;
create function app_private.post_snapshot_individual_pickup(p_event uuid,p_force boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.offline_events_inbox%rowtype;l public.staff_offline_leases%rowtype;m app_private.offline_manifests%rowtype;
 o public.orders%rowtype;snap jsonb;v_amount bigint;v_due bigint;v_excess bigint;v_piece bigint;v_available bigint;a record;
begin
 select * into e from public.offline_events_inbox where id=p_event for update;
 if e.event_kind<>'cash_pickup' then raise exception 'Tipo evento non valido';end if;
 if e.status='applied' then return jsonb_build_object('status','duplicate');end if;
 if p_force then
  if e.status<>'approved' or not app_private.can_review_school_offline(e.school_id) then raise exception 'Revisione Admin con 2FA richiesta';end if;
 else
  if e.barista_id<>auth.uid() or not app_private.has_barista_role(e.school_id,auth.uid()) then raise exception 'Autore richiesto';end if;
  select * into l from public.staff_offline_leases where barista_id=e.barista_id for update;
  if l.device_id is distinct from e.device_id or l.generation<>e.lease_generation or l.revoked_at is not null or l.expires_at<=now()
   or e.local_recorded_at is null or e.local_recorded_at<l.issued_at or e.local_recorded_at>least(l.expires_at,e.received_at+interval '2 minutes')
  then return jsonb_build_object('status','quarantined','reason','Lease revocato/scaduto o tempo non verificabile');end if;
 end if;
 select * into m from app_private.offline_manifests where id=(e.payload->>'snapshot_id')::uuid and barista_id=e.barista_id and school_id=e.school_id
  and device_id=e.device_id and generation=e.lease_generation;
 if not found then return jsonb_build_object('status','quarantined','reason','Manifest server non verificabile');end if;
 select x into snap from jsonb_array_elements(m.payload->'orders') x where x->>'id'=e.payload->>'order_id' and x->>'kind'='individual';
 select * into o from public.orders where id=(e.payload->>'order_id')::uuid for update;
 v_amount:=(e.payload->>'collected_cents')::bigint;
 if snap is null or o.school_id<>e.school_id or o.pickup_token::text<>e.payload->>'pickup_token' or o.status<>'ready'
  or o.total_cents<>(snap->>'total_cents')::bigint or v_amount<>(snap->>'due_cents')::bigint
  or (not p_force and e.local_recorded_at<(snap->>'can_pickup_at')::timestamptz)
 then return jsonb_build_object('status','quarantined','reason','QR, fascia, importo o stato diverso dal manifest');end if;
 perform app_private.assert_no_pending_checkout('individual',o.id);
 v_due:=greatest(0,o.total_cents-app_private.order_paid_cents('individual',o.id));v_excess:=greatest(0,v_amount-v_due);
 if v_amount=0 and v_due>0 then return jsonb_build_object('status','quarantined','reason','Saldo non completo');end if;
 if v_amount>0 then
  if v_excess>0 and not p_force and (select coalesce(sum(pa.amount_cents),0) from public.payment_attempts pa where pa.order_id=o.id and pa.status='succeeded' and pa.updated_at>=m.issued_at)<v_excess
   then return jsonb_build_object('status','quarantined','reason','Eccedenza non attribuibile con certezza ai pagatori successivi al manifest');end if;
  insert into public.order_additional_receipts(order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
  values(o.id,o.school_id,o.bar_id,e.barista_id,e.id,'cash',v_amount);
  for a in select * from public.payment_attempts where order_id=o.id and status='succeeded'
   and (p_force or updated_at>=m.issued_at) order by updated_at desc,id for update loop
   exit when v_excess=0;
   select greatest(0,a.amount_cents-coalesce(sum(amount_cents),0)) into v_available from public.payment_refunds where payment_id=a.id;
   v_piece:=least(v_excess,v_available);
   if v_piece>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
    values(a.id,e.id,v_piece,'pending','Doppio incasso gruppo: contanti offline e Stripe',jsonb_build_object('kind','individual','order_id',o.id));v_excess:=v_excess-v_piece;end if;
  end loop;
  if v_excess>0 then raise exception 'Eccedenza non riconciliata: revisione necessaria';end if;
 end if;
 insert into public.offline_order_pickups(offline_event_id,order_id,school_id,actor_id,collected_cents) values(e.id,o.id,o.school_id,e.barista_id,v_amount);
 update public.orders set status='delivered',payment_status='paid',updated_at=now() where id=o.id;
 insert into public.order_audit(order_id,school_id,actor_id,action) values(o.id,o.school_id,e.barista_id,'offline:delivered');
 update public.offline_events_inbox set status='applied',review_reason='Consegna gruppo riconciliata',reviewed_at=now() where id=e.id;
 return jsonb_build_object('status','applied','order_id',o.id,'refund_pending',v_amount>v_due);
end;$$;
revoke all on function app_private.post_snapshot_individual_pickup(uuid,boolean) from public,anon,authenticated,service_role;
alter function app_private.post_offline_order_pickup(uuid,boolean) rename to post_legacy_individual_pickup;
create function app_private.post_offline_order_pickup(p_event uuid,p_force_review boolean)
returns jsonb language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.offline_events_inbox where id=p_event and payload?'snapshot_id') then
  return app_private.post_snapshot_individual_pickup(p_event,p_force_review);end if;
 return app_private.post_legacy_individual_pickup(p_event,p_force_review);
end;$$;
revoke all on function app_private.post_offline_order_pickup(uuid,boolean) from public,anon,authenticated,service_role;


create or replace function public.school_financial_report(p_school uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_zone text;v_start timestamptz;v_end timestamptz;v_cash bigint;v_pos bigint;
 v_stripe bigint;v_refunds bigint;v_pending bigint;v_orders bigint;v_groups bigint;
 v_sales bigint;v_conflicts bigint;v_products jsonb;v_name text;
begin
 perform app_private.require_school_report(p_school,p_from,p_to);
 select timezone,name into v_zone,v_name from public.schools where id=p_school;
 v_start:=p_from::timestamp at time zone v_zone;v_end:=(p_to+1)::timestamp at time zone v_zone;
 with receipts as (
  select amount_cents,method from public.order_additional_receipts where school_id=p_school and created_at>=v_start and created_at<v_end
  union all
  select amount_cents,method from public.counter_payments
   where school_id=p_school and created_at>=v_start and created_at<v_end
  union all select amount_cents,method from public.group_counter_payments
   where school_id=p_school and paid_at>=v_start and paid_at<v_end
  union all select amount_cents,method from public.bar_counter_sales
   where school_id=p_school and created_at>=v_start and created_at<v_end
 ) select coalesce(sum(amount_cents) filter(where method='cash'),0),
   coalesce(sum(amount_cents) filter(where method='external_pos'),0) into v_cash,v_pos from receipts;
 select coalesce(sum(amount_cents),0) into v_stripe from public.payment_attempts
  where school_id=p_school and status='succeeded' and created_at>=v_start and created_at<v_end;
 select coalesce(sum(r.amount_cents) filter(where r.status='succeeded'),0),
   coalesce(sum(r.amount_cents) filter(where r.status in ('pending','processing','review','failed')),0)
  into v_refunds,v_pending from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id
  where a.school_id=p_school and r.created_at>=v_start and r.created_at<v_end;
 select count(*) into v_orders from public.orders where school_id=p_school and created_at>=v_start and created_at<v_end;
 select count(*) into v_groups from public.group_orders where school_id=p_school and created_at>=v_start and created_at<v_end;
 select count(*) into v_sales from public.bar_counter_sales where school_id=p_school and created_at>=v_start and created_at<v_end;
 select count(*) into v_conflicts from public.offline_stock_conflicts where school_id=p_school and status='open';
 with lines as (
  select i.product_id,i.product_name name,i.quantity,i.subtotal_cents cents from app_private.current_order_items i
   join public.orders o on o.id=i.order_id where o.school_id=p_school
   and o.status in ('confirmed','preparing','ready','delivered') and o.created_at>=v_start and o.created_at<v_end
  union all select i.product_id,i.name,i.quantity,i.subtotal_cents from public.group_order_lines i
   join public.group_orders o on o.id=i.group_order_id where o.school_id=p_school
   and o.status in ('confirmed','preparing','ready','delivered') and o.created_at>=v_start and o.created_at<v_end
  union all select i.product_id,i.product_name,i.quantity,i.quantity::bigint*i.unit_cents
   from public.bar_counter_sale_items i join public.bar_counter_sales s on s.id=i.sale_id
   where s.school_id=p_school and s.created_at>=v_start and s.created_at<v_end
 ) select coalesce(jsonb_agg(to_jsonb(x) order by x.quantity desc,x.product_id),'[]'::jsonb) into v_products
 from (select product_id,max(name) name,sum(quantity) quantity,sum(cents) amount_cents from lines
  group by product_id order by sum(quantity) desc,product_id limit 100) x;
 return jsonb_build_object('school_id',p_school,'school_name',v_name,'from',p_from,'to',p_to,
  'timezone',v_zone,'cash_cents',v_cash,'external_pos_cents',v_pos,'stripe_gross_cents',v_stripe,
  'stripe_refunded_cents',v_refunds,'stripe_refunds_pending_cents',v_pending,
  'cash_returned_cents',coalesce((select sum(amount_cents) from public.cash_refund_obligations where school_id=p_school and status='returned' and returned_at>=v_start and returned_at<v_end),0),
  'cash_refunds_pending_cents',coalesce((select sum(amount_cents) from public.cash_refund_obligations where school_id=p_school and status='pending'),0),
  'net_recorded_cents',v_cash+v_pos+v_stripe-v_refunds-coalesce((select sum(amount_cents) from public.cash_refund_obligations where school_id=p_school and status='returned' and returned_at>=v_start and returned_at<v_end),0),'individual_orders',v_orders,
  'group_orders',v_groups,'counter_sales',v_sales,'open_stock_conflicts',v_conflicts,
  'products',v_products,'generated_at',now());
end;$$;
create or replace function public.school_order_report_rows(
 p_school uuid,p_from date,p_to date,p_offset integer default 0,p_limit integer default 500
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_zone text;
begin
 perform app_private.require_school_report(p_school,p_from,p_to);
 if p_offset is null or p_offset<0 or p_limit is null or p_limit not between 1 and 1000
 then raise exception 'Paginazione non valida';end if;
 select timezone into v_zone from public.schools where id=p_school;
 with all_orders as (
  select o.id,'individual'::text kind,o.display_no::text reference,o.created_at,
   b.name bar,w.service_date,w.starts_at,o.status,o.total_cents,
   o.payment_status,
   case when o.status in ('cancelled','no_show') or o.payment_status<>'due'
    then 0 else o.total_cents end due_cents
  from public.orders o join public.bars b on b.id=o.bar_id
   join public.pickup_windows w on w.id=o.pickup_window_id
  where o.school_id=p_school and o.created_at>=p_from::timestamp at time zone v_zone
   and o.created_at<(p_to+1)::timestamp at time zone v_zone
  union all
  select o.id,'group','G-'||left(o.id::text,8),o.created_at,b.name,w.service_date,w.starts_at,
   o.status,o.total_cents,
   case when app_private.order_paid_cents('group',o.id)>=o.total_cents then 'paid' else 'due' end,
   case when o.status in ('cancelled','no_show') then 0 else
    greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id)) end
  from public.group_orders o join public.bars b on b.id=o.bar_id
   join public.pickup_windows w on w.id=o.pickup_window_id
   left join public.group_counter_payments c on c.group_order_id=o.id
   left join lateral (select sum(cl.amount_cents) cents from public.group_line_payment_claims cl
    join public.group_order_lines li on li.group_cart_item_id=cl.group_cart_item_id
    where li.group_order_id=o.id and cl.state='paid') paid on true
  where o.school_id=p_school and o.created_at>=p_from::timestamp at time zone v_zone
   and o.created_at<(p_to+1)::timestamp at time zone v_zone
 ) select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]'::jsonb) into v_rows
 from (select * from all_orders order by created_at desc,id offset p_offset limit p_limit) x;
 return v_rows;
end;$$;
commit;
