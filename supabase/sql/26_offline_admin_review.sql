-- BreakApp 26: auditable human review of offline events.
-- Approval is NOT application to the payment ledger or inventory.
begin;
create table public.offline_event_reviews (
 id bigint generated always as identity primary key,
 event_id uuid not null references public.offline_events_inbox(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 reviewer_id uuid not null references auth.users(id) on delete restrict,
 decision text not null check(decision in ('approved','rejected')),
 reason text not null check(char_length(btrim(reason)) between 10 and 500),
 created_at timestamptz not null default now()
);
create index offline_reviews_event on public.offline_event_reviews(event_id,created_at desc);
create index offline_reviews_school on public.offline_event_reviews(school_id,created_at desc);
create index offline_reviews_reviewer on public.offline_event_reviews(reviewer_id);
alter table public.offline_event_reviews enable row level security;
revoke all on public.offline_event_reviews from public,anon,authenticated;

create or replace function app_private.can_review_school_offline(p_school uuid)
returns boolean language sql stable security definer set search_path=''
as $review_permission$
 select p_school is not null
  and auth.uid() is not null
  and coalesce(auth.jwt()->>'is_anonymous','false')<>'true'
  and auth.jwt()->>'aal'='aal2'
  and not exists(select 1 from app_private.platform_admins pa where pa.user_id=auth.uid())
  and exists(select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id=m.id
    where m.user_id=auth.uid() and m.school_id=p_school
      and m.membership_status='active' and r.role_code='school_admin');
$review_permission$;
revoke all on function app_private.can_review_school_offline(uuid)
 from public,anon,authenticated;

create or replace function public.list_school_offline_events(p_school uuid)
returns jsonb language plpgsql security definer set search_path=''
as $offline_list$
declare v_events jsonb;
begin
 if not app_private.can_review_school_offline(p_school)
 then raise exception 'Verifica Admin AAL2 richiesta per questa scuola';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.id,'barista_id',e.barista_id,'event_kind',e.event_kind,
  'device_id',e.device_id,'lease_generation',e.lease_generation,
  'local_recorded_at',e.local_recorded_at,'received_at',e.received_at,
  'payload',e.payload,'status',e.status,'review_reason',e.review_reason,
  'reviewed_at',e.reviewed_at,'reviewed_by',e.reviewed_by,
  'reviewer_note',(select r.reason from public.offline_event_reviews r
    where r.event_id=e.id order by r.created_at desc limit 1)
 ) order by e.received_at desc),'[]'::jsonb) into v_events
 from (select * from public.offline_events_inbox
   where school_id=p_school order by received_at desc limit 100) e;
 return v_events;
end;$offline_list$;

create or replace function public.review_school_offline_event(
 p_event_id uuid,p_approve boolean,p_reason text
) returns jsonb language plpgsql security definer set search_path=''
as $offline_review$
declare v_event public.offline_events_inbox%rowtype;v_decision text;
begin
 if p_event_id is null or p_approve is null or
  char_length(btrim(coalesce(p_reason,''))) not between 10 and 500
 then raise exception 'Motivazione obbligatoria (10–500 caratteri)';end if;
 select * into v_event from public.offline_events_inbox
   where id=p_event_id for update;
 if not found or not app_private.can_review_school_offline(v_event.school_id)
 then raise exception 'Evento non accessibile oppure MFA mancante';end if;
 if v_event.status<>'quarantined'
 then raise exception 'Evento già valutato; nessuna doppia approvazione';end if;
 v_decision:=case when p_approve then 'approved' else 'rejected' end;
 update public.offline_events_inbox set status=v_decision,
  reviewed_by=auth.uid(),reviewed_at=now()
 where id=p_event_id and status='quarantined';
 insert into public.offline_event_reviews(event_id,school_id,reviewer_id,decision,reason)
 values(p_event_id,v_event.school_id,auth.uid(),v_decision,btrim(p_reason));
 return jsonb_build_object('event_id',p_event_id,'status',v_decision,
  'applied_to_ledger',false);
end;$offline_review$;

revoke all on function public.list_school_offline_events(uuid),
 public.review_school_offline_event(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.list_school_offline_events(uuid),
 public.review_school_offline_event(uuid,boolean,text) to authenticated;
commit;
