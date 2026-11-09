-- Only the private dispatcher can claim these details. Send a useful,
-- Version aligned with the hosted Supabase migration history.
-- non-sensitive push and open its corresponding section in the PWA.
do $push_context$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('public.claim_push_jobs(integer)'::regprocedure);
 if pg_catalog.strpos(v_def,'''auth'',s.auth_key,''message'',n.message')=0 then
  raise exception 'claim_push_jobs is not compatible with contextual push migration';end if;
 v_def:=pg_catalog.replace(v_def,
   '''auth'',s.auth_key,''message'',n.message',
   '''auth'',s.auth_key,''notice_id'',n.id,''event_type'',n.event_type,''group_id'',n.group_id,''order_id'',n.order_id,''ticket_id'',n.ticket_id,''message'',n.message');
 execute v_def;
end;
$push_context$;
