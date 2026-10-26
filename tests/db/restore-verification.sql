-- CI restore rehearsal: inspect the restored copy, never a live Supabase DB.
reset role;
do $recovery$
declare v_role oid;
begin
 if pg_catalog.to_regclass('public.orders') is null or
    pg_catalog.to_regclass('public.daily_stock') is null or
    pg_catalog.to_regclass('public.payment_attempts') is null or
    pg_catalog.to_regclass('app_private.notification_jobs') is null then
    raise exception 'Core tables missing after restore';
 end if;
 if (select count(*) from public.orders)=0 or
    (select count(*) from public.daily_stock)=0 or
    (select count(*) from public.payment_attempts)=0 or
    (select count(*) from auth.users)=0 then
    raise exception 'Restored database is missing synthetic business records';
 end if;
 if not (select relrowsecurity from pg_catalog.pg_class
         where oid='public.orders'::regclass) then
    raise exception 'RLS on orders was not restored';
 end if;
 v_role:=pg_catalog.to_regprocedure('public.claim_push_jobs(integer)')::oid;
 if v_role is null or
    pg_catalog.has_function_privilege('anon',v_role,'EXECUTE') or
    pg_catalog.has_function_privilege('authenticated',v_role,'EXECUTE') or
    not pg_catalog.has_function_privilege('service_role',v_role,'EXECUTE') then
    raise exception 'Privileged RPC grants were not restored';
 end if;
 if pg_catalog.to_regclass('public.idx_fk_nonexisting') is not null then
    raise exception 'Unexpected test index';
 end if;
end;
$recovery$;
