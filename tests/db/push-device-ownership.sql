-- Run after migration 24 and the original Web Push dispatcher test.
-- Shared browser endpoint: never send former user's notices to new account.
reset role;

do $gates$
begin
 if has_function_privilege('anon',
   'public.register_my_push_subscription(text,text,text)','EXECUTE')
 then raise exception 'Anonymous endpoint registration exposed';end if;
 if not has_function_privilege('authenticated',
   'public.register_my_push_subscription(text,text,text)','EXECUTE')
 then raise exception 'Authenticated registration unavailable';end if;
end;
$gates$;

-- User 222 owns this endpoint from push-dispatch.sql and has an old sent alert.
insert into public.customer_notifications(school_id,user_id,event_type,message)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '22222222-2222-4222-8222-222222222222','order_status',
 'Never deliver old account notice to a new user')
returning id as old_notice_id \gset

set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.register_my_push_subscription(
 'https://fcm.googleapis.com/fcm/send/pilot_push_test_012345678901',
 repeat('C',65),repeat('D',24)) as transferred_id \gset
reset role;

do $ownership$
declare v_subscription uuid:=:'transferred_id';
begin
 if (select count(*) from public.push_subscriptions
  where endpoint='https://fcm.googleapis.com/fcm/send/pilot_push_test_012345678901')<>1
 then raise exception 'One endpoint now has multiple owners';end if;
 if not exists(select 1 from public.push_subscriptions
  where id=v_subscription and user_id='11111111-1111-4111-8111-111111111111')
 then raise exception 'Push endpoint ownership transfer failed';end if;
 if not exists(select 1 from app_private.notification_jobs
  where notice_id=:'old_notice_id'::uuid and status='dead')
 then raise exception 'Old account queued notification was not retired';end if;
end;
$ownership$;

-- Client-side direct INSERT can no longer attach the endpoint to a second user.
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $forbid_duplicate$
declare denied boolean:=false;
begin
 begin
  insert into public.push_subscriptions(user_id,endpoint,p256dh,auth_key)
  values('22222222-2222-4222-8222-222222222222',
    'https://fcm.googleapis.com/fcm/send/pilot_push_test_012345678901',
    repeat('A',65),repeat('B',24));
 exception when unique_violation then denied:=true;end;
 if not denied then raise exception 'Duplicate push endpoint was accepted';end if;
end;
$forbid_duplicate$;
reset role;

insert into public.customer_notifications(school_id,user_id,event_type,message)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '11111111-1111-4111-8111-111111111111','order_status',
 'New owner can receive their own notification')
returning id as new_notice_id \gset

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.claim_push_jobs(10) as claimed \gset
reset role;
do $privacy$
declare v_claimed jsonb:=:'claimed'::jsonb;
begin
 if jsonb_array_length(v_claimed)<>1 then
  raise exception 'Expected only one new-owner push job';end if;
 if v_claimed->0->>'message'<>'New owner can receive their own notification'
 then raise exception 'Former user notification leaked to a new owner';end if;
end;
$privacy$;
