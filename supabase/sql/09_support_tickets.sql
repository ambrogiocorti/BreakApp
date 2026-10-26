-- BreakApp 09 - Centro assistenza personale con messaggi e allegati immagine privati.
-- Ticket di gruppo e pagatori terzi saranno implementati dopo modello gruppi/ledger.
begin;

create table public.support_tickets(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete restrict,
 order_id uuid references public.orders(id) on delete restrict,
 order_item_id uuid references public.order_items(id) on delete restrict,
 owner_id uuid not null references auth.users(id) on delete restrict,
 request_key uuid not null,
 category text not null check(category in ('order','product','payment','service','other')),
 subject text not null check(char_length(btrim(subject)) between 4 and 160),
 status text not null default 'open' check(status in ('open','in_progress','awaiting_customer','resolved','closed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(owner_id,request_key)
);
create index support_tickets_owner on public.support_tickets(owner_id,created_at desc);
create index support_tickets_school_status on public.support_tickets(school_id,status,updated_at desc);
create index support_tickets_order on public.support_tickets(order_id);

create table public.support_messages(
 id uuid primary key default gen_random_uuid(),
 ticket_id uuid not null references public.support_tickets(id) on delete restrict,
 author_id uuid not null references auth.users(id) on delete restrict,
 body text not null check(char_length(btrim(body)) between 1 and 4000),
 created_at timestamptz not null default now()
);
create index support_messages_ticket on public.support_messages(ticket_id,created_at);

create table public.support_attachments(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete restrict,
 ticket_id uuid not null references public.support_tickets(id) on delete restrict,
 message_id uuid not null references public.support_messages(id) on delete restrict,
 uploader_id uuid not null references auth.users(id) on delete restrict,
 object_path text not null unique,
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
 size_bytes bigint not null check(size_bytes between 1 and 4194304),
 created_at timestamptz not null default now(),
 check(
   object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
   and split_part(object_path,'/',1)=school_id::text
   and split_part(object_path,'/',2)=ticket_id::text
 )
);
create index support_attachments_message on public.support_attachments(message_id);

create table public.support_reopen_requests(
 id uuid primary key default gen_random_uuid(),
 ticket_id uuid not null references public.support_tickets(id) on delete restrict,
 requester_id uuid not null references auth.users(id) on delete restrict,
 reason text not null check(char_length(btrim(reason)) between 8 and 1000),
 status text not null default 'pending' check(status in ('pending','approved','denied')),
 resolved_by uuid references auth.users(id) on delete restrict,
 requested_at timestamptz not null default now(),
 resolved_at timestamptz
);
create unique index support_reopen_one_pending on public.support_reopen_requests(ticket_id)
 where status='pending';

create table public.support_status_events(
 id bigint generated always as identity primary key,
 ticket_id uuid not null references public.support_tickets(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 event_type text not null,
 description text not null default '',
 created_at timestamptz not null default now()
);
create index support_status_events_by_ticket on public.support_status_events(ticket_id,created_at desc);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
alter table public.support_attachments enable row level security;
alter table public.support_reopen_requests enable row level security;
alter table public.support_status_events enable row level security;

revoke all on public.support_tickets,public.support_messages,public.support_attachments,
  public.support_reopen_requests,public.support_status_events from public,anon,authenticated;
grant select on public.support_tickets,public.support_messages,public.support_attachments,
  public.support_reopen_requests,public.support_status_events to authenticated;
grant insert(ticket_id,message_id,school_id,uploader_id,object_path,mime_type,size_bytes)
  on public.support_attachments to authenticated;

create or replace function app_private.can_manage_support_school(p_school uuid)
returns boolean language sql stable security definer set search_path=''
as $support_acl$
 select (select auth.uid()) is not null and (select auth.jwt()->>'aal')='aal2'
  and exists(select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id=m.id
    where m.school_id=p_school and m.user_id=(select auth.uid())
     and m.membership_status='active' and r.role_code='school_admin');
$support_acl$;
revoke all on function app_private.can_manage_support_school(uuid) from public,anon,authenticated;

create policy support_tickets_owner_or_admin on public.support_tickets
for select to authenticated using (
 owner_id=(select auth.uid()) or app_private.can_manage_support_school(school_id)
);
create policy support_messages_visible_for_ticket on public.support_messages
for select to authenticated using(
 exists(select 1 from public.support_tickets t where t.id=support_messages.ticket_id)
);
create policy support_attachments_visible_for_ticket on public.support_attachments
for select to authenticated using (
 exists(select 1 from public.support_tickets t
   where t.id=support_attachments.ticket_id and t.school_id=support_attachments.school_id)
);
create policy support_attachments_add_by_author on public.support_attachments
for insert to authenticated with check(
 uploader_id=(select auth.uid())
 and exists(select 1 from public.support_tickets t
   join public.support_messages m on m.ticket_id=t.id and m.id=support_attachments.message_id
   where t.id=support_attachments.ticket_id and t.school_id=support_attachments.school_id
     and t.status not in ('closed','resolved')
     and m.author_id=(select auth.uid()))
);
create policy support_reopen_visible on public.support_reopen_requests
for select to authenticated using(
 exists(select 1 from public.support_tickets t where t.id=support_reopen_requests.ticket_id)
);
create policy support_status_events_visible on public.support_status_events
for select to authenticated using(
 exists(select 1 from public.support_tickets t where t.id=support_status_events.ticket_id)
);

create or replace function public.open_support_ticket(
 p_school_id uuid,p_order_id uuid,p_order_item_id uuid,
 p_category text,p_subject text,p_message text,p_request_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $create_ticket$
declare v_user uuid:=auth.uid();v_id uuid;
begin
 if v_user is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' then
  raise exception 'È richiesto un account registrato';end if;
 if p_request_key is null or p_school_id is null or
    p_category not in ('order','product','payment','service','other') or
    char_length(btrim(coalesce(p_subject,''))) not between 4 and 160 or
    char_length(btrim(coalesce(p_message,''))) not between 1 and 4000 then
  raise exception 'Campi ticket non validi';end if;
 if not exists(select 1 from public.schools where id=p_school_id and is_active)
 then raise exception 'Scuola non disponibile';end if;
 if p_order_id is not null and not exists(
   select 1 from public.orders o where o.id=p_order_id
    and o.school_id=p_school_id and o.customer_id=v_user
 ) then raise exception 'Ordine non disponibile per il tuo account';end if;
 if p_order_item_id is not null and (
    p_order_id is null or not exists(
      select 1 from public.order_items i where i.id=p_order_item_id and i.order_id=p_order_id
    )) then raise exception 'Prodotto non appartenente all''ordine';end if;
 perform pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('support:'||v_user::text,1)
 );
 select id into v_id from public.support_tickets
  where owner_id=v_user and request_key=p_request_key;
 if found then return v_id;end if;
 if (select count(*) from public.support_tickets
    where owner_id=v_user and created_at>now()-interval '1 hour')>=5 or
    (select count(*) from public.support_tickets
     where owner_id=v_user and status in ('open','in_progress','awaiting_customer'))>=20 then
  raise exception 'Limite temporaneo di richieste raggiunto';end if;
 insert into public.support_tickets(school_id,order_id,order_item_id,
   owner_id,request_key,category,subject)
 values(p_school_id,p_order_id,p_order_item_id,v_user,p_request_key,p_category,btrim(p_subject))
 returning id into v_id;
 insert into public.support_messages(ticket_id,author_id,body)
 values(v_id,v_user,btrim(p_message));
 insert into public.support_status_events(ticket_id,actor_id,event_type)
 values(v_id,v_user,'opened');
 return v_id;
end;
$create_ticket$;

create or replace function public.post_support_message(
 p_ticket_id uuid,p_body text
) returns uuid language plpgsql security definer set search_path=''
as $message$
declare v_ticket public.support_tickets%rowtype;v_user uuid:=auth.uid();v_msg uuid;v_is_staff boolean;
begin
 if v_user is null or p_ticket_id is null or
   char_length(btrim(coalesce(p_body,''))) not between 1 and 4000 then
   raise exception 'Messaggio non valido';end if;
 select * into v_ticket from public.support_tickets
  where id=p_ticket_id for update;
 if not found then raise exception 'Ticket non disponibile';end if;
 v_is_staff:=app_private.can_manage_support_school(v_ticket.school_id);
 if v_ticket.owner_id<>v_user and not v_is_staff then
   raise exception 'Non autorizzato a scrivere su questo ticket';end if;
 if v_ticket.status in ('resolved','closed') then
  raise exception 'Il ticket è risolto o chiuso: richiedi una riapertura';end if;
 if (select count(*) from public.support_messages
   where author_id=v_user and created_at>now()-interval '10 minutes')>=30 then
  raise exception 'Limite temporaneo di messaggi raggiunto';end if;
 insert into public.support_messages(ticket_id,author_id,body)
 values(p_ticket_id,v_user,btrim(p_body)) returning id into v_msg;
 update public.support_tickets set updated_at=now(),status=
  case when v_is_staff and v_ticket.owner_id<>v_user then 'awaiting_customer'
       else 'in_progress' end where id=p_ticket_id;
 return v_msg;
end;
$message$;

create or replace function public.set_support_ticket_status(
 p_ticket_id uuid,p_status text,p_reason text default ''
) returns void language plpgsql security definer set search_path=''
as $status$
declare v_ticket public.support_tickets%rowtype;
begin
 if p_status not in ('open','in_progress','awaiting_customer','resolved','closed')
  or char_length(coalesce(p_reason,''))>1000 then
  raise exception 'Stato ticket non valido';end if;
 select * into v_ticket from public.support_tickets where id=p_ticket_id for update;
 if not found or not app_private.can_manage_support_school(v_ticket.school_id) then
  raise exception 'Solo un Admin autorizzato può modificare lo stato';end if;
 update public.support_tickets set status=p_status,updated_at=now() where id=p_ticket_id;
 insert into public.support_status_events(ticket_id,actor_id,event_type,description)
 values(p_ticket_id,auth.uid(),'status:'||p_status,coalesce(p_reason,''));
end;
$status$;

create or replace function public.request_support_reopen(
 p_ticket_id uuid,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $request_reopen$
declare v_ticket public.support_tickets%rowtype;v_id uuid;
begin
 if auth.uid() is null or char_length(btrim(coalesce(p_reason,''))) not between 8 and 1000
 then raise exception 'Motivazione di riapertura non valida';end if;
 select * into v_ticket from public.support_tickets where id=p_ticket_id for update;
 if not found or v_ticket.owner_id<>auth.uid() then
  raise exception 'Ticket non disponibile';end if;
 if v_ticket.status not in ('resolved','closed') then
  raise exception 'Solo i ticket conclusi possono richiedere riapertura';end if;
 select id into v_id from public.support_reopen_requests
  where ticket_id=p_ticket_id and status='pending';
 if found then return v_id;end if;
 insert into public.support_reopen_requests(ticket_id,requester_id,reason)
 values(p_ticket_id,auth.uid(),btrim(p_reason)) returning id into v_id;
 insert into public.support_status_events(ticket_id,actor_id,event_type,description)
 values(p_ticket_id,auth.uid(),'reopen_requested',btrim(p_reason));
 return v_id;
end;
$request_reopen$;

create or replace function public.review_support_reopen(
 p_request_id uuid,p_approve boolean,p_reason text default ''
) returns void language plpgsql security definer set search_path=''
as $review_reopen$
declare v_request public.support_reopen_requests%rowtype;v_ticket public.support_tickets%rowtype;
begin
 if p_approve is null or char_length(coalesce(p_reason,''))>1000 then
   raise exception 'Decisione non valida';end if;
 select * into v_request from public.support_reopen_requests where id=p_request_id for update;
 if not found or v_request.status<>'pending' then raise exception 'Richiesta non disponibile';end if;
 select * into v_ticket from public.support_tickets where id=v_request.ticket_id for update;
 if not app_private.can_manage_support_school(v_ticket.school_id) then
  raise exception 'Solo Admin autorizzato può decidere';end if;
 update public.support_reopen_requests set status=case when p_approve then 'approved' else 'denied' end,
  resolved_by=auth.uid(),resolved_at=now() where id=p_request_id;
 if p_approve then
  update public.support_tickets set status='open',updated_at=now() where id=v_ticket.id;
 end if;
 insert into public.support_status_events(ticket_id,actor_id,event_type,description)
 values(v_ticket.id,auth.uid(),
 case when p_approve then 'reopen_approved' else 'reopen_denied' end,coalesce(p_reason,''));
end;
$review_reopen$;

revoke all on function public.open_support_ticket(uuid,uuid,uuid,text,text,text,uuid),
 public.post_support_message(uuid,text),
 public.set_support_ticket_status(uuid,text,text),
 public.request_support_reopen(uuid,text),
 public.review_support_reopen(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.open_support_ticket(uuid,uuid,uuid,text,text,text,uuid),
 public.post_support_message(uuid,text),
 public.set_support_ticket_status(uuid,text,text),
 public.request_support_reopen(uuid,text),
 public.review_support_reopen(uuid,boolean,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('breakapp-ticket-images','breakapp-ticket-images',false,4194304,
 array['image/jpeg','image/png','image/webp']::text[])
on conflict(id) do update set public=false,
 file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy breakapp_tickets_private_select on storage.objects
for select to authenticated using(
 bucket_id='breakapp-ticket-images' and
 storage.objects.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
 and exists(select 1 from public.support_tickets t
   where t.school_id::text=split_part(storage.objects.name,'/',1)
     and t.id::text=split_part(storage.objects.name,'/',2))
);
create policy breakapp_tickets_private_insert on storage.objects
for insert to authenticated with check(
 bucket_id='breakapp-ticket-images'
 and storage.objects.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
 and exists(select 1 from public.support_tickets t
   where t.school_id::text=split_part(storage.objects.name,'/',1)
     and t.id::text=split_part(storage.objects.name,'/',2)
     and t.status not in ('resolved','closed'))
);
-- No delete/update: allegati immutabili finché non viene attivata retention amministrativa.

commit;
