-- BreakApp 17: Stripe Checkout for CONFIRMED INDIVIDUAL ORDERS only.
-- Merchant must be independently configured and charges_enabled for school.
-- No group charge or refund is allowed by these entrypoints.
begin;
alter table public.payment_attempts add column stripe_checkout_session_id text unique;
alter table public.payment_attempts add column expires_at timestamptz;
alter table public.payment_attempts drop constraint payment_attempts_status_check;
alter table public.payment_attempts add constraint payment_attempts_status_check
 check(status in('initiated','requires_action','processing','succeeded','failed','cancelled','review'));

create or replace function public.begin_individual_stripe_checkout(
 p_order_id uuid,p_request_key uuid
) returns jsonb language plpgsql security definer set search_path=''
as $start_checkout$
declare v_order public.orders%rowtype;v_merchant public.school_stripe_merchants%rowtype;
 v_existing public.payment_attempts%rowtype;v_attempt uuid;v_user uuid:=auth.uid();
begin
 if v_user is null or p_order_id is null or p_request_key is null or
    coalesce(auth.jwt()->>'is_anonymous','false')='true'
 then raise exception 'Account registrato richiesto per Stripe';end if;
 if exists(select 1 from app_private.platform_admins where user_id=v_user)
 then raise exception 'Super Admin non può pagare come Cliente';end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.customer_id<>v_user
 then raise exception 'Ordine non disponibile';end if;
 if v_order.status in ('cancelled','delivered','no_show') or
    v_order.payment_status<>'due' or v_order.total_cents<=0
 then raise exception 'Ordine non pagabile online';end if;
 if exists(select 1 from public.counter_payments where order_id=v_order.id)
 then raise exception 'Ordine già incassato al banco';end if;
 select * into v_merchant from public.school_stripe_merchants
 where school_id=v_order.school_id and charges_enabled;
 if not found then raise exception 'Stripe non ancora abilitato per questa scuola';end if;
 select * into v_existing from public.payment_attempts
 where payer_id=v_user and request_key=p_request_key for update;
 if found then
   if v_existing.order_id<>p_order_id or
      v_existing.amount_cents<>v_order.total_cents or
      v_existing.stripe_account_id<>v_merchant.stripe_account_id
   then raise exception 'Chiave idempotenza già utilizzata per altra operazione';end if;
   return jsonb_build_object('attempt_id',v_existing.id,
      'amount_cents',v_existing.amount_cents,'currency','eur',
      'stripe_account_id',v_existing.stripe_account_id,
      'existing_session',v_existing.stripe_checkout_session_id);
 end if;
 if exists(select 1 from public.payment_attempts
   where order_id=v_order.id and status in ('initiated','requires_action','processing')
    and (expires_at is null or expires_at>now()))
 then raise exception 'Un checkout per questo ordine è già in corso';end if;
 insert into public.payment_attempts(school_id,payer_id,order_id,request_key,
   stripe_account_id,amount_cents,status,expires_at)
 values(v_order.school_id,v_user,v_order.id,p_request_key,
   v_merchant.stripe_account_id,v_order.total_cents,'initiated',now()+interval '10 minutes')
 returning id into v_attempt;
 return jsonb_build_object('attempt_id',v_attempt,'amount_cents',v_order.total_cents,
 'currency','eur','stripe_account_id',v_merchant.stripe_account_id,'existing_session',null);
end;
$start_checkout$;

-- Service-role only after Stripe API has created its Checkout session.
create or replace function public.attach_stripe_checkout_session(
 p_attempt uuid,p_session text
) returns void language plpgsql security definer set search_path=''
as $attach_checkout$
begin
 if current_user<>'service_role' then raise exception 'Service role richiesto';end if;
 if p_session !~ '^cs_(test|live)_[A-Za-z0-9]+$'
 then raise exception 'Sessione Stripe non valida';end if;
 update public.payment_attempts
 set stripe_checkout_session_id=p_session,status='requires_action',updated_at=now()
 where id=p_attempt and (stripe_checkout_session_id is null or
 stripe_checkout_session_id=p_session) and status in ('initiated','requires_action');
 if not found then raise exception 'Tentativo di pagamento non disponibile';end if;
end;
$attach_checkout$;

-- Webhook must be signature-verified BEFORE calling this function. This RPC
-- additionally validates amount, currency, account, attempt, session, payer,
-- order, and cash-payment conflict under locks.
create or replace function public.finalize_verified_checkout(
 p_event_id text,p_event_account text,p_session text,p_intent text,
 p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb
) returns text language plpgsql security definer set search_path=''
as $finalize_checkout$
declare v_attempt public.payment_attempts%rowtype;v_order public.orders%rowtype;
 v_processed boolean;v_decision text;
begin
 if current_user<>'service_role' then raise exception 'Service role richiesto';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$' or p_session !~ '^cs_(test|live)_[A-Za-z0-9]+$'
   or p_event_account !~ '^acct_[A-Za-z0-9]+$' or p_intent !~ '^pi_[A-Za-z0-9]+$'
   or p_amount<=0 or p_currency<>'eur' or p_attempt is null or not p_paid
 then raise exception 'Webhook non valido per registrazione incasso';end if;
 select processed_at is not null into v_processed from app_private.stripe_webhook_inbox
 where event_id=p_event_id;
 if found and v_processed then return 'duplicate';end if;
 select * into v_attempt from public.payment_attempts where id=p_attempt for update;
 if not found or v_attempt.stripe_account_id<>p_event_account
   or v_attempt.stripe_checkout_session_id<>p_session
   or v_attempt.amount_cents<>p_amount or v_attempt.currency<>p_currency
   or v_attempt.order_id is null
 then raise exception 'Webhook incoerente con il ledger locale';end if;
 select * into v_order from public.orders where id=v_attempt.order_id for update;
 if not found or v_order.school_id<>v_attempt.school_id or
 v_order.customer_id<>v_attempt.payer_id then
   raise exception 'Ordine o pagatore non corrispondenti';end if;
 if not exists(select 1 from public.school_stripe_merchants
    where school_id=v_order.school_id and stripe_account_id=p_event_account)
 then raise exception 'Stripe merchant della scuola non verificato';end if;
 insert into app_private.stripe_webhook_inbox(
  event_id,stripe_account_id,event_type,payload)
 values(p_event_id,p_event_account,'checkout.session.completed',p_payload)
 on conflict(event_id) do nothing;
 if v_attempt.status='succeeded' then
   v_decision:='duplicate_payment';
 elsif v_order.payment_status='paid' or
   v_order.status in ('cancelled','delivered','no_show') or
   exists(select 1 from public.counter_payments where order_id=v_order.id) then
   v_decision:='review';
 else
   v_decision:='succeeded';
 end if;
 update public.payment_attempts set
 stripe_payment_intent_id=p_intent,status=case when v_decision='succeeded'
   then 'succeeded' else 'review' end,updated_at=now()
 where id=v_attempt.id;
 if v_decision='succeeded' then
  update public.orders set payment_status='paid',updated_at=now() where id=v_order.id;
  insert into public.order_audit(order_id,school_id,actor_id,action)
  values(v_order.id,v_order.school_id,v_attempt.payer_id,'stripe_checkout_verified');
 end if;
 update app_private.stripe_webhook_inbox set processed_at=now()
 where event_id=p_event_id;
 return v_decision;
end;
$finalize_checkout$;

-- Cashier must not record cash while a fresh Checkout attempt may be
-- completing asynchronously. These records need explicit expiry/reconciliation.
create or replace function app_private.prevent_cash_stripe_overlap()
returns trigger language plpgsql security definer set search_path=''
as $cash_overlap$
begin
 if exists(select 1 from public.payment_attempts a
   where a.order_id=new.order_id and a.status in ('initiated','requires_action','processing')
     and (a.expires_at is null or a.expires_at>now()))
 then raise exception 'Checkout online in corso: attendere conferma o riconciliazione';end if;
 return new;
end;
$cash_overlap$;
drop trigger if exists counter_cash_stripe_overlap on public.counter_payments;
create trigger counter_cash_stripe_overlap before insert on public.counter_payments
for each row execute function app_private.prevent_cash_stripe_overlap();

revoke all on function public.begin_individual_stripe_checkout(uuid,uuid),
 public.attach_stripe_checkout_session(uuid,text),
 public.finalize_verified_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb)
 from public,anon,authenticated;
grant execute on function public.begin_individual_stripe_checkout(uuid,uuid) to authenticated;
grant execute on function public.attach_stripe_checkout_session(uuid,text),
 public.finalize_verified_checkout(text,text,text,text,uuid,bigint,text,boolean,jsonb)
 to service_role;
commit;
