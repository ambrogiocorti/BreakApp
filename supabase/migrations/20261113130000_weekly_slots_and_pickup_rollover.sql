-- BreakApp: fasce settimanali e passaggio automatico alla fascia successiva
-- (decisioni di Ambrogio del 13/11/2026).
--
-- 1. Fasce settimanali: l'Admin definisce una volta le fasce di ogni giorno
--    della settimana (es. lun-ven 9:40-9:50). Il server crea da solo le fasce
--    dei prossimi 14 giorni e, per gli stessi giorni, le scorte giornaliere dei
--    prodotti attivi copiando l'ultima capacita' impostata (nessuna = illimitata).
--    Bar senza fasce settimanali: nulla cambia.
-- 2. Ordine non ritirato nella sua fascia: passa da solo alla fascia successiva
--    dello stesso giorno e il cliente riceve un avviso. Se non c'e' piu' una
--    fascia, alla chiusura del bar resta la regola gia' esistente
--    (maintain_daily_orders): no-show e rimborso automatico ai pagatori.
-- Entrambe girano dentro maintain_daily_orders, gia' chiamata ogni minuto.

create table public.pickup_window_templates(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null,
 bar_id uuid not null,
 weekday smallint not null check (weekday between 0 and 6),
 starts_at time not null,
 ends_at time not null,
 is_active boolean not null default true,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check (starts_at<ends_at),
 unique (bar_id,weekday,starts_at),
 foreign key (school_id,bar_id) references public.bars(school_id,id) on delete restrict
);
create index pickup_window_templates_school_bar on public.pickup_window_templates(school_id,bar_id);
create index pickup_window_templates_created_by on public.pickup_window_templates(created_by);
alter table public.pickup_window_templates enable row level security;
revoke all on public.pickup_window_templates from public,anon,authenticated;

-- Crea fasce e scorte dei prossimi p_days giorni a partire dalle fasce settimanali.
create function app_private.generate_template_windows(p_clock timestamptz default now(),p_days integer default 14,p_bar uuid default null)
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer:=0;v_rows integer;
begin
 insert into public.pickup_windows(school_id,bar_id,service_date,starts_at,ends_at,is_active)
 select t.school_id,t.bar_id,d::date,t.starts_at,t.ends_at,true
 from public.pickup_window_templates t
 join public.schools s on s.id=t.school_id
 cross join lateral generate_series((p_clock at time zone s.timezone)::date,(p_clock at time zone s.timezone)::date+greatest(0,least(coalesce(p_days,14),60)),interval '1 day') d
 where t.is_active and (p_bar is null or t.bar_id=p_bar)
  and extract(dow from d)::int=t.weekday
  and exists(select 1 from public.bar_opening_hours h where h.bar_id=t.bar_id and h.weekday=t.weekday
   and h.starts_at<=t.starts_at and h.ends_at>=t.ends_at)
  and not exists(select 1 from public.bar_closures c where c.bar_id=t.bar_id and c.service_date=d::date
   and c.reopened_at is null and c.starts_at<t.ends_at and c.ends_at>t.starts_at)
 on conflict (bar_id,service_date,starts_at) do nothing;
 get diagnostics v_count=row_count;
 insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 select p.school_id,p.bar_id,p.id,x.service_date,
  (select ds.capacity from public.daily_stock ds where ds.bar_id=p.bar_id and ds.product_id=p.id order by ds.service_date desc limit 1)
 from (select distinct w.bar_id,w.service_date from public.pickup_windows w
   join public.pickup_window_templates t on t.bar_id=w.bar_id and t.weekday=extract(dow from w.service_date)::int and t.starts_at=w.starts_at and t.is_active
   join public.schools s on s.id=w.school_id
   where w.service_date>=(p_clock at time zone s.timezone)::date and (p_bar is null or w.bar_id=p_bar)) x
 join public.products p on p.bar_id=x.bar_id and p.is_active
 on conflict (bar_id,product_id,service_date) do nothing;
 get diagnostics v_rows=row_count;
 return v_count+v_rows;
end;$$;
revoke all on function app_private.generate_template_windows(timestamptz,integer,uuid) from public,anon,authenticated;

-- Sposta gli ordini non ritirati alla fascia successiva dello stesso giorno.
create function app_private.roll_over_missed_pickups(p_clock timestamptz default now())
returns integer language plpgsql security definer set search_path='' as $$
declare r record;v_next public.pickup_windows%rowtype;v_count integer:=0;
begin
 for r in select * from(
  select 'individual'::text kind,o.id,o.status,w.id window_id,w.bar_id,w.service_date,w.starts_at,w.ends_at,s.timezone
  from public.orders o join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id
  where o.status in ('confirmed','preparing','ready')
  union all
  select 'group',o.id,o.status,w.id,w.bar_id,w.service_date,w.starts_at,w.ends_at,s.timezone
  from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id
  where o.status in ('confirmed','preparing','ready')) q
 where q.service_date=(p_clock at time zone q.timezone)::date
  and (q.service_date+q.ends_at) at time zone q.timezone<=p_clock
 order by q.starts_at,q.id limit 500 loop
  -- Un ritiro offline in revisione non si sposta: decide l'Admin.
  if exists(select 1 from public.offline_events_inbox e where e.status in ('quarantined','approved')
   and e.event_kind=case when r.kind='group' then 'group_pickup' else 'cash_pickup' end and e.payload->>'order_id'=r.id::text) then continue;end if;
  select w.* into v_next from public.pickup_windows w
  where w.bar_id=r.bar_id and w.service_date=r.service_date and w.is_active and w.id<>r.window_id
   and w.starts_at>=r.starts_at and (w.service_date+w.ends_at) at time zone r.timezone>p_clock
   and not exists(select 1 from public.bar_closures c where c.bar_id=w.bar_id and c.service_date=w.service_date
    and c.reopened_at is null and c.starts_at<w.ends_at and c.ends_at>w.starts_at)
  order by w.starts_at,w.ends_at,w.id limit 1;
  if not found then continue;end if;
  if r.kind='individual' then
   update public.orders set pickup_window_id=v_next.id,updated_at=now() where id=r.id and pickup_window_id=r.window_id;
  else
   update public.group_orders set pickup_window_id=v_next.id,pickup_lease_until=null,pickup_lease_actor=null,updated_at=now()
    where id=r.id and pickup_window_id=r.window_id;
   update public.group_drafts set pickup_window_id=v_next.id where id=(select group_id from public.group_orders where id=r.id);
  end if;
  perform app_private.notify_order_change(r.kind,r.id,'Non hai ritirato in tempo: il tuo ordine è passato alla fascia '
   ||to_char(v_next.starts_at,'HH24:MI')||'–'||to_char(v_next.ends_at,'HH24:MI')
   ||'. Se non lo ritiri entro la chiusura del bar viene rimborsato in automatico.');
  v_count:=v_count+1;
 end loop;
 return v_count;
end;$$;
revoke all on function app_private.roll_over_missed_pickups(timestamptz) from public,anon,authenticated;

-- Lo scheduler esistente (ogni minuto) esegue anche fasce settimanali e spostamenti.
do $daily$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('public.maintain_daily_orders(timestamptz)'::regprocedure);
 if pg_catalog.strpos(v_def,'then raise exception ''Solo backend'';end if;')=0 then
  raise exception 'maintain_daily_orders non compatibile con la migrazione fasce';end if;
 v_def:=pg_catalog.replace(v_def,'then raise exception ''Solo backend'';end if;',
  'then raise exception ''Solo backend'';end if;'||chr(10)
  ||' perform app_private.generate_template_windows(p_clock,14,null);'||chr(10)
  ||' perform app_private.roll_over_missed_pickups(p_clock);');
 execute v_def;
end;
$daily$;

-- Admin della scuola con 2FA: elenco, aggiunta e rimozione delle fasce settimanali.
create function public.list_pickup_templates(p_bar uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_school uuid;
begin
 select school_id into v_school from public.bars where id=p_bar;
 if v_school is null or not app_private.can_manage_support_school(v_school) then raise exception 'Admin della scuola con 2FA richiesto';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'weekday',t.weekday,'starts_at',t.starts_at,'ends_at',t.ends_at,'is_active',t.is_active)
  order by t.weekday,t.starts_at) from public.pickup_window_templates t where t.bar_id=p_bar),'[]'::jsonb);
end;$$;
revoke all on function public.list_pickup_templates(uuid) from public,anon,authenticated;
grant execute on function public.list_pickup_templates(uuid) to authenticated;

create function public.add_pickup_templates(p_bar uuid,p_weekdays smallint[],p_starts time,p_ends time)
returns integer language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_day smallint;v_count integer:=0;
begin
 select school_id into v_school from public.bars where id=p_bar;
 if v_school is null or not app_private.can_manage_support_school(v_school) then raise exception 'Admin della scuola con 2FA richiesto';end if;
 if p_starts is null or p_ends is null or p_starts>=p_ends then raise exception 'Orario non valido';end if;
 if p_weekdays is null or cardinality(p_weekdays)=0 or exists(select 1 from unnest(p_weekdays) d where d not between 0 and 6) then
  raise exception 'Scegli almeno un giorno della settimana';end if;
 foreach v_day in array p_weekdays loop
  if not exists(select 1 from public.bar_opening_hours h where h.bar_id=p_bar and h.weekday=v_day and h.starts_at<=p_starts and h.ends_at>=p_ends) then
   raise exception 'Fascia fuori dagli orari di apertura del bar in uno dei giorni scelti';end if;
  insert into public.pickup_window_templates(school_id,bar_id,weekday,starts_at,ends_at,created_by)
  values(v_school,p_bar,v_day,p_starts,p_ends,auth.uid())
  on conflict (bar_id,weekday,starts_at) do update set ends_at=excluded.ends_at,is_active=true;
  v_count:=v_count+1;
 end loop;
 perform app_private.generate_template_windows(now(),14,p_bar);
 return v_count;
end;$$;
revoke all on function public.add_pickup_templates(uuid,smallint[],time,time) from public,anon,authenticated;
grant execute on function public.add_pickup_templates(uuid,smallint[],time,time) to authenticated;

-- Rimuovere una fascia settimanale non tocca le fasce gia' create (e i loro ordini).
create function public.remove_pickup_template(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare t public.pickup_window_templates%rowtype;
begin
 select * into t from public.pickup_window_templates where id=p_id;
 if not found or not app_private.can_manage_support_school(t.school_id) then raise exception 'Fascia non disponibile';end if;
 delete from public.pickup_window_templates where id=p_id;
end;$$;
revoke all on function public.remove_pickup_template(uuid) from public,anon,authenticated;
grant execute on function public.remove_pickup_template(uuid) to authenticated;
