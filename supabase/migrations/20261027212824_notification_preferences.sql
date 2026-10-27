begin;
-- Preferences affect optional browser delivery, never the persistent in-app ledger.
create table public.notification_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 browser_alerts boolean not null default true,
 push_orders boolean not null default true,
 push_groups boolean not null default true,
 push_support boolean not null default true,
 push_announcements boolean not null default true,
 updated_at timestamptz not null default now()
);
alter table public.notification_preferences enable row level security;
revoke all on public.notification_preferences from public,anon,authenticated;
grant select on public.notification_preferences to authenticated;
create policy own_notification_preferences on public.notification_preferences
for select to authenticated using(user_id=(select auth.uid()));

create function app_private.push_notice_allowed(p_user uuid,p_type text)
returns boolean language sql stable set search_path='' as $$
 select coalesce((select case
  when p_type like 'group\_%' escape '\' then p.push_groups
  when p_type like 'support\_%' escape '\' then p.push_support
  when p_type='school_announcement' then p.push_announcements
  else p.push_orders end
 from public.notification_preferences p where p.user_id=p_user),true);
$$;
revoke all on function app_private.push_notice_allowed(uuid,text) from public,anon,authenticated;

create function public.get_my_notification_preferences()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 select to_jsonb(p)-'user_id'-'updated_at' into v_result
 from public.notification_preferences p where p.user_id=auth.uid();
 return coalesce(v_result,jsonb_build_object('browser_alerts',true,'push_orders',true,
  'push_groups',true,'push_support',true,'push_announcements',true));
end;$$;

create function public.set_my_notification_preferences(
 p_browser_alerts boolean,p_push_orders boolean,p_push_groups boolean,
 p_push_support boolean,p_push_announcements boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 if p_browser_alerts is null or p_push_orders is null or p_push_groups is null
  or p_push_support is null or p_push_announcements is null
 then raise exception 'Preferenze incomplete';end if;
 insert into public.notification_preferences(user_id,browser_alerts,push_orders,
  push_groups,push_support,push_announcements)
 values(auth.uid(),p_browser_alerts,p_push_orders,p_push_groups,p_push_support,p_push_announcements)
 on conflict(user_id) do update set browser_alerts=excluded.browser_alerts,
  push_orders=excluded.push_orders,push_groups=excluded.push_groups,
  push_support=excluded.push_support,push_announcements=excluded.push_announcements,updated_at=now();
 update app_private.notification_jobs j set status='dead',last_error='Disabled by notification preference'
 from public.customer_notifications n
 where j.notice_id=n.id and j.user_id=auth.uid() and n.user_id=auth.uid()
  and j.status in ('pending','retry')
  and not app_private.push_notice_allowed(auth.uid(),n.event_type);
 return public.get_my_notification_preferences();
end;$$;
revoke all on function public.get_my_notification_preferences(),
 public.set_my_notification_preferences(boolean,boolean,boolean,boolean,boolean)
 from public,anon,authenticated;
grant execute on function public.get_my_notification_preferences(),
 public.set_my_notification_preferences(boolean,boolean,boolean,boolean,boolean) to authenticated;

-- Preserve delivery history: DELETE would fail once a subscription has an audit row.
create function public.disable_my_push_subscription(p_endpoint text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 if p_endpoint is null or length(p_endpoint) not between 30 and 2048
 then raise exception 'Sottoscrizione non valida';end if;
 update public.push_subscriptions set disabled_at=coalesce(disabled_at,now())
 where endpoint=p_endpoint and user_id=auth.uid() returning id into v_id;
 if v_id is null then return false;end if;
 update app_private.notification_jobs set status='dead',last_error='Push subscription disabled'
 where subscription_id=v_id and user_id=auth.uid() and status in ('pending','retry');
 return true;
end;$$;
revoke all on function public.disable_my_push_subscription(text) from public,anon,authenticated;
grant execute on function public.disable_my_push_subscription(text) to authenticated;

create or replace function app_private.queue_push_for_notice()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if app_private.push_notice_allowed(new.user_id,new.event_type) then
  insert into app_private.notification_jobs(user_id,notice_id,subscription_id,event_key)
  select new.user_id,new.id,s.id,new.id::text||':'||s.id::text
  from public.push_subscriptions s where s.user_id=new.user_id and s.disabled_at is null
  on conflict(event_key) do nothing;
 end if;
 return new;
end;$$;
revoke all on function app_private.queue_push_for_notice() from public,anon,authenticated;

create or replace function public.claim_push_jobs(p_limit integer default 15)
returns jsonb language plpgsql security definer set search_path='' as $$
declare results jsonb;
begin
 if auth.jwt()->>'role' is distinct from 'service_role'
 then raise exception 'Push dispatcher access denied';end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid batch limit';end if;
 -- A process dying on its final delivery attempt must not leave a job stuck forever.
 update app_private.notification_jobs set status='dead',last_error='Delivery attempts exhausted'
 where status in ('sending','retry','pending') and attempts>=6 and next_attempt_at<=now();
 with selected as (
  select j.id from app_private.notification_jobs j
  join public.push_subscriptions s on s.id=j.subscription_id and s.user_id=j.user_id
  join public.customer_notifications n on n.id=j.notice_id and n.user_id=j.user_id
  where j.status in ('pending','retry','sending') and j.next_attempt_at<=now()
   and j.attempts<6 and s.disabled_at is null
   and app_private.push_notice_allowed(j.user_id,n.event_type)
  order by j.next_attempt_at,j.created_at for update of j skip locked limit p_limit
 ),claimed as (
  update app_private.notification_jobs j set status='sending',attempts=j.attempts+1,
   next_attempt_at=now()+interval '5 minutes'
  from selected where j.id=selected.id
  returning j.id,j.user_id,j.subscription_id,j.notice_id,j.attempts
 )
 select coalesce(jsonb_agg(jsonb_build_object('job_id',c.id,'subscription_id',s.id,
  'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth_key,'message',n.message,
  'attempts',c.attempts)),'[]'::jsonb) into results from claimed c
 join public.push_subscriptions s on s.id=c.subscription_id and s.user_id=c.user_id
 join public.customer_notifications n on n.id=c.notice_id and n.user_id=c.user_id;
 return results;
end;$$;
revoke all on function public.claim_push_jobs(integer) from public,anon,authenticated;
grant execute on function public.claim_push_jobs(integer) to service_role;
commit;
