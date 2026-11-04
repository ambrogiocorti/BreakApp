-- Durable, serialized verification of the CURRENT Stripe refund state.
-- Stripe event snapshots may be delivered more than once or out of order.
begin;

create table app_private.stripe_refund_observations (
  refund_id uuid primary key references public.payment_refunds(id) on delete restrict,
  revision bigint not null default 1 check(revision>0),
  handled_revision bigint not null default 0 check(handled_revision>=0),
  lease_token uuid,
  lease_until timestamptz,
  claim_revision bigint,
  attempts integer not null default 0 check(attempts>=0),
  next_attempt_at timestamptz not null default now(),
  last_error text,
  updated_at timestamptz not null default now(),
  check(handled_revision<=revision),
  check((lease_token is null)=(lease_until is null))
);
create index stripe_refund_observations_due
  on app_private.stripe_refund_observations(next_attempt_at)
  where revision>handled_revision;
alter table app_private.stripe_refund_observations enable row level security;
revoke all on app_private.stripe_refund_observations from public,anon,authenticated,service_role;

-- All state-changing paths take locks in the same order as checkout settlement:
-- school order/group, payment attempt, refund, observation queue.
create function app_private.lock_refund_observation_scope(p_refund uuid)
returns void language plpgsql set search_path='' as $$
declare a public.payment_attempts%rowtype;
begin
 select a0.* into a from public.payment_refunds r
 join public.payment_attempts a0 on a0.id=r.payment_id where r.id=p_refund;
 if not found then raise exception 'Rimborso non trovato'; end if;
 if a.order_id is not null then
  perform id from public.orders where id=a.order_id for update;
  if not found then raise exception 'Ordine rimborso non trovato'; end if;
 elsif a.group_id is not null then
  perform id from public.group_drafts where id=a.group_id for update;
  if not found then raise exception 'Gruppo rimborso non trovato'; end if;
  perform id from public.group_orders where group_id=a.group_id for update;
 else raise exception 'Pagamento senza ordine'; end if;
 perform id from public.payment_attempts where id=a.id for update;
 perform id from public.payment_refunds where id=p_refund for update;
end;$$;
revoke all on function app_private.lock_refund_observation_scope(uuid) from public,anon,authenticated,service_role;

-- Idempotent attachment also tolerates the webhook arriving before POST returns.
create or replace function public.attach_verified_stripe_refund(p_refund_id uuid,p_stripe_refund text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.jwt()->>'role' is distinct from 'service_role'
  or coalesce(p_stripe_refund,'') !~ '^re_[A-Za-z0-9]+$' then
  raise exception 'Rimborso Stripe non valido';
 end if;
 update public.payment_refunds set stripe_refund_id=p_stripe_refund,
  status=case when status='pending' then 'processing' else status end,updated_at=now()
 where id=p_refund_id and status in ('pending','processing','succeeded','failed','review')
  and (stripe_refund_id is null or stripe_refund_id=p_stripe_refund);
 if not found then raise exception 'Rimborso non disponibile o incoerente'; end if;
end;$$;
revoke all on function public.attach_verified_stripe_refund(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_verified_stripe_refund(uuid,text) to service_role;

-- Record the verified event and request an authoritative provider lookup.
-- No event snapshot by itself marks a refund as succeeded.
create function public.enqueue_signed_refund_observation(
 p_event text,p_event_type text,p_account text,p_refund uuid,p_provider_refund text,
 p_intent text,p_amount bigint,p_currency text,p_snapshot_status text
) returns text language plpgsql security definer set search_path='' as $$
declare r public.payment_refunds%rowtype; a public.payment_attempts%rowtype;
 v_inserted text; v_previous app_private.stripe_webhook_inbox%rowtype; v_status text;
begin
 if auth.jwt()->>'role' is distinct from 'service_role'
  or coalesce(p_event,'') !~ '^evt_[A-Za-z0-9]+$'
  or p_event_type is null or p_event_type not in ('refund.created','refund.updated','refund.failed')
  or coalesce(p_account,'') !~ '^acct_[A-Za-z0-9]+$'
  or coalesce(p_provider_refund,'') !~ '^re_[A-Za-z0-9]+$'
  or coalesce(p_intent,'') !~ '^pi_[A-Za-z0-9]+$'
  or p_refund is null or p_amount is null or p_amount<=0
  or p_currency is distinct from 'eur'
  or p_snapshot_status is null or p_snapshot_status not in ('pending','requires_action','succeeded','failed','canceled')
  or (p_event_type='refund.failed' and p_snapshot_status<>'failed') then
  raise exception 'Evento rimborso non valido';
 end if;
 perform app_private.lock_refund_observation_scope(p_refund);
 select * into r from public.payment_refunds where id=p_refund;
 select * into a from public.payment_attempts where id=r.payment_id;
 if a.status is distinct from 'succeeded' or a.stripe_account_id is distinct from p_account
  or a.stripe_payment_intent_id is distinct from p_intent or r.amount_cents is distinct from p_amount
  or (r.stripe_refund_id is not null and r.stripe_refund_id is distinct from p_provider_refund) then
  raise exception 'Rimborso non coerente con il pagamento originale';
 end if;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload,processed_at)
 values(p_event,p_account,p_event_type,jsonb_build_object('refund_id',p_refund,
  'provider_refund',p_provider_refund,'payment_intent',p_intent,'amount',p_amount,
  'currency',p_currency,'snapshot_status',p_snapshot_status),now())
 on conflict(event_id) do nothing returning event_id into v_inserted;
 if v_inserted is null then
  select * into v_previous from app_private.stripe_webhook_inbox where event_id=p_event;
  if v_previous.stripe_account_id is distinct from p_account or v_previous.event_type is distinct from p_event_type
   or v_previous.payload is distinct from jsonb_build_object('refund_id',p_refund,
    'provider_refund',p_provider_refund,'payment_intent',p_intent,'amount',p_amount,
    'currency',p_currency,'snapshot_status',p_snapshot_status) then
   raise exception 'Identificativo evento già utilizzato';
  end if;
  return 'duplicate';
 end if;
 v_status:=case
  when p_snapshot_status in ('failed','canceled','requires_action') then 'review'
  when p_snapshot_status='pending' and r.status='succeeded' then 'review'
  when r.status='pending' then 'processing'
  else r.status end;
 update public.payment_refunds set stripe_refund_id=p_provider_refund,status=v_status,updated_at=now()
  where id=p_refund;
 if v_status<>'succeeded' then
  update public.group_line_payment_claims cl set state='refund_pending'
   from public.group_line_refunds gr where gr.refund_id=p_refund
   and cl.group_cart_item_id=gr.group_cart_item_id and cl.payment_id=a.id and cl.state='refunded';
 end if;
 if a.order_id is not null then perform app_private.refresh_individual_balance(a.order_id); end if;
 insert into app_private.stripe_refund_observations(refund_id)
 values(p_refund) on conflict(refund_id) do update set
  revision=app_private.stripe_refund_observations.revision+1,next_attempt_at=now(),updated_at=now();
 return 'queued';
end;$$;
revoke all on function public.enqueue_signed_refund_observation(text,text,text,uuid,text,text,bigint,text,text)
 from public,anon,authenticated;
grant execute on function public.enqueue_signed_refund_observation(text,text,text,uuid,text,text,bigint,text,text) to service_role;

create function public.claim_refund_observations(p_limit integer default 10)
returns table(refund_id uuid,lease_token uuid,claim_revision bigint,account text,
 provider_refund text,payment_intent text,amount_cents bigint)
language plpgsql security definer set search_path='' as $$
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo servizio backend'; end if;
 if p_limit is null or p_limit not between 1 and 30 then raise exception 'Limite non valido'; end if;
 return query with candidates as (
  select q.refund_id from app_private.stripe_refund_observations q
  where q.revision>q.handled_revision and q.next_attempt_at<=now()
   and (q.lease_until is null or q.lease_until<=now())
  order by q.next_attempt_at,q.refund_id for update of q skip locked limit p_limit
 ), claimed as (
  update app_private.stripe_refund_observations q set lease_token=gen_random_uuid(),
   lease_until=now()+interval '2 minutes',claim_revision=q.revision,
   attempts=q.attempts+1,updated_at=now() from candidates c where q.refund_id=c.refund_id
  returning q.refund_id,q.lease_token,q.claim_revision
 ) select c.refund_id,c.lease_token,c.claim_revision,a.stripe_account_id,
  r.stripe_refund_id,a.stripe_payment_intent_id,r.amount_cents
 from claimed c join public.payment_refunds r on r.id=c.refund_id
  join public.payment_attempts a on a.id=r.payment_id;
end;$$;
revoke all on function public.claim_refund_observations(integer) from public,anon,authenticated;
grant execute on function public.claim_refund_observations(integer) to service_role;

create function public.finish_refund_observation(
 p_refund uuid,p_token uuid,p_revision bigint,p_account text,p_provider_refund text,
 p_intent text,p_amount bigint,p_currency text,p_provider_status text
) returns text language plpgsql security definer set search_path='' as $$
declare q app_private.stripe_refund_observations%rowtype;
 r public.payment_refunds%rowtype; a public.payment_attempts%rowtype; v_status text;
begin
 if auth.jwt()->>'role' is distinct from 'service_role'
  or p_token is null or p_revision is null or p_revision<1
  or coalesce(p_account,'') !~ '^acct_[A-Za-z0-9]+$'
  or coalesce(p_provider_refund,'') !~ '^re_[A-Za-z0-9]+$'
  or coalesce(p_intent,'') !~ '^pi_[A-Za-z0-9]+$'
  or p_provider_status is null or p_provider_status not in ('pending','requires_action','succeeded','failed','canceled')
  or p_currency is distinct from 'eur' or p_amount is null or p_amount<=0 then
  raise exception 'Osservazione rimborso non valida';
 end if;
 perform app_private.lock_refund_observation_scope(p_refund);
 select * into r from public.payment_refunds where id=p_refund;
 select * into a from public.payment_attempts where id=r.payment_id;
 select * into q from app_private.stripe_refund_observations where refund_id=p_refund for update;
 if not found or q.lease_token is distinct from p_token or q.claim_revision is distinct from p_revision
  or q.lease_until<=clock_timestamp() then raise exception 'Lease di riconciliazione non valida'; end if;
 if a.status is distinct from 'succeeded' or a.stripe_account_id is distinct from p_account
  or a.stripe_payment_intent_id is distinct from p_intent or r.stripe_refund_id is distinct from p_provider_refund
  or r.amount_cents is distinct from p_amount then raise exception 'Osservazione non coerente con il ledger'; end if;
 if q.revision<>p_revision then
  update app_private.stripe_refund_observations set lease_token=null,lease_until=null,claim_revision=null,
   next_attempt_at=now(),updated_at=now() where refund_id=p_refund;
  return 'superseded';
 end if;
 v_status:=case p_provider_status when 'succeeded' then 'succeeded'
  when 'pending' then 'processing' when 'requires_action' then 'review' else 'failed' end;
 update public.payment_refunds set status=v_status,updated_at=now() where id=p_refund;
 update public.group_line_payment_claims cl
  set state=case when v_status='succeeded' then 'refunded' else 'refund_pending' end
  from public.group_line_refunds gr where gr.refund_id=p_refund
   and cl.group_cart_item_id=gr.group_cart_item_id and cl.payment_id=a.id
   and cl.state in ('refunded','refund_pending');
 if a.order_id is not null then perform app_private.refresh_individual_balance(a.order_id); end if;
 -- Nonterminal refunds remain observable even if a later webhook is delayed
 -- or lost. Retry at a bounded cadence rather than declaring them complete.
 update app_private.stripe_refund_observations set handled_revision=p_revision,
  revision=case when v_status in ('processing','review') then p_revision+1 else revision end,
  next_attempt_at=case when v_status in ('processing','review') then now()+interval '30 minutes' else now() end,
  lease_token=null,lease_until=null,claim_revision=null,attempts=0,last_error=null,updated_at=now()
  where refund_id=p_refund;
 return v_status;
end;$$;
revoke all on function public.finish_refund_observation(uuid,uuid,bigint,text,text,text,bigint,text,text)
 from public,anon,authenticated;
grant execute on function public.finish_refund_observation(uuid,uuid,bigint,text,text,text,bigint,text,text) to service_role;

-- Retry provider read errors with bounded backoff; after repeated failures,
-- raise a visible review state without declaring a refund successful.
create function public.fail_refund_observation(p_refund uuid,p_token uuid,p_revision bigint,p_code text)
returns void language plpgsql security definer set search_path='' as $$
declare q app_private.stripe_refund_observations%rowtype;
 r public.payment_refunds%rowtype; a public.payment_attempts%rowtype;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' or p_token is null
  or p_revision is null or coalesce(p_code,'') !~ '^[a-z0-9_]{1,80}$'
 then raise exception 'Errore osservazione non valido'; end if;
 perform app_private.lock_refund_observation_scope(p_refund);
 select * into r from public.payment_refunds where id=p_refund;
 select * into a from public.payment_attempts where id=r.payment_id;
 select * into q from app_private.stripe_refund_observations where refund_id=p_refund for update;
 if not found or q.lease_token is distinct from p_token or q.claim_revision is distinct from p_revision
  or q.lease_until<=clock_timestamp() then raise exception 'Lease di riconciliazione non valida'; end if;
 if q.attempts>=8 and r.status<>'review' then
  update public.payment_refunds set status='review',updated_at=now() where id=p_refund;
  update public.group_line_payment_claims cl set state='refund_pending'
   from public.group_line_refunds gr where gr.refund_id=p_refund
   and cl.group_cart_item_id=gr.group_cart_item_id and cl.payment_id=a.id and cl.state='refunded';
  if a.order_id is not null then perform app_private.refresh_individual_balance(a.order_id); end if;
 end if;
 update app_private.stripe_refund_observations set lease_token=null,lease_until=null,claim_revision=null,
  next_attempt_at=case when q.revision<>p_revision then now() else now()+make_interval(secs=>least(3600,30*power(2,least(q.attempts,7)))::int) end,
  last_error=p_code,updated_at=now() where refund_id=p_refund;
end;$$;
revoke all on function public.fail_refund_observation(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.fail_refund_observation(uuid,uuid,bigint,text) to service_role;
commit;
