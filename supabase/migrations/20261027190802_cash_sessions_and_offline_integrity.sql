-- Turni di cassa, movimenti immutabili e conservazione degli eventi di device revocati.
begin;
create table public.cash_sessions (
 id uuid primary key,
 school_id uuid not null references public.schools(id),
 bar_id uuid not null references public.bars(id),
 actor_id uuid not null references auth.users(id),
 opening_cents bigint not null check(opening_cents between 0 and 100000000),
 opened_at timestamptz not null default now(),
 closed_at timestamptz,
 expected_cents bigint,
 counted_cents bigint check(counted_cents between 0 and 100000000),
 closing_reason text not null default '' check(length(closing_reason)<=500),
 check((closed_at is null and expected_cents is null and counted_cents is null)
   or (closed_at is not null and expected_cents is not null and counted_cents is not null))
);
create unique index cash_one_open_per_bar on public.cash_sessions(bar_id) where closed_at is null;
create index cash_session_school on public.cash_sessions(school_id,opened_at desc);
create index cash_session_actor on public.cash_sessions(actor_id,opened_at desc);
create index cash_session_bar on public.cash_sessions(bar_id,opened_at desc);
create table public.cash_entries (
 id uuid primary key default gen_random_uuid(),
 session_id uuid references public.cash_sessions(id),
 school_id uuid not null references public.schools(id),
 bar_id uuid not null references public.bars(id),
 actor_id uuid not null references auth.users(id),
 kind text not null check(kind in ('receipt','deposit','withdrawal','adjustment')),
 amount_cents bigint not null check(amount_cents between -100000000 and 100000000 and amount_cents<>0),
 source_key text not null unique,
 reason text not null default '' check(length(reason)<=500),
 created_at timestamptz not null default now(),
 check((kind in ('receipt','deposit') and amount_cents>0) or
       (kind='withdrawal' and amount_cents<0) or kind='adjustment')
);
create index cash_entries_session on public.cash_entries(session_id,created_at);
create index cash_entries_school on public.cash_entries(school_id,created_at);
create index cash_entries_bar on public.cash_entries(bar_id,created_at);
create index cash_entries_actor on public.cash_entries(actor_id,created_at);
alter table public.cash_sessions enable row level security;
alter table public.cash_entries enable row level security;
revoke all on public.cash_sessions,public.cash_entries from public,anon,authenticated;

create or replace function app_private.cash_immutable()
returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Registro di cassa immutabile: inserire una rettifica motivata';end;$$;
revoke all on function app_private.cash_immutable() from public,anon,authenticated;
create trigger cash_entry_immutable before update or delete on public.cash_entries
for each row execute function app_private.cash_immutable();
create or replace function app_private.cash_close_immutable()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' or old.closed_at is not null then
  raise exception 'Chiusura confermata immutabile';end if;
 if (new.id,new.school_id,new.bar_id,new.actor_id,new.opening_cents,new.opened_at)
   is distinct from (old.id,old.school_id,old.bar_id,old.actor_id,old.opening_cents,old.opened_at)
 then raise exception 'Apertura di cassa immutabile';end if;
 return new;
end;$$;
revoke all on function app_private.cash_close_immutable() from public,anon,authenticated;
create trigger cash_session_immutable before update or delete on public.cash_sessions
for each row execute function app_private.cash_close_immutable();

-- Every real cash receipt enters this ledger exactly once. External POS is excluded.
create or replace function app_private.capture_cash_receipt()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_session uuid;v_source text;v_event uuid;v_requested uuid;
begin
 if new.method<>'cash' then return new;end if;
 v_source:=tg_table_name||':'||new.id;
 -- Serialize a closing count against concurrent cash receipts at this bar.
 perform 1 from public.bars where id=new.bar_id for update;
 if tg_table_name='bar_counter_sales' then v_event:=new.offline_event_id;
 elsif tg_table_name='counter_payments' then
  select e.id into v_event from public.offline_events_inbox e
   where e.request_key=new.request_key and e.barista_id=new.actor_id;
 end if;
 if v_event is not null then
  select nullif(payload->>'cash_session_id','')::uuid into v_requested
   from public.offline_events_inbox where id=v_event;
 end if;
 select id into v_session from public.cash_sessions
  where bar_id=new.bar_id and actor_id=new.actor_id and closed_at is null for update;
 if v_requested is not null and v_requested is distinct from v_session then
  raise exception 'Turno offline non più aperto: richiesta revisione Admin';end if;
 insert into public.cash_entries(session_id,school_id,bar_id,actor_id,kind,amount_cents,source_key)
 values(v_session,new.school_id,new.bar_id,new.actor_id,'receipt',new.amount_cents,v_source)
 on conflict(source_key) do nothing;
 return new;
end;$$;
revoke all on function app_private.capture_cash_receipt() from public,anon,authenticated;
create trigger individual_cash_ledger after insert on public.counter_payments
 for each row execute function app_private.capture_cash_receipt();
create trigger group_cash_ledger after insert on public.group_counter_payments
 for each row execute function app_private.capture_cash_receipt();
create trigger sale_cash_ledger after insert on public.bar_counter_sales
 for each row execute function app_private.capture_cash_receipt();

create or replace function app_private.apply_cash_operation(
 p_actor uuid,p_bar uuid,p_session uuid,p_action text,p_amount bigint,p_reason text,p_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_row public.cash_sessions%rowtype;v_expected bigint;
begin
 if p_actor is null or p_bar is null or p_session is null or p_key is null or
    p_action is null or p_action not in ('open','deposit','withdrawal','close','adjustment') or
    p_amount is null or abs(p_amount)>100000000 or length(coalesce(p_reason,''))>500
 then raise exception 'Operazione di cassa non valida';end if;
 select school_id into v_school from public.bars where id=p_bar and is_active for update;
 if v_school is null then raise exception 'Bar non operativo';end if;
 if p_action='open' then
  if p_amount<0 then raise exception 'Fondo iniziale non valido';end if;
  select * into v_row from public.cash_sessions where id=p_session;
  if found then
   if v_row.actor_id<>p_actor or v_row.bar_id<>p_bar or v_row.opening_cents<>p_amount
   then raise exception 'ID turno già utilizzato';end if;
   return jsonb_build_object('id',v_row.id,'duplicate',true);
  end if;
  insert into public.cash_sessions(id,school_id,bar_id,actor_id,opening_cents)
   values(p_session,v_school,p_bar,p_actor,p_amount);
 else
  select * into v_row from public.cash_sessions where id=p_session for update;
  if not found or v_row.bar_id<>p_bar or
    (p_action<>'adjustment' and v_row.actor_id<>p_actor)
  then raise exception 'Turno di un altro operatore o bar';end if;
  if p_action='adjustment' then
   if not app_private.can_review_school_offline(v_school) or v_row.closed_at is null
   then raise exception 'Rettifica riservata ad Admin 2FA dopo la chiusura';end if;
  elsif p_action='close' and v_row.closed_at is not null then
   if v_row.counted_cents<>p_amount or v_row.closing_reason<>coalesce(btrim(p_reason),'')
   then raise exception 'Chiusura confermata immutabile';end if;
   return jsonb_build_object('id',v_row.id,'duplicate',true);
  elsif v_row.closed_at is not null then raise exception 'Turno già chiuso';end if;
  if p_action='close' then
   if p_amount<0 then raise exception 'Conteggio non valido';end if;
   select v_row.opening_cents+coalesce(sum(amount_cents),0) into v_expected
    from public.cash_entries where session_id=p_session;
   if p_amount<>v_expected and length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Differenza di cassa: motivazione obbligatoria di almeno 10 caratteri';end if;
   update public.cash_sessions set closed_at=now(),expected_cents=v_expected,
    counted_cents=p_amount,closing_reason=coalesce(btrim(p_reason),'') where id=p_session;
  else
   if p_amount=0 or (p_action<>'adjustment' and p_amount<0) or
      length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Importo e motivazione (10–500 caratteri) obbligatori';end if;
   if exists(select 1 from public.cash_entries where source_key='operation:'||p_key and
     (session_id<>p_session or actor_id<>p_actor or reason<>btrim(p_reason) or
      amount_cents<>case when p_action='withdrawal' then -p_amount else p_amount end))
   then raise exception 'Idempotenza riutilizzata per movimento differente';end if;
   insert into public.cash_entries(session_id,school_id,bar_id,actor_id,kind,amount_cents,source_key,reason)
   values(p_session,v_school,p_bar,p_actor,p_action,
    case when p_action='withdrawal' then -p_amount else p_amount end,'operation:'||p_key,btrim(p_reason))
   on conflict(source_key) do nothing;
  end if;
 end if;
 return jsonb_build_object('id',p_session,'status',p_action,'expected_cents',v_expected);
end;$$;
revoke all on function app_private.apply_cash_operation(uuid,uuid,uuid,text,bigint,text,uuid)
 from public,anon,authenticated;

create or replace function public.record_cash_operation(
 p_bar uuid,p_session uuid,p_action text,p_amount bigint,p_reason text,p_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_school uuid;
begin
 select school_id into v_school from public.bars where id=p_bar;
 if (p_action='adjustment' and not app_private.can_review_school_offline(v_school)) or
    (p_action<>'adjustment' and not app_private.has_barista_role(v_school,auth.uid()))
 then raise exception 'Operatore cassa non autorizzato';end if;
 return app_private.apply_cash_operation(auth.uid(),p_bar,p_session,p_action,p_amount,p_reason,p_key);
end;$$;
revoke all on function public.record_cash_operation(uuid,uuid,text,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.record_cash_operation(uuid,uuid,text,bigint,text,uuid) to authenticated;

create or replace function public.cash_workspace(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_admin boolean;v_sessions jsonb;v_entries jsonb;v_unassigned bigint;
begin
 v_admin:=app_private.can_review_school_offline(p_school);
 if not v_admin and not app_private.has_barista_role(p_school,auth.uid()) then
  raise exception 'Accesso cassa non autorizzato';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.opened_at desc),'[]'::jsonb) into v_sessions
 from (select s.*,s.opening_cents+coalesce((select sum(amount_cents) from public.cash_entries
   where session_id=s.id and kind<>'adjustment'),0) as current_expected_cents,
   coalesce((select sum(amount_cents) from public.cash_entries
    where session_id=s.id and kind='adjustment'),0) as adjustments_cents
  from public.cash_sessions s where s.school_id=p_school and (v_admin or s.actor_id=auth.uid())
  order by opened_at desc limit 100) x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_entries
 from (select e.* from public.cash_entries e where school_id=p_school and
  (v_admin or actor_id=auth.uid()) order by created_at desc limit 300) x;
 select coalesce(sum(amount_cents),0) into v_unassigned from public.cash_entries where
  school_id=p_school and session_id is null and (v_admin or actor_id=auth.uid());
 return jsonb_build_object('sessions',v_sessions,'entries',v_entries,'unassigned_cents',v_unassigned);
end;$$;
revoke all on function public.cash_workspace(uuid) from public,anon,authenticated;
grant execute on function public.cash_workspace(uuid) to authenticated;

-- Keep historical device generations so a later transfer cannot change the tenant
-- attributed to pending physical operations. A revoked operator may upload only
-- events tied to their own previously issued lease; posting remains denied.
create table app_private.offline_lease_history (
 barista_id uuid not null references auth.users(id),
 school_id uuid not null references public.schools(id),
 device_id uuid not null,generation bigint not null,
 issued_at timestamptz not null,expires_at timestamptz not null,revoked_at timestamptz,
 primary key(barista_id,device_id,generation)
);
create index offline_history_school on app_private.offline_lease_history(school_id);
alter table app_private.offline_lease_history enable row level security;
revoke all on app_private.offline_lease_history from public,anon,authenticated;
insert into app_private.offline_lease_history
 select barista_id,school_id,device_id,generation,issued_at,expires_at,revoked_at
 from public.staff_offline_leases;
create or replace function app_private.remember_offline_lease()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  update app_private.offline_lease_history set revoked_at=coalesce(old.revoked_at,now())
   where barista_id=old.barista_id and device_id=old.device_id and generation=old.generation;
 end if;
 insert into app_private.offline_lease_history
 values(new.barista_id,new.school_id,new.device_id,new.generation,new.issued_at,new.expires_at,new.revoked_at)
 on conflict(barista_id,device_id,generation) do update set revoked_at=excluded.revoked_at;
 return new;
end;$$;
revoke all on function app_private.remember_offline_lease() from public,anon,authenticated;
create trigger offline_lease_history after insert or update on public.staff_offline_leases
for each row execute function app_private.remember_offline_lease();

create or replace function public.stage_my_offline_event(
 p_device uuid,p_generation bigint,p_request_key uuid,p_kind text,
 p_local_recorded_at timestamptz,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_lease app_private.offline_lease_history%rowtype;
 v_existing public.offline_events_inbox%rowtype;v_id uuid;v_reason text;
begin
 if v_user is null or p_device is null or p_request_key is null or p_generation is null
  or p_kind is null or p_kind not in ('counter_sale','cash_pickup','shift_change')
  or p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>65536
 then raise exception 'Evento offline non valido';end if;
 select * into v_lease from app_private.offline_lease_history where
  barista_id=v_user and device_id=p_device and generation=p_generation;
 if not found then raise exception 'Nessuna autorizzazione storica corrispondente';end if;
 select * into v_existing from public.offline_events_inbox
  where barista_id=v_user and request_key=p_request_key;
 if found then
  if v_existing.device_id<>p_device or v_existing.lease_generation<>p_generation or
    v_existing.event_kind<>p_kind or v_existing.payload<>p_payload or
    v_existing.local_recorded_at is distinct from p_local_recorded_at
  then raise exception 'ID evento riutilizzato con contenuto differente';end if;
  return jsonb_build_object('id',v_existing.id,'status',v_existing.status);
 end if;
 if (select count(*) from public.offline_events_inbox where barista_id=v_user
  and received_at>now()-interval '1 hour')>=500 then raise exception 'Limite acquisizione eventi: riprova più tardi';end if;
 v_reason:=case
  when not app_private.has_barista_role(v_lease.school_id,v_user) then 'Ruolo revocato: verifica Admin necessaria'
  when v_lease.revoked_at is not null then 'Dispositivo revocato: verifica Admin necessaria'
  when v_lease.expires_at<now() then 'Lease scaduto: verifica Admin necessaria'
  when p_local_recorded_at is null or p_local_recorded_at<v_lease.issued_at or
    p_local_recorded_at>least(v_lease.expires_at,now()+interval '2 minutes') then 'Orario locale non verificabile'
  else 'In attesa di riconciliazione server' end;
 insert into public.offline_events_inbox(barista_id,school_id,device_id,lease_generation,
  request_key,event_kind,local_recorded_at,payload,review_reason)
 values(v_user,v_lease.school_id,p_device,p_generation,p_request_key,p_kind,
  p_local_recorded_at,p_payload,v_reason) returning id into v_id;
 return jsonb_build_object('id',v_id,'status','quarantined','reason',v_reason);
end;$$;
revoke all on function public.stage_my_offline_event(uuid,bigint,uuid,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.stage_my_offline_event(uuid,bigint,uuid,text,timestamptz,jsonb) to authenticated;

create or replace function app_private.post_cash_shift_event(p_event uuid,p_admin boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.offline_events_inbox%rowtype;l public.staff_offline_leases%rowtype;v_result jsonb;v_bar uuid;
begin
 select * into e from public.offline_events_inbox where id=p_event for update;
 if not found or e.event_kind<>'shift_change' then raise exception 'Evento turno non valido';end if;
 if e.status='applied' then return jsonb_build_object('status','duplicate');end if;
 if p_admin then
  if e.status<>'approved' or not app_private.can_review_school_offline(e.school_id)
  then raise exception 'Approvazione Admin 2FA richiesta';end if;
 else
  select * into l from public.staff_offline_leases where barista_id=e.barista_id;
  if e.barista_id<>auth.uid() or not app_private.has_barista_role(e.school_id,auth.uid()) or
    l.device_id is distinct from e.device_id or l.generation is distinct from e.lease_generation or
    l.revoked_at is not null or l.expires_at<=now() or e.local_recorded_at is null or
    e.local_recorded_at not between l.issued_at and least(l.expires_at,e.received_at+interval '2 minutes')
  then return jsonb_build_object('status','quarantined');end if;
  if e.status<>'quarantined' then raise exception 'Evento non acquisibile';end if;
 end if;
 v_bar:=(e.payload->>'bar_id')::uuid;
 if not exists(select 1 from public.bars where id=v_bar and school_id=e.school_id)
 then raise exception 'Bar di altra scuola';end if;
 if e.payload->>'action' not in ('open','deposit','withdrawal','close')
 then raise exception 'Azione turno non consentita offline';end if;
 if e.payload->>'action'='close' and exists(select 1 from public.offline_events_inbox prior
   where prior.barista_id=e.barista_id and prior.device_id=e.device_id
    and prior.lease_generation=e.lease_generation and prior.received_at<=e.received_at
    and prior.id<>e.id and prior.status not in ('applied','rejected')
    and prior.event_kind in ('counter_sale','cash_pickup','shift_change'))
 then raise exception 'Risolvi gli eventi precedenti prima di contabilizzare la chiusura';end if;
 v_result:=app_private.apply_cash_operation(e.barista_id,v_bar,
  (e.payload->>'session_id')::uuid,e.payload->>'action',(e.payload->>'amount_cents')::bigint,
  e.payload->>'reason',e.request_key);
 update public.offline_events_inbox set status='applied',review_reason='Turno contabilizzato' where id=p_event;
 return v_result||jsonb_build_object('status','applied');
end;$$;
revoke all on function app_private.post_cash_shift_event(uuid,boolean) from public,anon,authenticated;
create or replace function public.reconcile_my_cash_shift_event(p_event uuid)
returns jsonb language sql security definer set search_path='' as $$
 select app_private.post_cash_shift_event(p_event,false);$$;
create or replace function public.apply_approved_cash_shift_event(p_event uuid)
returns jsonb language sql security definer set search_path='' as $$
 select app_private.post_cash_shift_event(p_event,true);$$;
revoke all on function public.reconcile_my_cash_shift_event(uuid),public.apply_approved_cash_shift_event(uuid)
 from public,anon,authenticated;
grant execute on function public.reconcile_my_cash_shift_event(uuid),public.apply_approved_cash_shift_event(uuid) to authenticated;
commit;
