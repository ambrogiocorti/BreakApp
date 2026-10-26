-- BreakApp 18: push jobs per subscription, retries, service-only dispatcher RPC.
begin;
alter table app_private.notification_jobs add column subscription_id uuid
 references public.push_subscriptions(id) on delete cascade;
create table app_private.notification_deliveries(
 job_id uuid primary key references app_private.notification_jobs(id) on delete cascade,
 subscription_id uuid not null references public.push_subscriptions(id) on delete restrict,
 status text not null check(status in('sent','failed','dead')),
 status_code integer,
 recorded_at timestamptz not null default now()
);
alter table app_private.notification_deliveries enable row level security;
revoke all on app_private.notification_deliveries from public,anon,authenticated;

-- Prevent a client from redirecting the dispatcher to an arbitrary HTTPS
-- endpoint: SSRF guard for known browser push providers.
alter table public.push_subscriptions add constraint subscription_known_push_vendor
check(
 split_part(endpoint,'/',1)='https:' and
 (
  split_part(endpoint,'/',3) in (
    'fcm.googleapis.com','updates.push.services.mozilla.com',
    'push.services.mozilla.com','web.push.apple.com'
  ) or split_part(endpoint,'/',3) like '%.notify.windows.com'
 )
);
alter table public.push_subscriptions add constraint subscription_safe_keys
check(length(p256dh) between 30 and 200 and length(auth_key) between 10 and 100);

create or replace function app_private.queue_push_for_notice()
returns trigger language plpgsql security definer set search_path=''
as $queue_push$
begin
 insert into app_private.notification_jobs(user_id,notice_id,subscription_id,event_key)
 select new.user_id,new.id,s.id,new.id::text||':'||s.id::text
 from public.push_subscriptions s
 where s.user_id=new.user_id and s.disabled_at is null
 on conflict(event_key) do nothing;
 return new;
end;
$queue_push$;
revoke all on function app_private.queue_push_for_notice() from public,anon,authenticated;
drop trigger if exists customer_notification_push_jobs on public.customer_notifications;
create trigger customer_notification_push_jobs
after insert on public.customer_notifications
for each row execute function app_private.queue_push_for_notice();

-- Service JWT only, never a user JWT; locks + marking are atomic.
create or replace function public.claim_push_jobs(p_limit integer default 15)
returns jsonb language plpgsql security definer set search_path=''
as $claim_push$
declare results jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception 'Push dispatcher access denied';end if;
 if p_limit not between 1 and 50 then raise exception 'Invalid batch limit';end if;
 with selected as (
  select j.id from app_private.notification_jobs j
  join public.push_subscriptions s on s.id=j.subscription_id
  where j.status in ('pending','retry','sending') and j.next_attempt_at<=now()
    and j.attempts<6 and s.disabled_at is null
  order by j.next_attempt_at,j.created_at for update of j skip locked
  limit p_limit
 ), claimed as (
  update app_private.notification_jobs j set status='sending',
   attempts=j.attempts+1,next_attempt_at=now()+interval '5 minutes'
  from selected where j.id=selected.id
  returning j.id,j.subscription_id,j.notice_id,j.attempts
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'job_id',c.id,'subscription_id',s.id,'endpoint',s.endpoint,'p256dh',s.p256dh,
  'auth',s.auth_key,'message',n.message,'attempts',c.attempts)),'[]'::jsonb)
 into results
 from claimed c
 join public.push_subscriptions s on s.id=c.subscription_id
 join public.customer_notifications n on n.id=c.notice_id;
 return results;
end;
$claim_push$;

create or replace function public.finish_push_job(
 p_job_id uuid,p_success boolean,p_status_code integer,p_error text default null
) returns void language plpgsql security definer set search_path=''
as $finish_push$
declare v_job app_private.notification_jobs%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception 'Push dispatcher access denied';end if;
 select * into v_job from app_private.notification_jobs where id=p_job_id for update;
 if not found or v_job.status<>'sending' then raise exception 'Job not claimed';end if;
 if p_success then
  update app_private.notification_jobs set status='sent',last_error=null
  where id=p_job_id;
  update public.push_subscriptions set last_success_at=now() where id=v_job.subscription_id;
 elsif p_status_code in(404,410) then
  update app_private.notification_jobs set status='dead',last_error='Push subscription expired'
   where id=p_job_id;
  update public.push_subscriptions set disabled_at=now() where id=v_job.subscription_id;
 else
  update app_private.notification_jobs set
    status=case when v_job.attempts>=6 then 'dead' else 'retry' end,
    next_attempt_at=now()+(least(60,2^least(5,v_job.attempts))::integer||' minutes')::interval,
    last_error=left(coalesce(p_error,'Delivery failure'),300)
  where id=p_job_id;
 end if;
 insert into app_private.notification_deliveries(job_id,subscription_id,status,status_code)
 values(p_job_id,v_job.subscription_id,
   case when p_success then 'sent' when p_status_code in(404,410) or v_job.attempts>=6
     then 'dead' else 'failed' end,p_status_code)
 on conflict(job_id) do update set status=excluded.status,status_code=excluded.status_code,recorded_at=now();
end;
$finish_push$;

revoke all on function public.claim_push_jobs(integer),
 public.finish_push_job(uuid,boolean,integer,text) from public,anon,authenticated;
grant execute on function public.claim_push_jobs(integer),
 public.finish_push_job(uuid,boolean,integer,text) to service_role;
commit;
