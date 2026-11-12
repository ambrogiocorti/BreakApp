-- BreakApp 31: encrypted-manifest-compatible individual offline delivery and cash ledger.
reset role;
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
  extract(dow from (now() at time zone 'Europe/Rome')::date)::int,'00:01','23:59')
 on conflict(bar_id,weekday,starts_at) do nothing;
update public.bar_service_state set accepting_orders=true
 where bar_id='aaaaaaaa-0000-4000-8000-000000000001';
insert into public.pickup_windows(school_id,bar_id,service_date,starts_at,ends_at)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
 (now() at time zone 'Europe/Rome')::date,'22:00','22:30') returning id as slot \gset
select set_config('app.offline_pickup_window',:'slot',false);
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,
 request_key,status,payment_method,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 current_setting('app.offline_pickup_window')::uuid,
 '11111111-0000-4000-8000-000000000451','ready','at_pickup','paid',500)
returning id as paid_order \gset
select set_config('app.offline_paid_order',:'paid_order',false);
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,
 request_key,status,payment_method,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 current_setting('app.offline_pickup_window')::uuid,
 '11111111-0000-4000-8000-000000000452','ready','at_pickup','due',750)
returning id as due_order \gset
select set_config('app.offline_due_order',:'due_order',false);
select set_config('app.offline_paid_token',(select pickup_token::text from public.orders
 where id=current_setting('app.offline_paid_order')::uuid),false);
select set_config('app.offline_due_token',(select pickup_token::text from public.orders
 where id=current_setting('app.offline_due_order')::uuid),false);
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.transfer_my_offline_device(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '33333333-0000-4000-8000-000000000453') as lease \gset
select set_config('app.offline_pickup_generation',(:'lease'::jsonb->>'generation'),false);
do $manifest$
declare j jsonb;
begin
 j:=public.offline_ready_order_manifest('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 if not exists(select 1 from jsonb_array_elements(j->'orders') row
 where row->>'id'=current_setting('app.offline_paid_order'))
 or not exists(select 1 from jsonb_array_elements(j->'orders') row
 where row->>'id'=current_setting('app.offline_due_order'))
 then raise exception 'Ready same-day manifest missing order';end if;
end;$manifest$;
select public.stage_my_offline_event(
 '33333333-0000-4000-8000-000000000453',
 current_setting('app.offline_pickup_generation')::bigint,
 '33333333-0000-4000-8000-000000000454',
 'cash_pickup',now(),
 jsonb_build_object('order_id',current_setting('app.offline_paid_order'),
 'pickup_token',current_setting('app.offline_paid_token'),
 'bar_id','aaaaaaaa-0000-4000-8000-000000000001','collected_cents',0)
) as staged_paid \gset
select public.reconcile_my_offline_pickup_event((:'staged_paid'::jsonb->>'id')::uuid) as result_paid \gset
select set_config('app.offline_result_paid',(:'result_paid'::jsonb->>'status'),false);
select public.stage_my_offline_event(
 '33333333-0000-4000-8000-000000000453',
 current_setting('app.offline_pickup_generation')::bigint,
 '33333333-0000-4000-8000-000000000455',
 'cash_pickup',now(),
 jsonb_build_object('order_id',current_setting('app.offline_due_order'),
 'pickup_token',current_setting('app.offline_due_token'),
 'bar_id','aaaaaaaa-0000-4000-8000-000000000001','collected_cents',750)
) as staged_due \gset
select public.reconcile_my_offline_pickup_event((:'staged_due'::jsonb->>'id')::uuid) as result_due \gset
select set_config('app.offline_result_due',(:'result_due'::jsonb->>'status'),false);
select public.reconcile_my_offline_pickup_event((:'staged_due'::jsonb->>'id')::uuid) as repeat_due \gset
select set_config('app.offline_repeat_due',(:'repeat_due'::jsonb->>'status'),false);
reset role;
do $offline_verify$
begin
 if current_setting('app.offline_result_paid')<>'applied'
 or current_setting('app.offline_result_due')<>'applied'
 or current_setting('app.offline_repeat_due')<>'duplicate'
 then raise exception 'Offline pickup missing or not idempotent';end if;
 if (select status from public.orders where id=current_setting('app.offline_paid_order')::uuid)<>'delivered'
 or (select status from public.orders where id=current_setting('app.offline_due_order')::uuid)<>'delivered'
 then raise exception 'Delivery did not persist';end if;
 if (select count(*) from public.counter_payments where order_id=current_setting('app.offline_due_order')::uuid)<>1
 or (select count(*) from public.counter_payments where order_id=current_setting('app.offline_paid_order')::uuid)<>0
 then raise exception 'Offline cash ledger not balanced';end if;
end;$offline_verify$;

-- Cash genuinely received offline, but Stripe later settled on the same order:
-- preserve cash and queue an original-payer Stripe refund, never silently drop it.
reset role;
insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,
 request_key,status,payment_method,payment_status,total_cents)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 '11111111-1111-4111-8111-111111111111',
 current_setting('app.offline_pickup_window')::uuid,
 '11111111-0000-4000-8000-000000000456','ready','stripe','paid',450)
returning id as double_order \gset
select set_config('app.offline_double_order',:'double_order',false);
select set_config('app.offline_double_token',(select pickup_token::text from public.orders
 where id=current_setting('app.offline_double_order')::uuid),false);
insert into public.payment_attempts(school_id,payer_id,order_id,
 stripe_account_id,stripe_payment_intent_id,stripe_checkout_session_id,
 request_key,amount_cents,status)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '11111111-1111-4111-8111-111111111111',
 current_setting('app.offline_double_order')::uuid,
 'acct_1UUniH2RLt7x5EeZ','pi_offlinedouble31','cs_test_offlinedouble31',
 '11111111-0000-4000-8000-000000000457',450,'succeeded');
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.stage_my_offline_event(
 '33333333-0000-4000-8000-000000000453',
 current_setting('app.offline_pickup_generation')::bigint,
 '33333333-0000-4000-8000-000000000458',
 'cash_pickup',now(),
 jsonb_build_object('order_id',current_setting('app.offline_double_order'),
 'pickup_token',current_setting('app.offline_double_token'),
 'bar_id','aaaaaaaa-0000-4000-8000-000000000001','collected_cents',450)
) as stage_double \gset
select public.reconcile_my_offline_pickup_event((:'stage_double'::jsonb->>'id')::uuid)
 as reconciled_double \gset
select set_config('app.offline_double_reconcile',(:'reconciled_double'::jsonb->>'status'),false);
reset role;
do $double_reconcile$
declare n integer;v_refund bigint;v_payer uuid;
begin
 select count(*),min(r.amount_cents),min(a.payer_id::text)::uuid
 into n,v_refund,v_payer
 from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id
 where a.order_id=current_setting('app.offline_double_order')::uuid;
 if current_setting('app.offline_double_reconcile')<>'applied'
 or n<>1 or v_refund<>450
 or v_payer<>'11111111-1111-4111-8111-111111111111'::uuid
 then raise exception 'Offline cash / Stripe collision not refunded to payer';end if;
 if (select count(*) from public.counter_payments
 where order_id=current_setting('app.offline_double_order')::uuid)<>1
 then raise exception 'Physical cash lost during double-charge reconciliation';end if;
end;$double_reconcile$;
