-- CI-only payment test, after migrations 01-17 and all prior DB tests.
reset role;
insert into public.school_stripe_merchants(school_id,stripe_account_id,charges_enabled)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'acct_1UUniH2RLt7x5EeZ',true);
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,
 request_key,status,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
'aaaaaaaa-0000-4000-8000-000000000001',
'11111111-1111-4111-8111-111111111111',
'aaaaaaaa-0000-4000-8000-000000000005',
'11111111-0000-4000-8000-000000000177','confirmed','due',250)
returning id as payment_test_order \gset
select set_config('app.stripe_test_order',:'payment_test_order',false);

set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $different_customer$
declare denied boolean:=false;
begin
 begin
  perform public.begin_individual_stripe_checkout(
    current_setting('app.stripe_test_order')::uuid,
    '11111111-0000-4000-8000-000000000178');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Non-owner opened checkout';end if;
end;$different_customer$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.begin_individual_stripe_checkout(
 current_setting('app.stripe_test_order')::uuid,
 '11111111-0000-4000-8000-000000000178') as checkout_started \gset
select set_config('app.stripe_attempt',
 (:'checkout_started'::jsonb->>'attempt_id'),false);

do $no_direct_webhook$
declare denied boolean:=false;
begin
 begin
  perform public.finalize_verified_checkout(
    'evt_abc123','acct_1UUniH2RLt7x5EeZ','cs_test_1234','pi_1234',
    current_setting('app.stripe_attempt')::uuid,250,'eur',true,'{}'::jsonb);
 exception when insufficient_privilege then denied:=true;
 when others then denied:=true;end;
 if not denied then raise exception 'Client invoked webhook ledger';end if;
end;$no_direct_webhook$;

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(
 current_setting('app.stripe_attempt')::uuid,'cs_test_abcdefghijklmnopqrstuvwxyz');
do $bad_amount$
declare denied boolean:=false;
begin
 begin
  perform public.finalize_verified_checkout(
    'evt_invalid123','acct_1UUniH2RLt7x5EeZ',
    'cs_test_abcdefghijklmnopqrstuvwxyz','pi_abcdefg1234',
    current_setting('app.stripe_attempt')::uuid,249,'eur',true,'{}'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Mismatched webhook amount accepted';end if;
end;$bad_amount$;
select public.finalize_verified_checkout(
 'evt_good123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_abcdefghijklmnopqrstuvwxyz','pi_abcdefg1234',
 current_setting('app.stripe_attempt')::uuid,250,'eur',true,'{}'::jsonb)
 as webhook_result \gset
do $settled$
begin
 if (select payment_status from public.orders
  where id=current_setting('app.stripe_test_order')::uuid)<>'paid'
 then raise exception 'Verified payment not booked';end if;
 if (select status from public.payment_attempts
  where id=current_setting('app.stripe_attempt')::uuid)<>'succeeded'
 then raise exception 'Stripe payment attempt not settled';end if;
end;$settled$;
select public.finalize_verified_checkout(
 'evt_good123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_abcdefghijklmnopqrstuvwxyz','pi_abcdefg1234',
 current_setting('app.stripe_attempt')::uuid,250,'eur',true,'{}'::jsonb)
 as duplicate_result \gset
do $dedupe$
begin
 if :'duplicate_result'<>'duplicate' then
  raise exception 'Webhook event processed twice';end if;
 if (select count(*) from public.order_audit
  where order_id=current_setting('app.stripe_test_order')::uuid
    and action='stripe_checkout_verified')<>1
 then raise exception 'Duplicate settlement audit';end if;
end;$dedupe$;
reset role;
