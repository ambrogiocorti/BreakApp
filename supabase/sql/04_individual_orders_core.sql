-- BreakApp: increment 04 / nucleo prenotazioni individuali con pagamento al ritiro.
-- Dipende da 01_breakapp_foundations.sql e 03_catalog_admin.sql.
-- ESEGUIRE ESCLUSIVAMENTE nel progetto Supabase BreakApp, prima dell'uso del relativo frontend.
-- NON implementa ancora Stripe, approvazioni manuali, ordini di gruppo o offline.
begin;

alter table public.schools
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists pickup_radius_m integer not null default 1000,
  add column if not exists booking_horizon_days integer not null default 30,
  add column if not exists max_unpaid_orders_per_customer integer not null default 3,
  add column if not exists cancel_cutoff_minutes integer not null default 10,
  add column if not exists approval_product_threshold integer,
  add column if not exists approval_amount_threshold_cents integer;

alter table public.schools
  add constraint schools_geo_valid check (
    (latitude is null and longitude is null) or
    (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180)
  ),
  add constraint schools_radius_valid check (pickup_radius_m between 100 and 10000),
  add constraint schools_horizon_valid check (booking_horizon_days between 1 and 365),
  add constraint schools_cancel_cutoff_valid check (cancel_cutoff_minutes between 0 and 1440),
  add constraint schools_unpaid_valid check (max_unpaid_orders_per_customer between 1 and 50),
  add constraint schools_approval_items_valid check
    (approval_product_threshold is null or approval_product_threshold > 0),
  add constraint schools_approval_cents_valid check
    (approval_amount_threshold_cents is null or approval_amount_threshold_cents > 0);

alter table public.bars
  add column if not exists preparation_mode text not null default 'active'
    check (preparation_mode in ('active', 'ready_made'));

create unique index if not exists products_school_bar_id_uk on public.products(school_id,bar_id,id);

create table if not exists public.pickup_windows (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  service_date date not null,
  starts_at time without time zone not null,
  ends_at time without time zone not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (starts_at < ends_at),
  unique (bar_id,service_date,starts_at),
  unique (school_id,bar_id,id),
  foreign key (school_id,bar_id) references public.bars(school_id,id) on delete restrict
);

create table if not exists public.daily_stock (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  product_id uuid not null,
  service_date date not null,
  capacity integer,
  allocated integer not null default 0,
  updated_at timestamptz not null default now(),
  check (capacity is null or capacity >= 0),
  check (allocated >= 0 and (capacity is null or allocated <= capacity)),
  unique (bar_id,product_id,service_date),
  foreign key (school_id,bar_id,product_id)
    references public.products(school_id,bar_id,id) on delete restrict
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  display_no bigint generated always as identity unique,
  school_id uuid not null,
  bar_id uuid not null,
  customer_id uuid not null references auth.users(id) on delete restrict,
  pickup_window_id uuid not null,
  request_key uuid not null,
  status text not null check
    (status in ('confirmed','preparing','ready','delivered','cancelled','no_show')),
  payment_method text not null default 'at_pickup' check (payment_method='at_pickup'),
  payment_status text not null default 'due' check (payment_status in ('due','paid')),
  total_cents bigint not null check (total_cents between 0 and 999999999),
  pickup_token uuid not null default gen_random_uuid() unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(customer_id,request_key),
  unique (school_id,bar_id,id),
  foreign key (school_id,bar_id,pickup_window_id)
    references public.pickup_windows(school_id,bar_id,id) on delete restrict,
  foreign key (school_id,bar_id) references public.bars(school_id,id) on delete restrict
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  order_id uuid not null,
  product_id uuid not null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_cents integer not null check (unit_cents>=0),
  subtotal_cents bigint generated always as (quantity::bigint*unit_cents::bigint) stored,
  unique(order_id,product_id),
  foreign key (school_id,bar_id,order_id)
    references public.orders(school_id,bar_id,id) on delete restrict,
  foreign key (school_id,bar_id,product_id)
    references public.products(school_id,bar_id,id) on delete restrict
);

create table if not exists public.counter_payments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  order_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  method text not null check (method in ('cash','external_pos')),
  amount_cents bigint not null check (amount_cents > 0),
  request_key uuid not null,
  created_at timestamptz not null default now(),
  unique(order_id,request_key),
  unique(order_id),
  foreign key (school_id,bar_id,order_id)
    references public.orders(school_id,bar_id,id) on delete restrict
);

create table if not exists public.order_audit (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete restrict,
  school_id uuid not null references public.schools(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  created_at timestamptz not null default now()
);


-- Non consentire spostamenti retroattivi di una fascia con ordini attivi.
-- La gestione d'impatto/annullamenti dovrà passare da un workflow dedicato.
create or replace function app_private.prevent_booked_window_shift()
returns trigger language plpgsql set search_path=''
as $
begin
  if (new.starts_at is distinct from old.starts_at
      or new.ends_at is distinct from old.ends_at)
    and exists (
      select 1 from public.orders o where o.pickup_window_id=old.id
      and o.status not in ('delivered','cancelled','no_show')
    ) then
    raise exception 'La fascia ha ordini attivi: usa il workflow di modifica con valutazione impatti';
  end if;
  return new;
end;
$;
drop trigger if exists pickup_window_shift_guard on public.pickup_windows;
create trigger pickup_window_shift_guard before update on public.pickup_windows
for each row execute function app_private.prevent_booked_window_shift();
revoke all on function app_private.prevent_booked_window_shift()
from public,anon,authenticated;

create index if not exists pickup_windows_by_day on public.pickup_windows(bar_id,service_date,starts_at);
create index if not exists daily_stock_by_day on public.daily_stock(bar_id,service_date);
create index if not exists orders_staff_queue on public.orders(bar_id,status,created_at);
create index if not exists orders_customer_history on public.orders(customer_id,created_at desc);
create index if not exists order_items_by_order on public.order_items(order_id);

alter table public.pickup_windows enable row level security;
alter table public.daily_stock enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.counter_payments enable row level security;
alter table public.order_audit enable row level security;

revoke all on public.pickup_windows,public.daily_stock,public.orders,
  public.order_items,public.counter_payments,public.order_audit from public,anon,authenticated;

grant select on public.pickup_windows to anon,authenticated;
grant insert (school_id,bar_id,service_date,starts_at,ends_at,is_active) on public.pickup_windows to authenticated;
grant update (is_active,starts_at,ends_at) on public.pickup_windows to authenticated;
grant select on public.daily_stock to authenticated;
grant insert (school_id,bar_id,product_id,service_date,capacity) on public.daily_stock to authenticated;
grant update (capacity) on public.daily_stock to authenticated;
grant select on public.orders, public.order_items, public.counter_payments, public.order_audit to authenticated;

create policy pickup_windows_public on public.pickup_windows for select to anon,authenticated
using (is_active and exists (
  select 1 from public.bars b join public.schools s on s.id=b.school_id
  where b.id=pickup_windows.bar_id and b.school_id=pickup_windows.school_id
  and b.is_active and s.is_active));

create policy pickup_windows_admin_read on public.pickup_windows for select to authenticated
using ((select auth.jwt()->>'aal')='aal2' and exists (
  select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=pickup_windows.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active' and r.role_code='school_admin'));

create policy pickup_windows_admin_insert on public.pickup_windows for insert to authenticated
with check ((select auth.jwt()->>'aal')='aal2' and exists (
  select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=pickup_windows.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active' and r.role_code='school_admin'));

create policy pickup_windows_admin_update on public.pickup_windows for update to authenticated
using ((select auth.jwt()->>'aal')='aal2' and exists (
  select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.school_id=pickup_windows.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active' and r.role_code='school_admin'))
with check ((select auth.jwt()->>'aal')='aal2' and exists (
  select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.school_id=pickup_windows.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active' and r.role_code='school_admin'));

-- Magazzino: i clienti possono vedere la disponibilità pubblica del giorno;
-- modifiche ammesse solo ad Admin con AAL2 o Magazziniere della stessa scuola.
create policy stock_read on public.daily_stock for select to authenticated
using (exists (select 1 from public.bars b join public.schools s on s.id=b.school_id
 where b.id=daily_stock.bar_id and b.school_id=daily_stock.school_id and b.is_active and s.is_active));
create policy stock_staff_insert on public.daily_stock for insert to authenticated
with check (exists (
  select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.school_id=daily_stock.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active'
  and (r.role_code='warehouse_manager' or (r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2'))));
create policy stock_staff_update on public.daily_stock for update to authenticated
using (exists (
  select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.school_id=daily_stock.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active'
  and (r.role_code='warehouse_manager' or (r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2'))))
with check (exists (
  select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.school_id=daily_stock.school_id and m.user_id=(select auth.uid())
  and m.membership_status='active'
  and (r.role_code='warehouse_manager' or (r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2'))));

create policy orders_customer_and_staff_read on public.orders for select to authenticated using (
  customer_id=(select auth.uid()) or exists (
    select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
    where m.school_id=orders.school_id and m.user_id=(select auth.uid())
    and m.membership_status='active'
    and (r.role_code='bartender' or (r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2'))));
create policy order_items_customer_and_staff_read on public.order_items for select to authenticated using (
  exists (select 1 from public.orders o where o.id=order_items.order_id));
create policy counter_payments_customer_and_staff_read on public.counter_payments for select to authenticated using (
  exists (select 1 from public.orders o where o.id=counter_payments.order_id));
create policy order_audit_customer_and_staff_read on public.order_audit for select to authenticated using (
  exists (select 1 from public.orders o where o.id=order_audit.order_id));

-- Chiunque possa eseguire RPC può solo agire sulle proprie prenotazioni e nella
-- scuola selezionata; le funzioni privileged in public richiedono grant espliciti.
-- SECURITY DEFINER è usato SOLO dove serve l'operazione atomica con stock;
-- ogni percorso convalida esplicitamente identità, tenant, ruolo, stato e dati.
create or replace function public.submit_individual_order(
  p_bar_id uuid, p_window_id uuid, p_items jsonb, p_request_key uuid,
  p_latitude double precision, p_longitude double precision,
  p_accuracy_m double precision, p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_window public.pickup_windows%rowtype;
  v_school public.schools%rowtype;
  v_bar public.bars%rowtype;
  v_product record;
  v_stock public.daily_stock%rowtype;
  v_item record;
  v_count integer;
  v_units integer := 0;
  v_total bigint := 0;
  v_distance double precision;
begin
  if v_user is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' then
    raise exception 'Per prenotare è richiesto un account registrato';
  end if;
  if p_request_key is null or p_bar_id is null or p_window_id is null then
    raise exception 'Richiesta incompleta';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text||':'||p_request_key::text,0));
  select id into v_order from public.orders
    where customer_id=v_user and request_key=p_request_key;
  if found then return v_order; end if;

  select * into v_window from public.pickup_windows
    where id=p_window_id and bar_id=p_bar_id and is_active for share;
  if not found then raise exception 'Fascia di ritiro non disponibile'; end if;
  select * into v_bar from public.bars where id=p_bar_id and school_id=v_window.school_id and is_active for share;
  if not found then raise exception 'Bar non disponibile'; end if;
  select * into v_school from public.schools where id=v_window.school_id and is_active for share;
  if not found then raise exception 'Scuola non disponibile'; end if;

  if v_window.service_date < (now() at time zone v_school.timezone)::date
    or v_window.service_date > (now() at time zone v_school.timezone)::date + v_school.booking_horizon_days
    or (v_window.service_date + v_window.starts_at) at time zone v_school.timezone <= now() then
      raise exception 'La fascia di ritiro è scaduta oppure fuori periodo';
  end if;

  -- Geolocalizzazione client-side non è prova antifrode infallibile.
  -- Richiede consenso, coordinate valide, accuratezza e osservazione recente.
  if v_school.latitude is null or v_school.longitude is null then
    raise exception 'La scuola non ha ancora configurato la posizione per le prenotazioni';
  end if;
  if p_latitude is null or p_longitude is null or
    p_latitude not between -90 and 90 or p_longitude not between -180 and 180 or
    p_accuracy_m is null or p_accuracy_m < 0 or p_accuracy_m > 100 or
    p_observed_at is null or p_observed_at < now()-interval '2 minutes' or p_observed_at > now()+interval '15 seconds' then
    raise exception 'Posizione non verificabile o non sufficientemente precisa';
  end if;
  v_distance := 6371000 * 2 * pg_catalog.asin(least(1.0::double precision,
    pg_catalog.sqrt(
      pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_latitude-v_school.latitude)/2),2)
      + pg_catalog.cos(pg_catalog.radians(v_school.latitude))*pg_catalog.cos(pg_catalog.radians(p_latitude))
      * pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_longitude-v_school.longitude)/2),2)
    )));
  if v_distance + p_accuracy_m > v_school.pickup_radius_m then
    raise exception 'Posizione esterna al raggio consentito dalla scuola';
  end if;

  if p_items is null or jsonb_typeof(p_items)<>'array'
    or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'Carrello non valido';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
    where x.product_id is null or x.quantity is null or x.quantity<=0 or x.quantity>1000) then
    raise exception 'Quantità non valida';
  end if;
  if (select count(*) from public.orders
    where customer_id=v_user and status in ('confirmed','preparing','ready')
    and payment_status='due') >= v_school.max_unpaid_orders_per_customer then
    raise exception 'Hai già raggiunto il limite di ordini non pagati';
  end if;

  -- LOCK dei prodotti e dei magazzini sempre in ordine UUID, previene overbooking.
  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
    group by x.product_id order by x.product_id
  loop
    if v_item.quantity > 1000 then raise exception 'Quantità troppo elevata per una riga'; end if;
    select p.id,p.name,p.price_cents into v_product
      from public.products p join public.categories c
       on c.id=p.category_id and c.school_id=p.school_id and c.bar_id=p.bar_id
      where p.id=v_item.product_id and p.bar_id=p_bar_id and p.school_id=v_school.id
        and p.is_active and c.is_active
      for share of p;
    if not found then raise exception 'Prodotto non più disponibile'; end if;
    select * into v_stock from public.daily_stock
      where product_id=v_item.product_id and bar_id=p_bar_id
        and school_id=v_school.id and service_date=v_window.service_date for update;
    if not found then raise exception 'Scorte non configurate per la data selezionata'; end if;
    if v_stock.capacity is not null and v_stock.allocated + v_item.quantity > v_stock.capacity then
      raise exception 'Scorte insufficienti per %', v_product.name;
    end if;
    v_units:=v_units+v_item.quantity;
    v_total:=v_total+v_item.quantity::bigint*v_product.price_cents;
    if v_total>999999999 then raise exception 'Importo troppo elevato'; end if;
  end loop;
  if (v_school.approval_product_threshold is not null and v_units>v_school.approval_product_threshold)
    or (v_school.approval_amount_threshold_cents is not null and
         v_total>v_school.approval_amount_threshold_cents) then
    raise exception 'Questa richiesta richiede approvazione manuale: flusso non ancora disponibile';
  end if;

  insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,request_key,
    status,payment_method,payment_status,total_cents)
  values (v_school.id,p_bar_id,v_user,p_window_id,p_request_key,
    case when v_bar.preparation_mode='ready_made' then 'ready' else 'confirmed' end,
    'at_pickup',case when v_total=0 then 'paid' else 'due' end,v_total)
  returning id into v_order;

  for v_item in
    select x.product_id,sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
    group by x.product_id order by x.product_id
  loop
    select p.name,p.price_cents into v_product from public.products p where p.id=v_item.product_id;
    update public.daily_stock set allocated=allocated+v_item.quantity,updated_at=now()
      where product_id=v_item.product_id and bar_id=p_bar_id and service_date=v_window.service_date;
    insert into public.order_items(school_id,bar_id,order_id,product_id,product_name,quantity,unit_cents)
    values(v_school.id,p_bar_id,v_order,v_item.product_id,v_product.name,v_item.quantity,v_product.price_cents);
  end loop;
  insert into public.order_audit(order_id,school_id,actor_id,action)
  values(v_order,v_school.id,v_user,'created');
  return v_order;
end;
$$;

create or replace function public.advance_individual_order(p_order_id uuid,p_next text)
returns void language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_order public.orders%rowtype;
  v_mode text;
  v_slot public.pickup_windows%rowtype;
begin
  if v_user is null or p_order_id is null then raise exception 'Accesso non valido'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Ordine inesistente'; end if;
  if not exists (
    select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
    where m.school_id=v_order.school_id and m.user_id=v_user and m.membership_status='active'
    and (r.role_code='bartender' or
      (r.role_code='school_admin' and (auth.jwt()->>'aal')='aal2'))
  ) then raise exception 'Non autorizzato'; end if;
  if not ((v_order.status='confirmed' and p_next in ('preparing','ready')) or
          (v_order.status='preparing' and p_next='ready') or
          (v_order.status='ready' and p_next='delivered')) then
    raise exception 'Transizione di stato non consentita'; end if;
  if p_next='delivered' then
    if v_order.payment_status<>'paid' then
      raise exception 'Saldo non ancora pagato: consegna bloccata'; end if;
    select * into v_slot from public.pickup_windows where id=v_order.pickup_window_id;
    select preparation_mode into v_mode from public.bars where id=v_order.bar_id;
    if v_mode='ready_made' and (v_slot.service_date+v_slot.starts_at) at time zone
      (select timezone from public.schools where id=v_order.school_id) > now() then
      raise exception 'La fascia di ritiro non è ancora iniziata'; end if;
  end if;
  update public.orders set status=p_next,updated_at=now() where id=p_order_id;
  insert into public.order_audit(order_id,school_id,actor_id,action)
    values(p_order_id,v_order.school_id,v_user,'status:'||p_next);
end;
$$;

create or replace function public.record_individual_counter_payment(
  p_order_id uuid,p_method text,p_request_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_order public.orders%rowtype;
  v_existing uuid;
  v_new uuid;
begin
  if v_user is null or p_order_id is null or p_request_key is null or
    p_method not in ('cash','external_pos') then raise exception 'Pagamento non valido'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Ordine inesistente'; end if;
  if not exists (
    select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
    where m.school_id=v_order.school_id and m.user_id=v_user and m.membership_status='active'
    and (r.role_code='bartender' or (r.role_code='school_admin' and (auth.jwt()->>'aal')='aal2'))
  ) then raise exception 'Non autorizzato'; end if;
  select id into v_existing from public.counter_payments where order_id=p_order_id;
  if found then
    if exists(select 1 from public.counter_payments
      where id=v_existing and request_key=p_request_key) then return v_existing; end if;
    raise exception 'Ordine già pagato: non registrare un secondo incasso';
  end if;
  if v_order.payment_status<>'due' or v_order.status in ('cancelled','delivered','no_show') then
    raise exception 'L''ordine non accetta pagamenti'; end if;
  if v_order.total_cents<=0 then raise exception 'Non occorre registrare un incasso'; end if;
  insert into public.counter_payments(school_id,bar_id,order_id,actor_id,method,amount_cents,request_key)
  values(v_order.school_id,v_order.bar_id,p_order_id,v_user,p_method,v_order.total_cents,p_request_key)
  returning id into v_new;
  update public.orders set payment_status='paid',updated_at=now() where id=p_order_id;
  insert into public.order_audit(order_id,school_id,actor_id,action)
  values(p_order_id,v_order.school_id,v_user,'counter_payment:'||p_method);
  return v_new;
end;
$$;

create or replace function public.cancel_individual_order(p_order_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_order public.orders%rowtype;
  v_slot public.pickup_windows%rowtype;
  v_tz text;
  v_cutoff integer;
  v_item record;
begin
  if v_user is null or p_order_id is null then raise exception 'Utente non autenticato'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.customer_id<>v_user then raise exception 'Ordine non disponibile'; end if;
  if v_order.payment_status<>'due' or v_order.status<>'confirmed' then
    raise exception 'L''annullamento non è disponibile per questo stato'; end if;
  select * into v_slot from public.pickup_windows where id=v_order.pickup_window_id;
  select timezone,cancel_cutoff_minutes into v_tz,v_cutoff from public.schools where id=v_order.school_id;
  if (v_slot.service_date+v_slot.starts_at) at time zone v_tz < now()+make_interval(mins=>v_cutoff) then
    raise exception 'Il termine per annullare l''ordine è scaduto'; end if;
  for v_item in select product_id,quantity from public.order_items where order_id=p_order_id order by product_id loop
    update public.daily_stock set allocated=allocated-v_item.quantity,updated_at=now()
    where product_id=v_item.product_id and bar_id=v_order.bar_id and service_date=v_slot.service_date;
  end loop;
  update public.orders set status='cancelled',updated_at=now() where id=p_order_id;
  insert into public.order_audit(order_id,school_id,actor_id,action)
    values(p_order_id,v_order.school_id,v_user,'cancelled');
end;
$$;

-- Nessuna esecuzione per PUBLIC o anon; nessuna mutazione arbitraria via Data API.
revoke all on function public.submit_individual_order(
  uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz) from public,anon,authenticated;
revoke all on function public.advance_individual_order(uuid,text) from public,anon,authenticated;
revoke all on function public.record_individual_counter_payment(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.cancel_individual_order(uuid) from public,anon,authenticated;
grant execute on function public.submit_individual_order(
  uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz) to authenticated;
grant execute on function public.advance_individual_order(uuid,text) to authenticated;
grant execute on function public.record_individual_counter_payment(uuid,text,uuid) to authenticated;
grant execute on function public.cancel_individual_order(uuid) to authenticated;


-- Configurazione geolocalizzazione e regole prenotazione: SOLO Admin scuola AAL2.
-- Le coordinate reali sono impostate da personale autorizzato, mai dal cliente.
create or replace function public.configure_school_booking(
  p_school_id uuid, p_latitude double precision, p_longitude double precision,
  p_radius_m integer, p_horizon_days integer, p_cancel_cutoff_minutes integer,
  p_max_unpaid integer, p_approval_product_threshold integer,
  p_approval_amount_threshold_cents integer
) returns void language plpgsql security definer set search_path=''
as $
begin
  if auth.uid() is null or (auth.jwt()->>'aal')<>'aal2' then
    raise exception 'È richiesta autenticazione Admin con 2FA';
  end if;
  if not exists (
    select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
    where m.school_id=p_school_id and m.user_id=auth.uid()
      and m.membership_status='active' and r.role_code='school_admin'
  ) then raise exception 'Non sei Admin della scuola selezionata'; end if;
  if p_latitude is null or p_longitude is null
    or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
    or p_radius_m not between 100 and 10000
    or p_horizon_days not between 1 and 365
    or p_cancel_cutoff_minutes not between 0 and 1440
    or p_max_unpaid not between 1 and 50
    or (p_approval_product_threshold is not null and p_approval_product_threshold<=0)
    or (p_approval_amount_threshold_cents is not null and p_approval_amount_threshold_cents<=0)
  then raise exception 'Parametri di prenotazione non validi'; end if;
  update public.schools set
    latitude=p_latitude,longitude=p_longitude,pickup_radius_m=p_radius_m,
    booking_horizon_days=p_horizon_days,cancel_cutoff_minutes=p_cancel_cutoff_minutes,
    max_unpaid_orders_per_customer=p_max_unpaid,
    approval_product_threshold=p_approval_product_threshold,
    approval_amount_threshold_cents=p_approval_amount_threshold_cents
  where id=p_school_id;
  if not found then raise exception 'Scuola non disponibile'; end if;
end;
$;

revoke all on function public.configure_school_booking(
  uuid,double precision,double precision,integer,integer,integer,integer,integer,integer
) from public,anon,authenticated;
grant execute on function public.configure_school_booking(
  uuid,double precision,double precision,integer,integer,integer,integer,integer,integer
) to authenticated;

commit;
