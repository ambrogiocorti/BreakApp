begin;
reset role;
do $$begin
 if has_function_privilege('authenticated','public.push_runtime_configuration()','EXECUTE') or
    has_function_privilege('anon','public.push_runtime_configuration()','EXECUTE') or
    has_function_privilege('authenticated','public.claim_refund_dispatch(integer)','EXECUTE') or
    has_function_privilege('authenticated','public.finish_refund_dispatch(uuid,text,text)','EXECUTE')
 then raise exception 'Backend secrets or refund dispatcher exposed';end if;
end;$$;
insert into public.payment_refunds(id,payment_id,request_key,amount_cents,status,reason)
select '34000000-0000-4000-8000-000000000001',id,'34000000-0000-4000-8000-000000000002',1,'pending',
 'Test retry rimborso transitorio' from public.payment_attempts
where status='succeeded' and stripe_payment_intent_id is not null order by created_at limit 1;
insert into public.payment_refunds(id,payment_id,request_key,amount_cents,status,reason,created_at)
select '34000000-0000-4000-8000-000000000003',id,'34000000-0000-4000-8000-000000000004',1,'pending',
 'Test rimborso oltre finestra idempotenza',now()-interval '24 hours' from public.payment_attempts
where status='succeeded' and stripe_payment_intent_id is not null order by created_at limit 1;
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select * from public.claim_refund_dispatch(30);
select public.finish_refund_dispatch('34000000-0000-4000-8000-000000000001','retry','network_error');
reset role;
do $$begin
 if not exists(select 1 from public.payment_refunds where id='34000000-0000-4000-8000-000000000001'
  and dispatch_attempts=1 and next_dispatch_at>now() and status='pending') then raise exception 'Retry/backoff not applied';end if;
 if (select status from public.payment_refunds where id='34000000-0000-4000-8000-000000000003')<>'review'
 then raise exception 'Old refund retried beyond provider idempotency window';end if;
end;$$;
update public.payment_refunds set dispatch_attempts=8 where id='34000000-0000-4000-8000-000000000001';
set role service_role;
select public.finish_refund_dispatch('34000000-0000-4000-8000-000000000001','retry','network_error');
reset role;
do $$begin
 if (select status from public.payment_refunds where id='34000000-0000-4000-8000-000000000001')<>'review'
 then raise exception 'Exhausted retries not escalated';end if;
 if not exists(select 1 from public.customer_notifications where event_type='refund_issue')
 then raise exception 'Refund problem not notified';end if;
end;$$;
rollback;
