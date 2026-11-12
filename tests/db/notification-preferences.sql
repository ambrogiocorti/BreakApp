-- Disposable database only; existing order fixtures provide School A.
begin;
reset role;
insert into auth.users(id,email) values
 ('70707070-7070-4070-8070-707070707070','notice-owner@test.invalid'),
 ('71717171-7171-4171-8171-717171717171','notice-other@test.invalid');
insert into public.push_subscriptions(user_id,endpoint,p256dh,auth_key) values
 ('70707070-7070-4070-8070-707070707070','https://fcm.googleapis.com/fcm/send/preferences_test_70707070',repeat('A',65),repeat('B',24));
set local role authenticated;
select set_config('request.jwt.claim.sub','70707070-7070-4070-8070-707070707070',true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
do $$begin
 if public.get_my_notification_preferences()->>'push_groups'<>'true'
 then raise exception 'Defaults missing';end if;
 perform public.set_my_notification_preferences(false,true,false,true,false);
 if (select count(*) from public.notification_preferences)<>1
 then raise exception 'Owner cannot read own preference';end if;
end;$$;
reset role;
insert into public.customer_notifications(school_id,user_id,event_type,message) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','70707070-7070-4070-8070-707070707070','school_announcement','preference-announcement'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','70707070-7070-4070-8070-707070707070','group_join_requested','preference-group'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','70707070-7070-4070-8070-707070707070','order_status','preference-order');
do $$begin
 if (select count(*) from public.customer_notifications where user_id='70707070-7070-4070-8070-707070707070')<>3
 then raise exception 'Preferences suppressed in-app messages';end if;
 if (select count(*) from app_private.notification_jobs where user_id='70707070-7070-4070-8070-707070707070')<>1
 then raise exception 'Wrong push categories queued';end if;
end;$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','71717171-7171-4171-8171-717171717171',true);
do $$begin
 if exists(select 1 from public.notification_preferences)
 then raise exception 'Cross-user preference leakage';end if;
 perform public.set_my_notification_preferences(true,false,true,false,true);
end;$$;
select set_config('request.jwt.claim.sub','70707070-7070-4070-8070-707070707070',true);
select public.set_my_notification_preferences(false,false,false,true,false);
reset role;
do $$begin
 if exists(select 1 from app_private.notification_jobs
  where user_id='70707070-7070-4070-8070-707070707070' and status<>'dead')
 then raise exception 'Queued delivery survived opt-out';end if;
 if (select push_orders from public.notification_preferences where user_id='71717171-7171-4171-8171-717171717171')
 then raise exception 'Saving modified another account';end if;
 if has_function_privilege('anon','public.get_my_notification_preferences()','execute')
 or has_table_privilege('authenticated','public.notification_preferences','update')
 then raise exception 'Preferences permission bypass';end if;
end;$$;
-- An abandoned sixth delivery attempt is terminal, rather than stuck in sending.
update app_private.notification_jobs set status='sending',attempts=6,next_attempt_at=now()-interval '1 second'
 where user_id='70707070-7070-4070-8070-707070707070';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.claim_push_jobs(1);
reset role;
do $$begin
 if exists(select 1 from app_private.notification_jobs
  where user_id='70707070-7070-4070-8070-707070707070' and status<>'dead')
 then raise exception 'Exhausted delivery was not finalized';end if;
end;$$;
-- Soft revocation works even with an existing delivery audit (FK restrict).
insert into app_private.notification_deliveries(job_id,subscription_id,status,status_code)
 select id,subscription_id,'failed',503 from app_private.notification_jobs
 where user_id='70707070-7070-4070-8070-707070707070';
set local role authenticated;
select set_config('request.jwt.claim.sub','71717171-7171-4171-8171-717171717171',true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
do $$begin
 if public.disable_my_push_subscription('https://fcm.googleapis.com/fcm/send/preferences_test_70707070')
 then raise exception 'Another account disabled this device';end if;
end;$$;
select set_config('request.jwt.claim.sub','70707070-7070-4070-8070-707070707070',true);
select public.disable_my_push_subscription('https://fcm.googleapis.com/fcm/send/preferences_test_70707070');
reset role;
do $$begin
 if not exists(select 1 from public.push_subscriptions
  where user_id='70707070-7070-4070-8070-707070707070' and disabled_at is not null)
 then raise exception 'Subscription not disabled';end if;
 if not exists(select 1 from app_private.notification_deliveries d
  join public.push_subscriptions s on s.id=d.subscription_id
  where s.user_id='70707070-7070-4070-8070-707070707070')
 then raise exception 'Delivery history lost';end if;
end;$$;
rollback;
