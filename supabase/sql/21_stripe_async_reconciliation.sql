-- BreakApp 21: signed Stripe asynchronous Checkout outcomes.
-- Requires all prior scripts through 20. Apply once in test before production.
begin;

create or replace function public.reconcile_signed_checkout_failure(
 p_event_id text,p_stripe_account text,p_session text,p_intent text,
 p_attempt uuid,p_amount bigint,p_currency text
) returns text language plpgsql security definer set search_path=''
as $fail_checkout$
declare v_attempt public.payment_attempts%rowtype;v_order public.orders%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role'
 then raise exception 'Service role richiesto';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$'
  or p_stripe_account !~ '^acct_[A-Za-z0-9]+$'
  or p_session !~ '^cs_test_[A-Za-z0-9]+$'
  or p_intent !~ '^pi_[A-Za-z0-9]+$'
  or p_attempt is null or p_amount is null or p_amount<=0 or p_currency<>'eur'
 then raise exception 'Evento asincrono fallito non valido';end if;

 select * into v_attempt from public.payment_attempts where id=p_attempt for update;
 if not found or v_attempt.stripe_account_id<>p_stripe_account
  or v_attempt.stripe_checkout_session_id<>p_session
  or v_attempt.amount_cents<>p_amount or v_attempt.currency<>p_currency
  or (v_attempt.stripe_payment_intent_id is not null and
      v_attempt.stripe_payment_intent_id<>p_intent)
 then raise exception 'Evento non corrispondente al tentativo';end if;
 select * into v_order from public.orders where id=v_attempt.order_id for update;
 if not found or v_order.school_id<>v_attempt.school_id
  or v_order.customer_id<>v_attempt.payer_id
  or not exists(select 1 from public.school_stripe_merchants
    where school_id=v_order.school_id and stripe_account_id=p_stripe_account)
 then raise exception 'Scuola, pagatore o merchant non corrispondenti';end if;

 if v_attempt.status in ('succeeded','review') then return 'ignore_settled';end if;
 if v_attempt.status in ('failed','cancelled') then return 'duplicate';end if;
 if v_attempt.status not in ('initiated','requires_action','processing')
 then raise exception 'Stato Checkout incompatibile';end if;

 -- An actual signed failed event releases the cash desk lock. A local timeout
 -- is deliberately insufficient to do so (script 20).
 insert into app_private.stripe_webhook_inbox(
  event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event_id,p_stripe_account,'checkout.session.async_payment_failed',
  jsonb_build_object('session_id',p_session,'attempt_id',p_attempt,
   'payment_intent',p_intent,'amount_total',p_amount),now())
 on conflict(event_id) do nothing;
 update public.payment_attempts set status='failed',
  stripe_payment_intent_id=p_intent,updated_at=now()
 where id=v_attempt.id;
 insert into public.order_audit(order_id,school_id,actor_id,action)
 values(v_order.id,v_order.school_id,v_attempt.payer_id,
  'stripe_async_payment_failed');
 return 'failed';
end;
$fail_checkout$;

-- Keep the original API signature, including existing test callers, but store
-- the true signed event type rather than labelling async success as completed.
create or replace function public.finalize_verified_checkout(
 p_event_id text,p_event_account text,p_session text,p_intent text,
 p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb
) returns text language plpgsql security definer set search_path=''
as $finalize_checkout$
declare v_attempt public.payment_attempts%rowtype;v_order public.orders%rowtype;
 v_processed boolean;v_decision text;
 v_event_type text:=coalesce(p_payload->>'event_type','checkout.session.completed');
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role'
 then raise exception 'Service role richiesto';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$' or p_session !~ '^cs_test_[A-Za-z0-9]+$'
   or p_event_account !~ '^acct_[A-Za-z0-9]+$' or p_intent !~ '^pi_[A-Za-z0-9]+$'
   or p_amount is null or p_amount<=0 or p_currency<>'eur' or p_attempt is null
   or not p_paid or v_event_type not in(
    'checkout.session.completed','checkout.session.async_payment_succeeded')
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
 v_order.customer_id<>v_attempt.payer_id
 then raise exception 'Ordine o pagatore non corrispondenti';end if;
 if not exists(select 1 from public.school_stripe_merchants
    where school_id=v_order.school_id and stripe_account_id=p_event_account)
 then raise exception 'Stripe merchant della scuola non verificato';end if;
 insert into app_private.stripe_webhook_inbox(
  event_id,stripe_account_id,event_type,payload)
 values(p_event_id,p_event_account,v_event_type,p_payload)
 on conflict(event_id) do nothing;
 if v_attempt.status='succeeded' then
   v_decision:='duplicate_payment';
 elsif v_order.payment_status='paid' or
   v_order.status in ('cancelled','delivered','no_show') or
   exists(select 1 from public.counter_payments where order_id=v_order.id) then
   v_decision:='review';
 else v_decision:='succeeded';end if;
 if v_decision<>'duplicate_payment' then
  update public.payment_attempts set
   stripe_payment_intent_id=p_intent,status=case when v_decision='succeeded'
     then 'succeeded' else 'review' end,updated_at=now()
  where id=v_attempt.id;
 end if;
 if v_decision='succeeded' then
  update public.orders set payment_status='paid',
    payment_method='stripe',updated_at=now() where id=v_order.id;
  insert into public.order_audit(order_id,school_id,actor_id,action)
  values(v_order.id,v_order.school_id,v_attempt.payer_id,'stripe_checkout_verified');
 end if;
 update app_private.stripe_webhook_inbox set processed_at=now()
 where event_id=p_event_id;
 return v_decision;
end;
$finalize_checkout$;

revoke all on function public.reconcile_signed_checkout_failure(
 text,text,text,text,uuid,bigint,text)
 from public,anon,authenticated;
grant execute on function public.reconcile_signed_checkout_failure(
 text,text,text,text,uuid,bigint,text)
 to service_role;

-- Keep the trusted webhook-settlement RPC exclusive to the service role.
revoke all on function public.finalize_verified_checkout(
 text,text,text,text,uuid,bigint,text,boolean,jsonb)
 from public,anon,authenticated;
grant execute on function public.finalize_verified_checkout(
 text,text,text,text,uuid,bigint,text,boolean,jsonb)
 to service_role;
commit;
