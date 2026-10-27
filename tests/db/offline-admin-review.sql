-- Offline review audit and privilege enforcement (migration 26).
reset role;
insert into auth.users(id,email) values
 ('55555555-5555-4555-8555-555555555555','offline-reviewer@example.invalid');
insert into public.school_memberships(id,school_id,user_id)
values('aaaaaaaa-0000-4000-8000-000000000096',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '55555555-5555-4555-8555-555555555555');
insert into public.role_assignments(membership_id,role_code)
values('aaaaaaaa-0000-4000-8000-000000000096','school_admin');
select id as staged_id from public.offline_events_inbox
 where request_key='aaaaaaaa-0000-4000-8000-000000000092' \gset
do $direct_denied$
begin
 if has_table_privilege('authenticated','public.offline_event_reviews','INSERT') or
    has_table_privilege('authenticated','public.offline_event_reviews','SELECT')
 then raise exception 'Offline event audit leaked via direct table permissions';end if;
end;$direct_denied$;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $barista_denied$
declare denied boolean:=false;
begin
 begin
  perform public.list_school_offline_events('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Barista accessed admin review queue';end if;
end;$barista_denied$;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $mfa_denied$
declare denied boolean:=false;
begin
 begin
  perform public.review_school_offline_event(:'staged_id'::uuid,true,
   'Verifica integrità e registri di cassa.');
 exception when others then denied:=true;end;
 if not denied then raise exception 'AAL1 Admin approved offline event';end if;
end;$mfa_denied$;
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $cross_school_denied$
declare denied boolean:=false;
begin
 begin
  perform public.list_school_offline_events('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Admin read another school';end if;
end;$cross_school_denied$;
do $queue_exists$
declare events jsonb;
begin
 events:=public.list_school_offline_events('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 if jsonb_array_length(events)<1 then raise exception 'Offline queue empty after staging';end if;
end;$queue_exists$;
select public.review_school_offline_event(:'staged_id'::uuid,true,
 'Decisione tracciata, riconciliazione contabile non ancora applicata.') as review_response \gset
do $no_double_review$
declare denied boolean:=false;
begin
 if (:'review_response'::jsonb->>'applied_to_ledger')::boolean
 then raise exception 'Review falsely marked ledger applied';end if;
 begin
  perform public.review_school_offline_event(:'staged_id'::uuid,false,
   'Tentativo duplicato della stessa revisione.');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Double review accepted';end if;
end;$no_double_review$;
reset role;
do $audit_written$
begin
 if not exists(select 1 from public.offline_event_reviews
 where event_id=:'staged_id'::uuid and decision='approved'
 and reviewer_id='55555555-5555-4555-8555-555555555555')
 then raise exception 'No immutable review audit record';end if;
 if (select status from public.offline_events_inbox where id=:'staged_id'::uuid)<>'approved'
 then raise exception 'Review status missing';end if;
end;$audit_written$;
