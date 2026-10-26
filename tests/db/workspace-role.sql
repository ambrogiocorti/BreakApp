-- Test identità Super Admin: AAL1 non basta, l'account deve essere assegnato.
reset role;
insert into app_private.platform_admins(user_id)
values('44444444-4444-4444-8444-444444444444');
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $aal1_platform$
begin
 if public.is_current_platform_admin() then
 raise exception 'Platform role granted without MFA';end if;
end;
$aal1_platform$;
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $aal2_platform$
begin
 if not public.is_current_platform_admin() then
 raise exception 'Platform admin AAL2 not recognized';end if;
end;
$aal2_platform$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $non_platform$
begin
 if public.is_current_platform_admin() then
 raise exception 'Platform admin leaked to ordinary user';end if;
end;
$non_platform$;
reset role;
