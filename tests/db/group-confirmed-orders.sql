-- Integration: confirm group, stock reservation, QR lease, cash and atomic delivery.
reset role;
update public.schools set approval_product_threshold=null,
 approval_amount_threshold_cents=null
where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
update public.daily_stock set capacity=coalesce(allocated,0)+10
where product_id='aaaaaaaa-0000-4000-8000-000000000003'
  and bar_id='aaaaaaaa-0000-4000-8000-000000000001';
select set_config('app.group_live_stock_before',
 (select allocated::text from public.daily_stock
  where product_id='aaaaaaaa-0000-4000-8000-000000000003' limit 1),false);
set role authenticated;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000097',
 'Gruppo prova conferma',false,3) as group_id \gset
select set_config('app.group_live_id',:'group_id',false);
select set_config('app.group_live_invite',
 public.group_draft_details(current_setting('app.group_live_id')::uuid)->>'invite_token',false);
select public.replace_group_personal_cart(current_setting('app.group_live_id')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.join_group_draft(current_setting('app.group_live_invite')::uuid,45,9,10,now());
select public.replace_group_personal_cart(current_setting('app.group_live_id')::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
select public.set_group_personal_ready(current_setting('app.group_live_id')::uuid,true);
do $outsider_confirm$
declare denied boolean:=false;
begin
 begin
  perform public.confirm_group_order(current_setting('app.group_live_id')::uuid,
  '11111111-0000-4000-8000-000000000098',true,45,9,10,now());
 exception when others then denied:=true;end;
 if not denied then raise exception 'Non coordinator confirmed group';end if;
end;$outsider_confirm$;

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $wrong_gps$
declare denied boolean:=false;
begin
 begin
  perform public.confirm_group_order(current_setting('app.group_live_id')::uuid,
  '11111111-0000-4000-8000-000000000098',true,46,10,10,now());
 exception when others then denied:=true;end;
 if not denied then raise exception 'Distant coordinator confirmed group';end if;
end;$wrong_gps$;
select public.confirm_group_order(current_setting('app.group_live_id')::uuid,
 '11111111-0000-4000-8000-000000000098',true,45,9,10,now()) as order_id \gset
select set_config('app.group_live_order',:'order_id',false);
select public.confirm_group_order(current_setting('app.group_live_id')::uuid,
 '11111111-0000-4000-8000-000000000098',true,45,9,10,now()) as repeated_order \gset
select case when :'order_id'=:'repeated_order' then 'OK' else (1/0)::text end as group_idempotent;
select set_config('app.group_live_token',
 public.group_order_details(current_setting('app.group_live_order')::uuid)->>'pickup_token',false);
do $lock_cart$
declare denied boolean:=false;
begin
 begin
  perform public.replace_group_personal_cart(current_setting('app.group_live_id')::uuid,'[]'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Confirmed group carrello still mutable';end if;
end;$lock_cart$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $privacy$
declare items jsonb; item jsonb;
begin
 items:=public.group_order_details(current_setting('app.group_live_order')::uuid)->'lines';
 if jsonb_array_length(items)<>2 then raise exception 'Expected two personal lines';end if;
 for item in select * from jsonb_array_elements(items) loop
  if item->>'beneficiary_id' is not null then raise exception 'Group beneficiary leaked';end if;
 end loop;
end;$privacy$;
do $customer_cannot_scan$
declare denied boolean:=false;
begin
 begin
  perform public.scan_group_pickup(current_setting('app.group_live_token')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Customer scanned a staff-only QR';end if;
end;$customer_cannot_scan$;
reset role;
do $stock_reserved$
begin
 if (select allocated from public.daily_stock
  where product_id='aaaaaaaa-0000-4000-8000-000000000003' limit 1)
  <>current_setting('app.group_live_stock_before')::integer+2
 then raise exception 'Group stock not atomically reserved';end if;
 if (select sum(quantity) from public.group_order_lines
  where group_order_id=current_setting('app.group_live_order')::uuid)<>2
 then raise exception 'Missing confirmed group line snapshots';end if;
end;$stock_reserved$;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $staff_list$
begin
 if jsonb_array_length(public.list_staff_group_orders(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'aaaaaaaa-0000-4000-8000-000000000001'))=0
 then raise exception 'Group missing from staff order list';end if;
end;$staff_list$;
select public.scan_group_pickup(current_setting('app.group_live_token')::uuid);
do $cannot_deliver_unpaid$
declare denied boolean:=false;
begin
 begin
  perform public.deliver_group_order(current_setting('app.group_live_order')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Unpaid or unready group delivered';end if;
end;$cannot_deliver_unpaid$;
do $make_ready$
declare s text;
begin
 s:=public.group_order_details(current_setting('app.group_live_order')::uuid)->>'status';
 if s='confirmed' then
  perform public.advance_group_order(current_setting('app.group_live_order')::uuid,'ready');
 elsif s<>'ready' then
  raise exception 'Unexpected group preparation status';end if;
end;$make_ready$;
select public.record_group_counter_payment(current_setting('app.group_live_order')::uuid,
 'cash','33333333-0000-4000-8000-000000000099');
select public.record_group_counter_payment(current_setting('app.group_live_order')::uuid,
 'cash','33333333-0000-4000-8000-000000000099') as idempotent_cash;
select public.deliver_group_order(current_setting('app.group_live_order')::uuid);
do $cannot_redeliver$
declare denied boolean:=false;
begin
 begin
  perform public.deliver_group_order(current_setting('app.group_live_order')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Duplicate delivery accepted';end if;
end;$cannot_redeliver$;
reset role;
do $settled_group$
begin
 if (select status from public.group_orders
   where id=current_setting('app.group_live_order')::uuid)<>'delivered'
 then raise exception 'Atomic delivery not stored';end if;
 if (select count(*) from public.group_counter_payments
   where group_order_id=current_setting('app.group_live_order')::uuid)<>1
 then raise exception 'Duplicate group cash payment';end if;
end;$settled_group$;
