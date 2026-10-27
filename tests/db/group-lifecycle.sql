-- Group management permissions and draft invariants, following migration 25.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.create_group_draft(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000005',
 '11111111-0000-4000-8000-000000000095',
 'Gruppo ciclo vita',false,3) as lifecycle_group \gset
select set_config('app.lifecycle_group',:'lifecycle_group',false);
select set_config('app.lifecycle_invite',
 (public.group_draft_details(:'lifecycle_group'::uuid)->>'invite_token'),false);

-- Cannot tighten a limit below current members once both join.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.join_group_draft(current_setting('app.lifecycle_invite')::uuid,45,9,10,now());
do $non_owner$
declare denied boolean:=false;
begin
 begin
  perform public.configure_group_draft(current_setting('app.lifecycle_group')::uuid,
   false,true,2,false);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Non-coordinator changed invite controls';end if;
end;$non_owner$;

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $limit_enforced$
declare denied boolean:=false;
begin
 begin
  perform public.configure_group_draft(current_setting('app.lifecycle_group')::uuid,
   true,false,1,false);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Member limit dropped below member count';end if;
end;$limit_enforced$;
select public.configure_group_draft(:'lifecycle_group'::uuid,false,true,2,true);
do $rotated$
declare new_token uuid;
begin
 new_token:=(public.group_draft_details(current_setting('app.lifecycle_group')::uuid)->>'invite_token')::uuid;
 if new_token=current_setting('app.lifecycle_invite')::uuid then
  raise exception 'Invitation was not rotated';end if;
 if (public.group_draft_details(current_setting('app.lifecycle_group')::uuid)->>'accepting_members')::boolean
 then raise exception 'Invitations should be closed';end if;
end;$rotated$;

-- Accepted (previously joined) registered member can become coordinator.
select public.transfer_group_coordinator(:'lifecycle_group'::uuid,
 '22222222-2222-4222-8222-222222222222');
do $former_owner_denied$
declare denied boolean:=false;
begin
 begin
  perform public.cancel_group_draft(current_setting('app.lifecycle_group')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Previous coordinator still allowed to cancel';end if;
end;$former_owner_denied$;
select public.leave_group_draft(:'lifecycle_group'::uuid);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $new_owner$
begin
 if (public.group_draft_details(current_setting('app.lifecycle_group')::uuid)->>'coordinator')::boolean=false
 then raise exception 'New coordinator flag missing';end if;
end;$new_owner$;
-- Old invite cannot work after rotation and closure.
do $closed$
declare denied boolean:=false;
begin
 begin
  perform public.join_group_draft(current_setting('app.lifecycle_invite')::uuid,45,9,10,now());
 exception when others then denied:=true;end;
 if not denied then raise exception 'Rotated invite still active';end if;
end;$closed$;
do $window_crossbar$
declare denied boolean:=false;
begin
 begin
  perform public.reschedule_group_draft(current_setting('app.lifecycle_group')::uuid,
   gen_random_uuid());
 exception when others then denied:=true;end;
 if not denied then raise exception 'Invalid window accepted';end if;
end;$window_crossbar$;
select public.cancel_group_draft(:'lifecycle_group'::uuid);
do $cancel_status$
begin
 if public.group_draft_details(current_setting('app.lifecycle_group')::uuid)->>'status'<>'cancelled'
 then raise exception 'Coordinator did not cancel group';end if;
end;$cancel_status$;
reset role;
