-- Preserve already staged legacy events and require explicit Admin approval for late cash.
begin;
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
 select * into v_existing from public.offline_events_inbox
  where barista_id=v_user and request_key=p_request_key;
 if found then
  if v_existing.device_id<>p_device or v_existing.lease_generation<>p_generation or
    v_existing.event_kind<>p_kind or v_existing.payload<>p_payload or
    v_existing.local_recorded_at is distinct from p_local_recorded_at
  then raise exception 'ID evento riutilizzato con contenuto differente';end if;
  return jsonb_build_object('id',v_existing.id,'status',v_existing.status);
 end if;
 select * into v_lease from app_private.offline_lease_history where
  barista_id=v_user and device_id=p_device and generation=p_generation;
 if not found then raise exception 'Nessuna autorizzazione storica corrispondente';end if;
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
   where (e.id=new.request_key or e.request_key=new.request_key) and e.barista_id=new.actor_id;
 end if;
 if v_event is not null then
  select nullif(payload->>'cash_session_id','')::uuid into v_requested
   from public.offline_events_inbox where id=v_event;
 end if;
 select id into v_session from public.cash_sessions
  where bar_id=new.bar_id and actor_id=new.actor_id and closed_at is null for update;
 if v_requested is not null and v_requested is distinct from v_session then
  if exists(select 1 from public.offline_events_inbox where id=v_event and status='approved')
    and app_private.can_review_school_offline(new.school_id) and exists(
      select 1 from public.cash_sessions where id=v_requested and bar_id=new.bar_id
       and school_id=new.school_id and actor_id=new.actor_id)
  then v_session:=v_requested;
  else raise exception 'Turno offline non più aperto: richiesta revisione Admin';end if;
 end if;
 insert into public.cash_entries(session_id,school_id,bar_id,actor_id,kind,amount_cents,source_key)
 values(v_session,new.school_id,new.bar_id,new.actor_id,'receipt',new.amount_cents,v_source)
 on conflict(source_key) do nothing;
 return new;
end;$$;
revoke all on function app_private.capture_cash_receipt() from public,anon,authenticated;
commit;
