-- BreakApp 27: atomic confirmation, stock, unique QR and payment-at-counter
-- for group orders. Does not claim that multi-payer Stripe is yet enabled.
begin;
alter table public.group_drafts drop constraint group_drafts_status_check;
alter table public.group_drafts add constraint group_drafts_status_check
 check(status in ('draft','expired','cancelled','confirmed'));

create table public.group_orders (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null unique references public.group_drafts(id) on delete restrict,
 school_id uuid not null,
 bar_id uuid not null,
 pickup_window_id uuid not null,
 coordinator_id uuid not null references auth.users(id) on delete restrict,
 request_key uuid not null,
 status text not null check(status in ('confirmed','preparing','ready','delivered','cancelled','no_show')),
 total_cents bigint not null check(total_cents between 0 and 999999999),
 pickup_token uuid not null unique default gen_random_uuid(),
 pickup_lease_until timestamptz,
 pickup_lease_actor uuid references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(coordinator_id,request_key),
 unique(school_id,bar_id,id),
 foreign key(school_id,bar_id) references public.bars(school_id,id) on delete restrict,
 foreign key(school_id,bar_id,pickup_window_id)
   references public.pickup_windows(school_id,bar_id,id) on delete restrict
);
create index group_orders_bar_status on public.group_orders(bar_id,status,created_at desc);
create index group_orders_coordinator on public.group_orders(coordinator_id,created_at desc);
create index group_orders_window_scope on public.group_orders(school_id,bar_id,pickup_window_id);
create index group_orders_lease_actor on public.group_orders(pickup_lease_actor);
create table public.group_order_lines (
 id uuid primary key default gen_random_uuid(),
 group_order_id uuid not null references public.group_orders(id) on delete restrict,
 group_cart_item_id uuid not null unique references public.group_cart_items(id) on delete restrict,
 beneficiary_id uuid not null references auth.users(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,
 name text not null,
 quantity integer not null check(quantity between 1 and 1000),
 unit_cents integer not null check(unit_cents>=0),
 subtotal_cents bigint generated always as (quantity::bigint*unit_cents::bigint) stored,
 unique(group_order_id,product_id,beneficiary_id)
);
create index group_order_lines_order on public.group_order_lines(group_order_id);
create index group_order_lines_beneficiary on public.group_order_lines(beneficiary_id);
create index group_order_lines_product on public.group_order_lines(product_id);

create table public.group_counter_payments(
 id uuid primary key default gen_random_uuid(),
 group_order_id uuid not null unique references public.group_orders(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 bar_id uuid not null references public.bars(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 request_key uuid not null,
 method text not null check(method in ('cash','external_pos')),
 amount_cents bigint not null check(amount_cents>0),
 paid_at timestamptz not null default now(),
 unique(group_order_id,request_key)
);
create index group_counter_payments_actor on public.group_counter_payments(actor_id);
create index group_counter_payments_school on public.group_counter_payments(school_id);
create index group_counter_payments_bar on public.group_counter_payments(bar_id);

create table public.group_order_audit (
 id bigint generated always as identity primary key,
 group_order_id uuid not null references public.group_orders(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 action text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index group_audit_order on public.group_order_audit(group_order_id,created_at desc);
create index group_audit_actor on public.group_order_audit(actor_id);

alter table public.group_orders enable row level security;
alter table public.group_order_lines enable row level security;
alter table public.group_counter_payments enable row level security;
alter table public.group_order_audit enable row level security;
revoke all on public.group_orders,public.group_order_lines,
 public.group_counter_payments,public.group_order_audit from public,anon,authenticated;

-- Reuse exactly the same server-side pause/closure/opening-hours guard
-- as for individual orders; the group table has matching scope columns.
create trigger group_orders_service_guard before insert on public.group_orders
 for each row execute function app_private.guard_new_order_service();

create or replace function app_private.can_serve_group_bar(p_school uuid)
returns boolean language sql stable security definer set search_path=''
as $staff$
 select auth.uid() is not null
   and not exists(select 1 from app_private.platform_admins where user_id=auth.uid())
   and exists(select 1 from public.school_memberships m
     join public.role_assignments r on r.membership_id=m.id
     where m.user_id=auth.uid() and m.school_id=p_school
      and m.membership_status='active'
      and (r.role_code='bartender' or
       (r.role_code='school_admin' and auth.jwt()->>'aal'='aal2')));
$staff$;
revoke all on function app_private.can_serve_group_bar(uuid) from public,anon,authenticated;

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
  v_total:=v_total+v_item.quantity::bigint*v_product.price_cents;
  v_units:=v_units+v_item.quantity;
  if v_total>999999999 then raise exception 'Importo del gruppo troppo elevato';end if;
 end loop;
 if v_count=0 then raise exception 'Il gruppo non contiene prodotti';end if;
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
 select v_order,i.id,i.user_id,i.product_id,p.name,i.quantity,p.price_cents
 from public.group_cart_items i join public.group_members m
  on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 join public.products p on p.id=i.product_id
 where i.group_id=p_group_id;
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
 select coalesce(sum(a.amount_cents),0) into v_payments
 from public.payment_item_allocations a join public.payment_attempts p on p.id=a.payment_id
  where p.group_id=v_order.group_id and p.status='succeeded';
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

-- Single pickup lease, 10m, acquired only by authenticated school staff.
create or replace function public.scan_group_pickup(p_pickup_token uuid)
returns jsonb language plpgsql security definer set search_path=''
as $group_scan$
declare v_order public.group_orders%rowtype;
begin
 if p_pickup_token is null then raise exception 'QR gruppo non valido';end if;
 select * into v_order from public.group_orders where pickup_token=p_pickup_token for update;
 if not found or not app_private.can_serve_group_bar(v_order.school_id)
 then raise exception 'QR non accessibile';end if;
 if v_order.status not in ('confirmed','preparing','ready')
 then raise exception 'Ordine gruppo non ritirabile';end if;
 if v_order.pickup_lease_until>now() and v_order.pickup_lease_actor<>auth.uid()
 then raise exception 'Ritiro gestito da un altro Barista: attendere 10 minuti';end if;
 update public.group_orders set pickup_lease_actor=auth.uid(),
  pickup_lease_until=now()+interval '10 minutes',updated_at=now()
  where id=v_order.id;
 insert into public.group_order_audit(group_order_id,actor_id,action)
 values(v_order.id,auth.uid(),'pickup_scanned');
 return jsonb_build_object('id',v_order.id,'status',v_order.status,
  'lease_expires_at',now()+interval '10 minutes');
end;$group_scan$;

create or replace function public.advance_group_order(
 p_group_order_id uuid,p_next text
) returns void language plpgsql security definer set search_path=''
as $group_advance$
declare v_order public.group_orders%rowtype;
begin
 select * into v_order from public.group_orders where id=p_group_order_id for update;
 if not found or not app_private.can_serve_group_bar(v_order.school_id)
 then raise exception 'Operazione non autorizzata';end if;
 if not ((v_order.status='confirmed' and p_next in ('preparing','ready'))
   or (v_order.status='preparing' and p_next='ready'))
 then raise exception 'Transizione di preparazione gruppo non valida';end if;
 update public.group_orders set status=p_next,updated_at=now() where id=v_order.id;
 insert into public.group_order_audit(group_order_id,actor_id,action)
 values(v_order.id,auth.uid(),'status:'||p_next);
end;$group_advance$;

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
 select coalesce(sum(a.amount_cents),0) into v_paid
  from public.payment_item_allocations a join public.payment_attempts p on p.id=a.payment_id
  where p.group_id=v_order.group_id and p.status='succeeded';
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
 select coalesce(sum(a.amount_cents),0) into v_paid
  from public.payment_item_allocations a join public.payment_attempts p on p.id=a.payment_id
  where p.group_id=v_order.group_id and p.status='succeeded';
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


create or replace function public.list_my_confirmed_group_orders()
returns jsonb language sql stable security definer set search_path=''
as $group_mine$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',o.id,'group_id',o.group_id,'status',o.status,
  'title',g.title,'total_cents',o.total_cents,'coordinator',o.coordinator_id=auth.uid(),
  'created_at',o.created_at) order by o.created_at desc),'[]'::jsonb)
 from public.group_orders o join public.group_drafts g on g.id=o.group_id
 join public.group_members m on m.group_id=o.group_id
 where m.user_id=auth.uid() and m.status='accepted';
$group_mine$;

create or replace function public.list_staff_group_orders(p_school uuid,p_bar uuid)
returns jsonb language plpgsql security definer set search_path=''
as $group_staff_list$
declare v_orders jsonb;
begin
 if not app_private.can_serve_group_bar(p_school)
 then raise exception 'Ruolo personale non verificato';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',o.id,'status',o.status,'title',g.title,
  'total_cents',o.total_cents,'pickup_window_id',o.pickup_window_id,
  'created_at',o.created_at) order by o.created_at desc),'[]'::jsonb)
 into v_orders from (select * from public.group_orders
  where school_id=p_school and (p_bar is null or bar_id=p_bar)
  order by created_at desc limit 100) o
 join public.group_drafts g on g.id=o.group_id;
 return v_orders;
end;$group_staff_list$;

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
      ('initiated','requires_action','processing','succeeded','review'))
 then raise exception 'Ordine con pagamento: attendere rimborso verificato prima di cancellare';end if;
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
 insert into public.group_order_audit(group_order_id,actor_id,action)
 values(v_order.id,auth.uid(),'cancelled');
end;$group_cancel_confirmed$;

revoke all on function public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz),
 public.group_order_details(uuid),public.scan_group_pickup(uuid),
 public.advance_group_order(uuid,text),public.record_group_counter_payment(uuid,text,uuid),
 public.deliver_group_order(uuid),public.list_my_confirmed_group_orders(),
 public.list_staff_group_orders(uuid,uuid),public.cancel_confirmed_group_order(uuid)
 from public,anon,authenticated;
grant execute on function public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz),
 public.group_order_details(uuid),public.scan_group_pickup(uuid),
 public.advance_group_order(uuid,text),public.record_group_counter_payment(uuid,text,uuid),
 public.deliver_group_order(uuid),public.list_my_confirmed_group_orders(),
 public.list_staff_group_orders(uuid,uuid),public.cancel_confirmed_group_order(uuid)
 to authenticated;
commit;
