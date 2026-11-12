-- Keep the historical five-argument RPC signature for already deployed clients.
-- Invitation access no longer verifies the participant's location. The separate
-- confirm_group_order RPC still requires a recent, accurate, in-radius GPS fix.
create or replace function public.join_group_draft(
 p_invite_token uuid,p_latitude double precision,p_longitude double precision,
 p_accuracy_m double precision,p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $join_group$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_status text;
begin
 if v_user is null or p_invite_token is null then
  raise exception 'Accedi come partecipante per aprire l''invito';end if;
 select * into v_group from public.group_drafts where invite_token=p_invite_token for update;
 if not found then raise exception 'Invito non valido';end if;
 if v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
   or not v_group.accepting_members then
  raise exception 'Il gruppo non accetta nuovi ingressi';end if;
 select status into v_status from public.group_members
  where group_id=v_group.id and user_id=v_user;
 if found and v_status<>'left' then
  if v_status='rejected' then raise exception 'Ingresso rifiutato';end if;
  return v_group.id;
 end if;
 if v_group.max_members is not null and
  (select count(*) from public.group_members where group_id=v_group.id
   and status in ('accepted','pending'))>=v_group.max_members
 then raise exception 'Gruppo al completo';end if;
 if not exists(select 1 from public.schools
   where id=v_group.school_id and is_active)
 then raise exception 'Scuola non disponibile';end if;
 insert into public.group_members(group_id,user_id,status)
 values(v_group.id,v_user,case when v_group.requires_approval then 'pending' else 'accepted' end)
 on conflict(group_id,user_id) do update
 set status=excluded.status,ready=false,approved_at=null,joined_at=now()
 where public.group_members.status='left';
 update public.group_drafts set updated_at=now() where id=v_group.id;
 return v_group.id;
end;
$join_group$;
