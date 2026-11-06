-- Reconcile a signed failed asynchronous Checkout without guessing from timeouts.
-- The webhook authenticates the Stripe signature before invoking this service-only RPC.
begin;

create or replace function public.reconcile_signed_async_checkout_failure(
  p_event_id text, p_stripe_account text, p_session text, p_intent text,
  p_attempt uuid, p_amount bigint, p_currency text
) returns text
language plpgsql security definer set search_path = ''
as $reconcile_async_failure$
declare
  v_initial public.payment_attempts%rowtype;
  v_attempt public.payment_attempts%rowtype;
  v_order public.orders%rowtype;
  v_group public.group_drafts%rowtype;
  v_existing app_private.stripe_webhook_inbox%rowtype;
  v_inserted text;
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Service role richiesto';
  end if;
  if coalesce(p_event_id,'') !~ '^evt_[A-Za-z0-9]+$'
    or coalesce(p_stripe_account,'') !~ '^acct_[A-Za-z0-9]+$'
    or coalesce(p_session,'') !~ '^cs_(test|live)_[A-Za-z0-9]+$'
    or coalesce(p_intent,'') !~ '^pi_[A-Za-z0-9]+$'
    or p_attempt is null or p_amount is null or p_amount <= 0
    or p_currency is distinct from 'eur' then
    raise exception 'Evento Checkout asincrono non valido';
  end if;

  -- Match the locking order used by the current settlement flow: order/group
  -- first, payment attempt afterwards. Re-read and validate after locking.
  select * into v_initial from public.payment_attempts where id=p_attempt;
  if not found then raise exception 'Tentativo Stripe non trovato'; end if;
  if v_initial.order_id is not null then
    select * into v_order from public.orders where id=v_initial.order_id for update;
    if not found then raise exception 'Ordine non trovato'; end if;
  elsif v_initial.group_id is not null then
    select * into v_group from public.group_drafts where id=v_initial.group_id for update;
    if not found then raise exception 'Gruppo non trovato'; end if;
    perform id from public.group_orders where group_id=v_initial.group_id for update;
  else
    raise exception 'Tentativo Stripe privo di ordine';
  end if;
  select * into v_attempt from public.payment_attempts where id=p_attempt for update;
  if not found or v_attempt.order_id is distinct from v_initial.order_id
    or v_attempt.group_id is distinct from v_initial.group_id
    or v_attempt.stripe_account_id is distinct from p_stripe_account
    or v_attempt.stripe_checkout_session_id is distinct from p_session
    or v_attempt.amount_cents is distinct from p_amount
    or v_attempt.currency is distinct from p_currency
    or (v_attempt.stripe_payment_intent_id is not null
      and v_attempt.stripe_payment_intent_id is distinct from p_intent)
    or (v_attempt.order_id is not null and
      (v_order.school_id is distinct from v_attempt.school_id
       or v_order.customer_id is distinct from v_attempt.payer_id))
    or (v_attempt.group_id is not null and
      v_group.school_id is distinct from v_attempt.school_id) then
    raise exception 'Evento non corrispondente al ledger';
  end if;

  insert into app_private.stripe_webhook_inbox
    (event_id,stripe_account_id,event_type,payload,processed_at)
  values (p_event_id,p_stripe_account,'checkout.session.async_payment_failed',
    jsonb_build_object('session_id',p_session,'attempt_id',p_attempt,
      'payment_intent',p_intent,'amount_total',p_amount,'currency',p_currency),now())
  on conflict(event_id) do nothing returning event_id into v_inserted;
  if v_inserted is null then
    select * into v_existing from app_private.stripe_webhook_inbox where event_id=p_event_id;
    if v_existing.stripe_account_id is distinct from p_stripe_account
      or v_existing.event_type is distinct from 'checkout.session.async_payment_failed'
      or v_existing.payload->>'session_id' is distinct from p_session
      or v_existing.payload->>'attempt_id' is distinct from p_attempt::text
      or v_existing.payload->>'payment_intent' is distinct from p_intent
      or v_existing.payload->>'amount_total' is distinct from p_amount::text
      or v_existing.payload->>'currency' is distinct from p_currency then
      raise exception 'Identificativo evento Stripe già utilizzato';
    end if;
    return 'duplicate';
  end if;

  if v_attempt.status in ('succeeded','review') then return 'ignore_settled'; end if;
  if v_attempt.status in ('failed','cancelled') then return 'duplicate'; end if;
  if v_attempt.status not in ('initiated','requires_action','processing') then
    raise exception 'Stato pagamento non riconciliabile';
  end if;

  -- Only an authenticated provider failure releases the cash/group payment lock.
  -- The existing trigger releases pending supplements when status becomes failed.
  if v_attempt.group_id is not null then
    delete from public.group_line_payment_claims
      where payment_id=v_attempt.id and state='pending';
  end if;
  update public.payment_attempts set status='failed',
    stripe_payment_intent_id=p_intent,updated_at=now() where id=v_attempt.id;
  return 'failed';
end;
$reconcile_async_failure$;

revoke all on function public.reconcile_signed_async_checkout_failure(text,text,text,text,uuid,bigint,text)
  from public,anon,authenticated;
grant execute on function public.reconcile_signed_async_checkout_failure(text,text,text,text,uuid,bigint,text)
  to service_role;
commit;
