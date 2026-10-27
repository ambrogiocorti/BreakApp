-- BreakApp 24: prevent a shared browser push endpoint from belonging to
-- two school users, and retire queued alerts when ownership changes.
-- Existing duplicate endpoints require manual review: never discard user data.
begin;

do $duplicates$
begin
 if exists(select 1 from public.push_subscriptions group by endpoint having count(*)>1)
 then raise exception 'Duplicate push endpoints found; review and revoke them before migration 24';end if;
end;
$duplicates$;

create unique index if not exists push_subscriptions_endpoint_unique
 on public.push_subscriptions(endpoint);

create or replace function public.register_my_push_subscription(
 p_endpoint text, p_p256dh text, p_auth_key text
) returns uuid language plpgsql security definer set search_path=''
as $register$
declare
 v_user uuid:=auth.uid();
 v_id uuid;
 v_owner uuid;
begin
 if v_user is null or coalesce(auth.jwt()->>'is_anonymous','false')='true'
 then raise exception 'Account registrato richiesto';end if;
 if p_endpoint is null or pg_catalog.length(p_endpoint) not between 30 and 2048
    or p_endpoint !~ '^https://' or
    p_p256dh is null or pg_catalog.length(p_p256dh) not between 30 and 200
    or p_auth_key is null or pg_catalog.length(p_auth_key) not between 10 and 100
 then raise exception 'Sottoscrizione browser non valida';end if;

 -- Serialize ownership transfers of the same push service endpoint.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_endpoint,24));
 select id,user_id into v_id,v_owner from public.push_subscriptions
  where endpoint=p_endpoint for update;

 if found then
   if v_owner<>v_user then
     -- Sending jobs may already have been handed to a provider. Fail closed
     -- until their lease is finished, to avoid cross-account notification.
     if exists(select 1 from app_private.notification_jobs
       where subscription_id=v_id and status='sending' and next_attempt_at>now())
     then raise exception 'Notifiche precedenti in invio: riprova tra qualche minuto';end if;
     update app_private.notification_jobs
       set status='dead',last_error='Push endpoint transferred to another account'
       where subscription_id=v_id and user_id<>v_user
         and status in('pending','retry','sending');
   end if;
   update public.push_subscriptions set user_id=v_user,
     p256dh=p_p256dh,auth_key=p_auth_key,
     disabled_at=null,last_success_at=null
    where id=v_id;
 else
   insert into public.push_subscriptions(user_id,endpoint,p256dh,auth_key)
    values(v_user,p_endpoint,p_p256dh,p_auth_key) returning id into v_id;
 end if;
 return v_id;
end;
$register$;
revoke all on function public.register_my_push_subscription(text,text,text)
 from public,anon,authenticated;
grant execute on function public.register_my_push_subscription(text,text,text) to authenticated;

-- Defence in depth: a queued notice is deliverable only if its user still
-- owns the browser endpoint and the original notice belongs to that user.
create or replace function public.claim_push_jobs(p_limit integer default 15)
returns jsonb language plpgsql security definer set search_path=''
as $claim_push$
declare results jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role'
 then raise exception 'Push dispatcher access denied';end if;
 if p_limit not between 1 and 50 then raise exception 'Invalid batch limit';end if;
 with selected as (
  select j.id from app_private.notification_jobs j
  join public.push_subscriptions s
    on s.id=j.subscription_id and s.user_id=j.user_id
  join public.customer_notifications n
    on n.id=j.notice_id and n.user_id=j.user_id
  where j.status in ('pending','retry','sending') and j.next_attempt_at<=now()
    and j.attempts<6 and s.disabled_at is null
  order by j.next_attempt_at,j.created_at for update of j skip locked
  limit p_limit
 ), claimed as (
  update app_private.notification_jobs j set status='sending',
   attempts=j.attempts+1,next_attempt_at=now()+interval '5 minutes'
  from selected where j.id=selected.id
  returning j.id,j.user_id,j.subscription_id,j.notice_id,j.attempts
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'job_id',c.id,'subscription_id',s.id,'endpoint',s.endpoint,
  'p256dh',s.p256dh,'auth',s.auth_key,'message',n.message,
  'attempts',c.attempts)),'[]'::jsonb)
 into results from claimed c
 join public.push_subscriptions s
   on s.id=c.subscription_id and s.user_id=c.user_id
 join public.customer_notifications n
   on n.id=c.notice_id and n.user_id=c.user_id;
 return results;
end;
$claim_push$;
revoke all on function public.claim_push_jobs(integer) from public,anon,authenticated;
grant execute on function public.claim_push_jobs(integer) to service_role;
commit;
