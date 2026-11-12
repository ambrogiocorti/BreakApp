-- BreakApp 25: safe lifecycle controls for group drafts (no payment/stock mutation).
begin;

create or replace function public.configure_group_draft(
 p_group_id uuid, p_accepting boolean, p_requires_approval boolean,
 p_max_members integer, p_rotate_invite boolean default false
) returns jsonb language plpgsql security definer set search_path=''
as $group_config$
declare v_group public.group_drafts%rowtype; v_active integer;
begin
 if auth.uid() is null or p_group_id is null or p_accepting is null
   or p_requires_approval is null or p_rotate_invite is null
   or (p_max_members is not null and p_max_members not between 1 and 100)
 then raise exception 'Impostazioni gruppo non valide'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>auth.uid() or v_group.status<>'draft'
   or v_group.updated_at < now()-interval '24 hours'
 then raise exception 'Bozza non modificabile dal coordinatore'; end if;
 select count(*) into v_active from public.group_members
   where group_id=p_group_id and status in ('accepted','pending');
 if p_max_members is not null and p_max_members<v_active
 then raise exception 'Limite inferiore ai partecipanti presenti'; end if;
 update public.group_drafts set accepting_members=p_accepting,
   requires_approval=p_requires_approval, max_members=p_max_members,
   invite_token=case when p_rotate_invite then gen_random_uuid() else invite_token end,
   updated_at=now() where id=p_group_id;
 return jsonb_build_object('active_members',v_active,'invite_rotated',p_rotate_invite);
end;$group_config$;

create or replace function public.transfer_group_coordinator(
 p_group_id uuid,p_new_coordinator uuid
) returns void language plpgsql security definer set search_path=''
as $group_transfer$
declare v_group public.group_drafts%rowtype;
begin
 if auth.uid() is null or p_new_coordinator is null
 then raise exception 'Nuovo coordinatore richiesto'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>auth.uid() or v_group.status<>'draft'
   or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Solo il coordinatore attivo può trasferire il gruppo'; end if;
 if p_new_coordinator=auth.uid() then raise exception 'Sei già il coordinatore'; end if;
 if not exists(select 1 from public.group_members where group_id=p_group_id
  and user_id=p_new_coordinator and status='accepted')
 then raise exception 'Seleziona un partecipante approvato'; end if;
 if exists(select 1 from app_private.platform_admins where user_id=p_new_coordinator)
  or not exists(select 1 from auth.users u where u.id=p_new_coordinator
   and coalesce((to_jsonb(u)->>'is_anonymous')::boolean,false)=false)
 then raise exception 'Il coordinatore deve avere un account registrato'; end if;
 update public.group_drafts set coordinator_id=p_new_coordinator,updated_at=now()
 where id=p_group_id;
end;$group_transfer$;

create or replace function public.leave_group_draft(p_group_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_leave$
declare v_group public.group_drafts%rowtype; v_members integer;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status<>'draft'
   or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Gruppo non modificabile'; end if;
 if not exists(select 1 from public.group_members where group_id=p_group_id
   and user_id=auth.uid() and status in ('pending','accepted'))
 then raise exception 'Non fai parte di questo gruppo'; end if;
 if v_group.coordinator_id=auth.uid() then
  select count(*) into v_members from public.group_members
    where group_id=p_group_id and status in ('pending','accepted');
  if v_members>1 then
   raise exception 'Trasferisci il coordinamento prima di uscire';
  end if;
  update public.group_drafts set status='cancelled',accepting_members=false,
    updated_at=now() where id=p_group_id;
 else
  delete from public.group_cart_items where group_id=p_group_id and user_id=auth.uid();
  delete from public.group_members where group_id=p_group_id and user_id=auth.uid();
  update public.group_drafts set updated_at=now() where id=p_group_id;
 end if;
end;$group_leave$;

create or replace function public.cancel_group_draft(p_group_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_cancel$
declare v_group public.group_drafts%rowtype;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>auth.uid() or v_group.status<>'draft'
 then raise exception 'Solo il coordinatore può annullare questa bozza'; end if;
 update public.group_drafts set status='cancelled',accepting_members=false,
  updated_at=now() where id=p_group_id;
end;$group_cancel$;

create or replace function public.reschedule_group_draft(p_group_id uuid,p_window_id uuid)
returns void language plpgsql security definer set search_path=''
as $group_window$
declare v_group public.group_drafts%rowtype; v_window public.pickup_windows%rowtype;
  v_school public.schools%rowtype;
begin
 if auth.uid() is null or p_window_id is null then raise exception 'Fascia richiesta'; end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>auth.uid() or v_group.status<>'draft'
   or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Solo il coordinatore può cambiare fascia'; end if;
 select * into v_window from public.pickup_windows where id=p_window_id
   and school_id=v_group.school_id and bar_id=v_group.bar_id and is_active for share;
 if not found then raise exception 'Fascia non disponibile nel bar del gruppo'; end if;
 select * into v_school from public.schools where id=v_group.school_id and is_active;
 if not found or v_window.service_date<(now() at time zone v_school.timezone)::date
  or v_window.service_date>(now() at time zone v_school.timezone)::date+v_school.booking_horizon_days
  or (v_window.service_date+v_window.starts_at) at time zone v_school.timezone<=now()
 then raise exception 'Fascia scaduta o fuori periodo'; end if;
 update public.group_drafts set pickup_window_id=p_window_id,updated_at=now()
 where id=p_group_id;
end;$group_window$;

revoke all on function public.configure_group_draft(uuid,boolean,boolean,integer,boolean),
 public.transfer_group_coordinator(uuid,uuid),
 public.leave_group_draft(uuid),
 public.cancel_group_draft(uuid),
 public.reschedule_group_draft(uuid,uuid) from public,anon,authenticated;
grant execute on function public.configure_group_draft(uuid,boolean,boolean,integer,boolean),
 public.transfer_group_coordinator(uuid,uuid),
 public.leave_group_draft(uuid),
 public.cancel_group_draft(uuid),
 public.reschedule_group_draft(uuid,uuid) to authenticated;
commit;
