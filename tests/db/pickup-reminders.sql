begin;
reset role;
insert into auth.users(id,email) values
 ('73737373-7373-4373-8373-737373737373','pickup-coordinator@test.invalid'),
 ('74747474-7474-4474-8474-747474747474','pickup-member@test.invalid');
update public.bar_service_state set accepting_orders=true
 where bar_id='aaaaaaaa-0000-4000-8000-000000000001';
delete from public.bar_closures where bar_id='aaaaaaaa-0000-4000-8000-000000000001'
 and service_date=current_date+2;
delete from public.bar_opening_hours where bar_id='aaaaaaaa-0000-4000-8000-000000000001';
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',extract(dow from current_date+2),'08:00','12:00'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',extract(dow from current_date+2),'12:00','14:00');
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('73000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',current_date+2,'12:04','12:10');
insert into public.orders(id,school_id,bar_id,customer_id,pickup_window_id,request_key,status,payment_status,total_cents) values
 ('73000000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
  '73737373-7373-4373-8373-737373737373','73000000-0000-4000-8000-000000000001',gen_random_uuid(),'ready','due',500),
 ('73000000-0000-4000-8000-000000000003','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
  '73737373-7373-4373-8373-737373737373','73000000-0000-4000-8000-000000000001',gen_random_uuid(),'delivered','paid',100);
insert into public.group_drafts(id,school_id,bar_id,pickup_window_id,coordinator_id,request_key,title,status) values
 ('73000000-0000-4000-8000-000000000004','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
  '73000000-0000-4000-8000-000000000001','73737373-7373-4373-8373-737373737373',gen_random_uuid(),'Unpaid reminder group','confirmed'),
 ('73000000-0000-4000-8000-000000000005','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
  '73000000-0000-4000-8000-000000000001','73737373-7373-4373-8373-737373737373',gen_random_uuid(),'Paid reminder group','confirmed');
insert into public.group_members(group_id,user_id,status)
 select g.id,u.id,'accepted' from public.group_drafts g cross join auth.users u
 where g.id in ('73000000-0000-4000-8000-000000000004','73000000-0000-4000-8000-000000000005')
 and u.id in ('73737373-7373-4373-8373-737373737373','74747474-7474-4474-8474-747474747474');
insert into public.group_cart_items(group_id,user_id,product_id,product_name,unit_price_cents,quantity)
 select group_id,user_id,'aaaaaaaa-0000-4000-8000-000000000003','Product reminder test',100,1
 from public.group_members where group_id in ('73000000-0000-4000-8000-000000000004','73000000-0000-4000-8000-000000000005');
insert into public.group_orders(id,group_id,school_id,bar_id,pickup_window_id,coordinator_id,request_key,status,total_cents)
 select case when id='73000000-0000-4000-8000-000000000004' then '73000000-0000-4000-8000-000000000006'::uuid
  else '73000000-0000-4000-8000-000000000007'::uuid end,id,school_id,bar_id,pickup_window_id,coordinator_id,gen_random_uuid(),'ready',200
 from public.group_drafts where id in ('73000000-0000-4000-8000-000000000004','73000000-0000-4000-8000-000000000005');
insert into public.group_order_lines(group_order_id,group_cart_item_id,beneficiary_id,product_id,name,quantity,unit_cents)
 select o.id,i.id,i.user_id,i.product_id,i.product_name,i.quantity,i.unit_price_cents
 from public.group_cart_items i join public.group_orders o on o.group_id=i.group_id
 where o.id in ('73000000-0000-4000-8000-000000000006','73000000-0000-4000-8000-000000000007');
insert into public.group_counter_payments(group_order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
 values('73000000-0000-4000-8000-000000000007','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001',
 '73737373-7373-4373-8373-737373737373',gen_random_uuid(),'cash',200);

select app_private.enqueue_due_pickup_notices((current_date+2+time '11:45') at time zone 'Europe/Rome',500);
do $$begin
 if exists(select 1 from public.customer_notifications where delivery_event_key like 'closing:%73000000%')
 then raise exception 'Lunch pause treated as daily closing';end if;
end;$$;
select app_private.enqueue_due_pickup_notices((current_date+2+time '12:00') at time zone 'Europe/Rome',1);
select app_private.enqueue_due_pickup_notices((current_date+2+time '12:00') at time zone 'Europe/Rome',500);
select app_private.enqueue_due_pickup_notices((current_date+2+time '12:00') at time zone 'Europe/Rome',500);
do $$begin
 if (select count(*) from public.customer_notifications where delivery_event_key like 'pickup:%73000000%')<>4
 then raise exception 'Pickup reminders missed, duplicated or sent to paid participants';end if;
 if exists(select 1 from public.customer_notifications where event_type='group_pickup_reminder'
  and group_id='73000000-0000-4000-8000-000000000005' and user_id='74747474-7474-4474-8474-747474747474')
 then raise exception 'Fully paid member received due reminder';end if;
 if exists(select 1 from public.customer_notifications where event_type='pickup_reminder'
  and order_id='73000000-0000-4000-8000-000000000003')
 then raise exception 'Delivered order received reminder';end if;
 if not exists(select 1 from public.customer_notifications where order_id='73000000-0000-4000-8000-000000000002'
  and event_type='pickup_reminder' and message like '%5,00%')
 then raise exception 'Individual due amount missing';end if;
 if not exists(select 1 from public.customer_notifications where group_id='73000000-0000-4000-8000-000000000004'
  and user_id='73737373-7373-4373-8373-737373737373' and event_type='group_pickup_reminder' and message like '%2,00%')
 then raise exception 'Coordinator balance missing';end if;
end;$$;
select app_private.enqueue_due_pickup_notices((current_date+2+time '13:45') at time zone 'Europe/Rome',500);
select app_private.enqueue_due_pickup_notices((current_date+2+time '13:45') at time zone 'Europe/Rome',500);
do $$begin
 if (select count(*) from public.customer_notifications where delivery_event_key like 'closing:%73000000%')<>3
 then raise exception 'Closing reminders missing or duplicated';end if;
 if exists(select 1 from public.customer_notifications where event_type='group_closing_reminder'
  and group_id in ('73000000-0000-4000-8000-000000000004','73000000-0000-4000-8000-000000000005')
  and user_id<>'73737373-7373-4373-8373-737373737373')
 then raise exception 'Closing reminder sent to non-coordinator';end if;
 if has_function_privilege('authenticated','public.enqueue_pickup_reminders(integer)','execute')
  or has_function_privilege('service_role','app_private.enqueue_due_pickup_notices(timestamptz,integer)','execute')
 then raise exception 'Scheduler authorization bypass';end if;
end;$$;
rollback;
