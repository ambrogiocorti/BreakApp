-- BreakApp 20: prevent Stripe + cash double charge on locally expired checkout.
begin;
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
     )
 then raise exception 'Un checkout per questo ordine è già in corso';end if;
 insert into public.payment_attempts(school_id,payer_id,order_id,request_key,
   stripe_account_id,amount_cents,status,expires_at)
 values(v_order.school_id,v_user,v_order.id,p_request_key,
   v_merchant.stripe_account_id,v_order.total_cents,'initiated',now()+interval '40 minutes')
 returning id into v_attempt;
 return jsonb_build_object('attempt_id',v_attempt,'amount_cents',v_order.total_cents,
 'currency','eur','stripe_account_id',v_merchant.stripe_account_id,'existing_session',null);
end;
$start_checkout$;

-- Service-role only after Stripe API has created its Checkout session.

create or replace function app_private.prevent_cash_stripe_overlap()
returns trigger language plpgsql security definer set search_path=''
as $cash_overlap$
begin
 if exists(select 1 from public.payment_attempts a
   where a.order_id=new.order_id
     and a.status in ('initiated','requires_action','processing'))
 then raise exception 'Checkout Stripe non riconciliato: non incassare contanti';end if;
 return new;
end;
$cash_overlap$;
-- Expiry events must be received from Stripe, not guessed from client clocks.
create or replace function public.reconcile_signed_checkout_expiry(
 p_event_id text,p_stripe_account text,p_session text,p_attempt uuid
) returns text language plpgsql security definer set search_path=''
as $expire_checkout$
declare v_attempt public.payment_attempts%rowtype;v_decision text;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role'
 then raise exception 'Service role richiesto';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$'
   or p_stripe_account !~ '^acct_[A-Za-z0-9]+$'
   or p_session !~ '^cs_(test|live)_[A-Za-z0-9]+$'
   or p_attempt is null
 then raise exception 'Evento Checkout scaduto non valido';end if;
 select * into v_attempt from public.payment_attempts where id=p_attempt for update;
 if not found or v_attempt.stripe_account_id<>p_stripe_account or
  v_attempt.stripe_checkout_session_id<>p_session
 then raise exception 'Evento scadenza non corrisponde al pagamento';end if;
 if v_attempt.status in ('succeeded','review') then
   return 'ignore_settled';end if;
 if v_attempt.status='cancelled' then return 'duplicate';end if;
 if v_attempt.status not in ('initiated','requires_action','processing')
 then raise exception 'Stato pagamento incompatibile con la scadenza';end if;
 update public.payment_attempts set status='cancelled',updated_at=now()
 where id=p_attempt;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event_id,p_stripe_account,'checkout.session.expired',
   jsonb_build_object('session',p_session,'attempt',p_attempt),now())
 on conflict(event_id) do nothing;
 return 'cancelled';
end;
$expire_checkout$;
revoke all on function public.reconcile_signed_checkout_expiry(text,text,text,uuid)
 from public,anon,authenticated;
grant execute on function public.reconcile_signed_checkout_expiry(text,text,text,uuid)
 to service_role;

commit;
