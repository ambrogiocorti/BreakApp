-- Applied after the timestamped migration: joining requires an invitation,
-- but location is checked only by confirm_group_order at final submission.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000120',
 'Accesso remoto consentito',false,3) as group_id \gset
select set_config('app.remote_group_id',:'group_id',false);
select set_config('app.remote_group_invite',
 public.group_draft_details(:'group_id'::uuid)->>'invite_token',false);
select public.replace_group_personal_cart(:'group_id'::uuid,
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb);

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.join_group_draft(current_setting('app.remote_group_invite')::uuid,
 null,null,null,null) as joined_group \gset
select set_config('app.remote_group_joined',:'joined_group',false);
do $join_without_gps$
begin
 if current_setting('app.remote_group_joined')::uuid <> current_setting('app.remote_group_id')::uuid then
  raise exception 'Joining without GPS returned the wrong group';end if;
 if public.group_draft_details(current_setting('app.remote_group_id')::uuid)->>'my_status'<>'accepted' then
  raise exception 'Joining without GPS did not accept the participant';end if;
end;$join_without_gps$;
do $wrong_invite$
declare denied boolean:=false;
begin
 begin
  perform public.join_group_draft('aaaaaaaa-0000-4000-8000-000000000999',
    null,null,null,null);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Unknown invitation accepted';end if;
end;$wrong_invite$;

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $coordinator_still_needs_location$
declare denied boolean:=false;
begin
 begin
  perform public.confirm_group_order(current_setting('app.remote_group_id')::uuid,
   '11111111-0000-4000-8000-000000000121',true,null,null,null,null);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Confirmed group without GPS';end if;
end;$coordinator_still_needs_location$;
reset role;
