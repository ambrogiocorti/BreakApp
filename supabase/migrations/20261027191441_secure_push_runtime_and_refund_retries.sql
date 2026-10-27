-- Runtime secrets remain in Supabase Vault; only the backend service may retrieve them.
begin;
create or replace function public.push_runtime_configuration()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_config jsonb;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo servizio backend';end if;
 execute 'select coalesce(jsonb_object_agg(name,decrypted_secret),''{}''::jsonb)
  from vault.decrypted_secrets where name in (''breakapp_vapid_public'',''breakapp_vapid_private'',
   ''breakapp_vapid_subject'',''breakapp_dispatch_token'')' into v_config;
 return v_config;
end;$$;
revoke all on function public.push_runtime_configuration() from public,anon,authenticated;
grant execute on function public.push_runtime_configuration() to service_role;

alter table public.payment_refunds add column dispatch_attempts integer not null default 0,
 add column next_dispatch_at timestamptz not null default now(),
 add column dispatch_lease_until timestamptz,
 add column dispatch_error_code text;
create index refunds_dispatch_due on public.payment_refunds(next_dispatch_at,created_at)
 where status in ('pending','processing') and stripe_refund_id is null;
create or replace function public.claim_refund_dispatch(p_limit integer default 10)
returns table(refund_id uuid,account text,payment_intent text,amount_cents bigint)
language plpgsql security definer set search_path='' as $$
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo servizio backend';end if;
 if p_limit is null or p_limit not between 1 and 30 then raise exception 'Limite non valido';end if;
 -- After the provider idempotency retention window a person must verify Stripe
 -- before another attempt; never silently drop an old pending refund.
 update public.payment_refunds set status='review',dispatch_error_code='idempotency_window',updated_at=now()
 where status in ('pending','processing') and stripe_refund_id is null and
  (created_at<now()-interval '23 hours' or (dispatch_attempts>=8 and dispatch_lease_until<=now()));
 return query with candidates as (
  select r.id from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id
  where r.status in ('pending','processing') and r.stripe_refund_id is null
   and r.next_dispatch_at<=now() and (r.dispatch_lease_until is null or r.dispatch_lease_until<=now())
   and r.dispatch_attempts<8 and a.status='succeeded' and a.stripe_payment_intent_id is not null
  order by r.created_at,r.id for update of r skip locked limit p_limit
 ),claimed as (
  update public.payment_refunds r set dispatch_lease_until=now()+interval '2 minutes',
   dispatch_attempts=dispatch_attempts+1 from candidates c where r.id=c.id returning r.*
 ) select r.id,a.stripe_account_id,a.stripe_payment_intent_id,r.amount_cents
 from claimed r join public.payment_attempts a on a.id=r.payment_id;
end;$$;
revoke all on function public.claim_refund_dispatch(integer) from public,anon,authenticated;
grant execute on function public.claim_refund_dispatch(integer) to service_role;
create or replace function public.finish_refund_dispatch(p_refund uuid,p_result text,p_code text default '')
returns void language plpgsql security definer set search_path='' as $$
declare r public.payment_refunds%rowtype;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo servizio backend';end if;
 if p_result is null or p_result not in ('sent','retry','review') or length(coalesce(p_code,''))>80
 then raise exception 'Esito dispatcher non valido';end if;
 select * into r from public.payment_refunds where id=p_refund for update;
 if not found then raise exception 'Rimborso non trovato';end if;
 if r.status in ('succeeded','failed','review') then return;end if;
 update public.payment_refunds set dispatch_lease_until=null,
  status=case when p_result='review' or (p_result='retry' and r.dispatch_attempts>=8) then 'review' else status end,
  next_dispatch_at=now()+make_interval(secs=>least(3600,30*power(2,least(r.dispatch_attempts,7)))::int),
  dispatch_error_code=nullif(p_code,''),updated_at=now() where id=p_refund;
end;$$;
revoke all on function public.finish_refund_dispatch(uuid,text,text) from public,anon,authenticated;
grant execute on function public.finish_refund_dispatch(uuid,text,text) to service_role;
do $$declare v_check text;begin
 select pg_get_expr(conbin,conrelid) into v_check from pg_constraint where
  conrelid='public.customer_notifications'::regclass and conname='customer_notifications_event_type_check';
 alter table public.customer_notifications drop constraint customer_notifications_event_type_check;
 execute format('alter table public.customer_notifications add constraint customer_notifications_event_type_check check (%s or event_type=''refund_issue'')',v_check);
end;$$;
create or replace function app_private.notify_refund_review()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_payer uuid;
begin
 if new.status in ('review','failed') and old.status is distinct from new.status then
  select school_id,payer_id into v_school,v_payer from public.payment_attempts where id=new.payment_id;
  insert into public.customer_notifications(school_id,user_id,event_type,message)
  select v_school,x.user_id,'refund_issue','Un rimborso richiede verifica del personale. Riferimento '||left(new.id::text,8)||'.'
  from (select v_payer user_id union select m.user_id from public.school_memberships m
   join public.role_assignments a on a.membership_id=m.id where m.school_id=v_school
    and m.membership_status='active' and a.role_code='school_admin') x;
 end if;return new;
end;$$;
revoke all on function app_private.notify_refund_review() from public,anon,authenticated;
create trigger refund_review_notice after update of status on public.payment_refunds
for each row execute function app_private.notify_refund_review();
commit;
