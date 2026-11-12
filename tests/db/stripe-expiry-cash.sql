-- Stripe Checkout cash overlap must remain blocked beyond any LOCAL timeout.
reset role;
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,request_key,
 status,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000210','ready','due',300)
returning id as reconciliation_order \gset
select set_config('app.expire_order',:'reconciliation_order',false);
insert into public.payment_attempts(
 school_id,payer_id,order_id,stripe_account_id,request_key,
 amount_cents,stripe_checkout_session_id,status,expires_at
) values (
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '11111111-1111-4111-8111-111111111111',
 :'reconciliation_order'::uuid,
 'acct_1UUniH2RLt7x5EeZ','11111111-0000-4000-8000-000000000211',
 300,'cs_test_expired12345678','requires_action',now()-interval '1 day'
) returning id as reconciliation_attempt \gset
select set_config('app.expire_attempt',:'reconciliation_attempt',false);
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $cash_denied_after_timeout$
declare denied boolean:=false;
begin
 begin
  perform public.record_individual_counter_payment(
    current_setting('app.expire_order')::uuid,'cash',
    '11111111-0000-4000-8000-000000000212');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Cash accepted during unresolved Stripe session';end if;
end;$cash_denied_after_timeout$;
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.reconcile_signed_checkout_expiry(
 'evt_expiregood123','acct_1UUniH2RLt7x5EeZ',
 'cs_test_expired12345678',current_setting('app.expire_attempt')::uuid) as expired \gset
reset role;
do $expired_not_paid$
begin
 if (select status from public.payment_attempts
   where id=current_setting('app.expire_attempt')::uuid)<>'cancelled'
 then raise exception 'Provider expiry did not cancel Stripe attempt';end if;
 if (select payment_status from public.orders
   where id=current_setting('app.expire_order')::uuid)<>'due'
 then raise exception 'Expiry incorrectly marked paid';end if;
end;$expired_not_paid$;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.record_individual_counter_payment(
 current_setting('app.expire_order')::uuid,'cash',
 '11111111-0000-4000-8000-000000000212') as cash_after_provider_expiry \gset
reset role;
do $cash_permitted_after_expiry$
begin
 if (select payment_status from public.orders
   where id=current_setting('app.expire_order')::uuid)<>'paid'
 then raise exception 'Cash rejected after authenticated provider expiry';end if;
end;$cash_permitted_after_expiry$;
