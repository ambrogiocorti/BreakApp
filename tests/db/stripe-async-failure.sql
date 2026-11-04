-- Disposable PostgreSQL only: never creates a Stripe transaction.
begin;
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('93000000-0000-4000-8000-000000000101','async-customer@test.invalid',now());
insert into public.schools(id,slug,name) values
 ('93000000-0000-4000-8000-000000000001','async-failure-test','Async Test School');
insert into public.bars(id,school_id,name) values
 ('93000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000001','Async Bar');
insert into public.categories(id,school_id,bar_id,name) values
 ('93000000-0000-4000-8000-000000000003','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','Food');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents) values
 ('93000000-0000-4000-8000-000000000004','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000003','Bread',300);
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('93000000-0000-4000-8000-000000000005','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002',current_date+1,'12:00','12:15');
insert into public.orders(id,school_id,bar_id,customer_id,pickup_window_id,request_key,status,payment_status,total_cents) values
 ('93000000-0000-4000-8000-000000000006','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000101','93000000-0000-4000-8000-000000000005',gen_random_uuid(),'ready','due',400);
insert into public.group_drafts(id,school_id,bar_id,pickup_window_id,coordinator_id,request_key,title,status) values
 ('93000000-0000-4000-8000-000000000007','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000005','93000000-0000-4000-8000-000000000101',gen_random_uuid(),'Async group','confirmed');
insert into public.group_members(group_id,user_id,status) values
 ('93000000-0000-4000-8000-000000000007','93000000-0000-4000-8000-000000000101','accepted');
insert into public.group_cart_items(id,group_id,user_id,product_id,product_name,unit_price_cents,quantity) values
 ('93000000-0000-4000-8000-000000000008','93000000-0000-4000-8000-000000000007','93000000-0000-4000-8000-000000000101','93000000-0000-4000-8000-000000000004','Bread',300,1);
insert into public.group_orders(id,group_id,school_id,bar_id,pickup_window_id,coordinator_id,request_key,status,total_cents) values
 ('93000000-0000-4000-8000-000000000009','93000000-0000-4000-8000-000000000007','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000005','93000000-0000-4000-8000-000000000101',gen_random_uuid(),'confirmed',500);
insert into public.group_order_lines(id,group_order_id,group_cart_item_id,beneficiary_id,product_id,name,quantity,unit_cents) values
 ('93000000-0000-4000-8000-000000000010','93000000-0000-4000-8000-000000000009','93000000-0000-4000-8000-000000000008','93000000-0000-4000-8000-000000000101','93000000-0000-4000-8000-000000000004','Bread',1,300);
insert into public.payment_attempts(id,school_id,payer_id,order_id,stripe_account_id,request_key,amount_cents,stripe_checkout_session_id,status,workflow_v2) values
 ('93000000-0000-4000-8000-000000000011','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000101','93000000-0000-4000-8000-000000000006','acct_AsyncTest',gen_random_uuid(),400,'cs_test_AsyncIndividual','requires_action',true);
insert into public.payment_attempts(id,school_id,payer_id,group_id,stripe_account_id,request_key,amount_cents,stripe_checkout_session_id,status,workflow_v2) values
 ('93000000-0000-4000-8000-000000000012','93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000101','93000000-0000-4000-8000-000000000007','acct_AsyncTest',gen_random_uuid(),500,'cs_test_AsyncGroup','requires_action',true);
insert into public.group_line_payment_claims(group_cart_item_id,payment_id,payer_id,beneficiary_id,amount_cents,state) values
 ('93000000-0000-4000-8000-000000000008','93000000-0000-4000-8000-000000000012','93000000-0000-4000-8000-000000000101','93000000-0000-4000-8000-000000000101',300,'pending');
insert into public.order_supplements(id,group_order_id,group_line_id,beneficiary_id,description,amount_cents,state,payment_id) values
 ('93000000-0000-4000-8000-000000000013','93000000-0000-4000-8000-000000000009','93000000-0000-4000-8000-000000000010','93000000-0000-4000-8000-000000000101','Difference',200,'pending','93000000-0000-4000-8000-000000000012');
insert into public.payment_item_allocations(payment_id,group_cart_item_id,beneficiary_id,amount_cents) values
 ('93000000-0000-4000-8000-000000000012','93000000-0000-4000-8000-000000000008','93000000-0000-4000-8000-000000000101',300);
insert into public.payment_item_allocations(payment_id,supplement_id,beneficiary_id,amount_cents) values
 ('93000000-0000-4000-8000-000000000012','93000000-0000-4000-8000-000000000013','93000000-0000-4000-8000-000000000101',200);

do $$
begin
 if has_function_privilege('anon','public.reconcile_signed_async_checkout_failure(text,text,text,text,uuid,bigint,text)','execute')
  or has_function_privilege('authenticated','public.reconcile_signed_async_checkout_failure(text,text,text,text,uuid,bigint,text)','execute')
  or not has_function_privilege('service_role','public.reconcile_signed_async_checkout_failure(text,text,text,text,uuid,bigint,text)','execute')
 then raise exception 'Async failure RPC privileges are unsafe'; end if;
end;$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
declare denied boolean:=false; result text;
begin
 begin
  perform public.reconcile_signed_async_checkout_failure('evt_AsyncBadAmount','acct_AsyncTest','cs_test_AsyncIndividual','pi_AsyncIndividual','93000000-0000-4000-8000-000000000011',401,'eur');
 exception when others then denied:=true; end;
 if not denied then raise exception 'Wrong amount was accepted'; end if;
 if (select status from public.payment_attempts where id='93000000-0000-4000-8000-000000000011')<>'requires_action'
 then raise exception 'Invalid event released the cash lock'; end if;
 result:=public.reconcile_signed_async_checkout_failure('evt_AsyncIndividual','acct_AsyncTest','cs_test_AsyncIndividual','pi_AsyncIndividual','93000000-0000-4000-8000-000000000011',400,'eur');
 if result<>'failed' then raise exception 'Individual failure not reconciled'; end if;
 result:=public.reconcile_signed_async_checkout_failure('evt_AsyncIndividual','acct_AsyncTest','cs_test_AsyncIndividual','pi_AsyncIndividual','93000000-0000-4000-8000-000000000011',400,'eur');
 if result<>'duplicate' then raise exception 'Failure replay not idempotent'; end if;
 result:=public.reconcile_signed_async_checkout_failure('evt_AsyncGroup','acct_AsyncTest','cs_test_AsyncGroup','pi_AsyncGroup','93000000-0000-4000-8000-000000000012',500,'eur');
 if result<>'failed' then raise exception 'Group failure not reconciled'; end if;
 if exists(select 1 from public.group_line_payment_claims where payment_id='93000000-0000-4000-8000-000000000012')
 then raise exception 'Failed group checkout retained pending claims'; end if;
 if not exists(select 1 from public.order_supplements where id='93000000-0000-4000-8000-000000000013' and state='available' and payment_id is null)
 then raise exception 'Failed checkout did not release supplement'; end if;
 if exists(select 1 from public.payment_item_allocations where supplement_id='93000000-0000-4000-8000-000000000013')
 then raise exception 'Failed checkout retained supplement allocation'; end if;
end;$$;

-- A later valid settlement after a failed event is not lost: the full amount
-- is queued for return to the original payer instead of charging twice.
insert into public.counter_payments(school_id,bar_id,order_id,actor_id,method,amount_cents,request_key) values
 ('93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000006','93000000-0000-4000-8000-000000000101','cash',400,gen_random_uuid());
do $$
declare result text;
begin
 result:=public.finalize_verified_checkout('evt_AsyncLateIndividual','acct_AsyncTest','cs_test_AsyncIndividual','pi_AsyncIndividual','93000000-0000-4000-8000-000000000011',400,'eur',true,'{}'::jsonb);
 if result<>'refund_required' or not exists(select 1 from public.payment_refunds where payment_id='93000000-0000-4000-8000-000000000011' and amount_cents=400 and status='pending')
 then raise exception 'Late individual payment was not queued for refund'; end if;
 result:=public.finalize_verified_group_checkout('evt_AsyncLateGroup','acct_AsyncTest','cs_test_AsyncGroup','pi_AsyncGroup','93000000-0000-4000-8000-000000000012',500,'eur',true,'{}'::jsonb);
 if result<>'refund_required' or not exists(select 1 from public.payment_refunds where payment_id='93000000-0000-4000-8000-000000000012' and amount_cents=500 and status='pending')
 then raise exception 'Late group payment was not queued for refund'; end if;
 result:=public.reconcile_signed_async_checkout_failure('evt_AsyncAfterSuccess','acct_AsyncTest','cs_test_AsyncGroup','pi_AsyncGroup','93000000-0000-4000-8000-000000000012',500,'eur');
 if result<>'ignore_settled' or (select status from public.payment_attempts where id='93000000-0000-4000-8000-000000000012')<>'succeeded'
 then raise exception 'Late failure reversed a settled payment'; end if;
end;$$;
rollback;
