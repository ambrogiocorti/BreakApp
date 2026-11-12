-- Tests after migrations 01-16 and previous database integration tests.
reset role;
do $default_deny$
begin
 if has_table_privilege('authenticated','public.payment_attempts','INSERT')
 or has_table_privilege('authenticated','public.offline_events_inbox','INSERT')
 or has_table_privilege('authenticated','public.school_stripe_merchants','SELECT')
 then raise exception 'Financial or offline ledger accidentally public';end if;
 if not (select relrowsecurity from pg_class where oid='public.payment_attempts'::regclass)
 then raise exception 'Payment RLS disabled';end if;
end;$default_deny$;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.transfer_my_offline_device(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000090') as first_lease \gset
select set_config('app.offline_first_gen',
 (:'first_lease'::jsonb->>'generation'),false);
select public.transfer_my_offline_device(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000091') as new_lease \gset
reset role;
do $single_device$
begin
 if (select device_id from public.staff_offline_leases
  where barista_id='33333333-3333-4333-8333-333333333333') <> 'aaaaaaaa-0000-4000-8000-000000000091'::uuid
 then raise exception 'Old device still active';end if;
 if (select generation from public.staff_offline_leases
  where barista_id=auth.uid())<=current_setting('app.offline_first_gen')::bigint
 then raise exception 'Offline transfer did not revoke first generation';end if;
end;$single_device$;
set role authenticated;
select public.stage_my_offline_event(
 'aaaaaaaa-0000-4000-8000-000000000090',
 current_setting('app.offline_first_gen')::bigint,
 'aaaaaaaa-0000-4000-8000-000000000092',
 'counter_sale',now(),'{"amount_cents":200}'::jsonb) as quarantined_event \gset
reset role;
do $quarantined$
begin
 if not exists(select 1 from public.offline_events_inbox
   where barista_id=auth.uid() and status='quarantined'
   and review_reason like '%revocat%') then
  raise exception 'Revoked device event was not quarantined';end if;
end;$quarantined$;
set role authenticated;
-- Customer and superadmin cannot transfer offline authorization.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $customer_denied$
declare denied boolean:=false;
begin
 begin
  perform public.transfer_my_offline_device(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-0000-4000-8000-000000000093');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Customer received offline bartender lease';end if;
end;$customer_denied$;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $platform_denied$
declare denied boolean:=false;
begin
 begin
  perform public.transfer_my_offline_device(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-0000-4000-8000-000000000094');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Super Admin received offline bartender lease';end if;
end;$platform_denied$;
reset role;
