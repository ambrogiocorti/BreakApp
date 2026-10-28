-- Disposable PostgreSQL CI only. No real user identity or Auth secret is used.
begin;
reset role;
insert into auth.users(id,email) values
 ('ab100000-0000-4000-8000-000000000001','auth-policy-one@example.invalid'),
 ('ab100000-0000-4000-8000-000000000002','auth-policy-two@example.invalid');

-- An Auth service role can enroll the first factor despite the helper being
-- private and not executable through the public Data API.
set role supabase_auth_admin;
insert into auth.mfa_factors(id,user_id,factor_type,status) values
 ('ab200000-0000-4000-8000-000000000001','ab100000-0000-4000-8000-000000000001','totp','unverified');
update auth.mfa_factors set status='verified' where id='ab200000-0000-4000-8000-000000000001';
update auth.mfa_factors set last_challenged_at=now(),status='verified' where id='ab200000-0000-4000-8000-000000000001';
do $$declare denied boolean:=false;begin
 begin
  insert into auth.mfa_factors(id,user_id,factor_type,status) values
   ('ab200000-0000-4000-8000-000000000002','ab100000-0000-4000-8000-000000000001','totp','unverified');
 exception when check_violation then denied:=true;end;
 if not denied then raise exception 'Second Authenticator was permitted';end if;
end;$$;
-- A separate account retains its own independent first factor.
insert into auth.mfa_factors(id,user_id,factor_type,status) values
 ('ab200000-0000-4000-8000-000000000003','ab100000-0000-4000-8000-000000000002','totp','unverified');
delete from auth.mfa_factors where id='ab200000-0000-4000-8000-000000000003';
insert into auth.mfa_factors(id,user_id,factor_type,status) values
 ('ab200000-0000-4000-8000-000000000004','ab100000-0000-4000-8000-000000000002','totp','unverified');
reset role;

-- Legacy spare factors are retained, but a previously pending spare cannot be
-- activated after this policy is installed.
alter table auth.mfa_factors disable trigger breakapp_single_totp_factor;
insert into auth.mfa_factors(id,user_id,factor_type,status) values
 ('ab200000-0000-4000-8000-000000000005','ab100000-0000-4000-8000-000000000001','totp','unverified');
alter table auth.mfa_factors enable trigger breakapp_single_totp_factor;
set role supabase_auth_admin;
do $$declare denied boolean:=false;begin
 begin update auth.mfa_factors set status='verified' where id='ab200000-0000-4000-8000-000000000005';
 exception when check_violation then denied:=true;end;
 if not denied then raise exception 'Pending spare factor was activated';end if;
end;$$;
reset role;
do $$begin
 if (select count(*) from auth.mfa_factors where user_id='ab100000-0000-4000-8000-000000000001')<>2 then raise exception 'Existing factors were removed';end if;
 if has_function_privilege('anon','public.claim_admin_registration(text)','execute') or
    has_function_privilege('authenticated','public.claim_admin_registration(text)','execute') or
    has_function_privilege('anon','app_private.enforce_single_totp_factor()','execute') then
  raise exception 'Unprivileged role can execute auth helpers';end if;
end;$$;

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.claim_admin_registration(repeat('a',64)) from generate_series(1,5);
do $$declare denied boolean:=false;begin
 begin perform public.claim_admin_registration(repeat('a',64));exception when raise_exception then denied:=true;end;
 if not denied then raise exception 'Per-source signup limit was bypassed';end if;
end;$$;
-- A different source has an independent allowance.
select public.claim_admin_registration(repeat('b',64));
reset role;
rollback;
