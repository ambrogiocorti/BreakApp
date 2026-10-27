-- Run after scripts 01-21 and their existing integration tests.
reset role;
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,request_key,
 status,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000301','ready','due',375)
returning id as async_failure_order \gset
select set_config('app.async_failure_order',:'async_failure_order',false);
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.begin_individual_stripe_checkout(
 current_setting('app.async_failure_order')::uuid,
 '11111111-0000-4000-8000-000000000302') as async_failure_checkout \gset
select set_config('app.async_failure_attempt',
 (:'async_failure_checkout'::jsonb->>'attempt_id'),false);
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(
 current_setting('app.async_failure_attempt')::uuid,'cs_test_asyncfailed123456');
do $reject_wrong_amount$
declare rejected boolean:=false;
begin
 begin
  perform public.reconcile_signed_checkout_failure(
   'evt_asyncbadamount123','acct_1UUniH2RLt7x5EeZ',
   'cs_test_asyncfailed123456','pi_failed1234567',
   current_setting('app.async_failure_attempt')::uuid,376,'eur');
 exception when others then rejected:=true;end;
 if not rejected then raise exception 'Mismatched async failure freed the cash lock';end if;
end;$reject_wrong_amount$;
select public.reconcile_signed_checkout_failure(
 'evt_asyncfailed123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_asyncfailed123456','pi_failed1234567',
 current_setting('app.async_failure_attempt')::uuid,375,'eur')
 as failure_result \gset
select public.reconcile_signed_checkout_failure(
 'evt_asyncfailed123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_asyncfailed123456','pi_failed1234567',
 current_setting('app.async_failure_attempt')::uuid,375,'eur')
 as duplicate_failure_result \gset
reset role;
do $failure_only$
begin
 if (select status from public.payment_attempts
   where id=current_setting('app.async_failure_attempt')::uuid)<>'failed'
 then raise exception 'Failed async Checkout not reconciled';end if;
 if (select payment_status from public.orders
   where id=current_setting('app.async_failure_order')::uuid)<>'due'
 then raise exception 'Failed async Checkout marked order paid';end if;
 if (select count(*) from public.order_audit where
   order_id=current_setting('app.async_failure_order')::uuid and
   action='stripe_async_payment_failed')<>1
 then raise exception 'Duplicate async failure audit';end if;
end;$failure_only$;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.record_individual_counter_payment(
 current_setting('app.async_failure_order')::uuid,'cash',
 '11111111-0000-4000-8000-000000000303') as cash_after_async_failure \gset
reset role;
do $cash_after_failure$
begin
 if (select payment_status from public.orders
  where id=current_setting('app.async_failure_order')::uuid)<>'paid'
 then raise exception 'Cash still blocked after signed async failure';end if;
end;$cash_after_failure$;

-- A delayed success settles exactly once, recording its actual event type.
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,request_key,
 status,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000304','confirmed','due',425)
returning id as async_success_order \gset
select set_config('app.async_success_order',:'async_success_order',false);
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.begin_individual_stripe_checkout(
 current_setting('app.async_success_order')::uuid,
 '11111111-0000-4000-8000-000000000305') as async_success_checkout \gset
select set_config('app.async_success_attempt',
 (:'async_success_checkout'::jsonb->>'attempt_id'),false);
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(
 current_setting('app.async_success_attempt')::uuid,'cs_test_asyncsuccess123456');
select public.finalize_verified_checkout(
 'evt_asyncsuccess123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_asyncsuccess123456','pi_success123456',
 current_setting('app.async_success_attempt')::uuid,425,'eur',true,
 '{"event_type":"checkout.session.async_payment_succeeded"}'::jsonb)
 as async_success_result \gset
select public.finalize_verified_checkout(
 'evt_asyncsuccess123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_asyncsuccess123456','pi_success123456',
 current_setting('app.async_success_attempt')::uuid,425,'eur',true,
 '{"event_type":"checkout.session.async_payment_succeeded"}'::jsonb)
 as duplicate_success_result \gset
reset role;
do $async_settled_once$
begin
 if (select payment_status from public.orders
  where id=current_setting('app.async_success_order')::uuid)<>'paid'
 then raise exception 'Async success not paid';end if;
 if (select event_type from app_private.stripe_webhook_inbox
  where event_id='evt_asyncsuccess123')<>'checkout.session.async_payment_succeeded'
 then raise exception 'Actual async event type lost';end if;
 if (select count(*) from public.order_audit where
  order_id=current_setting('app.async_success_order')::uuid and
  action='stripe_checkout_verified')<>1
 then raise exception 'Async success recorded twice';end if;
end;$async_settled_once$;

-- Recognize the syntactic live-session prefix as well as test sessions.
-- This uses only synthetic IDs in the disposable CI database; NOT a live charge.
reset role;
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,request_key,
 status,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000306','ready','due',275)
returning id as live_format_order \gset
select set_config('app.live_format_order',:'live_format_order',false);
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.begin_individual_stripe_checkout(
 current_setting('app.live_format_order')::uuid,
 '11111111-0000-4000-8000-000000000307') as live_format_checkout \gset
select set_config('app.live_format_attempt',
 (:'live_format_checkout'::jsonb->>'attempt_id'),false);
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(
 current_setting('app.live_format_attempt')::uuid,'cs_live_synthetic123456');
select public.reconcile_signed_checkout_failure(
 'evt_liveformat123','acct_1UUniH2RLt7x5EeZ',
 'cs_live_synthetic123456','pi_liveformat123',
 current_setting('app.live_format_attempt')::uuid,275,'eur');
reset role;
do $live_prefix_guard$
begin
 if (select status from public.payment_attempts
  where id=current_setting('app.live_format_attempt')::uuid)<>'failed' then
  raise exception 'Verified live-format session failure was rejected';
 end if;
 if (select payment_status from public.orders
  where id=current_setting('app.live_format_order')::uuid)<>'due' then
  raise exception 'Fake live-format failure must never mark order paid';
 end if;
end;
$live_prefix_guard$;
