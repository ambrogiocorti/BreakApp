begin;
-- The registered email identity proves mailbox ownership; the financial guest
-- identity remains unchanged. No global Secure Email Change setting is relaxed.
create table app_private.guest_email_requests(
 id uuid primary key default gen_random_uuid(),guest_user_id uuid not null references auth.users(id) on delete cascade,
 email_hash text not null check(email_hash~'^[a-f0-9]{64}$'),state text not null default 'pending' check(state in ('pending','verified','expired')),
 verified_identity_id uuid references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '1 hour',verified_at timestamptz);
create index guest_email_requests_guest on app_private.guest_email_requests(guest_user_id,created_at);
create index guest_email_requests_identity on app_private.guest_email_requests(verified_identity_id);
create index guest_email_requests_hash on app_private.guest_email_requests(email_hash,state);
create unique index guest_email_request_pending on app_private.guest_email_requests(guest_user_id,email_hash) where state='pending';
create table app_private.guest_email_links(
 guest_user_id uuid primary key references auth.users(id) on delete cascade,
 verified_identity_id uuid not null unique references auth.users(id) on delete cascade,
 verified_at timestamptz not null default now());
alter table app_private.guest_email_requests enable row level security;
alter table app_private.guest_email_links enable row level security;
revoke all on app_private.guest_email_requests,app_private.guest_email_links from public,anon,authenticated,service_role;
create function public.prepare_guest_email_recovery(p_guest uuid,p_email_hash text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;begin
 if auth.jwt()->>'role' is distinct from 'service_role' or coalesce(p_email_hash,'')!~'^[a-f0-9]{64}$' then raise exception 'Solo backend';end if;
 perform 1 from app_private.guest_access_keys g join public.schools s on s.id=g.school_id where g.user_id=p_guest and g.revoked_at is null and s.is_active for update of g;
 if not found then raise exception 'Profilo ospite non disponibile';end if;
 update app_private.guest_email_requests set state='expired' where guest_user_id=p_guest and state='pending' and expires_at<=now();
 select id into v_id from app_private.guest_email_requests where guest_user_id=p_guest and email_hash=p_email_hash and state='pending';
 if found then return v_id;end if;
 if (select count(*) from app_private.guest_email_requests where guest_user_id=p_guest and created_at>now()-interval '1 hour')>=5 then raise exception 'Troppe richieste di recupero: riprova più tardi';end if;
 insert into app_private.guest_email_requests(guest_user_id,email_hash) values(p_guest,p_email_hash) returning id into v_id;
 return v_id;end;$$;
create function public.list_verified_guest_recovery(p_identity uuid,p_email_hash text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare pending jsonb;linked jsonb;begin
 if auth.jwt()->>'role' is distinct from 'service_role' or not exists(select 1 from auth.users where id=p_identity and email_confirmed_at is not null) or coalesce(p_email_hash,'')!~'^[a-f0-9]{64}$' then raise exception 'Identità email verificata richiesta';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',g.name,'school',s.name)),'[]'::jsonb) into pending
 from app_private.guest_email_requests r join app_private.guest_access_keys g on g.user_id=r.guest_user_id join public.schools s on s.id=g.school_id
 where r.email_hash=p_email_hash and r.state='pending' and r.expires_at>now() and g.revoked_at is null and s.is_active;
 select coalesce(jsonb_agg(jsonb_build_object('id',g.user_id,'name',g.name,'school',s.name)),'[]'::jsonb) into linked
 from app_private.guest_email_links l join app_private.guest_access_keys g on g.user_id=l.guest_user_id join public.schools s on s.id=g.school_id
 where l.verified_identity_id=p_identity and g.revoked_at is null and s.is_active;
 return jsonb_build_object('pending',pending,'linked',linked);end;$$;
create function public.confirm_guest_email_recovery(p_request uuid,p_identity uuid,p_email_hash text)
returns uuid language plpgsql security definer set search_path='' as $$
declare r app_private.guest_email_requests%rowtype;begin
 if auth.jwt()->>'role' is distinct from 'service_role' or not exists(select 1 from auth.users where id=p_identity and email_confirmed_at is not null) then raise exception 'Identità email verificata richiesta';end if;
 select * into r from app_private.guest_email_requests where id=p_request for update;
 if found and r.state='verified' and r.verified_identity_id=p_identity and r.email_hash=p_email_hash then return r.guest_user_id;end if;
 if not found or r.email_hash is distinct from p_email_hash or r.state<>'pending' or r.expires_at<=now() then raise exception 'Richiesta non disponibile per questa email';end if;
 perform 1 from app_private.guest_access_keys g join public.schools s on s.id=g.school_id where g.user_id=r.guest_user_id and g.revoked_at is null and s.is_active for update of g;
 if not found then raise exception 'Profilo ospite non disponibile';end if;
 if exists(select 1 from app_private.guest_email_links where verified_identity_id=p_identity and guest_user_id<>r.guest_user_id) then raise exception 'Email già collegata a un altro profilo ospite: recupera quello esistente';end if;
 insert into app_private.guest_email_links(guest_user_id,verified_identity_id) values(r.guest_user_id,p_identity)
 on conflict(guest_user_id) do update set verified_identity_id=excluded.verified_identity_id,verified_at=now();
 update app_private.guest_email_requests set state='verified',verified_identity_id=p_identity,verified_at=now() where id=r.id;
 return r.guest_user_id;end;$$;
create function public.resolve_verified_guest_recovery(p_identity uuid)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare v_user uuid;begin
 if auth.jwt()->>'role' is distinct from 'service_role' or not exists(select 1 from auth.users where id=p_identity and email_confirmed_at is not null) then raise exception 'Identità email verificata richiesta';end if;
 select g.user_id into v_user from app_private.guest_email_links l join app_private.guest_access_keys g on g.user_id=l.guest_user_id join public.schools s on s.id=g.school_id
 where l.verified_identity_id=p_identity and g.revoked_at is null and s.is_active;return v_user;end;$$;
create function public.rotate_guest_private_link(p_guest uuid,p_hash text)
returns void language plpgsql security definer set search_path='' as $$begin
 if auth.jwt()->>'role' is distinct from 'service_role' or coalesce(p_hash,'')!~'^[a-f0-9]{64}$' then raise exception 'Solo backend';end if;
 update app_private.guest_access_keys set token_hash=p_hash,expires_at=now()+interval '30 days' where user_id=p_guest and revoked_at is null;
 if not found then raise exception 'Profilo ospite non disponibile';end if;
end;$$;
revoke all on function public.prepare_guest_email_recovery(uuid,text),public.list_verified_guest_recovery(uuid,text),
 public.confirm_guest_email_recovery(uuid,uuid,text),public.resolve_verified_guest_recovery(uuid),public.rotate_guest_private_link(uuid,text) from public,anon,authenticated;
grant execute on function public.prepare_guest_email_recovery(uuid,text),public.list_verified_guest_recovery(uuid,text),
 public.confirm_guest_email_recovery(uuid,uuid,text),public.resolve_verified_guest_recovery(uuid),public.rotate_guest_private_link(uuid,text) to service_role;
create function public.my_guest_email_recovery_status()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.guest_email_links where guest_user_id=(select auth.uid()));
$$;
create function public.remove_my_guest_email_recovery()
returns void language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from app_private.guest_access_keys where user_id=auth.uid()) then raise exception 'Accesso ospite richiesto';end if;
 delete from app_private.guest_email_links where guest_user_id=auth.uid();
 update app_private.guest_email_requests set state='expired' where guest_user_id=auth.uid() and state='pending';
end;$$;
revoke all on function public.my_guest_email_recovery_status(),public.remove_my_guest_email_recovery() from public,anon,authenticated;
grant execute on function public.my_guest_email_recovery_status(),public.remove_my_guest_email_recovery() to authenticated;
commit;
