-- Phase A / P0: repeatable permission gates for the complete pilot schema.
-- Run in the disposable CI database only, after all applicable SQL scripts.
reset role;

do $definer_checks$
declare v_anon text;v_path text;v_rls text;
begin
  select string_agg(p.oid::regprocedure::text, E'\n' order by p.oid::regprocedure::text)
  into v_anon
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','app_private') and p.prosecdef
    and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
  if v_anon is not null then
    raise exception 'Anonymous can execute SECURITY DEFINER function(s): %',v_anon;
  end if;

  select string_agg(p.oid::regprocedure::text,E'\n' order by p.oid::regprocedure::text)
  into v_path
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','app_private') and p.prosecdef
    and not exists (
      select 1 from pg_catalog.unnest(coalesce(p.proconfig,array[]::text[])) cfg
      -- PostgreSQL serializes an empty GUC either as the empty suffix
      -- or as two quote characters (search_path="").
      where cfg in ('search_path=','search_path=""')
    );
  if v_path is not null then
    raise exception 'SECURITY DEFINER functions without empty search_path: %',v_path;
  end if;

  select string_agg(quote_ident(n.nspname)||'.'||quote_ident(c.relname),E'\n')
  into v_rls
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
  if v_rls is not null then
    raise exception 'Exposed tables without RLS: %',v_rls;
  end if;
end;
$definer_checks$;

-- The functions that process signed provider/server jobs are not public APIs.
do $privileged_rpcs$
declare v_function text;v_oid oid;
begin
  foreach v_function in array array[
    'public.attach_stripe_checkout_session(uuid,text)',
    'public.finalize_verified_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb)',
    'public.reconcile_signed_checkout_expiry(text,text,text,uuid)',
    'public.attach_verified_stripe_refund(uuid,text)',
    'public.finalize_verified_stripe_refund(text,text,uuid,text,text,bigint,text,text)',
    'public.claim_push_jobs(integer)',
    'public.finish_push_job(uuid,boolean,integer,text)',
    'public.prepare_guest_email_recovery(uuid,text)',
    'public.list_verified_guest_recovery(uuid,text)',
    'public.confirm_guest_email_recovery(uuid,uuid,text)',
    'public.resolve_verified_guest_recovery(uuid)',
    'public.rotate_guest_private_link(uuid,text)',
    'public.claim_admin_registration(text)'
  ] loop
    v_oid:=pg_catalog.to_regprocedure(v_function)::oid;
    if v_oid is null then
      raise exception 'Required privileged RPC is missing: %',v_function;
    end if;
    if pg_catalog.has_function_privilege('anon',v_oid,'EXECUTE') or
       pg_catalog.has_function_privilege('authenticated',v_oid,'EXECUTE') then
      raise exception 'Unprivileged role can call service RPC: %',v_function;
    end if;
    if not pg_catalog.has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'Service role cannot call its own RPC: %',v_function;
    end if;
  end loop;
end;
$privileged_rpcs$;

-- Signed-in app users may call audited RPCs, not read raw payment ledgers.
do $raw_ledger$
declare v_relation text;
begin
  foreach v_relation in array array[
    'public.school_stripe_merchants','public.payment_attempts',
    'public.payment_item_allocations','public.payment_refunds',
    'public.staff_offline_leases','public.offline_events_inbox'
  ] loop
    if pg_catalog.has_table_privilege('anon',v_relation,'SELECT') or
       pg_catalog.has_table_privilege('authenticated',v_relation,'SELECT') then
      raise exception 'Direct public ledger access: %',v_relation;
    end if;
  end loop;
end;
$raw_ledger$;

-- A real Admin of School A with verified AAL2 cannot alter School B settings.
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $cross_school$
declare v_denied boolean:=false;
begin
  begin
    perform public.configure_school_booking(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',46.0,10.0,800,30,10,3,null,null);
  exception when others then v_denied:=true;end;
  if not v_denied then
    raise exception 'Admin of school A changed school B settings';
  end if;
end;
$cross_school$;
reset role;

do $no_cross_tenant_write$
begin
  if (select pickup_radius_m from public.schools where
    id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')=800 then
    raise exception 'School B settings were changed by School A Admin';
  end if;
end;
$no_cross_tenant_write$;
