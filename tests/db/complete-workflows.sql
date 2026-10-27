-- Disposable CI database. Stripe signatures are checked by the Edge webhook;
-- these tests exercise the trusted settlement boundary, never a live payment.
begin;
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('81111111-1111-4111-8111-111111111111','workflow-customer@test.invalid',now()),
 ('82222222-2222-4222-8222-222222222222','workflow-guest@test.invalid',now()),
 ('83333333-3333-4333-8333-333333333333','workflow-barista@test.invalid',now()),
 ('84444444-4444-4444-8444-444444444444','workflow-admin@test.invalid',now()),
 ('85555555-5555-4555-8555-555555555555','workflow-platform@test.invalid',now());
insert into public.schools(id,slug,name,latitude,longitude,approval_product_threshold,max_active_approvals,cancel_cutoff_minutes)
 values('81000000-0000-4000-8000-000000000001','workflow-school','Workflow School',45,9,1,1,0);
insert into public.bars(id,school_id,name) values('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','Workflow Bar');
insert into public.categories(id,school_id,bar_id,name) values('81000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','Food');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents,allergens) values
 ('81000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000003','Bread',200,array['gluten']),
 ('81000000-0000-4000-8000-000000000005','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000003','Milk snack',300,array['milk']),
 ('81000000-0000-4000-8000-000000000006','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000003','Fruit',100,'{}');
insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 select p.school_id,p.bar_id,p.id,(now() at time zone 'Europe/Rome')::date+d,1000 from public.products p cross join generate_series(0,1) d where p.bar_id='81000000-0000-4000-8000-000000000002';
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select '81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002',d,'00:00','23:59' from generate_series(0,6) d;
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('81000000-0000-4000-8000-000000000007','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date+1,'12:00','12:15'),
 ('81000000-0000-4000-8000-000000000008','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date+1,'13:00','13:15');
insert into public.school_memberships(school_id,user_id) values
 ('81000000-0000-4000-8000-000000000001','83333333-3333-4333-8333-333333333333'),
 ('81000000-0000-4000-8000-000000000001','84444444-4444-4444-8444-444444444444');
insert into public.role_assignments(membership_id,role_code)
 select id,case when user_id='83333333-3333-4333-8333-333333333333' then 'bartender' else 'school_admin' end
 from public.school_memberships where school_id='81000000-0000-4000-8000-000000000001';
insert into app_private.platform_admins(user_id) values('85555555-5555-4555-8555-555555555555');
insert into public.school_stripe_merchants(school_id,stripe_account_id,charges_enabled) values('81000000-0000-4000-8000-000000000001','acct_workflow810',true);
create function pg_temp.actor(p_user uuid,p_role text default 'authenticated',p_aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',p_user::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('role',p_role,'aal',p_aal,'is_anonymous',false)::text,true);
end;$$;
select pg_temp.actor('82222222-2222-4222-8222-222222222222','service_role');
select public.create_guest_access('82222222-2222-4222-8222-222222222222','81000000-0000-4000-8000-000000000001','Guest Student','5A',repeat('8',64));

do $$declare a uuid;b uuid;r uuid;c uuid;j jsonb;line uuid;pay uuid;ref uuid;denied boolean;before_stock integer;
begin
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 a:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000008',
 '[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now());
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');
 b:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007',
 '[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":3}]',gen_random_uuid(),45,9,10,now());
 if (select sum(allocated) from public.daily_stock where bar_id='81000000-0000-4000-8000-000000000002')<>0 then raise exception 'Queued requests reserved stock without staff';end if;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 perform public.set_staff_service_presence('81000000-0000-4000-8000-000000000002',true);
 if (select status from public.orders where id=b)<>'approval_active' or (select status from public.orders where id=a)<>'approval_queued' then raise exception 'Pickup priority/capacity incorrect';end if;
 select id into r from public.order_approvals where order_id=b;perform public.decide_order_approval(r,true,'');
 select id into r from public.order_approvals where order_id=a;perform public.decide_order_approval(r,false,'No capacity');
 if (select sum(allocated) from public.daily_stock where bar_id='81000000-0000-4000-8000-000000000002')<>3 then raise exception 'Approval reserve/release incorrect';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');
 j:=public.begin_individual_stripe_checkout(b,gen_random_uuid());pay:=(j->>'attempt_id')::uuid;
 if (j->>'amount_cents')::int<>600 then raise exception 'Initial charge incorrect';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222','service_role');
 perform public.attach_stripe_checkout_session(pay,'cs_test_workflow8101');
 perform public.finalize_verified_checkout('evt_workflow8101','acct_workflow810','cs_test_workflow8101','pi_workflow8101',pay,600,'eur',true,'{}');
 if public.finalize_verified_checkout('evt_workflow8101','acct_workflow810','cs_test_workflow8101','pi_workflow8101',pay,600,'eur',true,'{}')<>'duplicate_payment' then raise exception 'Duplicate settlement failed';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');
 c:=public.request_order_amendment(b,'[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid());
 if (select total_cents from public.orders where id=b)<>400 or app_private.order_paid_cents('individual',b)<>400 then raise exception 'Paid decrease/net ledger incorrect';end if;
 if (select sum(amount_cents) from public.payment_refunds where payment_id=pay)<>200 then raise exception 'Partial refund not queued';end if;
 select id into line from public.order_items where order_id=b and removed_at is null;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 c:=public.propose_order_exception('individual',b,'substitution',line,'81000000-0000-4000-8000-000000000005',null,gen_random_uuid());
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');denied:=false;
 begin perform public.respond_order_exception(c,'accept');exception when others then denied:=true;end;
 if not denied then raise exception 'Another customer accepted substitution';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');perform public.respond_order_exception(c,'accept');
 j:=public.begin_individual_stripe_checkout(b,gen_random_uuid());
 if (j->>'amount_cents')::int<>200 then raise exception 'Additional charge must be only the price difference';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222','service_role');
 perform public.attach_stripe_checkout_session((j->>'attempt_id')::uuid,'cs_test_workflow8102');
 perform public.finalize_verified_checkout('evt_workflow8102','acct_workflow810','cs_test_workflow8102','pi_workflow8102',(j->>'attempt_id')::uuid,200,'eur',true,'{}');
 if app_private.order_paid_cents('individual',b)<>600 or (select payment_status from public.orders where id=b)<>'paid' then raise exception 'Top-up did not balance';end if;
 select id into ref from public.payment_refunds where payment_id=pay;
 perform public.finalize_verified_stripe_refund('evt_workflow8103','acct_workflow810',ref,'re_workflow8101','pi_workflow8101',200,'eur','succeeded');
 if (select payment_status from public.orders where id=b)<>'paid' then raise exception 'Partial refund falsely marked full refund';end if;
 -- A failed stock increase must preserve the original order and money.
 update public.daily_stock set capacity=allocated where product_id='81000000-0000-4000-8000-000000000006';
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');denied:=false;
 c:=public.request_order_amendment(b,'[{"product_id":"81000000-0000-4000-8000-000000000006","quantity":100}]',gen_random_uuid());
 if (select state from public.order_change_requests where id=c)<>'staff_pending' then raise exception 'Large amendment bypassed staff approval';end if;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 begin perform public.decide_order_amendment(c,true);exception when others then denied:=true;end;
 if not denied or (select total_cents from public.orders where id=b)<>600 then raise exception 'Failed change destroyed original';end if;
 perform set_config('test.workflow_order',b::text,true);
end;$$;

do $$declare g uuid;go uuid;invite uuid;line uuid;payment jsonb;proposal uuid;sp uuid;denied boolean;
begin
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 g:=public.create_group_draft('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007',gen_random_uuid(),'Workflow group',false,4);
 invite:=(public.group_draft_details(g)->>'invite_token')::uuid;
 perform public.replace_group_personal_cart(g,'[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":1}]');
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');perform public.join_group_draft(invite,45,9,10,now());
 perform public.replace_group_personal_cart(g,'[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":1}]');
 denied:=false;begin perform public.create_group_draft('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007',gen_random_uuid(),'Guest forbidden',false,4);exception when others then denied:=true;end;
 if not denied then raise exception 'Guest coordinated a group';end if;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');denied:=false;
 begin perform public.transfer_group_coordinator(g,'82222222-2222-4222-8222-222222222222');exception when others then denied:=true;end;
 if not denied then raise exception 'Guest became coordinator by transfer';end if;
 select id into line from public.group_cart_items where group_id=g and user_id='82222222-2222-4222-8222-222222222222';
 payment:=public.begin_group_stripe_checkout(g,array[line],gen_random_uuid());
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111','service_role');
 perform public.attach_stripe_checkout_session((payment->>'attempt_id')::uuid,'cs_test_workflow8201');
 perform public.finalize_verified_group_checkout('evt_workflow8201','acct_workflow810','cs_test_workflow8201','pi_workflow8201',(payment->>'attempt_id')::uuid,200,'eur',true,'{}');
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 go:=public.confirm_group_order(g,gen_random_uuid(),true,45,9,10,now());
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 perform public.decide_order_approval((select id from public.order_approvals where group_order_id=go),true,'');
 select id into line from public.group_order_lines where group_order_id=go and beneficiary_id='82222222-2222-4222-8222-222222222222';
 -- Restore fruit stock for a lower-price replacement, refund goes to the gift payer.
 update public.daily_stock set capacity=1000 where product_id='81000000-0000-4000-8000-000000000006';
 proposal:=public.propose_order_exception('group',go,'substitution',line,'81000000-0000-4000-8000-000000000006',null,gen_random_uuid());
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');denied:=false;
 begin perform public.respond_order_exception(proposal,'accept');exception when others then denied:=true;end;
 if not denied then raise exception 'Non-coordinator accepted group substitution';end if;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');perform public.respond_order_exception(proposal,'accept');
 if not exists(select 1 from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id
  where r.request_key=proposal and r.amount_cents=100 and a.payer_id='81111111-1111-4111-8111-111111111111') then raise exception 'Group credit lost its actual payer';end if;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 proposal:=public.propose_order_exception('group',go,'substitution',line,'81000000-0000-4000-8000-000000000005',null,gen_random_uuid());
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');perform public.respond_order_exception(proposal,'accept');
 select id into sp from public.order_supplements where group_order_id=go and state='available';
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');payment:=public.begin_group_stripe_checkout(g,array[sp],gen_random_uuid());
 if (payment->>'amount_cents')::int<>200 then raise exception 'Group supplement not the exact difference';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222','service_role');
 perform public.attach_stripe_checkout_session((payment->>'attempt_id')::uuid,'cs_test_workflow8202');
 perform public.finalize_verified_group_checkout('evt_workflow8202','acct_workflow810','cs_test_workflow8202','pi_workflow8202',(payment->>'attempt_id')::uuid,200,'eur',true,'{}');
 if app_private.order_paid_cents('group',go)<>300 then raise exception 'Group net payment/refund sum incorrect';end if;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 perform public.scan_group_pickup((select pickup_token from public.group_orders where id=go));
 perform public.record_group_counter_payment(go,'cash',gen_random_uuid());
 perform public.advance_group_order(go,'ready');perform public.deliver_group_order(go);
 if (select status from public.group_orders where id=go)<>'delivered' or app_private.order_paid_cents('group',go)<>500 then raise exception 'Group final balance/delivery failed';end if;
end;$$;

do $$declare p uuid;o uuid;k uuid:=gen_random_uuid();denied boolean;j jsonb;
begin
 update public.schools set approval_product_threshold=null where id='81000000-0000-4000-8000-000000000001';
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','authenticated','aal2');
 p:=public.save_school_promotion(null,'81000000-0000-4000-8000-000000000002','TEST25','Quarter discount','percent',25,now()-interval '1 hour',now()+interval '1 day',1,1,'[]');
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 o:=public.submit_promoted_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',k,45,9,10,now(),'TEST25');
 if (select total_cents from public.orders where id=o)<>300 then raise exception 'Coupon quote incorrect';end if;
 if public.submit_promoted_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',k,45,9,10,now(),'TEST25')<>o then raise exception 'Coupon idempotence failed';end if;
 denied:=false;begin perform public.submit_promoted_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now(),'TEST25');exception when others then denied:=true;end;
 if not denied then raise exception 'Coupon quota bypassed';end if;
 perform pg_temp.actor('85555555-5555-4555-8555-555555555555','authenticated','aal2');
 j:=public.platform_onboard_school('workflow-second','Second school','Second bar',45,9,'ready_made','workflow-admin@test.invalid');
 if not exists(select 1 from public.bar_service_state where bar_id=(j->>'bar_id')::uuid and not accepting_orders) then raise exception 'New school opened before setup';end if;
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','authenticated','aal2');
 if public.import_school_classes('81000000-0000-4000-8000-000000000001','["5A","5B","5A"]')<>2 then raise exception 'Class import duplicate handling incorrect';end if;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');denied:=false;
 begin perform public.import_school_classes('81000000-0000-4000-8000-000000000001','["5C"]');exception when others then denied:=true;end;
 if not denied then raise exception 'Customer changed school classes';end if;
end;$$;
do $$declare o uuid;r uuid;stock_before integer;c uuid;old_window uuid;new_group uuid;group_order uuid;manifest jsonb;event jsonb;receipt jsonb;device uuid:=gen_random_uuid();
begin
 -- Last slot -> two-hour customer decision, no reservation; then expiry.
 update public.schools set approval_product_threshold=1 where id='81000000-0000-4000-8000-000000000001';
 delete from public.staff_service_presence where school_id='81000000-0000-4000-8000-000000000001';
 select allocated into stock_before from public.daily_stock where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date+1;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000008','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now());
 perform app_private.process_approval_queue('81000000-0000-4000-8000-000000000002',((now() at time zone 'Europe/Rome')::date+1+time '14:00') at time zone 'Europe/Rome');
 if (select status from public.orders where id=o)<>'awaiting_reschedule' then raise exception 'Last slot did not request customer decision';end if;
 perform app_private.process_approval_queue('81000000-0000-4000-8000-000000000002',((now() at time zone 'Europe/Rome')::date+1+time '16:00:01') at time zone 'Europe/Rome');
 if (select status from public.orders where id=o)<>'cancelled' or (select allocated from public.daily_stock where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date+1)<>stock_before then raise exception 'Two-hour expiry leaked stock';end if;
 -- Active ten-minute lease expiry releases stock and does not confirm anything.
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');perform public.set_staff_service_presence('81000000-0000-4000-8000-000000000002',true);
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000008','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now());
 update public.order_approvals set lease_until=now()-interval '1 second' where order_id=o;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111','service_role');perform public.maintain_approval_queues();
 if (select status from public.orders where id=o)<>'cancelled' or (select allocated from public.daily_stock where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date+1)<>stock_before then raise exception 'Ten-minute expiry leaked stock';end if;
 -- A delay without a reply keeps its original slot.
 o:=current_setting('test.workflow_order')::uuid;select pickup_window_id into old_window from public.orders where id=o;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 c:=public.propose_order_exception('individual',o,'delay',null,null,'81000000-0000-4000-8000-000000000008',gen_random_uuid());
 update public.order_change_requests set expires_at=now()-interval '1 second' where id=c;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333','service_role');perform public.maintain_order_changes();
 if (select pickup_window_id from public.orders where id=o)<>old_window or (select status from public.orders where id=o)='cancelled' then raise exception 'Silent reschedule/cancellation after delay';end if;
 -- A paid group is included in extraordinary closure and refunded to its real payer.
 update public.schools set approval_product_threshold=null where id='81000000-0000-4000-8000-000000000001';
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 new_group:=public.create_group_draft('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007',gen_random_uuid(),'Closure group',false,4);
 perform public.replace_group_personal_cart(new_group,'[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":1}]');
 group_order:=public.confirm_group_order(new_group,gen_random_uuid(),true,45,9,10,now());
 -- Model an already signature-verified test payment, not an external Stripe request.
 insert into public.payment_attempts(school_id,payer_id,group_id,stripe_account_id,request_key,amount_cents,status,stripe_payment_intent_id)
 values('81000000-0000-4000-8000-000000000001','81111111-1111-4111-8111-111111111111',new_group,'acct_workflow810',gen_random_uuid(),200,'succeeded','pi_workflowclosure');
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 c:=public.close_bar_interval('81000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date+1,'11:59','12:30','extraordinary','Confirmed test closure');
 if (select status from public.group_orders where id=group_order)<>'cancelled' then raise exception 'Group survived extraordinary closure';end if;
 if not exists(select 1 from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id where a.group_id=new_group and r.amount_cents=200)
 then raise exception 'Paid group closure did not queue refund';end if;
 perform public.reopen_bar_interval(c);
 if (select status from public.group_orders where id=group_order)<>'cancelled' then raise exception 'Reopening resurrected cancelled group';end if;
 -- A real daily group manifest and a cash pickup are bound to the author/device generation.
 insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at)
 values('81000000-0000-4000-8000-000000000009','81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date,'00:01','23:58');
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 new_group:=public.create_group_draft('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007',gen_random_uuid(),'Offline pickup group',false,4);
 perform public.replace_group_personal_cart(new_group,'[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":1}]');
 group_order:=public.confirm_group_order(new_group,gen_random_uuid(),true,45,9,10,now());
 update public.group_orders set pickup_window_id='81000000-0000-4000-8000-000000000009',status='ready' where id=group_order;
 update public.group_drafts set pickup_window_id='81000000-0000-4000-8000-000000000009' where id=new_group;
 update public.daily_stock set allocated=allocated-1 where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date+1;
 update public.daily_stock set allocated=allocated+1 where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 receipt:=public.transfer_my_offline_device('81000000-0000-4000-8000-000000000001',device);
 perform public.record_cash_operation('81000000-0000-4000-8000-000000000002',gen_random_uuid(),'open',1000,'',gen_random_uuid());
 manifest:=public.offline_ready_order_manifest('81000000-0000-4000-8000-000000000001');
 if not exists(select 1 from jsonb_array_elements(manifest->'orders') x where x->>'id'=group_order::text and x->>'kind'='group') then raise exception 'Group absent from encrypted-ready manifest';end if;
 event:=public.stage_my_offline_event(device,(receipt->>'generation')::bigint,gen_random_uuid(),'group_pickup',now(),
  jsonb_build_object('order_id',group_order,'pickup_token',(select pickup_token from public.group_orders where id=group_order),
   'bar_id','81000000-0000-4000-8000-000000000002','snapshot_id',manifest->>'snapshot_id','collected_cents',200));
 receipt:=public.reconcile_my_offline_group_pickup((event->>'id')::uuid);
 if receipt->>'status'<>'applied' or (select status from public.group_orders where id=group_order)<>'delivered' then raise exception 'Offline cash group pickup not applied: %',receipt;end if;
 if public.reconcile_my_offline_group_pickup((event->>'id')::uuid)->>'status'<>'duplicate' then raise exception 'Offline group replay duplicated delivery';end if;
end;$$;

-- Shared tickets expose neither private lines nor another payer's receipt.
do $$declare g uuid;shared uuid;personal uuid;line uuid;pay uuid;r uuid;denied boolean;
begin
 select id into g from public.group_drafts where title='Workflow group';
 if g is null then select id into g from public.group_drafts where coordinator_id='81111111-1111-4111-8111-111111111111' and exists(select 1 from public.group_members m where m.group_id=group_drafts.id and m.user_id='82222222-2222-4222-8222-222222222222' and m.status='accepted') limit 1;end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');
 shared:=public.open_group_support_ticket(g,'group',null,null,'Problema ritiro gruppo','Il gruppo ha bisogno di assistenza',gen_random_uuid());
 select id into line from public.group_cart_items where group_id=g and user_id='82222222-2222-4222-8222-222222222222' limit 1;
 personal:=public.open_group_support_ticket(g,'personal',line,null,'Prodotto personale','Richiesta riservata sul mio prodotto',gen_random_uuid());
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 if not app_private.can_read_support(shared) or app_private.can_read_support(personal) then raise exception 'Group ticket privacy failed';end if;
 perform public.post_support_message(shared,'Commento del coordinatore');
 select id into pay from public.payment_attempts where group_id=g and payer_id='82222222-2222-4222-8222-222222222222' limit 1;
 denied:=false;begin perform public.open_group_support_ticket(g,'personal',null,pay,'Ricevuta di un altro','Tentativo vietato',gen_random_uuid());exception when others then denied:=true;end;
 if pay is not null and not denied then raise exception 'Coordinator read another payer receipt';end if;
 denied:=false;begin perform public.set_support_ticket_status(shared,'resolved','');exception when others then denied:=true;end;
 if not denied then raise exception 'Member resolved group ticket';end if;
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','authenticated','aal2');perform public.set_support_ticket_status(shared,'resolved','Verificato');
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');r:=public.request_support_reopen(shared,'Il problema rimane ancora presente');
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','authenticated','aal2');perform public.review_support_reopen(r,true,'Nuova verifica');
 if (select status from public.support_tickets where id=shared)<>'open' then raise exception 'Group reopen failed';end if;
 perform set_config('test.shared_ticket',shared::text,true);perform set_config('test.personal_ticket',personal::text,true);
end;$$;
set local role authenticated;
select pg_temp.actor('81111111-1111-4111-8111-111111111111');
do $$begin
 if not exists(select 1 from public.support_tickets where id=current_setting('test.shared_ticket')::uuid) or exists(select 1 from public.support_tickets where id=current_setting('test.personal_ticket')::uuid) then raise exception 'Ticket RLS exposed another member private record';end if;
end;$$;
reset role;
-- An honest physical shortage preserves the earlier order and isolates product/day.
do $$declare early uuid;late uuid;stock uuid;c uuid;n integer;before_units integer;denied boolean;
begin
 update public.schools set approval_product_threshold=null,approval_amount_threshold_cents=null,max_unpaid_orders_per_customer=50 where id='81000000-0000-4000-8000-000000000001';
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 early:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007','[{"product_id":"81000000-0000-4000-8000-000000000006","quantity":1}]',gen_random_uuid(),45,9,10,now());
 late:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000008','[{"product_id":"81000000-0000-4000-8000-000000000006","quantity":1}]',gen_random_uuid(),45,9,10,now());
 select id,allocated into stock,before_units from public.daily_stock where product_id='81000000-0000-4000-8000-000000000006' and service_date=(now() at time zone 'Europe/Rome')::date+1;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 n:=public.reconcile_physical_stock(stock,before_units-1,'Conteggio fisico verificato dal personale');
 if n<>1 or exists(select 1 from public.order_change_requests where order_id=early and payload->>'unavailable'='true') then raise exception 'Stock shortage ignored pickup priority';end if;
 select id into c from public.order_change_requests where order_id=late and state='customer_pending' and payload->>'unavailable'='true';
 if c is null then raise exception 'Shortage did not start affected line exception';end if;
 denied:=false;begin update public.daily_stock set allocated=allocated+1 where id=stock;exception when others then denied:=true;end;
 if not denied then raise exception 'Shortage allowed new allocation';end if;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');
 perform public.respond_order_exception(c,'reject');
 if (select allocated>capacity from public.daily_stock where id=stock) then raise exception 'Shortage did not release unavailable allocation';end if;
 if (select status from public.orders where id=early)='cancelled' then raise exception 'Earlier order cancelled by shortage';end if;
 perform set_config('test.no_show_early',early::text,true);
end;$$;
-- A cached partially paid order receives only its residual in cash; refund the
-- Stripe top-up that arrived after the manifest, preserving both real receipts.
do $$declare o uuid;a uuid;topup uuid;j jsonb;m jsonb;e jsonb;r jsonb;l public.staff_offline_leases%rowtype;
begin
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');
 o:=public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000008','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 j:=public.begin_individual_stripe_checkout(o,gen_random_uuid());a:=(j->>'attempt_id')::uuid;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222','service_role');
 perform public.attach_stripe_checkout_session(a,'cs_test_offlinepartial1');
 perform public.finalize_verified_checkout('evt_offlinepartial1','acct_workflow810','cs_test_offlinepartial1','pi_offlinepartial1',a,200,'eur',true,'{}');
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');
 perform public.request_order_amendment(o,'[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid());
 update public.orders set status='ready',pickup_window_id='81000000-0000-4000-8000-000000000009' where id=o;
 update public.daily_stock set allocated=allocated-2 where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date+1;
 update public.daily_stock set allocated=allocated+2 where product_id='81000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date;
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 select * into l from public.staff_offline_leases where barista_id=auth.uid();m:=public.offline_ready_order_manifest(l.school_id);
 if not exists(select 1 from jsonb_array_elements(m->'orders') x where x->>'id'=o::text and (x->>'due_cents')::int=200) then raise exception 'Cached individual residual incorrect';end if;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222');j:=public.begin_individual_stripe_checkout(o,gen_random_uuid());topup:=(j->>'attempt_id')::uuid;
 perform pg_temp.actor('82222222-2222-4222-8222-222222222222','service_role');perform public.attach_stripe_checkout_session(topup,'cs_test_offlinepartial2');
 perform public.finalize_verified_checkout('evt_offlinepartial2','acct_workflow810','cs_test_offlinepartial2','pi_offlinepartial2',topup,200,'eur',true,'{}');
 perform pg_temp.actor('83333333-3333-4333-8333-333333333333');
 e:=public.stage_my_offline_event(l.device_id,l.generation,gen_random_uuid(),'cash_pickup',now(),jsonb_build_object('order_id',o,'pickup_token',(select pickup_token from public.orders where id=o),'bar_id','81000000-0000-4000-8000-000000000002','snapshot_id',m->>'snapshot_id','collected_cents',200));
 r:=public.reconcile_my_offline_pickup_event((e->>'id')::uuid);
 if r->>'status'<>'applied' or app_private.order_paid_cents('individual',o)<>400 or not exists(select 1 from public.payment_refunds where payment_id=topup and amount_cents=200) then raise exception 'Residual offline/Stripe overlap incorrect: %',r;end if;
 if exists(select 1 from public.payment_refunds where payment_id=a) then raise exception 'Refunded the wrong earlier payment';end if;
 if public.reconcile_my_offline_pickup_event((e->>'id')::uuid)->>'status'<>'duplicate' then raise exception 'Individual offline replay not idempotent';end if;
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','authenticated','aal2');
 j:=public.request_completed_order_refund('individual',o,gen_random_uuid(),'Verifica rimborso ordine con saldo misto');
 if (j->>'cash_pending')::int<>200 or jsonb_array_length(j->'online')<>1 or app_private.order_paid_cents('individual',o)<>0 then raise exception 'Mixed completed-order refund did not balance';end if;
end;$$;

-- A no-show never returns food to stock; only a registered owner is penalized.
do $$declare before_units integer;n integer;denied boolean;begin
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','authenticated','aal2');
 perform public.set_no_show_policy('81000000-0000-4000-8000-000000000001',60);
 select sum(allocated) into before_units from public.daily_stock where school_id='81000000-0000-4000-8000-000000000001';
 perform pg_temp.actor('84444444-4444-4444-8444-444444444444','service_role');
 n:=public.maintain_daily_orders(now()+interval '3 days');
 if n<1 or (select status from public.orders where id=current_setting('test.no_show_early')::uuid)<>'no_show' then raise exception 'Daily no-show job skipped closed orders';end if;
 if (select sum(allocated) from public.daily_stock where school_id='81000000-0000-4000-8000-000000000001')<>before_units then raise exception 'No-show recycled perishable food';end if;
 if exists(select 1 from public.order_no_shows where accountable_user_id='82222222-2222-4222-8222-222222222222' and penalty_until is not null) then raise exception 'Guest penalized for no-show';end if;
 if public.maintain_daily_orders(now()+interval '3 days')<>0 then raise exception 'Daily no-show replay not idempotent';end if;
 perform pg_temp.actor('81111111-1111-4111-8111-111111111111');denied:=false;
 begin perform public.submit_individual_order('81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000007','[{"product_id":"81000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());exception when others then denied:=true;end;
 if not denied then raise exception 'Configured no-show booking restriction bypassed';end if;
end;$$;
rollback;
