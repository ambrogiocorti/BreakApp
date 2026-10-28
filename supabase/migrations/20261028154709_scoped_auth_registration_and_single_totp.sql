begin;

-- Only the private registration service can consume its bounded allowance.
create table app_private.admin_registration_limits(
 scope text not null,
 bucket timestamptz not null,
 attempts integer not null check(attempts>0),
 primary key(scope,bucket)
);
alter table app_private.admin_registration_limits enable row level security;
revoke all on app_private.admin_registration_limits from public,anon,authenticated,service_role;

create function public.claim_admin_registration(p_fingerprint text)
returns void language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' or coalesce(p_fingerprint,'')!~'^[a-f0-9]{64}$' then
  raise exception 'Solo backend' using errcode='42501';
 end if;
 insert into app_private.admin_registration_limits(scope,bucket,attempts)
 values(p_fingerprint,date_trunc('minute',now()),1)
 on conflict(scope,bucket) do update set attempts=admin_registration_limits.attempts+1 returning attempts into n;
 if n>5 then raise exception 'Troppe richieste' using errcode='P0001';end if;
 insert into app_private.admin_registration_limits(scope,bucket,attempts)
 values('global-minute',date_trunc('minute',now()),1)
 on conflict(scope,bucket) do update set attempts=admin_registration_limits.attempts+1 returning attempts into n;
 if n>30 then raise exception 'Limite temporaneo del servizio' using errcode='P0001';end if;
 insert into app_private.admin_registration_limits(scope,bucket,attempts)
 values('global-day',date_trunc('day',now()),1)
 on conflict(scope,bucket) do update set attempts=admin_registration_limits.attempts+1 returning attempts into n;
 if n>200 then raise exception 'Limite giornaliero del servizio' using errcode='P0001';end if;
 delete from app_private.admin_registration_limits where bucket<now()-interval '2 days';
end;$$;
revoke all on function public.claim_admin_registration(text) from public,anon,authenticated;
grant execute on function public.claim_admin_registration(text) to service_role;

-- Guard the Auth persistence boundary as well as the UI. Existing verified
-- authenticators are retained; new spare factors and activation of an older
-- pending spare are refused. The per-user lock also serializes parallel enrolls.
create function app_private.enforce_single_totp_factor()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.factor_type<>'totp' then return new;end if;
 if tg_op='UPDATE' then
  if new.user_id=old.user_id and new.factor_type=old.factor_type and
    (new.status=old.status or new.status<>'verified') then return new;end if;
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('breakapp:single-totp:'||new.user_id::text,0));
 if exists(select 1 from auth.mfa_factors f where f.user_id=new.user_id and f.factor_type='totp' and f.id<>new.id) then
  raise exception 'Un Authenticator è già associato. Non è consentito aggiungerne uno di riserva.' using errcode='23514';
 end if;
 return new;
end;$$;
revoke all on function app_private.enforce_single_totp_factor() from public,anon,authenticated,service_role;
create trigger breakapp_single_totp_factor
 before insert or update of user_id,factor_type,status on auth.mfa_factors
 for each row execute function app_private.enforce_single_totp_factor();
comment on function app_private.enforce_single_totp_factor() is 'Blocks additional TOTP enrollment and pending-spare activation without deleting existing authenticators.';

commit;
