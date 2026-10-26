-- BreakApp 15 — Immediate IN-APP notifications using Supabase Realtime.
-- Foreground OS notifications require explicit permission; background Web Push
-- and VAPID dispatcher are a separate phase. No secrets in GitHub Pages.
begin;

alter table public.customer_notifications
 drop constraint if exists customer_notifications_event_type_check;
alter table public.customer_notifications
 add constraint customer_notifications_event_type_check check(event_type in
  ('closure_order_cancelled','order_status','group_join_requested',
   'group_join_approved','group_join_rejected','support_reply'));

alter table public.customer_notifications
 add column if not exists group_id uuid references public.group_drafts(id) on delete restrict,
 add column if not exists ticket_id uuid references public.support_tickets(id) on delete restrict;
create index if not exists customer_notifications_unread
 on public.customer_notifications(user_id,created_at desc) where read_at is null;

-- Emitted by the same transaction that updates the order; safe on retry.
create or replace function app_private.notify_order_state()
returns trigger language plpgsql security definer set search_path=''
as $notify_order$
begin
 if new.status is distinct from old.status and new.customer_id is not null then
   insert into public.customer_notifications(school_id,user_id,order_id,event_type,message)
   values(new.school_id,new.customer_id,new.id,'order_status',
    'Ordine #'||new.display_no||': stato aggiornato a '||new.status||'.');
 end if;
 return new;
end;
$notify_order$;
revoke all on function app_private.notify_order_state() from public,anon,authenticated;
drop trigger if exists orders_notify_state on public.orders;
create trigger orders_notify_state after update of status on public.orders
for each row execute function app_private.notify_order_state();

create or replace function app_private.notify_group_member()
returns trigger language plpgsql security definer set search_path=''
as $notify_member$
declare v_group public.group_drafts%rowtype;v_event text;v_target uuid;
begin
 select * into v_group from public.group_drafts where id=new.group_id;
 if v_group.id is null then return new;end if;
 if tg_op='INSERT' then
   if new.status<>'pending' or new.user_id=v_group.coordinator_id then return new;end if;
   v_target:=v_group.coordinator_id;v_event:='group_join_requested';
 elsif tg_op='UPDATE' then
   if old.status is not distinct from new.status or old.status<>'pending'
     or new.status not in ('accepted','rejected') then return new;end if;
   v_target:=new.user_id;
   v_event:=case when new.status='accepted'
      then 'group_join_approved' else 'group_join_rejected' end;
 else return new;end if;
 insert into public.customer_notifications(school_id,user_id,group_id,event_type,message)
 values(v_group.school_id,v_target,v_group.id,v_event,
   case v_event
    when 'group_join_requested' then 'Una persona ha chiesto di entrare nel gruppo '||v_group.title||'.'
    when 'group_join_approved' then 'Sei stato accettato nel gruppo '||v_group.title||'.'
    else 'La richiesta di entrare nel gruppo '||v_group.title||' è stata rifiutata.'
   end);
 return new;
end;
$notify_member$;
revoke all on function app_private.notify_group_member() from public,anon,authenticated;
drop trigger if exists group_members_notify on public.group_members;
create trigger group_members_notify after insert or update of status on public.group_members
for each row execute function app_private.notify_group_member();

create or replace function app_private.notify_support_reply()
returns trigger language plpgsql security definer set search_path=''
as $notify_support$
declare v_ticket public.support_tickets%rowtype;
begin
 select * into v_ticket from public.support_tickets where id=new.ticket_id;
 if v_ticket.id is null or new.author_id=v_ticket.owner_id then return new;end if;
 insert into public.customer_notifications(school_id,user_id,ticket_id,event_type,message)
 values(v_ticket.school_id,v_ticket.owner_id,v_ticket.id,'support_reply',
  'Nuova risposta del personale al ticket: '||v_ticket.subject);
 return new;
end;
$notify_support$;
revoke all on function app_private.notify_support_reply() from public,anon,authenticated;
drop trigger if exists support_messages_notify_reply on public.support_messages;
create trigger support_messages_notify_reply after insert on public.support_messages
for each row execute function app_private.notify_support_reply();

-- Protect messages from frontend UPDATE, except the read_at column already
-- granted in migration 07 with own-user RLS. Anonymous access is prohibited.
do $publication$
begin
 if not exists(select 1 from pg_publication_tables
   where pubname='supabase_realtime' and schemaname='public'
      and tablename='customer_notifications') then
  alter publication supabase_realtime add table public.customer_notifications;
 end if;
end;
$publication$;
commit;
