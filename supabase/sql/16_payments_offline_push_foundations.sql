-- BreakApp 16: secure foundations. No checkout or offline cash execution yet.
begin;
create table public.school_stripe_merchants(
 school_id uuid primary key references public.schools(id) on delete restrict,
 stripe_account_id text not null unique check(stripe_account_id ~ '^acct_[A-Za-z0-9]+$'),
 charges_enabled boolean not null default false,
 payouts_enabled boolean not null default false,
 verified_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.payment_attempts(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete restrict,
 payer_id uuid not null references auth.users(id) on delete restrict,
 order_id uuid references public.orders(id) on delete restrict,
 group_id uuid references public.group_drafts(id) on delete restrict,
 stripe_account_id text not null,
 stripe_payment_intent_id text unique,
 request_key uuid not null,
 amount_cents bigint not null check(amount_cents>0),
 currency text not null default 'eur' check(currency='eur'),
 status text not null default 'initiated' check(status in
 ('initiated','requires_action','processing','succeeded','failed','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(payer_id,request_key),
 check(num_nonnulls(order_id,group_id)=1)
);
create table public.payment_item_allocations(
 id uuid primary key default gen_random_uuid(),
 payment_id uuid not null references public.payment_attempts(id) on delete restrict,
 order_item_id uuid references public.order_items(id) on delete restrict,
 group_cart_item_id uuid references public.group_cart_items(id) on delete restrict,
 beneficiary_id uuid not null references auth.users(id) on delete restrict,
 amount_cents bigint not null check(amount_cents>0),
 check(num_nonnulls(order_item_id,group_cart_item_id)=1),
 unique(payment_id,order_item_id),unique(payment_id,group_cart_item_id)
);
create table public.payment_refunds(
 id uuid primary key default gen_random_uuid(),
 payment_id uuid not null references public.payment_attempts(id) on delete restrict,
 stripe_refund_id text unique,
 request_key uuid not null,
 amount_cents bigint not null check(amount_cents>0),
 status text not null default 'pending' check(status in('pending','processing','succeeded','failed','review')),
 reason text not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(payment_id,request_key)
);
create table app_private.stripe_webhook_inbox(
 event_id text primary key,
 stripe_account_id text not null,
 event_type text not null,
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 payload jsonb not null,
 error_text text
);
create table public.staff_offline_leases(
 barista_id uuid primary key references auth.users(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 device_id uuid not null,
 generation bigint not null default 1,
 issued_at timestamptz not null default now(),
 expires_at timestamptz not null,
 revoked_at timestamptz,
 updated_at timestamptz not null default now(),
 check(expires_at>issued_at)
);
create table public.offline_events_inbox(
 id uuid primary key default gen_random_uuid(),
 barista_id uuid not null references auth.users(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 device_id uuid not null,
 lease_generation bigint not null,
 request_key uuid not null,
 event_kind text not null check(event_kind in('counter_sale','cash_pickup','shift_change')),
 local_recorded_at timestamptz,
 received_at timestamptz not null default now(),
 payload jsonb not null,
 status text not null default 'quarantined' check(status in('quarantined','approved','rejected','applied')),
 review_reason text,
 reviewed_by uuid references auth.users(id) on delete restrict,
 reviewed_at timestamptz,
 unique(barista_id,request_key)
);
create table public.push_subscriptions(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null,
 p256dh text not null,
 auth_key text not null,
 created_at timestamptz not null default now(),
 last_success_at timestamptz,
 disabled_at timestamptz,
 unique(user_id,endpoint),
 check(length(endpoint) between 30 and 2048),
 check(endpoint ~ '^https://')
);
create table app_private.notification_jobs(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 notice_id uuid references public.customer_notifications(id) on delete restrict,
 event_key text not null unique,
 status text not null default 'pending' check(status in('pending','sending','sent','retry','dead')),
 attempts integer not null default 0 check(attempts>=0),
 next_attempt_at timestamptz not null default now(),
 last_error text,
 created_at timestamptz not null default now()
);
create index on app_private.notification_jobs(status,next_attempt_at);
do $rls$
declare t text;
begin
 foreach t in array array['school_stripe_merchants','payment_attempts','payment_item_allocations',
  'payment_refunds','staff_offline_leases','offline_events_inbox','push_subscriptions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
 alter table app_private.stripe_webhook_inbox enable row level security;
 alter table app_private.notification_jobs enable row level security;
end;$rls$;
revoke all on app_private.stripe_webhook_inbox,app_private.notification_jobs from public,anon,authenticated;

-- A transfer increments generation while server retains one row per barista.
-- Revoked/expired/stale-generation event is ALWAYS quarantined and never
-- booked as cash by this RPC. Even valid lease events remain staged until
-- replay protection and inventory/payments reconciliation are implemented.
create or replace function public.transfer_my_offline_device(p_school uuid,p_device uuid)
returns jsonb language plpgsql security definer set search_path=''
as $lease$
declare v_user uuid:=auth.uid();v_previous public.staff_offline_leases%rowtype;
 v_generation bigint;
begin
 if v_user is null or p_school is null or p_device is null or
  coalesce(auth.jwt()->>'is_anonymous','false')='true'
 then raise exception 'Autenticazione online richiesta';end if;
 if not exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.user_id=v_user and m.school_id=p_school
    and m.membership_status='active' and r.role_code='bartender')
 then raise exception 'Ruolo Barista non verificato per questa scuola';end if;
 if exists(select 1 from app_private.platform_admins where user_id=v_user)
 then raise exception 'Super Admin non può essere Barista offline';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,1));
 select * into v_previous from public.staff_offline_leases where barista_id=v_user for update;
 v_generation:=case when found then v_previous.generation+1 else 1 end;
 insert into public.staff_offline_leases(barista_id,school_id,device_id,generation,issued_at,expires_at,revoked_at)
 values(v_user,p_school,p_device,v_generation,now(),now()+interval '8 hours',null)
 on conflict(barista_id) do update
 set school_id=excluded.school_id,device_id=excluded.device_id,generation=excluded.generation,
 issued_at=excluded.issued_at,expires_at=excluded.expires_at,revoked_at=null,updated_at=now();
 return jsonb_build_object('device_id',p_device,'generation',v_generation,
  'expires_at',(select expires_at from public.staff_offline_leases where barista_id=v_user),
  'server_time',now());
end;
$lease$;

create or replace function public.stage_my_offline_event(
 p_device uuid,p_generation bigint,p_request_key uuid,p_kind text,
 p_local_recorded_at timestamptz,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $stage$
declare v_user uuid:=auth.uid();v_lease public.staff_offline_leases%rowtype;
 v_id uuid;v_reason text;
begin
 if v_user is null or p_device is null or p_request_key is null or
  p_generation is null or p_kind not in('counter_sale','cash_pickup','shift_change')
  or p_payload is null or jsonb_typeof(p_payload)<>'object'
  or pg_catalog.octet_length(p_payload::text)>65536
 then raise exception 'Evento offline non valido';end if;
 select * into v_lease from public.staff_offline_leases
 where barista_id=v_user for update;
 if not found then raise exception 'Nessuna autorizzazione offline precedente';end if;
 if not exists(select 1 from public.school_memberships m join public.role_assignments r
   on r.membership_id=m.id where m.user_id=v_user and m.school_id=v_lease.school_id
    and m.membership_status='active' and r.role_code='bartender')
 then raise exception 'Ruolo Barista revocato';end if;
 select id into v_id from public.offline_events_inbox
 where barista_id=v_user and request_key=p_request_key;
 if found then return jsonb_build_object('id',v_id,'status','quarantined');end if;
 v_reason:=case
   when v_lease.device_id<>p_device or v_lease.generation<>p_generation
     then 'Dispositivo o generazione revocati: verifica Admin necessaria'
   when v_lease.expires_at<now() then 'Lease scaduto: verifica Admin necessaria'
   when p_local_recorded_at is null or p_local_recorded_at>now()+interval '2 minutes'
     then 'Timestamp assente o inattendibile'
   else 'In attesa di riconciliazione server prima della contabilizzazione'
 end;
 insert into public.offline_events_inbox(barista_id,school_id,device_id,
  lease_generation,request_key,event_kind,local_recorded_at,payload,review_reason)
 values(v_user,v_lease.school_id,p_device,p_generation,p_request_key,p_kind,
  p_local_recorded_at,p_payload,v_reason) returning id into v_id;
 return jsonb_build_object('id',v_id,'status','quarantined','reason',v_reason);
end;
$stage$;
revoke all on function public.transfer_my_offline_device(uuid,uuid),
 public.stage_my_offline_event(uuid,bigint,uuid,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.transfer_my_offline_device(uuid,uuid),
 public.stage_my_offline_event(uuid,bigint,uuid,text,timestamptz,jsonb) to authenticated;

-- Only user's own subscription can be inserted/revoked. Exact endpoint, key
-- and authenticated ownership are validated server-side by RLS.
grant select,insert,delete on public.push_subscriptions to authenticated;
create policy push_own_select on public.push_subscriptions for select to authenticated
 using(user_id=(select auth.uid()));
create policy push_own_insert on public.push_subscriptions for insert to authenticated
 with check(user_id=(select auth.uid()) and
  coalesce(auth.jwt()->>'is_anonymous','false')<>'true');
create policy push_own_delete on public.push_subscriptions for delete to authenticated
 using(user_id=(select auth.uid()));
commit;
