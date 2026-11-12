begin;
alter table public.schools add column require_guest_class boolean not null default false;
create table app_private.guest_access_keys(
 user_id uuid primary key references auth.users(id) on delete cascade,
 school_id uuid not null references public.schools(id),name text not null check(length(name) between 2 and 100),
 class_name text not null default '' check(length(class_name)<=80),token_hash text not null unique check(token_hash~'^[a-f0-9]{64}$'),
 expires_at timestamptz not null default now()+interval '30 days',revoked_at timestamptz,created_at timestamptz not null default now()
);
create index guest_school on app_private.guest_access_keys(school_id);
create table app_private.guest_rate_limits(fingerprint text not null,minute_bucket timestamptz not null,n integer not null,primary key(fingerprint,minute_bucket));
alter table app_private.guest_access_keys enable row level security;
alter table app_private.guest_rate_limits enable row level security;
revoke all on app_private.guest_access_keys,app_private.guest_rate_limits from public,anon,authenticated,service_role;
create function public.claim_guest_creation(p_fingerprint text)
returns void language plpgsql security definer set search_path='' as $$
declare n integer;begin
 if auth.jwt()->>'role' is distinct from 'service_role' or coalesce(p_fingerprint,'')!~'^[a-f0-9]{64}$' then raise exception 'Solo backend';end if;
 insert into app_private.guest_rate_limits(fingerprint,minute_bucket,n) values(p_fingerprint,date_trunc('minute',now()),1)
 on conflict(fingerprint,minute_bucket) do update set n=guest_rate_limits.n+1 returning guest_rate_limits.n into n;
 if n>10 then raise exception 'Troppe richieste: riprova più tardi';end if;
 insert into app_private.guest_rate_limits(fingerprint,minute_bucket,n) values('global-minute',date_trunc('minute',now()),1)
 on conflict(fingerprint,minute_bucket) do update set n=guest_rate_limits.n+1 returning guest_rate_limits.n into n;
 if n>300 then raise exception 'Limite temporaneo del servizio ospiti raggiunto';end if;
 insert into app_private.guest_rate_limits(fingerprint,minute_bucket,n) values('global-day',date_trunc('day',now()),1)
 on conflict(fingerprint,minute_bucket) do update set n=guest_rate_limits.n+1 returning guest_rate_limits.n into n;
 if n>1000 then raise exception 'Limite giornaliero del servizio ospiti raggiunto';end if;
 delete from app_private.guest_rate_limits where minute_bucket<now()-interval '1 day';
end;$$;
create function public.create_guest_access(p_user uuid,p_school uuid,p_name text,p_class text,p_hash text)
returns void language plpgsql security definer set search_path='' as $$
declare m uuid;begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo backend';end if;
 if not exists(select 1 from public.schools where id=p_school and is_active) then raise exception 'Scuola non disponibile';end if;
 if exists(select 1 from public.schools where id=p_school and require_guest_class) and not exists(select 1 from public.school_classes where school_id=p_school and name=btrim(p_class) and active) then raise exception 'Scegli una classe attiva della scuola';end if;
 insert into app_private.guest_access_keys(user_id,school_id,name,class_name,token_hash) values(p_user,p_school,btrim(p_name),btrim(p_class),p_hash);
 insert into public.school_memberships(school_id,user_id,membership_status) values(p_school,p_user,'active') returning id into m;
 insert into public.role_assignments(membership_id,role_code) values(m,'customer');
end;$$;
create function public.resolve_guest_access(p_hash text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid;begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo backend';end if;
 select user_id into v_user from app_private.guest_access_keys k join public.schools s on s.id=k.school_id
 where k.token_hash=p_hash and k.revoked_at is null and k.expires_at>now() and s.is_active;return v_user;
end;$$;
revoke all on function public.claim_guest_creation(text),public.create_guest_access(uuid,uuid,text,text,text),public.resolve_guest_access(text) from public,anon,authenticated;
grant execute on function public.claim_guest_creation(text),public.create_guest_access(uuid,uuid,text,text,text),public.resolve_guest_access(text) to service_role;
-- Guest authorization derives from a protected row, never user-editable metadata.
create or replace function app_private.is_registered_group_user(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null and not exists(select 1 from app_private.platform_admins where user_id=p_user)
 and not exists(select 1 from app_private.guest_access_keys where user_id=p_user)
 and coalesce(auth.jwt()->>'is_anonymous','false')<>'true';
$$;
create function public.my_guest_profile()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb;begin
 select jsonb_build_object('name',name,'school_id',school_id,'class_name',class_name,'expires_at',expires_at)
 into j from app_private.guest_access_keys where user_id=auth.uid();return j;
end;$$;
revoke all on function public.my_guest_profile() from public,anon,authenticated;
grant execute on function public.my_guest_profile() to authenticated;

create table public.school_classes(
 id uuid primary key default gen_random_uuid(),school_id uuid not null references public.schools(id),
 name text not null check(length(name) between 1 and 80),active boolean not null default true,unique(school_id,name)
);
create index school_class_school on public.school_classes(school_id);
alter table public.school_classes enable row level security;
revoke all on public.school_classes from public,anon,authenticated;
grant select on public.school_classes to anon,authenticated;
create policy classes_active on public.school_classes for select to anon,authenticated using(active and exists(select 1 from public.schools s where s.id=school_classes.school_id and s.is_active));
create function public.set_guest_class_policy(p_school uuid,p_required boolean)
returns void language plpgsql security definer set search_path='' as $$begin
 if not app_private.can_review_school_offline(p_school) or p_required is null then raise exception 'Admin con 2FA richiesto';end if;
 if p_required and not exists(select 1 from public.school_classes where school_id=p_school and active) then raise exception 'Importa prima le classi della scuola';end if;
 update public.schools set require_guest_class=p_required where id=p_school;
end;$$;
revoke all on function public.set_guest_class_policy(uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_guest_class_policy(uuid,boolean) to authenticated;
create table app_private.school_onboarding_audit(
 id bigint generated always as identity primary key,school_id uuid not null references public.schools(id),actor_id uuid not null references auth.users(id),
 action text not null,details jsonb not null,created_at timestamptz not null default now()
);
alter table app_private.school_onboarding_audit enable row level security;
create index school_onboarding_school on app_private.school_onboarding_audit(school_id);
create index school_onboarding_actor on app_private.school_onboarding_audit(actor_id);
revoke all on app_private.school_onboarding_audit from public,anon,authenticated;
create function public.platform_onboard_school(p_slug text,p_name text,p_bar_name text,p_latitude double precision,p_longitude double precision,p_mode text,p_admin_email text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_bar uuid;begin
 if not app_private.platform_approved() then raise exception 'Super Admin con 2FA richiesto';end if;
 if p_latitude is null or p_longitude is null or p_mode not in ('active','ready_made') then raise exception 'Posizione e modalità richieste';end if;
 insert into public.schools(slug,name,latitude,longitude) values(lower(btrim(p_slug)),btrim(p_name),p_latitude,p_longitude) returning id into v_school;
 insert into public.bars(school_id,name,preparation_mode) values(v_school,btrim(p_bar_name),p_mode) returning id into v_bar;
 insert into public.bar_service_state(school_id,bar_id,accepting_orders,reason) values(v_school,v_bar,false,'Completa menu, orari, fasce e scorte prima di aprire il servizio');
 perform public.platform_assign_school_staff(v_school,p_admin_email,'school_admin');
 insert into app_private.school_onboarding_audit(school_id,actor_id,action,details) values(v_school,auth.uid(),'created',jsonb_build_object('bar_id',v_bar));
 return jsonb_build_object('school_id',v_school,'bar_id',v_bar);
end;$$;
create function public.import_school_classes(p_school uuid,p_names jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 if not app_private.can_review_school_offline(p_school) or jsonb_typeof(p_names)<>'array' or jsonb_array_length(p_names) not between 1 and 1000
 then raise exception 'Admin con 2FA e massimo 1000 classi richiesti';end if;
 insert into public.school_classes(school_id,name) select distinct p_school,btrim(value) from jsonb_array_elements_text(p_names)
 on conflict(school_id,name) do update set active=true;get diagnostics n=row_count;return n;
end;$$;
create function public.school_assign_staff(p_school uuid,p_email text,p_role text)
returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid;v_member uuid;begin
 if not app_private.can_review_school_offline(p_school) or p_role not in ('bartender','warehouse_manager') then raise exception 'Admin scuola con 2FA richiesto';end if;
 select id into v_user from auth.users where lower(email)=lower(btrim(p_email)) and email_confirmed_at is not null;
 if v_user is null or exists(select 1 from app_private.platform_admins where user_id=v_user) or exists(select 1 from app_private.guest_access_keys where user_id=v_user)
 then raise exception 'È richiesto un account registrato con email verificata';end if;
 insert into public.school_memberships(school_id,user_id,membership_status) values(p_school,v_user,'active')
 on conflict(school_id,user_id) do update set membership_status='active' returning id into v_member;
 insert into public.role_assignments(membership_id,role_code) values(v_member,p_role) on conflict do nothing;
 insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action) values(auth.uid(),v_user,p_school,p_role,'role_assigned');
end;$$;
create function public.platform_set_school_active(p_school uuid,p_active boolean,p_reason text)
returns void language plpgsql security definer set search_path='' as $$begin
 if not app_private.platform_approved() or length(btrim(coalesce(p_reason,'')))<8 or p_active is null then raise exception 'Super Admin con 2FA e motivazione richiesti';end if;
 update public.schools set is_active=p_active where id=p_school;
 insert into app_private.school_onboarding_audit(school_id,actor_id,action,details) values(p_school,auth.uid(),'active_changed',jsonb_build_object('active',p_active,'reason',p_reason));
end;$$;
revoke all on function public.platform_onboard_school(text,text,text,double precision,double precision,text,text),public.import_school_classes(uuid,jsonb),public.school_assign_staff(uuid,text,text),public.platform_set_school_active(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.platform_onboard_school(text,text,text,double precision,double precision,text,text),public.import_school_classes(uuid,jsonb),public.school_assign_staff(uuid,text,text),public.platform_set_school_active(uuid,boolean,text) to authenticated;
do $$declare d text;begin
 d:=pg_get_functiondef('public.transfer_group_coordinator(uuid,uuid)'::regprocedure);
 d:=replace(d,'if exists(select 1 from app_private.platform_admins where user_id=p_new_coordinator)',
 'if exists(select 1 from app_private.guest_access_keys where user_id=p_new_coordinator) or exists(select 1 from app_private.platform_admins where user_id=p_new_coordinator)');execute d;
end;$$;
commit;
