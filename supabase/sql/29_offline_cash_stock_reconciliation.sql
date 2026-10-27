-- BreakApp 29: itemized cash counter sales, offline replay and stock conflicts.
-- Cash is recorded only when a human actually declares it received.
begin;
create table public.bar_counter_sales(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete restrict,
 bar_id uuid not null references public.bars(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 request_key uuid not null,
 offline_event_id uuid unique references public.offline_events_inbox(id) on delete restrict,
 service_date date not null,
 amount_cents bigint not null check(amount_cents between 1 and 1000000),
 method text not null default 'cash' check(method='cash'),
 source text not null check(source in ('online','offline')),
 status text not null check(status in ('posted','stock_conflict')),
 note text not null default '' check(length(note)<=120),
 created_at timestamptz not null default now(),
 unique(actor_id,request_key)
);
create index bar_sales_school_date on public.bar_counter_sales(school_id,bar_id,service_date,created_at);
create index bar_sales_actor on public.bar_counter_sales(actor_id,created_at);
create index bar_sales_bar on public.bar_counter_sales(bar_id,service_date);
create table public.bar_counter_sale_items(
 id bigint generated always as identity primary key,
 sale_id uuid not null references public.bar_counter_sales(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,
 product_name text not null,
 quantity integer not null check(quantity between 1 and 1000),
 unit_cents integer not null check(unit_cents>=0),
 unique(sale_id,product_id)
);
create index bar_sale_items_product on public.bar_counter_sale_items(product_id);
create table public.offline_stock_conflicts(
 id uuid primary key default gen_random_uuid(),
 offline_event_id uuid not null references public.offline_events_inbox(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 bar_id uuid not null references public.bars(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,
 service_date date not null,
 sold_quantity integer not null check(sold_quantity>0),
 reason text not null,
 status text not null default 'open' check(status in ('open','resolved')),
 resolved_by uuid references auth.users(id) on delete restrict,
 resolved_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(offline_event_id,product_id)
);
create index offline_conflicts_stock_open on public.offline_stock_conflicts(
 school_id,bar_id,product_id,service_date) where status='open';
create index offline_conflicts_resolver on public.offline_stock_conflicts(resolved_by);
create index offline_conflicts_school on public.offline_stock_conflicts(school_id);
create index offline_conflicts_bar on public.offline_stock_conflicts(bar_id);
create index offline_conflicts_product on public.offline_stock_conflicts(product_id);
create table public.offline_stock_conflict_audit(
 id bigint generated always as identity primary key,
 conflict_id uuid not null references public.offline_stock_conflicts(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 previous_capacity integer,
 new_capacity integer,
 previous_allocated integer not null,
 reason text not null check(length(btrim(reason)) between 10 and 500),
 created_at timestamptz not null default now()
);
create index offline_conflict_audit_actor on public.offline_stock_conflict_audit(actor_id);
create index offline_conflict_audit_conflict on public.offline_stock_conflict_audit(conflict_id);

do $rls$
declare t text;
begin
 foreach t in array array['bar_counter_sales','bar_counter_sale_items',
  'offline_stock_conflicts','offline_stock_conflict_audit'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end;$rls$;
-- Fail closed only for the conflicting stock row, not the whole school/bar.
create or replace function app_private.guard_offline_stock_conflict()
returns trigger language plpgsql security definer set search_path=''
as $stock_guard$
begin
 if new.allocated>(case when tg_op='INSERT' then 0 else old.allocated end)
  and exists(select 1 from public.offline_stock_conflicts c
   where c.school_id=new.school_id and c.bar_id=new.bar_id
    and c.product_id=new.product_id and c.service_date=new.service_date
    and c.status='open')
 then raise exception 'Prodotto sospeso per conflitto di magazzino offline';end if;
 return new;
end;$stock_guard$;
revoke all on function app_private.guard_offline_stock_conflict()
 from public,anon,authenticated;
create trigger bar_offline_stock_guard before insert or update of allocated
 on public.daily_stock for each row execute function app_private.guard_offline_stock_conflict();

create or replace function app_private.has_barista_role(p_school uuid,p_actor uuid)
returns boolean language sql stable security definer set search_path=''
as $bartender$
 select p_school is not null and p_actor is not null and
 not exists(select 1 from app_private.platform_admins where user_id=p_actor)
 and exists(select 1 from public.school_memberships m
 join public.role_assignments r on r.membership_id=m.id
 where m.school_id=p_school and m.user_id=p_actor
  and m.membership_status='active' and r.role_code='bartender');
$bartender$;
revoke all on function app_private.has_barista_role(uuid,uuid) from public,anon,authenticated;

create or replace function public.offline_bartender_catalog(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $offline_catalog$
declare v_out jsonb;v_today date;
begin
 if not app_private.has_barista_role(p_school,auth.uid())
 then raise exception 'Catalogo offline disponibile soltanto al Barista';end if;
 select (now() at time zone s.timezone)::date into v_today from public.schools s
  where id=p_school and is_active;
 if v_today is null then raise exception 'Scuola non operativa';end if;
 select jsonb_build_object('school_id',p_school,'service_date',v_today,
  'server_synced_at',now(),'bars',coalesce((
   select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) order by b.name)
   from public.bars b where b.school_id=p_school and b.is_active),'[]'::jsonb),
  'products',coalesce((
   select jsonb_agg(jsonb_build_object('id',p.id,'bar_id',p.bar_id,
    'name',p.name,'unit_cents',p.price_cents,
    'capacity',d.capacity,'allocated',d.allocated) order by p.name)
   from public.products p
   join public.bars b on b.id=p.bar_id and b.school_id=p.school_id and b.is_active
   join public.categories c on c.id=p.category_id
    and c.school_id=p.school_id and c.bar_id=p.bar_id and c.is_active
   join public.daily_stock d on d.school_id=p.school_id and d.bar_id=p.bar_id
    and d.product_id=p.id and d.service_date=v_today
   where p.school_id=p_school and p.is_active),'[]'::jsonb)) into v_out;
 return v_out;
end;$offline_catalog$;

-- One atomic cash/inventory entry; caller has already checked physical cash.
create or replace function public.record_online_bar_cash_sale(
 p_bar uuid,p_items jsonb,p_request_key uuid,p_note text default ''
) returns jsonb language plpgsql security definer set search_path=''
as $online_sale$
declare v_user uuid:=auth.uid();v_bar public.bars%rowtype;
 v_date date;v_item record;v_product public.products%rowtype;
 v_stock public.daily_stock%rowtype;v_count int:=0;v_total bigint:=0;v_sale uuid;
begin
 if v_user is null or p_bar is null or p_request_key is null or
  p_items is null or jsonb_typeof(p_items)<>'array' or
  jsonb_array_length(p_items) not between 1 and 50 or
  length(coalesce(p_note,''))>120
 then raise exception 'Vendita non valida';end if;
 select * into v_bar from public.bars where id=p_bar and is_active;
 if not found or not app_private.has_barista_role(v_bar.school_id,v_user)
 then raise exception 'Barista non autorizzato alla vendita';end if;
 select (now() at time zone s.timezone)::date into v_date from public.schools s
  where id=v_bar.school_id and is_active;
 if v_date is null then raise exception 'Scuola disattivata';end if;
 select id into v_sale from public.bar_counter_sales
  where actor_id=v_user and request_key=p_request_key;
 if found then return jsonb_build_object('sale_id',v_sale,'status','duplicate');end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
  where x.product_id is null or x.quantity not between 1 and 1000)
  or (select count(distinct x.product_id) from jsonb_to_recordset(p_items)
    as x(product_id uuid,quantity integer))<>jsonb_array_length(p_items)
 then raise exception 'Prodotti duplicati o quantità non valide';end if;
 -- Lock in product UUID order to serialize with confirmed orders and other sales.
 for v_item in select x.product_id,x.quantity from jsonb_to_recordset(p_items)
  as x(product_id uuid,quantity integer) order by x.product_id loop
  select p.* into v_product from public.products p
   join public.categories c on c.id=p.category_id and c.is_active
  where p.id=v_item.product_id and p.school_id=v_bar.school_id
   and p.bar_id=v_bar.id and p.is_active for share of p;
  if not found then raise exception 'Articolo non valido per questo bar';end if;
  select * into v_stock from public.daily_stock
   where school_id=v_bar.school_id and bar_id=v_bar.id
    and product_id=v_item.product_id and service_date=v_date for update;
  if not found or (v_stock.capacity is not null
    and v_stock.allocated+v_item.quantity>v_stock.capacity)
  then raise exception 'Scorte disponibili insufficienti';end if;
  v_count:=v_count+1;v_total:=v_total+v_item.quantity::bigint*v_product.price_cents;
 end loop;
 if v_count=0 or v_total<=0 or v_total>1000000 then raise exception 'Totale non consentito';end if;
 insert into public.bar_counter_sales(school_id,bar_id,actor_id,request_key,
  service_date,amount_cents,source,status,note)
 values(v_bar.school_id,p_bar,v_user,p_request_key,v_date,v_total,'online','posted',
  coalesce(p_note,'')) returning id into v_sale;
 insert into public.bar_counter_sale_items(sale_id,product_id,product_name,quantity,unit_cents)
 select v_sale,p.id,p.name,x.quantity,p.price_cents
 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
 join public.products p on p.id=x.product_id;
 for v_item in select x.product_id,x.quantity from jsonb_to_recordset(p_items)
  as x(product_id uuid,quantity integer) order by x.product_id loop
  update public.daily_stock set allocated=allocated+v_item.quantity,updated_at=now()
   where school_id=v_bar.school_id and bar_id=p_bar
   and product_id=v_item.product_id and service_date=v_date;
 end loop;
 return jsonb_build_object('sale_id',v_sale,'status','posted','amount_cents',v_total);
end;$online_sale$;

-- Only an existing inbox event can be posted. The backend never trusts
-- a claimed client timestamp to prove a revoked device was valid.
create or replace function app_private.post_offline_cash_sale(p_event uuid,p_force_review boolean)
returns jsonb language plpgsql security definer set search_path=''
as $post_offline$
declare v_event public.offline_events_inbox%rowtype;v_lease public.staff_offline_leases%rowtype;
 v_bar public.bars%rowtype;v_date date;v_now_day date;v_stock public.daily_stock%rowtype;
 v_product public.products%rowtype;v_item record;v_total bigint:=0;
 v_count integer:=0;v_conflicts integer:=0;v_sale uuid;v_amount bigint;
begin
 select * into v_event from public.offline_events_inbox where id=p_event for update;
 if not found then raise exception 'Evento offline non trovato';end if;
 select id into v_sale from public.bar_counter_sales where offline_event_id=p_event;
 if found then return jsonb_build_object('sale_id',v_sale,'status','duplicate');end if;
 if v_event.event_kind<>'counter_sale' or v_event.status='rejected'
 then raise exception 'Evento non contabilizzabile come vendita';end if;
 if p_force_review then
  if v_event.status<>'approved' or
   not app_private.can_review_school_offline(v_event.school_id)
  then raise exception 'Approvazione Admin AAL2 richiesta';end if;
 else
  if v_event.status<>'quarantined' or
    not app_private.has_barista_role(v_event.school_id,auth.uid()) or
    v_event.barista_id<>auth.uid()
  then raise exception 'Barista e lease corrente richiesti';end if;
  select * into v_lease from public.staff_offline_leases
   where barista_id=v_event.barista_id for update;
  if not found or v_lease.device_id<>v_event.device_id or
   v_lease.generation<>v_event.lease_generation or
   v_lease.expires_at<=now() or v_lease.revoked_at is not null or
   v_event.local_recorded_at is null or
   v_event.local_recorded_at<v_lease.issued_at or
   v_event.local_recorded_at>v_lease.expires_at or
   v_event.local_recorded_at>v_event.received_at+interval '2 minutes'
  then return jsonb_build_object('status','quarantined','reason','Lease revocato, scaduto o data non affidabile');end if;
 end if;
 if jsonb_typeof(v_event.payload->'items')<>'array' or
  jsonb_array_length(v_event.payload->'items') not between 1 and 50 or
  v_event.payload->>'method'<>'cash'
 then return jsonb_build_object('status','quarantined','reason','Dettaglio vendita da verificare');end if;
 if v_event.payload->>'bar_id' is null then raise exception 'Bar assente';end if;
 select * into v_bar from public.bars
  where id=(v_event.payload->>'bar_id')::uuid and school_id=v_event.school_id;
 if not found then raise exception 'Bar non appartenente alla scuola';end if;
 select (now() at time zone s.timezone)::date,
  (v_event.local_recorded_at at time zone s.timezone)::date
 into v_now_day,v_date from public.schools s where s.id=v_event.school_id;
 if v_date is null or v_date>v_now_day or v_date<v_now_day-7
 then return jsonb_build_object('status','quarantined','reason','Data vendita da verificare');end if;
 if not p_force_review and v_date<>v_now_day
 then return jsonb_build_object('status','quarantined','reason','Vendita di altro giorno da verificare');end if;
 if exists(select 1 from jsonb_to_recordset(v_event.payload->'items')
  as x(product_id uuid,quantity integer,unit_cents integer)
  where x.product_id is null or x.quantity not between 1 and 1000
   or x.unit_cents is null or x.unit_cents not between 0 and 1000000)
  or (select count(distinct x.product_id)
   from jsonb_to_recordset(v_event.payload->'items')
    as x(product_id uuid,quantity integer))
  <>jsonb_array_length(v_event.payload->'items')
 then return jsonb_build_object('status','quarantined','reason','Righe vendita da verificare');end if;
 for v_item in select x.product_id,x.quantity,x.unit_cents
  from jsonb_to_recordset(v_event.payload->'items')
   as x(product_id uuid,quantity integer,unit_cents integer) order by x.product_id loop
  select * into v_product from public.products p where p.id=v_item.product_id
   and p.school_id=v_event.school_id and p.bar_id=v_bar.id for share;
  if not found then raise exception 'Prodotto cross-school non ammesso';end if;
  if not p_force_review and (not v_product.is_active or v_product.price_cents<>v_item.unit_cents)
  then return jsonb_build_object('status','quarantined','reason','Prezzo o catalogo variati');end if;
  v_total:=v_total+v_item.unit_cents::bigint*v_item.quantity;
  v_count:=v_count+1;
 end loop;
 v_amount:=(v_event.payload->>'amount_cents')::bigint;
 if v_count=0 or v_total<>v_amount or v_total<=0 or v_total>1000000
 then return jsonb_build_object('status','quarantined','reason','Totale del contante non quadrato');end if;
 if length(coalesce(v_event.payload->>'note',''))>120
 then raise exception 'Nota troppo lunga';end if;
 if not p_force_review then
  -- Never auto-post a sale if any dated stock item is insufficient.
  for v_item in select x.product_id,x.quantity from jsonb_to_recordset(v_event.payload->'items')
   as x(product_id uuid,quantity integer) order by x.product_id loop
   select * into v_stock from public.daily_stock
    where school_id=v_event.school_id and bar_id=v_bar.id
     and product_id=v_item.product_id and service_date=v_date for update;
   if not found or (v_stock.capacity is not null
    and v_stock.allocated+v_item.quantity>v_stock.capacity)
    or exists(select 1 from public.offline_stock_conflicts c
      where c.school_id=v_event.school_id and c.bar_id=v_bar.id
       and c.product_id=v_item.product_id and c.service_date=v_date and c.status='open')
   then return jsonb_build_object('status','quarantined','reason','Conflitto stock: Admin deve confermare');end if;
  end loop;
 end if;
 -- Commit the actual cash declaration even if offline physical sales exceeded
 -- online stock: never erase the cash, preserve confirmed order reservations.
 insert into public.bar_counter_sales(school_id,bar_id,actor_id,request_key,
  offline_event_id,service_date,amount_cents,source,status,note)
 values(v_event.school_id,v_bar.id,v_event.barista_id,v_event.request_key,p_event,
  v_date,v_total,'offline','posted',coalesce(v_event.payload->>'note',''))
 returning id into v_sale;
 insert into public.bar_counter_sale_items(sale_id,product_id,product_name,quantity,unit_cents)
 select v_sale,p.id,p.name,x.quantity,x.unit_cents
 from jsonb_to_recordset(v_event.payload->'items')
  as x(product_id uuid,quantity integer,unit_cents integer)
 join public.products p on p.id=x.product_id;
 for v_item in select x.product_id,x.quantity
  from jsonb_to_recordset(v_event.payload->'items')
    as x(product_id uuid,quantity integer) order by x.product_id loop
  select * into v_stock from public.daily_stock
   where school_id=v_event.school_id and bar_id=v_bar.id
    and product_id=v_item.product_id and service_date=v_date for update;
  if not found or (v_stock.capacity is not null
   and v_stock.allocated+v_item.quantity>v_stock.capacity)
   or exists(select 1 from public.offline_stock_conflicts c
    where c.school_id=v_event.school_id and c.bar_id=v_bar.id
     and c.product_id=v_item.product_id and c.service_date=v_date and c.status='open')
  then
   v_conflicts:=v_conflicts+1;
   insert into public.offline_stock_conflicts(
    offline_event_id,school_id,bar_id,product_id,service_date,sold_quantity,reason)
   values(p_event,v_event.school_id,v_bar.id,v_item.product_id,v_date,v_item.quantity,
    'Vendita contante già avvenuta: scorte insufficienti per prenotazioni online');
  else
   update public.daily_stock set allocated=allocated+v_item.quantity,updated_at=now()
    where id=v_stock.id;
  end if;
 end loop;
 if v_conflicts>0 then
  update public.bar_counter_sales set status='stock_conflict' where id=v_sale;
 end if;
 update public.offline_events_inbox set status='applied',
  review_reason=case when v_conflicts>0 then
   'Contabilizzata: conflitto stock aperto, nuove prenotazioni prodotto sospese'
   else 'Contabilizzata nel registro cassa e nelle scorte' end,
  reviewed_at=case when p_force_review then reviewed_at else now() end,
  reviewed_by=case when p_force_review then reviewed_by else auth.uid() end
 where id=p_event;
 return jsonb_build_object('sale_id',v_sale,'status','applied',
  'amount_cents',v_total,'stock_conflicts',v_conflicts);
end;$post_offline$;
revoke all on function app_private.post_offline_cash_sale(uuid,boolean)
 from public,anon,authenticated;

create or replace function public.reconcile_my_offline_cash_event(p_event uuid)
returns jsonb language plpgsql security definer set search_path=''
as $my_replay$
begin
 if auth.uid() is null then raise exception 'Autenticazione richiesta';end if;
 return app_private.post_offline_cash_sale(p_event,false);
end;$my_replay$;
create or replace function public.apply_approved_offline_cash_event(p_event uuid)
returns jsonb language plpgsql security definer set search_path=''
as $admin_replay$
begin
 if auth.uid() is null then raise exception 'Autenticazione richiesta';end if;
 return app_private.post_offline_cash_sale(p_event,true);
end;$admin_replay$;

create or replace function public.resolve_offline_stock_conflict(
 p_conflict uuid,p_new_capacity integer,p_reason text
) returns jsonb language plpgsql security definer set search_path=''
as $resolve_stock$
declare v_conflict public.offline_stock_conflicts%rowtype;
 v_stock public.daily_stock%rowtype;v_user uuid:=auth.uid();
 v_units integer;v_affected integer;
begin
 if p_conflict is null or p_new_capacity is null or p_new_capacity<0 or
  length(btrim(coalesce(p_reason,''))) not between 10 and 500
 then raise exception 'Riconciliazione motivata e stock fisico obbligatori';end if;
 select * into v_conflict from public.offline_stock_conflicts where id=p_conflict;
 if not found or v_conflict.status<>'open'
 then raise exception 'Conflitto già risolto o inesistente';end if;
 if not exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=v_conflict.school_id and m.user_id=v_user
   and m.membership_status='active' and r.role_code in
   ('school_admin','warehouse_manager','bartender'))
 then raise exception 'Solo personale della scuola può riconciliare';end if;
 select * into v_stock from public.daily_stock where
  school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
  and product_id=v_conflict.product_id and service_date=v_conflict.service_date
  for update;
 if not found then raise exception 'Scorta non inizializzata: occorre inventario fisico';end if;
 -- Resolve *all* conflicts for the same product/date in one transaction.
 -- Their physical cash sales already happened: preserve reservation priority.
 perform id from public.offline_stock_conflicts
  where school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
   and product_id=v_conflict.product_id and service_date=v_conflict.service_date
   and status='open' for update;
 select count(*),coalesce(sum(sold_quantity),0)
 into v_affected,v_units from public.offline_stock_conflicts
 where school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
   and product_id=v_conflict.product_id and service_date=v_conflict.service_date
   and status='open';
 if p_new_capacity<v_stock.allocated+v_units
 then raise exception 'Capacità sotto prenotazioni più vendite offline avvenute: avvia sostituzioni e nuova conta';end if;
 insert into public.offline_stock_conflict_audit(
  conflict_id,actor_id,previous_capacity,new_capacity,previous_allocated,reason)
 select c.id,v_user,v_stock.capacity,p_new_capacity,v_stock.allocated,btrim(p_reason)
 from public.offline_stock_conflicts c
 where c.school_id=v_conflict.school_id and c.bar_id=v_conflict.bar_id
  and c.product_id=v_conflict.product_id and c.service_date=v_conflict.service_date
  and c.status='open';
 update public.offline_stock_conflicts set status='resolved',
  resolved_by=v_user,resolved_at=now(),resolution_reason=btrim(p_reason)
 where school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
  and product_id=v_conflict.product_id and service_date=v_conflict.service_date
  and status='open';
 update public.daily_stock set capacity=p_new_capacity,
  allocated=allocated+v_units,updated_at=now() where id=v_stock.id;
 return jsonb_build_object('status','resolved','capacity',p_new_capacity,
  'physical_sales_accounted',v_units,'conflicts_resolved',v_affected);
end;$resolve_stock$;
create or replace function public.list_school_stock_conflicts(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $stock_list$
declare v_out jsonb;
begin
 if not exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=p_school and m.user_id=auth.uid()
   and m.membership_status='active' and r.role_code in
   ('school_admin','warehouse_manager','bartender'))
 then raise exception 'Accesso riservato al personale';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'bar_id',c.bar_id,'product_id',c.product_id,
  'service_date',c.service_date,'sold_quantity',c.sold_quantity,
  'reason',c.reason,'created_at',c.created_at,
  'capacity',d.capacity,'allocated',d.allocated,
  'status',c.status) order by c.created_at desc),'[]'::jsonb)
 into v_out from public.offline_stock_conflicts c
 left join public.daily_stock d on d.school_id=c.school_id and d.bar_id=c.bar_id
  and d.product_id=c.product_id and d.service_date=c.service_date
 where c.school_id=p_school and c.status='open';
 return v_out;
end;$stock_list$;

-- Revoked staff still sends evidence into quarantine: the old device is NOT
-- allowed to post to cash ledger or stock until independent Admin review.
create or replace function public.stage_my_offline_event(
 p_device uuid,p_generation bigint,p_request_key uuid,p_kind text,
 p_local_recorded_at timestamptz,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $stage$
declare v_user uuid:=auth.uid();v_lease public.staff_offline_leases%rowtype;
 v_id uuid;v_reason text;v_is_staff boolean;
begin
 if v_user is null or p_device is null or p_request_key is null or
  p_generation is null or p_kind not in('counter_sale','cash_pickup','shift_change')
  or p_payload is null or jsonb_typeof(p_payload)<>'object'
  or pg_catalog.octet_length(p_payload::text)>65536
 then raise exception 'Evento offline non valido';end if;
 select * into v_lease from public.staff_offline_leases
 where barista_id=v_user for update;
 if not found then raise exception 'Nessuna autorizzazione offline precedente';end if;
 select app_private.has_barista_role(v_lease.school_id,v_user) into v_is_staff;
 select id into v_id from public.offline_events_inbox
 where barista_id=v_user and request_key=p_request_key;
 if found then return jsonb_build_object('id',v_id,'status',
  (select status from public.offline_events_inbox where id=v_id));end if;
 v_reason:=case
   when not v_is_staff then 'Ruolo revocato: verifica Admin obbligatoria'
   when v_lease.device_id<>p_device or v_lease.generation<>p_generation
     then 'Dispositivo o generazione revocati: verifica Admin obbligatoria'
   when v_lease.expires_at<now() then 'Lease scaduto: verifica Admin obbligatoria'
   when p_local_recorded_at is null or p_local_recorded_at>now()+interval '2 minutes'
     then 'Timestamp assente o inattendibile'
   else 'Registrazione in attesa di riconciliazione server'
 end;
 insert into public.offline_events_inbox(barista_id,school_id,device_id,
  lease_generation,request_key,event_kind,local_recorded_at,payload,review_reason)
 values(v_user,v_lease.school_id,p_device,p_generation,p_request_key,p_kind,
  p_local_recorded_at,p_payload,v_reason) returning id into v_id;
 return jsonb_build_object('id',v_id,'status','quarantined','reason',v_reason);
end;$stage$;

revoke all on function public.record_online_bar_cash_sale(uuid,jsonb,uuid,text),
 public.offline_bartender_catalog(uuid),public.reconcile_my_offline_cash_event(uuid),
 public.apply_approved_offline_cash_event(uuid),
 public.resolve_offline_stock_conflict(uuid,integer,text),
 public.list_school_stock_conflicts(uuid) from public,anon,authenticated;
grant execute on function public.record_online_bar_cash_sale(uuid,jsonb,uuid,text),
 public.offline_bartender_catalog(uuid),public.reconcile_my_offline_cash_event(uuid),
 public.apply_approved_offline_cash_event(uuid),
 public.resolve_offline_stock_conflict(uuid,integer,text),
 public.list_school_stock_conflicts(uuid) to authenticated;
commit;
