-- Group Stripe multipayer isolation, idempotence, signature boundary, and cash reconciliation.
reset role;
update public.school_stripe_merchants set charges_enabled=true
where school_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000197',
 'Stripe multi-payer test',false,3) as group_id \gset
select set_config('app.group_stripe_id',:'group_id',false);
select set_config('app.group_stripe_invite',
 public.group_draft_details(current_setting('app.group_stripe_id')::uuid)->>'invite_token',false);
select public.replace_group_personal_cart(current_setting('app.group_stripe_id')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.join_group_draft(current_setting('app.group_stripe_invite')::uuid,45,9,10,now());
select public.replace_group_personal_cart(current_setting('app.group_stripe_id')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":2}]'::jsonb);
select set_config('app.group_stripe_line',
 (select id::text from public.group_cart_items
  where group_id=current_setting('app.group_stripe_id')::uuid
   and user_id='22222222-2222-4222-8222-222222222222'),false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $lines$
declare a jsonb;
begin
 a:=public.group_payable_lines(current_setting('app.group_stripe_id')::uuid);
 if jsonb_array_length(a)<>2 then raise exception 'Payable lines count mismatch';end if;
end;$lines$;
select public.begin_group_stripe_checkout(
 current_setting('app.group_stripe_id')::uuid,
 array[current_setting('app.group_stripe_line')::uuid],
 '11111111-0000-4000-8000-000000000198') as checkout \gset
select set_config('app.group_stripe_attempt',
 (:'checkout'::jsonb->>'attempt_id'),false);
-- The payer may pay another accepted member's WHOLE line.
do $payer$
declare p uuid;b uuid;
begin
 select payer_id into p from public.payment_attempts
  where id=current_setting('app.group_stripe_attempt')::uuid;
 select beneficiary_id into b from public.group_line_payment_claims
  where payment_id=current_setting('app.group_stripe_attempt')::uuid;
 if p<>'11111111-1111-4111-8111-111111111111'::uuid or
    b<>'22222222-2222-4222-8222-222222222222'::uuid
 then raise exception 'Wrong payer attribution';end if;
end;$payer$;
select public.begin_group_stripe_checkout(
 current_setting('app.group_stripe_id')::uuid,
 array[current_setting('app.group_stripe_line')::uuid],
 '11111111-0000-4000-8000-000000000198') as retry \gset
select set_config('app.group_stripe_retry',(:'retry'::jsonb->>'attempt_id'),false);
do $retry$
begin
 if current_setting('app.group_stripe_retry')<>current_setting('app.group_stripe_attempt')
 then raise exception 'Idempotent group payment diverged';end if;
end;$retry$;
do $double_pay$
declare denied boolean:=false;
begin
 begin
 perform public.begin_group_stripe_checkout(
  current_setting('app.group_stripe_id')::uuid,
  array[current_setting('app.group_stripe_line')::uuid],
  '11111111-0000-4000-8000-000000000199');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Two payments claimed the same line';end if;
end;$double_pay$;
do $not_webhook$
declare denied boolean:=false;
begin
 begin
 perform public.finalize_verified_group_checkout('evt_grouptest1',
  'acct_1UUniH2RLt7x5EeZ','cs_test_group123','pi_grouptest123',
  current_setting('app.group_stripe_attempt')::uuid,500,'eur',true,'{}'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Client certified Stripe money';end if;
end;$not_webhook$;
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(
 current_setting('app.group_stripe_attempt')::uuid,
 'cs_test_group1234');
do $invalid_amount$
declare denied boolean:=false;
begin
 begin
 perform public.finalize_verified_group_checkout('evt_grouptest2',
  'acct_1UUniH2RLt7x5EeZ','cs_test_group1234','pi_grouptest1234',
  current_setting('app.group_stripe_attempt')::uuid,1,'eur',true,'{}'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Wrong Stripe amount accepted';end if;
end;$invalid_amount$;
select public.finalize_verified_group_checkout('evt_grouptest3',
 'acct_1UUniH2RLt7x5EeZ','cs_test_group1234','pi_grouptest1234',
 current_setting('app.group_stripe_attempt')::uuid,
 (select amount_cents from public.payment_attempts
  where id=current_setting('app.group_stripe_attempt')::uuid),
 'eur',true,'{}'::jsonb) as settled \gset
select set_config('app.group_stripe_settled',:'settled',false);
do $settled$
begin
 if current_setting('app.group_stripe_settled')<>'succeeded' or
  (select state from public.group_line_payment_claims
   where payment_id=current_setting('app.group_stripe_attempt')::uuid)<>'paid'
 then raise exception 'Payment proof was not committed';end if;
end;$settled$;
select public.finalize_verified_group_checkout('evt_grouptest3',
 'acct_1UUniH2RLt7x5EeZ','cs_test_group1234','pi_grouptest1234',
 current_setting('app.group_stripe_attempt')::uuid,
 (select amount_cents from public.payment_attempts
  where id=current_setting('app.group_stripe_attempt')::uuid),
 'eur',true,'{}'::jsonb) as replay \gset
select set_config('app.group_stripe_replay',:'replay',false);
do $replay$
begin
 if current_setting('app.group_stripe_replay')<>'duplicate' then raise exception 'Webhook event replay not deduped';end if;
end;$replay$;
reset role;
-- Paid group lines must survive confirmation with their original quote.
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.confirm_group_order(current_setting('app.group_stripe_id')::uuid,
 '11111111-0000-4000-8000-000000000200',true,45,9,10,now()) as order_id \gset
select set_config('app.group_stripe_order',:'order_id',false);
reset role;
do $due$
declare amount bigint;due bigint;paid bigint;
begin
 select total_cents into amount from public.group_orders
 where id=current_setting('app.group_stripe_order')::uuid;
 select coalesce(sum(a.amount_cents),0) into paid
 from public.payment_item_allocations a join public.payment_attempts p on p.id=a.payment_id
 where p.group_id=current_setting('app.group_stripe_id')::uuid and p.status='succeeded';
 due:=amount-paid;
 if due<=0 or due>=amount then raise exception 'Partial group payment not reconciled';end if;
end;$due$;
