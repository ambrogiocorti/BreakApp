-- BreakApp 30: Anna beneficiary, Luca payer, partial refund ownership and expiry.
reset role;
update public.school_stripe_merchants set charges_enabled=true
 where school_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000301',
 'Group refund original payer test',false,3) as id \gset
select set_config('app.refund_group',:'id',false);
select set_config('app.refund_invite',
 public.group_draft_details(current_setting('app.refund_group')::uuid)->>'invite_token',false);
select public.replace_group_personal_cart(current_setting('app.refund_group')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.join_group_draft(current_setting('app.refund_invite')::uuid,45,9,10,now());
select public.replace_group_personal_cart(current_setting('app.refund_group')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":2}]'::jsonb);
select set_config('app.refund_member_line',(select line->>'line_id'
 from jsonb_array_elements(public.group_payable_lines(current_setting('app.refund_group')::uuid)) line
 where (line->>'quantity')::integer=2),false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.begin_group_stripe_checkout(
 current_setting('app.refund_group')::uuid,
 array[current_setting('app.refund_member_line')::uuid],
 '11111111-0000-4000-8000-000000000302') as payment \gset
select set_config('app.refund_payment',(:'payment'::jsonb->>'attempt_id'),false);
reset role;
select set_config('app.refund_amount',(select amount_cents::text from public.payment_attempts
 where id=current_setting('app.refund_payment')::uuid),false);
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(current_setting('app.refund_payment')::uuid,
 'cs_test_grouprefund301');
select public.finalize_verified_group_checkout('evt_grouprefund301',
 'acct_1UUniH2RLt7x5EeZ','cs_test_grouprefund301','pi_grouprefund301',
 current_setting('app.refund_payment')::uuid,
 current_setting('app.refund_amount')::bigint,'eur',true,'{}'::jsonb);
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.leave_group_draft(current_setting('app.refund_group')::uuid);
reset role;
do $original_payer$
declare n int; payer uuid; state text; amt bigint;removed timestamptz;
begin
 select count(*),min(original_payer_id::text)::uuid,max(amount_cents) into n,payer,amt
 from public.group_line_refunds where group_cart_item_id=current_setting('app.refund_member_line')::uuid;
 select cl.state,i.removed_at into state,removed
 from public.group_line_payment_claims cl
 join public.group_cart_items i on i.id=cl.group_cart_item_id
 where cl.group_cart_item_id=current_setting('app.refund_member_line')::uuid;
 if n<>1 or payer<>'11111111-1111-4111-8111-111111111111'::uuid
 or amt<>current_setting('app.refund_amount')::bigint
 or state<>'refund_pending' or removed is null
 then raise exception 'Third-party refund was not assigned to original payer';end if;
 if (select count(*) from public.group_cart_items where group_id=current_setting('app.refund_group')::uuid
 and removed_at is null)<>1 then raise exception 'Unrelated group cart line unexpectedly removed';end if;
end;$original_payer$;
select set_config('app.refund_id',(select refund_id::text from public.group_line_refunds
 where group_cart_item_id=current_setting('app.refund_member_line')::uuid),false);
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.finalize_verified_group_refund('evt_grouprefund302',
 'acct_1UUniH2RLt7x5EeZ',current_setting('app.refund_id')::uuid,'re_grouprefund302',
 'pi_grouprefund301',current_setting('app.refund_amount')::bigint,'eur','succeeded');
reset role;
do $refunded$
begin
 if (select state from public.group_line_payment_claims
 where group_cart_item_id=current_setting('app.refund_member_line')::uuid)<>'refunded'
 then raise exception 'Signed group refund not reconciled';end if;
end;$refunded$;

-- Pending payment is allowed to settle only into an automatic refund after draft cancellation.
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000303',
 'Late signed payment refund test',false,3) as id \gset
select set_config('app.late_group',:'id',false);
select public.replace_group_personal_cart(current_setting('app.late_group')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
select set_config('app.late_line',(select line->>'line_id'
 from jsonb_array_elements(public.group_payable_lines(current_setting('app.late_group')::uuid)) line
 limit 1),false);
select public.begin_group_stripe_checkout(current_setting('app.late_group')::uuid,
 array[current_setting('app.late_line')::uuid],
 '11111111-0000-4000-8000-000000000304') as payment \gset
select set_config('app.late_payment',(:'payment'::jsonb->>'attempt_id'),false);
select public.cancel_group_draft(current_setting('app.late_group')::uuid);
reset role;
select set_config('app.late_amount',(select amount_cents::text from public.payment_attempts
 where id=current_setting('app.late_payment')::uuid),false);
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.attach_stripe_checkout_session(current_setting('app.late_payment')::uuid,
 'cs_test_grouprefund303');
select public.finalize_verified_group_checkout('evt_grouprefund303',
 'acct_1UUniH2RLt7x5EeZ','cs_test_grouprefund303','pi_grouprefund303',
 current_setting('app.late_payment')::uuid,
 current_setting('app.late_amount')::bigint,'eur',true,'{}'::jsonb) as result \gset
select set_config('app.late_result',:'result',false);
reset role;
do $late_refund$
begin
 if current_setting('app.late_result')<>'refund_required' or not exists(
  select 1 from public.group_line_refunds
  where group_cart_item_id=current_setting('app.late_line')::uuid)
 then raise exception 'Late settled group payment not queued for refund';end if;
end;$late_refund$;

-- 24-hour inactivity expiry is a server-only operation and releases draft entries.
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000305',
 'Inactivity expiration test',false,3) as id \gset
select set_config('app.expiring_group',:'id',false);
select public.replace_group_personal_cart(current_setting('app.expiring_group')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
reset role;
update public.group_drafts set updated_at=now()-interval '25 hours'
 where id=current_setting('app.expiring_group')::uuid;
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.expire_group_drafts(100);
reset role;
do $expiry$
begin
 if (select status from public.group_drafts
 where id=current_setting('app.expiring_group')::uuid)<>'expired'
 then raise exception 'Unattended draft not expired';end if;
 if exists(select 1 from public.group_cart_items
  where group_id=current_setting('app.expiring_group')::uuid)
 then raise exception 'Expired unclaimed draft lines not released';end if;
end;$expiry$;

-- Warning is delivered exactly once per real inactivity deadline.
reset role;
update public.group_drafts set updated_at=now()-interval '23 hours 10 minutes'
where id=current_setting('app.expiring_group')::uuid;
update public.group_drafts set status='draft'
where id=current_setting('app.expiring_group')::uuid;
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.warn_group_drafts_before_expiry(100);
select public.warn_group_drafts_before_expiry(100);
reset role;
do $warning$
begin
 if (select count(*) from public.customer_notifications
 where group_id=current_setting('app.expiring_group')::uuid and event_type='group_draft_expiry')<>1
 then raise exception 'Expiry warning not exactly-once';end if;
end;$warning$;
