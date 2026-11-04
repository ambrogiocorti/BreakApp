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
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select '93000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002',day,'00:00','23:59'
 from generate_series(0,6) as day;
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

update public.orders set status='delivered' where id='93000000-0000-4000-8000-000000000006';
update public.payment_attempts set status='succeeded',stripe_payment_intent_id='pi_RefundIndividual'
 where id='93000000-0000-4000-8000-000000000011';
update public.payment_attempts set status='succeeded',stripe_payment_intent_id='pi_RefundGroup'
 where id='93000000-0000-4000-8000-000000000012';
update public.group_line_payment_claims set state='refund_pending'
 where group_cart_item_id='93000000-0000-4000-8000-000000000008';
insert into public.payment_refunds(id,payment_id,request_key,amount_cents,status,reason) values
 ('94000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000011',gen_random_uuid(),400,'processing','Individual refund test'),
 ('94000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000012',gen_random_uuid(),300,'processing','Group refund test');
insert into public.group_line_refunds(group_cart_item_id,refund_id,original_payer_id,amount_cents) values
 ('93000000-0000-4000-8000-000000000008','94000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000101',300);

select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
declare job record; result text; denied boolean; notices integer;
begin
 result:=public.enqueue_signed_refund_observation('evt_RefundInitial','refund.created','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000001','re_RefundIndividual','pi_RefundIndividual',400,'eur','pending');
 if result<>'queued' or (select status from public.payment_refunds where id='94000000-0000-4000-8000-000000000001')<>'processing'
 then raise exception 'A snapshot alone finalized a refund'; end if;
 select * into job from public.claim_refund_observations(1);
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','pending');
 if result<>'processing' or not exists(select 1 from app_private.stripe_refund_observations
  where refund_id=job.refund_id and revision>handled_revision and next_attempt_at>now())
 then raise exception 'Pending refund was not scheduled for rechecking'; end if;
 perform public.enqueue_signed_refund_observation('evt_RefundSuccess','refund.updated','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000001','re_RefundIndividual','pi_RefundIndividual',400,'eur','succeeded');
 select * into job from public.claim_refund_observations(1);
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','succeeded');
 if result<>'succeeded' or (select payment_status from public.orders where id='93000000-0000-4000-8000-000000000006')<>'refunded'
 then raise exception 'Verified individual refund was not recorded'; end if;

 -- A later failure makes the completed refund visibly unresolved immediately.
 result:=public.enqueue_signed_refund_observation('evt_RefundFailed','refund.failed','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000001','re_RefundIndividual','pi_RefundIndividual',400,'eur','failed');
 if result<>'queued' or (select status from public.payment_refunds where id='94000000-0000-4000-8000-000000000001')<>'review'
  or (select payment_status from public.orders where id='93000000-0000-4000-8000-000000000006')<>'refund_pending'
 then raise exception 'Late failure left a refund falsely completed'; end if;
 select count(*) into notices from public.customer_notifications where user_id='93000000-0000-4000-8000-000000000101' and event_type='refund_issue';
 if notices<1 then raise exception 'Refund failure did not notify the payer'; end if;
 result:=public.enqueue_signed_refund_observation('evt_RefundFailed','refund.failed','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000001','re_RefundIndividual','pi_RefundIndividual',400,'eur','failed');
 if result<>'duplicate' then raise exception 'Repeated Stripe event was not deduplicated'; end if;

 -- An event arriving during a provider lookup invalidates the leased result.
 select * into job from public.claim_refund_observations(1);
 perform public.enqueue_signed_refund_observation('evt_RefundNewer','refund.updated','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000001','re_RefundIndividual','pi_RefundIndividual',400,'eur','pending');
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','succeeded');
 if result<>'superseded' or (select status from public.payment_refunds where id=job.refund_id)<>'review'
 then raise exception 'Stale provider observation overrode a newer event'; end if;
 select * into job from public.claim_refund_observations(1);
 denied:=false;
 begin
  perform public.finish_refund_observation(job.refund_id,gen_random_uuid(),job.claim_revision,job.account,
   job.provider_refund,job.payment_intent,job.amount_cents,'eur','failed');
 exception when others then denied:=true; end;
 if not denied then raise exception 'Invalid lease was accepted'; end if;
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','failed');
 if result<>'failed' or (select status from public.payment_refunds where id=job.refund_id)<>'failed'
 then raise exception 'Current provider failure was not recorded'; end if;

 -- An older success snapshot must not override the provider's current failure.
 perform public.enqueue_signed_refund_observation('evt_RefundOldSuccess','refund.created','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000001','re_RefundIndividual','pi_RefundIndividual',400,'eur','succeeded');
 select * into job from public.claim_refund_observations(1);
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','failed');
 if result<>'failed' or (select payment_status from public.orders where id='93000000-0000-4000-8000-000000000006')<>'refund_pending'
 then raise exception 'Out-of-order event falsely restored a refund'; end if;

 -- A group refund follows the original payer and its line returns to pending.
 perform public.enqueue_signed_refund_observation('evt_GroupRefundSuccess','refund.updated','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000002','re_RefundGroup','pi_RefundGroup',300,'eur','succeeded');
 select * into job from public.claim_refund_observations(1);
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','succeeded');
 if result<>'succeeded' or (select state from public.group_line_payment_claims where group_cart_item_id='93000000-0000-4000-8000-000000000008')<>'refunded'
 then raise exception 'Group line not refunded to original payer'; end if;
 perform public.enqueue_signed_refund_observation('evt_GroupRefundFailed','refund.failed','acct_AsyncTest',
  '94000000-0000-4000-8000-000000000002','re_RefundGroup','pi_RefundGroup',300,'eur','failed');
 if (select state from public.group_line_payment_claims where group_cart_item_id='93000000-0000-4000-8000-000000000008')<>'refund_pending'
 then raise exception 'Group line remained refunded after failure'; end if;
 select * into job from public.claim_refund_observations(1);
 result:=public.finish_refund_observation(job.refund_id,job.lease_token,job.claim_revision,job.account,
  job.provider_refund,job.payment_intent,job.amount_cents,'eur','failed');
 if result<>'failed' then raise exception 'Group refund failure not reconciled'; end if;
 denied:=false;
 begin
  perform public.enqueue_signed_refund_observation('evt_RefundWrongAmount','refund.updated','acct_AsyncTest',
   '94000000-0000-4000-8000-000000000002','re_RefundGroup','pi_RefundGroup',301,'eur','succeeded');
 exception when others then denied:=true; end;
 if not denied then raise exception 'Mismatched refund was accepted'; end if;
end;$$;
rollback;

