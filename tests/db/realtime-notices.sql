-- Realtime notices tests after 15; uses group and support fixtures.
reset role;
select set_config('app.notify_group_id',(select id::text from public.group_drafts order by created_at limit 1),false);
select set_config('app.notify_invite',(select invite_token::text from public.group_drafts order by created_at limit 1),false);
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.join_group_draft(current_setting('app.notify_invite')::uuid,
 45.0,9.0,10,now());
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $notice_to_coordinator$
begin
 if not exists(select 1 from public.customer_notifications
   where user_id=auth.uid() and event_type='group_join_requested'
     and group_id=current_setting('app.notify_group_id')::uuid)
 then raise exception 'Group join request did not notify coordinator';end if;
end;$notice_to_coordinator$;

select public.review_group_member(current_setting('app.notify_group_id')::uuid,
 '33333333-3333-4333-8333-333333333333',true);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $notice_to_joiner$
begin
 if not exists(select 1 from public.customer_notifications
   where user_id=auth.uid() and event_type='group_join_approved')
 then raise exception 'Approval did not notify member';end if;
end;$notice_to_joiner$;

-- Other authenticated accounts cannot see or mark someone else's notices.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $notice_isolation$
begin
 if exists(select 1 from public.customer_notifications n
   where n.event_type='group_join_approved'
    and n.user_id='33333333-3333-4333-8333-333333333333')
 then raise exception 'Cross-user notice exposed';end if;
end;$notice_isolation$;
reset role;
do $realtime_published$
begin
 if not exists(select 1 from pg_publication_tables
   where pubname='supabase_realtime' and tablename='customer_notifications')
 then raise exception 'Realtime publication missing';end if;
end;$realtime_published$;
