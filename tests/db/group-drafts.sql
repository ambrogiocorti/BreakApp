-- Group draft integration, run after migration 14.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000050',
 'Gruppo classe A',true,3) as group_id \gset
select set_config('app.test_group_id',:'group_id',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000050',
 'Gruppo classe A',true,3) as repeated_group \gset
select case when :'group_id'=:'repeated_group' then 'OK' else (1/0)::text end as group_idempotence;
select set_config('app.test_invite',
 (public.group_draft_details(:'group_id'::uuid)->>'invite_token'),false);
-- group_drafts is intentionally not directly accessible even to its coordinator.
do $no_direct_table$
declare denied boolean:=false;
begin
 begin
  perform count(*) from public.group_drafts;
 exception when insufficient_privilege then denied:=true;
 end;
 if not denied then raise exception 'Direct group table readable';end if;
end;$no_direct_table$;

-- A different user cannot join without fresh GPS within school radius.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $geo_denied$
declare denied boolean:=false;
begin
 begin
  perform public.join_group_draft(
   current_setting('app.test_invite')::uuid,46,10,10,now());
 exception when others then denied:=true;end;
 if not denied then raise exception 'Distant participant joined';end if;
end;$geo_denied$;
select public.join_group_draft(current_setting('app.test_invite')::uuid,45,9,10,now());
do $join_pending$
declare status_text text;
begin
 status_text:=public.group_draft_details(current_setting('app.test_group_id')::uuid)->>'my_status';
 if status_text<>'pending' then raise exception 'Approval group accepted unauthorized participant';end if;
end;$join_pending$;

-- Pending user cannot edit cart.
do $pending_denied$
declare denied boolean:=false;
begin
 begin
  perform public.replace_group_personal_cart(
   current_setting('app.test_group_id')::uuid,
   '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Pending member changed cart';end if;
end;$pending_denied$;

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.review_group_member(:'group_id'::uuid,
 '22222222-2222-4222-8222-222222222222',true);

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.replace_group_personal_cart(:'group_id'::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":2}]'::jsonb);
select public.set_group_personal_ready(:'group_id'::uuid,true);
do $cannot_edit_ready$
declare denied boolean:=false; details jsonb;
begin
 details:=public.group_draft_details(current_setting('app.test_group_id')::uuid);
 if (details->'totals'->>'count')::int<>2
 then raise exception 'Aggregate group total incorrect';end if;
 if jsonb_typeof(details->'members')<>'object'
 then raise exception 'Participant should see counts, not member identities';end if;
 begin
  perform public.replace_group_personal_cart(
   current_setting('app.test_group_id')::uuid,'[]'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Ready participant edited locked cart';end if;
end;$cannot_edit_ready$;

-- Aggregate draft lines never allocate inventory.
reset role;
do $stock_untouched$
begin
 if (select allocated from public.daily_stock
    where product_id='aaaaaaaa-0000-4000-8000-000000000003')<>1
 then raise exception 'Draft group reserved stock';end if;
end;$stock_untouched$;

-- A Super Admin may not coordinate group orders.
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $platform_denied$
declare denied boolean:=false;
begin
 begin
  perform public.create_group_draft(
  'aaaaaaaa-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000005',
  '44444444-0000-4000-8000-000000000001','Global should not order',false,null);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Global admin created group order';end if;
end;$platform_denied$;
reset role;
