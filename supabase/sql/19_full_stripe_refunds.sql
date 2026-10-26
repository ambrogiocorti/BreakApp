-- BreakApp 19: FULL refund for a delivered individual Stripe order.
-- Actual payer is the payment_attempts.payer_id, never a client-supplied ID.
begin;
alter table public.orders drop constraint orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
 check(payment_status in ('due','paid','refunded'));

create or replace function public.request_full_individual_stripe_refund(
 p_order_id uuid,p_request_key uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=''
as $refund_request$
declare v_user uuid:=auth.uid();v_order public.orders%rowtype;
 v_attempt public.payment_attempts%rowtype;v_refund public.payment_refunds%rowtype;
 v_new uuid;
begin
 if v_user is null or p_order_id is null or p_request_key is null or
  length(btrim(coalesce(p_reason,''))) not between 8 and 300
 then raise exception 'Richiesta rimborso non valida';end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'Ordine inesistente';end if;
 if not (
  (auth.jwt()->>'aal'='aal2' and exists(select 1 from app_private.platform_admins
     where user_id=v_user))
  or (auth.jwt()->>'aal'='aal2' and exists(
   select 1 from public.school_memberships m
   join public.role_assignments r on r.membership_id=m.id
   where m.school_id=v_order.school_id and m.user_id=v_user
    and m.membership_status='active' and r.role_code='school_admin'))
 ) then raise exception 'Admin verificato e 2FA richiesti';end if;
 if v_order.status not in ('delivered','no_show') or v_order.payment_status<>'paid' or
 v_order.payment_method<>'stripe'
 then raise exception 'Solo ordini consegnati pagati online ammettono rimborso completo';end if;
 select * into v_attempt from public.payment_attempts
 where order_id=v_order.id and status='succeeded' for update;
 if not found or v_attempt.stripe_payment_intent_id is null
 then raise exception 'Pagamento Stripe originale non disponibile';end if;
 select * into v_refund from public.payment_refunds
 where payment_id=v_attempt.id and request_key=p_request_key for update;
 if found then return jsonb_build_object('refund_id',v_refund.id,
   'account',v_attempt.stripe_account_id,
   'payment_intent',v_attempt.stripe_payment_intent_id,
   'amount_cents',v_refund.amount_cents,'status',v_refund.status);end if;
 if exists(select 1 from public.payment_refunds
  where payment_id=v_attempt.id and status in('pending','processing','succeeded','review'))
 then raise exception 'Questo pagamento ha già una richiesta di rimborso';end if;
 insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason)
 values(v_attempt.id,p_request_key,v_attempt.amount_cents,'pending',btrim(p_reason))
 returning id into v_new;
 insert into public.order_audit(order_id,school_id,actor_id,action)
 values(v_order.id,v_order.school_id,v_user,'stripe_full_refund_requested');
 return jsonb_build_object('refund_id',v_new,'account',v_attempt.stripe_account_id,
  'payment_intent',v_attempt.stripe_payment_intent_id,
  'amount_cents',v_attempt.amount_cents,'status','pending');
end;
$refund_request$;

create or replace function public.attach_verified_stripe_refund(
 p_refund_id uuid,p_stripe_refund text
) returns void language plpgsql security definer set search_path=''
as $attach_refund$
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role'
 then raise exception 'Service role richiesto';end if;
 if p_stripe_refund !~ '^re_[A-Za-z0-9]+$' then raise exception 'ID rimborso non valido';end if;
 update public.payment_refunds set stripe_refund_id=p_stripe_refund,
  status=case when status='pending' then 'processing' else status end,updated_at=now()
 where id=p_refund_id and status in ('pending','processing')
 and (stripe_refund_id is null or stripe_refund_id=p_stripe_refund);
 if not found then raise exception 'Rimborso non disponibile o duplicato incoerente';end if;
end;
$attach_refund$;

create or replace function public.finalize_verified_stripe_refund(
 p_event_id text,p_stripe_account text,p_refund_id uuid,p_stripe_refund text,
 p_payment_intent text,p_amount bigint,p_currency text,p_status text
) returns text language plpgsql security definer set search_path=''
as $finalize_refund$
declare v_refund public.payment_refunds%rowtype;v_attempt public.payment_attempts%rowtype;
 v_order public.orders%rowtype;v_action text;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role richiesto';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$'
  or p_stripe_account !~ '^acct_[A-Za-z0-9]+$'
  or p_stripe_refund !~ '^re_[A-Za-z0-9]+$'
  or p_payment_intent !~ '^pi_[A-Za-z0-9]+$'
  or p_status not in('succeeded','failed') or p_currency<>'eur'
  or p_amount<=0 or p_refund_id is null
 then raise exception 'Evento rimborso non valido';end if;
 select * into v_refund from public.payment_refunds where id=p_refund_id for update;
 if not found or v_refund.amount_cents<>p_amount or
    (v_refund.stripe_refund_id is not null and v_refund.stripe_refund_id<>p_stripe_refund)
 then raise exception 'Importo o refund ID non corrispondenti';end if;
 select * into v_attempt from public.payment_attempts where id=v_refund.payment_id for update;
 if not found or v_attempt.stripe_account_id<>p_stripe_account or
  v_attempt.stripe_payment_intent_id<>p_payment_intent or v_attempt.status<>'succeeded'
 then raise exception 'Stripe Connect account o pagamento originale non valido';end if;
 select * into v_order from public.orders where id=v_attempt.order_id for update;
 if not found or v_order.school_id<>v_attempt.school_id or
  v_order.customer_id<>v_attempt.payer_id
 then raise exception 'Scuola o pagatore del rimborso incoerenti';end if;
 if v_refund.status=p_status then return 'duplicate';end if;
 if v_refund.status='succeeded' then return 'duplicate';end if;
 v_action:=case when p_status='succeeded' then 'stripe_refund_succeeded'
   else 'stripe_refund_failed' end;
 update public.payment_refunds set status=p_status,stripe_refund_id=p_stripe_refund,
   updated_at=now() where id=p_refund_id;
 if p_status='succeeded' then
  update public.orders set payment_status='refunded',updated_at=now() where id=v_order.id;
 end if;
 insert into public.order_audit(order_id,school_id,actor_id,action)
 values(v_order.id,v_order.school_id,v_attempt.payer_id,v_action);
 return p_status;
end;
$finalize_refund$;
revoke all on function public.request_full_individual_stripe_refund(uuid,uuid,text),
 public.attach_verified_stripe_refund(uuid,text),
 public.finalize_verified_stripe_refund(text,text,uuid,text,text,bigint,text,text)
 from public,anon,authenticated;
grant execute on function public.request_full_individual_stripe_refund(uuid,uuid,text)
 to authenticated;
grant execute on function public.attach_verified_stripe_refund(uuid,text),
 public.finalize_verified_stripe_refund(text,text,uuid,text,text,bigint,text,text)
 to service_role;
commit;
