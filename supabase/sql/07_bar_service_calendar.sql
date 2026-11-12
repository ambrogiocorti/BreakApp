-- BreakApp migration 07: orari settimanali, pausa prenotazioni,
-- chiusure programmate/straordinarie con impatto transazionale e avvisi in-app.
-- Solo sul progetto BreakApp; dipende dalle migrazioni 01..06.
-- Non implementa rimborsi Stripe: ordini con somme realmente incassate bloccano
-- la chiusura anziché cancellarsi senza rimborso.
begin;

create table public.bar_service_state (
  school_id uuid not null,
  bar_id uuid not null,
  accepting_orders boolean not null default true,
  reason text not null default '' check (char_length(reason)<=500),
  changed_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (school_id,bar_id),
  foreign key (school_id,bar_id) references public.bars(school_id,id) on delete cascade
);

create table public.bar_opening_hours (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  weekday smallint not null check(weekday between 0 and 6),
  starts_at time without time zone not null,
  ends_at time without time zone not null,
  check (starts_at < ends_at),
  unique(bar_id,weekday,starts_at),
  foreign key(school_id,bar_id) references public.bars(school_id,id) on delete cascade
);

create table public.bar_closures (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  service_date date not null,
  starts_at time without time zone not null,
  ends_at time without time zone not null,
  closure_type text not null check(closure_type in ('planned','extraordinary')),
  reason text not null check(char_length(btrim(reason)) between 3 and 500),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  reopened_at timestamptz,
  reopened_by uuid references auth.users(id) on delete restrict,
  check (starts_at < ends_at),
  foreign key(school_id,bar_id) references public.bars(school_id,id) on delete restrict
);

create table public.bar_service_events (
  id bigint generated always as identity primary key,
  school_id uuid not null,
  bar_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (school_id,bar_id) references public.bars(school_id,id) on delete restrict
);

create table public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  order_id uuid references public.orders(id) on delete restrict,
  event_type text not null check(event_type in ('closure_order_cancelled')),
  message text not null check(char_length(message) between 1 and 1000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index bar_opening_by_day on public.bar_opening_hours(bar_id,weekday,starts_at);
create index bar_closures_for_day on public.bar_closures(bar_id,service_date,starts_at) where reopened_at is null;
create index bar_service_events_by_bar on public.bar_service_events(bar_id,created_at desc);
create index customer_notifications_for_user on public.customer_notifications(user_id,created_at desc);

alter table public.bar_service_state enable row level security;
alter table public.bar_opening_hours enable row level security;
alter table public.bar_closures enable row level security;
alter table public.bar_service_events enable row level security;
alter table public.customer_notifications enable row level security;

revoke all on public.bar_service_state,public.bar_opening_hours,public.bar_closures,
  public.bar_service_events,public.customer_notifications from public,anon,authenticated;

grant select on public.bar_service_state,public.bar_opening_hours,public.bar_closures to anon,authenticated;
grant select on public.bar_service_events,public.customer_notifications to authenticated;
grant update(read_at) on public.customer_notifications to authenticated;

create policy bar_service_status_public on public.bar_service_state
for select to anon,authenticated using (
  exists(select 1 from public.bars b join public.schools s on s.id=b.school_id
    where b.school_id=bar_service_state.school_id and b.id=bar_service_state.bar_id
    and s.is_active and b.is_active)
);

create policy bar_opening_public on public.bar_opening_hours
for select to anon,authenticated using (
  exists(select 1 from public.bars b join public.schools s on s.id=b.school_id
    where b.school_id=bar_opening_hours.school_id and b.id=bar_opening_hours.bar_id
    and s.is_active and b.is_active)
);

create policy bar_closures_public on public.bar_closures
for select to anon,authenticated using (
  exists(select 1 from public.bars b join public.schools s on s.id=b.school_id
    where b.school_id=bar_closures.school_id and b.id=bar_closures.bar_id
    and s.is_active and b.is_active)
);

create policy bar_service_events_staff on public.bar_service_events
for select to authenticated using (
  exists(select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id=m.id
    where m.school_id=bar_service_events.school_id and m.user_id=(select auth.uid())
    and m.membership_status='active'
    and (r.role_code='bartender' or
      (r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2')))
);

create policy customer_notifications_own on public.customer_notifications
for select to authenticated using (user_id=(select auth.uid()));
create policy customer_notifications_read_own on public.customer_notifications
for update to authenticated
using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()));

-- Riduce il rischio di UPDATE client fuori scope quando su notifications sono
-- concessi solo privilegi colonnari read_at. Nessun client può inserire avvisi.

create or replace function app_private.can_operate_bar(p_school_id uuid,p_admin_only boolean default false)
returns boolean language sql stable security definer set search_path=''
as $can_operate$
 select (select auth.uid()) is not null and exists(
  select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=p_school_id and m.user_id=(select auth.uid())
    and m.membership_status='active' and (
      (r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2')
      or (not p_admin_only and r.role_code='bartender')
    )
 );
$can_operate$;
revoke all on function app_private.can_operate_bar(uuid,boolean) from public,anon,authenticated;

-- RPC pause: non modifica/annulla mai gli ordini già confermati.
create or replace function public.set_bar_booking_pause(
 p_bar_id uuid,p_paused boolean,p_reason text default ''
) returns void language plpgsql security definer set search_path=''
as $pause$
declare v_bar public.bars%rowtype;
begin
 if p_paused is null then raise exception 'Stato pausa non valido'; end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active for update;
 if not found then raise exception 'Bar non trovato'; end if;
 if not app_private.can_operate_bar(v_bar.school_id,false) then raise exception 'Non autorizzato'; end if;
 if p_paused and char_length(btrim(coalesce(p_reason,'')))<3 then
   raise exception 'Indicare il motivo della pausa';
 end if;
 if char_length(coalesce(p_reason,''))>500 then raise exception 'Motivazione troppo lunga'; end if;
 insert into public.bar_service_state(school_id,bar_id,accepting_orders,reason,changed_by,updated_at)
 values(v_bar.school_id,v_bar.id,not p_paused,case when p_paused then btrim(p_reason) else '' end,auth.uid(),now())
 on conflict(school_id,bar_id) do update set
 accepting_orders=excluded.accepting_orders,reason=excluded.reason,
 changed_by=excluded.changed_by,updated_at=now();
 insert into public.bar_service_events(school_id,bar_id,actor_id,action,details)
 values(v_bar.school_id,v_bar.id,auth.uid(),
  case when p_paused then 'booking_paused' else 'booking_resumed' end,
  jsonb_build_object('reason',p_reason));
end;
$pause$;

create or replace function public.set_bar_weekly_hours(
 p_bar_id uuid,p_weekday integer,p_periods jsonb
) returns void language plpgsql security definer set search_path=''
as $hours$
declare v_bar public.bars%rowtype; v_period record;
 v_last_end time without time zone;
 v_tz text;
begin
 if p_weekday not between 0 and 6 or p_periods is null or
    jsonb_typeof(p_periods)<>'array' or jsonb_array_length(p_periods)>8 then
   raise exception 'Orari settimanali non validi';
 end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active for update;
 if not found then raise exception 'Bar non trovato'; end if;
 if not app_private.can_operate_bar(v_bar.school_id,true) then
   raise exception 'Solo Admin scuola con 2FA può modificare gli orari';
 end if;
 for v_period in
    select x.starts_at,x.ends_at from jsonb_to_recordset(p_periods)
      as x(starts_at time, ends_at time)
    order by starts_at
 loop
   if v_period.starts_at is null or v_period.ends_at is null
     or v_period.starts_at>=v_period.ends_at then
       raise exception 'Gli orari di un intervallo sono invalidi';
   end if;
   if v_last_end is not null and v_period.starts_at < v_last_end then
       raise exception 'Intervalli di apertura sovrapposti';
   end if;
   v_last_end := v_period.ends_at;
 end loop;

 select timezone into v_tz from public.schools where id=v_bar.school_id;
 -- Una modifica non può lasciare fasce future già pubblicate senza apertura.
 if exists(
   select 1 from public.pickup_windows w
   where w.bar_id=p_bar_id and w.is_active
     and w.service_date >= (now() at time zone v_tz)::date
     and extract(dow from w.service_date)::int = p_weekday
     and not exists(
       select 1 from jsonb_to_recordset(p_periods) x(starts_at time,ends_at time)
       where x.starts_at<=w.starts_at and x.ends_at>=w.ends_at
     )
 ) then
   raise exception 'Alcune fasce future non rientrano nei nuovi orari: verifica prima gli ordini';
 end if;
 delete from public.bar_opening_hours where bar_id=v_bar.id and weekday=p_weekday;
 insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select v_bar.school_id,v_bar.id,p_weekday,x.starts_at,x.ends_at
 from jsonb_to_recordset(p_periods) as x(starts_at time,ends_at time);
 insert into public.bar_service_events(school_id,bar_id,actor_id,action,details)
 values(v_bar.school_id,v_bar.id,auth.uid(),'weekly_hours_updated',
  jsonb_build_object('weekday',p_weekday,'periods',p_periods));
end;
$hours$;

-- La preview è obbligatoria come UI, ma l'RPC ricontrolla sempre l'impatto.
create or replace function public.preview_bar_closure(
 p_bar_id uuid,p_date date,p_start time,p_end time
) returns jsonb language plpgsql security definer set search_path=''
as $preview$
declare v_bar public.bars%rowtype;v_active integer;v_paid bigint;v_orders jsonb;
begin
 select * into v_bar from public.bars where id=p_bar_id and is_active;
 if not found or not app_private.can_operate_bar(v_bar.school_id,false) then
  raise exception 'Non autorizzato';end if;
 if p_date is null or p_start is null or p_end is null or p_start>=p_end then
  raise exception 'Intervallo di chiusura non valido'; end if;
 select count(*),coalesce(sum(case when o.payment_status='paid' then o.total_cents else 0 end),0),
   coalesce(jsonb_agg(jsonb_build_object('display_no',o.display_no,'status',o.status))
     filter(where o.id is not null),'[]'::jsonb)
 into v_active,v_paid,v_orders
 from public.orders o
 join public.pickup_windows w on w.id=o.pickup_window_id
 where o.bar_id=p_bar_id and w.service_date=p_date
  and w.starts_at<p_end and w.ends_at>p_start
  and o.status not in ('delivered','cancelled','no_show');
 return jsonb_build_object('active_orders',v_active,'paid_cents',v_paid,'orders',v_orders);
end;
$preview$;

create or replace function public.close_bar_interval(
 p_bar_id uuid,p_date date,p_start time,p_end time,
 p_kind text,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $closure$
declare v_bar public.bars%rowtype;v_day date;v_order record;v_item record;
 v_closure uuid;v_tz text;
begin
 if p_date is null or p_start is null or p_end is null or p_start>=p_end
   or p_kind not in ('planned','extraordinary') or p_kind is null
   or char_length(btrim(coalesce(p_reason,''))) not between 3 and 500 then
   raise exception 'Dati di chiusura non validi';
 end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active for update;
 if not found then raise exception 'Bar non trovato';end if;
 if not app_private.can_operate_bar(v_bar.school_id,p_kind='planned') then
  raise exception 'Non autorizzato alla chiusura'; end if;
 select timezone into v_tz from public.schools where id=v_bar.school_id;
 v_day:=(now() at time zone v_tz)::date;
 if p_date<v_day or p_date>v_day+365 then
  raise exception 'La chiusura deve riguardare una data presente o futura';end if;
 if exists(select 1 from public.bar_closures c
  where c.bar_id=v_bar.id and c.service_date=p_date and c.reopened_at is null
  and c.starts_at<p_end and c.ends_at>p_start)
 then raise exception 'Esiste già una chiusura sovrapposta';end if;

 -- Blocca le righe ordine nello stesso ordine prima di mutare alcunché.
 for v_order in
  select o.* from public.orders o
   join public.pickup_windows w on w.id=o.pickup_window_id
  where o.bar_id=p_bar_id and w.service_date=p_date
    and w.starts_at<p_end and w.ends_at>p_start
    and o.status not in ('delivered','cancelled','no_show')
  order by o.id for update of o
 loop
  if p_kind='planned' then
   raise exception 'Sono presenti ordini attivi: usa una chiusura straordinaria con valutazione impatto';
  end if;
  if v_order.payment_status='paid' and v_order.total_cents>0 then
   raise exception 'Ordine pagato presente: chiusura bloccata finché i rimborsi non sono automatizzati';
  end if;
 end loop;

 insert into public.bar_closures(school_id,bar_id,service_date,starts_at,ends_at,closure_type,reason,created_by)
 values(v_bar.school_id,v_bar.id,p_date,p_start,p_end,p_kind,btrim(p_reason),auth.uid())
 returning id into v_closure;

 if p_kind='extraordinary' then
   for v_order in
     select o.* from public.orders o
      join public.pickup_windows w on w.id=o.pickup_window_id
     where o.bar_id=p_bar_id and w.service_date=p_date
       and w.starts_at<p_end and w.ends_at>p_start
       and o.status not in ('delivered','cancelled','no_show')
     order by o.id for update of o
   loop
     for v_item in
       select i.product_id,i.quantity,w.service_date from public.order_items i
       join public.pickup_windows w on w.id=v_order.pickup_window_id
       where i.order_id=v_order.id order by i.product_id
     loop
       update public.daily_stock
         set allocated=allocated-v_item.quantity,updated_at=now()
       where school_id=v_bar.school_id and bar_id=v_bar.id
          and service_date=v_item.service_date and product_id=v_item.product_id;
     end loop;
     update public.orders set status='cancelled',updated_at=now() where id=v_order.id;
     insert into public.order_audit(order_id,school_id,actor_id,action)
      values(v_order.id,v_bar.school_id,auth.uid(),'extraordinary_closure_cancelled');
     insert into public.customer_notifications(school_id,user_id,order_id,event_type,message)
      values(v_bar.school_id,v_order.customer_id,v_order.id,'closure_order_cancelled',
        'Ordine #'||v_order.display_no||' annullato per chiusura straordinaria del bar.');
   end loop;
 end if;
 insert into public.bar_service_events(school_id,bar_id,actor_id,action,details)
 values(v_bar.school_id,v_bar.id,auth.uid(),'closure_created',
   jsonb_build_object('closure_id',v_closure,'kind',p_kind,'date',p_date,
      'starts_at',p_start,'ends_at',p_end,'reason',p_reason));
 return v_closure;
end;
$closure$;

create or replace function public.reopen_bar_interval(p_closure_id uuid)
returns void language plpgsql security definer set search_path=''
as $reopen$
declare v_close public.bar_closures%rowtype;v_bar public.bars%rowtype;
begin
 if p_closure_id is null then raise exception 'Chiusura non valida';end if;
 -- Blocca il bar per serializzare prenotazioni e riaperture.
 select b.* into v_bar from public.bars b
 join public.bar_closures c on c.bar_id=b.id where c.id=p_closure_id for update of b;
 if not found then raise exception 'Chiusura non trovata';end if;
 if not app_private.can_operate_bar(v_bar.school_id,false) then
   raise exception 'Non autorizzato alla riapertura';end if;
 select * into v_close from public.bar_closures where id=p_closure_id for update;
 if v_close.reopened_at is not null then raise exception 'Bar già riaperto';end if;
 update public.bar_closures set reopened_at=now(),reopened_by=auth.uid() where id=p_closure_id;
 insert into public.bar_service_events(school_id,bar_id,actor_id,action,details)
 values(v_bar.school_id,v_bar.id,auth.uid(),'closure_reopened',
   jsonb_build_object('closure_id',p_closure_id));
 -- Gli ordini già annullati NON vengono mai ripristinati.
end;
$reopen$;

-- Difesa server contro un checkout durante pausa, chiusura, orario non aperto.
-- Non dipende da un flag del frontend.
create or replace function app_private.guard_new_order_service()
returns trigger language plpgsql set search_path=''
as $guard_order$
declare v_slot public.pickup_windows%rowtype;
begin
 select * into v_slot from public.pickup_windows where id=new.pickup_window_id;
 if v_slot.id is null or new.bar_id<>v_slot.bar_id
  or new.school_id<>v_slot.school_id then raise exception 'Fascia non valida';end if;
 if exists(select 1 from public.bar_service_state s
   where s.bar_id=new.bar_id and not s.accepting_orders) then
   raise exception 'Le nuove prenotazioni sono temporaneamente sospese';end if;
 if exists(select 1 from public.bar_closures c where c.bar_id=new.bar_id
   and c.service_date=v_slot.service_date and c.reopened_at is null
   and c.starts_at<v_slot.ends_at and c.ends_at>v_slot.starts_at) then
   raise exception 'Il bar è chiuso nella fascia selezionata';end if;
 if not exists(select 1 from public.bar_opening_hours h where h.bar_id=new.bar_id
   and h.weekday=extract(dow from v_slot.service_date)::int
   and h.starts_at<=v_slot.starts_at and h.ends_at>=v_slot.ends_at) then
   raise exception 'Fascia fuori dagli orari settimanali di apertura';end if;
 return new;
end;
$guard_order$;

create trigger orders_service_guard before insert on public.orders
for each row execute function app_private.guard_new_order_service();

create or replace function app_private.guard_pickup_window_service()
returns trigger language plpgsql set search_path=''
as $guard_slot$
begin
 if new.is_active and (
  not exists(select 1 from public.bar_opening_hours h where h.bar_id=new.bar_id
   and h.weekday=extract(dow from new.service_date)::int
   and h.starts_at<=new.starts_at and h.ends_at>=new.ends_at)
  or exists(select 1 from public.bar_closures c where c.bar_id=new.bar_id
   and c.service_date=new.service_date and c.reopened_at is null
   and c.starts_at<new.ends_at and c.ends_at>new.starts_at)
 ) then raise exception 'Fascia non valida: bar chiuso o fuori dagli orari';end if;
 return new;
end;
$guard_slot$;

create trigger pickup_windows_service_guard before insert or update
on public.pickup_windows for each row execute function app_private.guard_pickup_window_service();

revoke all on function app_private.guard_new_order_service() from public,anon,authenticated;
revoke all on function app_private.guard_pickup_window_service() from public,anon,authenticated;

revoke all on function public.set_bar_booking_pause(uuid,boolean,text),
 public.set_bar_weekly_hours(uuid,integer,jsonb),
 public.preview_bar_closure(uuid,date,time,time),
 public.close_bar_interval(uuid,date,time,time,text,text),
 public.reopen_bar_interval(uuid) from public,anon,authenticated;
grant execute on function public.set_bar_booking_pause(uuid,boolean,text),
 public.set_bar_weekly_hours(uuid,integer,jsonb),
 public.preview_bar_closure(uuid,date,time,time),
 public.close_bar_interval(uuid,date,time,time,text,text),
 public.reopen_bar_interval(uuid) to authenticated;

commit;
