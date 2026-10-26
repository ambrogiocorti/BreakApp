-- Refund test after Stripe integration test created one paid online order.
reset role;
select o.id as refund_test_order,a.id as refund_test_attempt
from public.orders o join public.payment_attempts a on a.order_id=o.id
where a.status='succeeded' and o.payment_status='paid'
order by o.created_at desc limit 1 \gset
select set_config('app.refund_order',:'refund_test_order',false);
select set_config('app.refund_attempt',:'refund_test_attempt',false);
update public.orders set status='delivered'
where id=current_setting('app.refund_order')::uuid;

set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $customer_denied$
declare denied boolean:=false;
begin
 begin
  perform public.request_full_individual_stripe_refund(
   current_setting('app.refund_order')::uuid,
   '11111111-1111-4111-8111-111111111901',
   'Richiesta rimborso non autorizzata');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Customer requested admin-only Stripe refund';end if;
end;$customer_denied$;

select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $admin_aal1_denied$
declare denied boolean:=false;
begin
 begin
  perform public.request_full_individual_stripe_refund(
   current_setting('app.refund_order')::uuid,
   '11111111-1111-4111-8111-111111111902',
   'Rimborso senza autenticazione forte');
 exception when others then denied:=true;end;
 if not denied then raise exception 'AAL1 admin refund accepted';end if;
end;$admin_aal1_denied$;

select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.request_full_individual_stripe_refund(
 current_setting('app.refund_order')::uuid,
 '11111111-1111-4111-8111-111111111903',
 'Rimborso completo concordato con il cliente') as refund_request \gset
select set_config('app.refund_id',(:'refund_request'::jsonb->>'refund_id'),false);
do $refund_dedupe$
declare denied boolean:=false;
begin
 begin
  perform public.request_full_individual_stripe_refund(
   current_setting('app.refund_order')::uuid,
   '11111111-1111-4111-8111-111111111904',
   'Seconda richiesta illegittima');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Duplicate full refund request accepted';end if;
end;$refund_dedupe$;

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_verified_stripe_refund(
 current_setting('app.refund_id')::uuid,'re_testing123456789');
do $wrong_refund_amount$
declare denied boolean:=false;
begin
 begin
  perform public.finalize_verified_stripe_refund(
   'evt_refund_bad123','acct_1UUniH2RLt7x5EeZ',
   current_setting('app.refund_id')::uuid,
   're_testing123456789','pi_abcdefg1234',249,'eur','succeeded');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Wrong refund amount accepted';end if;
end;$wrong_refund_amount$;
select public.finalize_verified_stripe_refund(
 'evt_refund_good123','acct_1UUniH2RLt7x5EeZ',
 current_setting('app.refund_id')::uuid,
 're_testing123456789','pi_abcdefg1234',250,'eur','succeeded') as completed_refund \gset
reset role;
do $refund_settled$
begin
 if (select payment_status from public.orders
   where id=current_setting('app.refund_order')::uuid)<>'refunded'
 then raise exception 'Order not marked refunded';end if;
 if (select status from public.payment_refunds
   where id=current_setting('app.refund_id')::uuid)<>'succeeded'
 then raise exception 'Original payer ledger not refunded';end if;
 if (select count(*) from public.order_audit
   where order_id=current_setting('app.refund_order')::uuid
    and action='stripe_refund_succeeded')<>1
 then raise exception 'Refund audit missing/duplicated';end if;
end;$refund_settled$;
