begin;
-- A verified request is idempotent only while its current recovery link remains active.
create or replace function public.confirm_guest_email_recovery(p_request uuid,p_identity uuid,p_email_hash text)
returns uuid language plpgsql security definer set search_path='' as $$
declare r app_private.guest_email_requests%rowtype;begin
 if auth.jwt()->>'role' is distinct from 'service_role' or not exists(select 1 from auth.users where id=p_identity and email_confirmed_at is not null) then raise exception 'Identità email verificata richiesta';end if;
 select * into r from app_private.guest_email_requests where id=p_request for update;
 if found and r.state='verified' and r.verified_identity_id=p_identity and r.email_hash=p_email_hash
 and exists(select 1 from app_private.guest_email_links l
  join app_private.guest_access_keys g on g.user_id=l.guest_user_id
  join public.schools s on s.id=g.school_id
  where l.guest_user_id=r.guest_user_id and l.verified_identity_id=p_identity
   and g.revoked_at is null and s.is_active)
 then return r.guest_user_id;end if;
 if not found or r.email_hash is distinct from p_email_hash or r.state<>'pending' or r.expires_at<=now() then raise exception 'Richiesta non disponibile per questa email';end if;
 perform 1 from app_private.guest_access_keys g join public.schools s on s.id=g.school_id where g.user_id=r.guest_user_id and g.revoked_at is null and s.is_active for update of g;
 if not found then raise exception 'Profilo ospite non disponibile';end if;
 if exists(select 1 from app_private.guest_email_links where verified_identity_id=p_identity and guest_user_id<>r.guest_user_id) then raise exception 'Email già collegata a un altro profilo ospite: recupera quello esistente';end if;
 insert into app_private.guest_email_links(guest_user_id,verified_identity_id) values(r.guest_user_id,p_identity)
 on conflict(guest_user_id) do update set verified_identity_id=excluded.verified_identity_id,verified_at=now();
 update app_private.guest_email_requests set state='verified',verified_identity_id=p_identity,verified_at=now() where id=r.id;
 return r.guest_user_id;end;$$;
revoke all on function public.confirm_guest_email_recovery(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.confirm_guest_email_recovery(uuid,uuid,text) to service_role;
commit;
