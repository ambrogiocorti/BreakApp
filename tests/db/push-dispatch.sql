-- Integration test with Stripe/Groups/Realtime fixtures already installed.
reset role;
do $no_public_privilege$
begin
 if has_function_privilege('authenticated','public.claim_push_jobs(integer)','EXECUTE')
 or has_function_privilege('anon','public.finish_push_job(uuid,boolean,integer,text)','EXECUTE')
 then raise exception 'Dispatcher RPC exposed to public';end if;
 if not (select relrowsecurity from pg_class where oid='app_private.notification_deliveries'::regclass)
 then raise exception 'Delivery audit RLS disabled';end if;
end;$no_public_privilege$;

set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
insert into public.push_subscriptions(user_id,endpoint,p256dh,auth_key)
values('22222222-2222-4222-8222-222222222222',
 'https://fcm.googleapis.com/fcm/send/pilot_push_test_012345678901',
 repeat('A',65),repeat('B',24))
returning id as subscription_id \gset
select set_config('app.push_sub_id',:'subscription_id',false);
do $no_client_claim$
declare denied boolean:=false;
begin
 begin perform public.claim_push_jobs(2);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Customer claimed push queue';end if;
end;$no_client_claim$;
reset role;
insert into public.customer_notifications(school_id,user_id,event_type,message)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '22222222-2222-4222-8222-222222222222','order_status',
 'Notifica di integrazione Web Push')
returning id as notice_id \gset
select set_config('app.push_notice_id',:'notice_id',false);
do $enqueued$
begin
 if (select count(*) from app_private.notification_jobs
     where notice_id=current_setting('app.push_notice_id')::uuid
       and subscription_id=current_setting('app.push_sub_id')::uuid)<>1
 then raise exception 'Push event did not enqueue';end if;
end;$enqueued$;
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.claim_push_jobs(10) as claimed \gset
select set_config('app.push_claimed',:'claimed',false);
do $claimed_once$
begin
 if jsonb_array_length(current_setting('app.push_claimed')::jsonb)<1
 then raise exception 'Dispatcher did not claim push';end if;
end;$claimed_once$;
select public.finish_push_job(
 (current_setting('app.push_claimed')::jsonb->0->>'job_id')::uuid,
 true,201,null);
reset role;
do $marked_sent$
begin
 if not exists(select 1 from app_private.notification_jobs
  where notice_id=current_setting('app.push_notice_id')::uuid and status='sent')
 then raise exception 'Delivered push was not marked sent';end if;
 if not exists(select 1 from public.push_subscriptions
  where id=current_setting('app.push_sub_id')::uuid and last_success_at is not null)
 then raise exception 'Subscription delivery timestamp missing';end if;
end;$marked_sent$;
