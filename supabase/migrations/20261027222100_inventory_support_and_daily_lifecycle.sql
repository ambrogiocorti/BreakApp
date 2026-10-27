begin;
-- Private transaction-scoped authorization: browser-set GUCs cannot bypass stock.
create table app_private.stock_reconciliation_authorizations(
 transaction_id bigint not null,stock_id uuid not null references public.daily_stock(id),primary key(transaction_id,stock_id));
create index stock_reconciliation_by_stock on app_private.stock_reconciliation_authorizations(stock_id);
revoke all on app_private.stock_reconciliation_authorizations from public,anon,authenticated,service_role;
do $$declare c record;begin
 for c in select conname from pg_constraint where conrelid='public.daily_stock'::regclass and contype='c' and pg_get_constraintdef(oid) like '%allocated%' loop
  execute format('alter table public.daily_stock drop constraint %I',c.conname);end loop;
end;$$;
-- Extend the existing private image/thread/reopen machinery to group tickets.
alter table public.support_tickets add column group_id uuid references public.group_drafts(id),
 add column group_cart_item_id uuid references public.group_cart_items(id),
 add column payment_id uuid references public.payment_attempts(id),
 add column visibility text not null default 'personal' check(visibility in ('personal','group')),
 add constraint support_scope_exclusive check(group_id is null or order_id is null),
 add constraint support_shared_scope check(visibility='personal' or (group_id is not null and group_cart_item_id is null and payment_id is null));
create index support_group on public.support_tickets(group_id);
create index support_group_item on public.support_tickets(group_cart_item_id);
create index support_payment on public.support_tickets(payment_id);
create function app_private.can_read_support(p_ticket uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.support_tickets t where t.id=p_ticket and
 (t.owner_id=(select auth.uid()) or app_private.can_manage_support_school(t.school_id) or
 (t.visibility='group' and exists(select 1 from public.group_members m where m.group_id=t.group_id and m.user_id=(select auth.uid()) and m.status='accepted'))));
$$;
revoke all on function app_private.can_read_support(uuid) from public,anon,authenticated;
grant execute on function app_private.can_read_support(uuid) to authenticated;
drop policy support_tickets_owner_or_admin on public.support_tickets;
create policy support_ticket_visible on public.support_tickets for select to authenticated using(app_private.can_read_support(id));
create function public.open_group_support_ticket(p_group uuid,p_visibility text,p_line uuid,p_payment uuid,p_subject text,p_message text,p_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare g public.group_drafts%rowtype;v_id uuid;t public.support_tickets%rowtype;begin
 if auth.uid() is null or p_visibility is null or p_visibility not in ('personal','group') then raise exception 'Accesso e visibilità obbligatori';end if;
 select * into g from public.group_drafts where id=p_group;
 if not found then raise exception 'Gruppo non disponibile';end if;
 if p_visibility='group' and (p_line is not null or p_payment is not null) then raise exception 'I riferimenti personali richiedono un ticket privato';end if;
 if p_payment is not null then
  if not exists(select 1 from public.payment_attempts where id=p_payment and group_id=p_group and payer_id=auth.uid()) then raise exception 'Pagamento non appartenente al tuo account';end if;
 elsif not exists(select 1 from public.group_members where group_id=p_group and user_id=auth.uid() and status='accepted') then raise exception 'Partecipazione al gruppo richiesta';end if;
 if p_line is not null and not exists(select 1 from public.group_cart_items where id=p_line and group_id=p_group and user_id=auth.uid()) then raise exception 'Puoi riferirti soltanto ai tuoi prodotti';end if;
 select * into t from public.support_tickets where owner_id=auth.uid() and request_key=p_key;
 if found then
  if t.group_id is distinct from p_group or t.visibility<>p_visibility or t.group_cart_item_id is distinct from p_line or t.payment_id is distinct from p_payment then raise exception 'Chiave già utilizzata per un altro ticket';end if;return t.id;end if;
 v_id:=public.open_support_ticket(g.school_id,null,null,case when p_payment is null then 'order' else 'payment' end,p_subject,p_message,p_key);
 update public.support_tickets set group_id=p_group,visibility=p_visibility,group_cart_item_id=p_line,payment_id=p_payment where id=v_id;
 return v_id;
end;$$;
revoke all on function public.open_group_support_ticket(uuid,text,uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.open_group_support_ticket(uuid,text,uuid,uuid,text,text,uuid) to authenticated;
do $$declare d text;begin
 d:=pg_get_functiondef('public.post_support_message(uuid,text)'::regprocedure);
 d:=replace(d,'v_ticket.owner_id<>v_user and not v_is_staff','not app_private.can_read_support(v_ticket.id)');execute d;
 d:=pg_get_functiondef('public.request_support_reopen(uuid,text)'::regprocedure);
 d:=replace(d,'v_ticket.owner_id<>auth.uid()','not app_private.can_read_support(v_ticket.id)');execute d;
end;$$;
create or replace function app_private.notify_support_reply()
returns trigger language plpgsql security definer set search_path='' as $$
declare t public.support_tickets%rowtype;begin
 select * into t from public.support_tickets where id=new.ticket_id;
 if t.visibility='group' then
  insert into public.customer_notifications(school_id,user_id,ticket_id,event_type,message)
   select t.school_id,user_id,t.id,'support_reply','Nuovo messaggio nel ticket condiviso del gruppo: '||t.subject
   from public.group_members where group_id=t.group_id and status='accepted' and user_id<>new.author_id;
 elsif t.owner_id<>new.author_id then
  insert into public.customer_notifications(school_id,user_id,ticket_id,event_type,message)
  values(t.school_id,t.owner_id,t.id,'support_reply','Nuova risposta al ticket: '||t.subject);
 end if;return new;end;$$;
alter table public.daily_stock add constraint daily_stock_allocated_nonnegative check(allocated>=0);
create function app_private.guard_reconciled_stock()
returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.capacity is not null and new.allocated>new.capacity
  and (tg_op='INSERT' or new.allocated>old.allocated or new.capacity is distinct from old.capacity)
  and not exists(select 1 from app_private.stock_reconciliation_authorizations where transaction_id=txid_current() and stock_id=new.id)
 then raise exception 'Scorte insufficienti; la conta fisica sotto il prenotato richiede riconciliazione motivata';end if;
 return new;end;$$;
revoke all on function app_private.guard_reconciled_stock() from public,anon,authenticated,service_role;
create trigger stock_capacity_integrity before insert or update on public.daily_stock for each row execute function app_private.guard_reconciled_stock();
create table public.stock_shortages(
 id uuid primary key default gen_random_uuid(),stock_id uuid not null references public.daily_stock(id),
 school_id uuid not null references public.schools(id),actor_id uuid not null references auth.users(id),
 previous_capacity integer,physical_capacity integer not null,allocated integer not null,
 reason text not null,created_at timestamptz not null default now());
create index shortages_stock on public.stock_shortages(stock_id,created_at desc);
create index shortages_school on public.stock_shortages(school_id);
create index shortages_actor on public.stock_shortages(actor_id);
alter table public.stock_shortages enable row level security;
revoke all on public.stock_shortages from public,anon,authenticated;
create function app_private.record_stock_shortage(p_stock uuid,p_reason text)
returns integer language plpgsql security definer set search_path='' as $$
declare s public.daily_stock%rowtype;r record;v_active integer;v_available integer;v_short uuid;v_count integer:=0;j jsonb;v_at timestamptz;
begin
 select * into s from public.daily_stock where id=p_stock for update;
 if s.capacity is null or s.allocated<=s.capacity then return 0;end if;
 insert into public.stock_shortages(stock_id,school_id,actor_id,previous_capacity,physical_capacity,allocated,reason)
 values(s.id,s.school_id,auth.uid(),null,s.capacity,s.allocated,p_reason) returning id into v_short;
 select coalesce(sum(q.quantity),0) into v_active from(
  select i.quantity from public.order_items i join public.orders o on o.id=i.order_id join public.pickup_windows w on w.id=o.pickup_window_id
  where i.product_id=s.product_id and i.removed_at is null and o.bar_id=s.bar_id and w.service_date=s.service_date and o.stock_reserved and o.status in ('confirmed','preparing','ready','approval_active')
  union all select i.quantity from public.group_order_lines i join public.group_orders o on o.id=i.group_order_id join public.pickup_windows w on w.id=o.pickup_window_id
  where i.product_id=s.product_id and o.bar_id=s.bar_id and w.service_date=s.service_date and o.stock_reserved and o.status in ('confirmed','preparing','ready','approval_active')) q;
 v_available:=greatest(0,s.capacity-(s.allocated-v_active));
 for r in select * from(
  select 'individual'::text kind,o.id order_id,i.id line_id,i.quantity,o.created_at,w.starts_at,o.customer_id owner_id,(w.service_date+w.starts_at) at time zone sc.timezone pickup_at
   from public.order_items i join public.orders o on o.id=i.order_id join public.pickup_windows w on w.id=o.pickup_window_id join public.schools sc on sc.id=o.school_id
   where i.product_id=s.product_id and i.removed_at is null and o.bar_id=s.bar_id and w.service_date=s.service_date and o.stock_reserved and o.status in ('confirmed','preparing','ready','approval_active')
  union all select 'group',o.id,i.id,i.quantity,o.created_at,w.starts_at,o.coordinator_id,(w.service_date+w.starts_at) at time zone sc.timezone
   from public.group_order_lines i join public.group_orders o on o.id=i.group_order_id join public.pickup_windows w on w.id=o.pickup_window_id join public.schools sc on sc.id=o.school_id
   where i.product_id=s.product_id and i.quantity>0 and o.bar_id=s.bar_id and w.service_date=s.service_date and o.stock_reserved and o.status in ('confirmed','preparing','ready','approval_active')) q order by starts_at,created_at,order_id,line_id loop
  if v_available>=r.quantity then v_available:=v_available-r.quantity;continue;end if;
  -- Preserve earlier pickup priority; offer the entire affected line explicitly.
  v_available:=0;
  if exists(select 1 from public.order_approvals where (order_id=r.order_id or group_order_id=r.order_id) and state='active') then
   perform app_private.end_approval((select id from public.order_approvals where order_id=r.order_id or group_order_id=r.order_id),'rejected','Scorta fisica insufficiente: priorità agli ordini confermati e alla fascia di ritiro');continue;end if;
  if exists(select 1 from public.order_change_requests c where (c.order_id=r.order_id or c.group_order_id=r.order_id) and c.kind='substitution' and c.state='customer_pending' and c.payload->>'line_id'=r.line_id::text) then continue;end if;
  insert into public.order_change_requests(school_id,order_id,group_order_id,actor_id,owner_id,kind,state,payload,request_key,expires_at)
  values(s.school_id,case when r.kind='individual' then r.order_id end,case when r.kind='group' then r.order_id end,auth.uid(),r.owner_id,'substitution','customer_pending',
   jsonb_build_object('line_id',r.line_id,'quantity',r.quantity,'remove_only',true,'unavailable',true,'shortage_id',v_short),gen_random_uuid(),greatest(now(),r.pickup_at));
  perform app_private.notify_order_change(r.kind,r.order_id,'Un articolo manca alla conta fisica. Il personale può proporre un sostituto; in assenza di accordo al ritiro verrà rimosso con rimborso al pagatore originale.');
  v_count:=v_count+1;
 end loop;
 return v_count;
end;$$;
revoke all on function app_private.record_stock_shortage(uuid,text) from public,anon,authenticated,service_role;
create or replace function public.resolve_offline_stock_conflict(
 p_conflict uuid,p_new_capacity integer,p_reason text
) returns jsonb language plpgsql security definer set search_path=''
as $resolve_stock$
declare v_conflict public.offline_stock_conflicts%rowtype;
 v_stock public.daily_stock%rowtype;v_user uuid:=auth.uid();
 v_units integer;v_affected integer;
begin
 if p_conflict is null or p_new_capacity is null or p_new_capacity<0 or
  length(btrim(coalesce(p_reason,''))) not between 10 and 500
 then raise exception 'Riconciliazione motivata e stock fisico obbligatori';end if;
 select * into v_conflict from public.offline_stock_conflicts where id=p_conflict;
 if not found or v_conflict.status<>'open'
 then raise exception 'Conflitto già risolto o inesistente';end if;
 if not exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=v_conflict.school_id and m.user_id=v_user
   and m.membership_status='active' and r.role_code in
   ('school_admin','warehouse_manager','bartender') and (r.role_code<>'school_admin' or auth.jwt()->>'aal'='aal2'))
 then raise exception 'Solo personale della scuola può riconciliare';end if;
 select * into v_stock from public.daily_stock where
  school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
  and product_id=v_conflict.product_id and service_date=v_conflict.service_date
  for update;
 if not found then raise exception 'Scorta non inizializzata: occorre inventario fisico';end if;
 -- Resolve *all* conflicts for the same product/date in one transaction.
 -- Their physical cash sales already happened: preserve reservation priority.
 perform id from public.offline_stock_conflicts
  where school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
   and product_id=v_conflict.product_id and service_date=v_conflict.service_date
   and status='open' for update;
 select count(*),coalesce(sum(sold_quantity),0)
 into v_affected,v_units from public.offline_stock_conflicts
 where school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
   and product_id=v_conflict.product_id and service_date=v_conflict.service_date
   and status='open';

 insert into public.offline_stock_conflict_audit(
  conflict_id,actor_id,previous_capacity,new_capacity,previous_allocated,reason)
 select c.id,v_user,v_stock.capacity,p_new_capacity,v_stock.allocated,btrim(p_reason)
 from public.offline_stock_conflicts c
 where c.school_id=v_conflict.school_id and c.bar_id=v_conflict.bar_id
  and c.product_id=v_conflict.product_id and c.service_date=v_conflict.service_date
  and c.status='open';
 update public.offline_stock_conflicts set status='resolved',
  resolved_by=v_user,resolved_at=now(),resolution_reason=btrim(p_reason)
 where school_id=v_conflict.school_id and bar_id=v_conflict.bar_id
  and product_id=v_conflict.product_id and service_date=v_conflict.service_date
  and status='open';
 insert into app_private.stock_reconciliation_authorizations values(txid_current(),v_stock.id);
 update public.daily_stock set capacity=p_new_capacity,
  allocated=allocated+v_units,updated_at=now() where id=v_stock.id;
 delete from app_private.stock_reconciliation_authorizations where transaction_id=txid_current() and stock_id=v_stock.id;
 perform app_private.record_stock_shortage(v_stock.id,btrim(p_reason));
 return jsonb_build_object('status','resolved','capacity',p_new_capacity,
  'physical_sales_accounted',v_units,'conflicts_resolved',v_affected);
end;$resolve_stock$;

create table app_private.stock_reconciliation_log(
 id bigint generated always as identity primary key,stock_id uuid not null references public.daily_stock(id),actor_id uuid not null references auth.users(id),
 old_capacity integer,new_capacity integer,allocated integer not null,reason text not null,recorded_at timestamptz not null default now());
create index stock_reconciliation_log_stock on app_private.stock_reconciliation_log(stock_id);
create index stock_reconciliation_log_actor on app_private.stock_reconciliation_log(actor_id);
revoke all on app_private.stock_reconciliation_log from public,anon,authenticated,service_role;
create function public.reconcile_physical_stock(p_stock uuid,p_capacity integer,p_reason text)
returns integer language plpgsql security definer set search_path='' as $$
declare s public.daily_stock%rowtype;n integer;begin
 select * into s from public.daily_stock where id=p_stock for update;
 if not found or not (app_private.can_serve_group_bar(s.school_id) or exists(select 1 from public.school_memberships m join public.role_assignments a on a.membership_id=m.id where m.school_id=s.school_id and m.user_id=auth.uid() and m.membership_status='active' and a.role_code='warehouse_manager')) then raise exception 'Personale della scuola richiesto';end if;
 if p_capacity is null or p_capacity<0 or length(btrim(coalesce(p_reason,''))) not between 10 and 500 then raise exception 'Conta fisica e motivazione obbligatorie';end if;
 insert into app_private.stock_reconciliation_authorizations values(txid_current(),s.id);
 update public.daily_stock set capacity=p_capacity,updated_at=now() where id=s.id;
 delete from app_private.stock_reconciliation_authorizations where transaction_id=txid_current() and stock_id=s.id;
 insert into app_private.stock_reconciliation_log(stock_id,actor_id,old_capacity,new_capacity,allocated,reason) values(s.id,auth.uid(),s.capacity,p_capacity,s.allocated,p_reason);
 n:=app_private.record_stock_shortage(s.id,p_reason);
 update public.stock_shortages set previous_capacity=s.capacity where stock_id=s.id and actor_id=auth.uid() and created_at=now();return n;
end;$$;
revoke all on function public.reconcile_physical_stock(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.reconcile_physical_stock(uuid,integer,text) to authenticated;
-- A proven unavailable product is not prepared waste and must release allocation.
do $$declare d text;begin
 d:=pg_get_functiondef('app_private.apply_order_substitution(uuid,boolean)'::regprocedure);
 d:=replace(d,$patch$ if not p_remove then
  if not exists$patch$, $patch$ if not p_remove and coalesce((c.payload->>'remove_only')::boolean,false) then raise exception 'Scegli la rimozione oppure attendi una proposta di sostituzione';end if;
 if not p_remove then
  if not exists$patch$);
 d:=replace(d,$patch$ if j->>'status'='confirmed' or$patch$, $patch$ if coalesce((c.payload->>'unavailable')::boolean,false) or j->>'status'='confirmed' or$patch$);execute d;
 d:=pg_get_functiondef('public.propose_order_exception(text,uuid,text,uuid,uuid,uuid,uuid)'::regprocedure);
 d:=replace(d,$patch$  select * into p from public.products$patch$, $patch$  if exists(select 1 from public.order_change_requests c where (c.order_id=p_order or c.group_order_id=p_order) and c.kind='substitution' and c.state='customer_pending' and c.payload->>'line_id'=p_line::text and coalesce((c.payload->>'unavailable')::boolean,false)) then
   update public.order_change_requests set state='rejected',resolved_at=now() where (order_id=p_order or group_order_id=p_order) and kind='substitution' and state='customer_pending' and payload->>'line_id'=p_line::text;
  end if;
  select * into p from public.products$patch$);
 d:=replace(d,$patch$'allergens',p.allergens);$patch$, $patch$'allergens',p.allergens,'unavailable',exists(select 1 from public.order_change_requests c where (c.order_id=p_order or c.group_order_id=p_order) and c.payload->>'line_id'=p_line::text and coalesce((c.payload->>'unavailable')::boolean,false)));$patch$);execute d;
end;$$;
-- Daily closing settles no-shows without returning perishable stock.
alter table public.schools add column no_show_penalty_minutes integer not null default 0 check(no_show_penalty_minutes between 0 and 10080);
create table public.order_no_shows(
 id uuid primary key default gen_random_uuid(),school_id uuid not null references public.schools(id),
 order_id uuid unique references public.orders(id),group_order_id uuid unique references public.group_orders(id),
 accountable_user_id uuid not null references auth.users(id),penalty_until timestamptz,
 recorded_at timestamptz not null default now(),check((order_id is null)<>(group_order_id is null)));
create index no_show_school on public.order_no_shows(school_id);
create index no_show_user on public.order_no_shows(accountable_user_id,penalty_until);
alter table public.order_no_shows enable row level security;
revoke all on public.order_no_shows from public,anon,authenticated;
create function app_private.check_no_show_booking()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_user uuid;begin
 v_user:=case when tg_table_name='orders' then to_jsonb(new)->>'customer_id' else to_jsonb(new)->>'coordinator_id' end;
 if exists(select 1 from public.order_no_shows where school_id=new.school_id and accountable_user_id=v_user and penalty_until>now()) then
  raise exception 'Prenotazioni temporaneamente sospese secondo la politica no-show della scuola';end if;
 return new;end;$$;
revoke all on function app_private.check_no_show_booking() from public,anon,authenticated,service_role;
create trigger individual_no_show_policy before insert on public.orders for each row execute function app_private.check_no_show_booking();
create trigger group_no_show_policy before insert on public.group_drafts for each row execute function app_private.check_no_show_booking();
create function public.set_no_show_policy(p_school uuid,p_minutes integer)
returns void language plpgsql security definer set search_path='' as $$begin
 if not app_private.can_manage_support_school(p_school) or p_minutes is null or p_minutes not between 0 and 10080 then raise exception 'Admin con 2FA e durata valida richiesti';end if;
 update public.schools set no_show_penalty_minutes=p_minutes where id=p_school;
end;$$;
revoke all on function public.set_no_show_policy(uuid,integer) from public,anon,authenticated;
grant execute on function public.set_no_show_policy(uuid,integer) to authenticated;
create function public.maintain_daily_orders(p_clock timestamptz default now())
returns integer language plpgsql security definer set search_path='' as $$
declare r record;j jsonb;v_paid bigint;v_user uuid;v_minutes integer;v_guest boolean;v_count integer:=0;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo backend';end if;
 for r in select * from(
  select 'individual'::text kind,o.id,w.service_date,w.bar_id,w.school_id,s.timezone,o.created_at
  from public.orders o join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id where o.status in ('confirmed','preparing','ready')
  union all select 'group',o.id,w.service_date,w.bar_id,w.school_id,s.timezone,o.created_at
  from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id where o.status in ('confirmed','preparing','ready')) q
 where coalesce((select (q.service_date+max(h.ends_at)) at time zone q.timezone from public.bar_opening_hours h where h.bar_id=q.bar_id and h.weekday=extract(dow from q.service_date)::int),
  (q.service_date+1)::timestamp at time zone q.timezone)<=p_clock
 order by service_date,created_at,id limit 200 loop
  j:=app_private.order_scope(r.kind,r.id,'internal');
  if j->>'status' not in ('confirmed','preparing','ready') then continue;end if;
  -- Staged physical pickups require review, never automatic refund/no-show.
  if exists(select 1 from public.offline_events_inbox e where e.status in ('quarantined','approved') and e.event_kind=case when r.kind='group' then 'group_pickup' else 'cash_pickup' end and e.payload->>'order_id'=r.id::text) then continue;end if;
  v_paid:=app_private.order_paid_cents(r.kind,r.id);v_user:=(j->>'owner_id')::uuid;
  select no_show_penalty_minutes into v_minutes from public.schools where id=r.school_id;
  v_guest:=exists(select 1 from app_private.guest_access_keys where user_id=v_user);
  insert into public.order_no_shows(school_id,order_id,group_order_id,accountable_user_id,penalty_until)
  values(r.school_id,case when r.kind='individual' then r.id end,case when r.kind='group' then r.id end,v_user,
   case when not v_guest and v_minutes>0 then p_clock+make_interval(mins=>v_minutes) end) on conflict do nothing;
  if r.kind='individual' then update public.orders set status='no_show',stock_reserved=false,updated_at=now() where id=r.id;
  else update public.group_orders set status='no_show',stock_reserved=false,pickup_lease_until=null,pickup_lease_actor=null,updated_at=now() where id=r.id;
   update public.order_supplements set state='cancelled' where group_order_id=r.id and state='available';end if;
  perform app_private.refund_order_credit(r.kind,r.id,null,v_paid,r.id,'Ordine non ritirato alla chiusura: rimborso ai pagatori originali');
  perform app_private.notify_order_change(r.kind,r.id,'Ordine non ritirato alla chiusura. Eventuali rimborsi sono in elaborazione; i prodotti non tornano automaticamente disponibili.');
  v_count:=v_count+1;
 end loop;
 -- Remove stale QR payloads only after every staged event is resolved.
 update app_private.offline_manifests m set payload='{"orders":[]}' where m.issued_at<now()-interval '90 days' and m.payload<>'{"orders":[]}'::jsonb
  and not exists(select 1 from public.offline_events_inbox e where e.payload->>'snapshot_id'=m.id::text and e.status in ('quarantined','approved'));
 return v_count;
end;$$;
revoke all on function public.maintain_daily_orders(timestamptz) from public,anon,authenticated;
grant execute on function public.maintain_daily_orders(timestamptz) to service_role;
create policy schools_platform_directory on public.schools for select to authenticated using(app_private.platform_approved());
-- Disable guest promotion to staff through the older platform endpoint as well.
do $$declare d text;begin
 d:=pg_get_functiondef('public.platform_assign_school_staff(uuid,text,text)'::regprocedure);
 d:=replace(d,'if exists(select 1 from app_private.platform_admins pa where pa.user_id=v_target)', 'if exists(select 1 from app_private.guest_access_keys where user_id=v_target) or exists(select 1 from app_private.platform_admins pa where pa.user_id=v_target)');execute d;
end;$$;
create function public.my_support_group_references()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb;begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into j from(select g.id,g.school_id,g.title,
  coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.product_name,'quantity',i.quantity)) from public.group_cart_items i where i.group_id=g.id and i.user_id=auth.uid()),'[]'::jsonb) lines,
  coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'amount_cents',p.amount_cents,'status',p.status)) from public.payment_attempts p where p.group_id=g.id and p.payer_id=auth.uid()),'[]'::jsonb) payments
 from public.group_drafts g where exists(select 1 from public.group_members m where m.group_id=g.id and m.user_id=auth.uid() and m.status='accepted')
 or exists(select 1 from public.payment_attempts p where p.group_id=g.id and p.payer_id=auth.uid()) order by g.updated_at desc limit 100) q;
 return j;end;$$;
revoke all on function public.my_support_group_references() from public,anon,authenticated;
grant execute on function public.my_support_group_references() to authenticated;
create function public.request_completed_order_refund(p_kind text,p_order uuid,p_key uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;v_paid bigint;outcome jsonb;begin
 j:=app_private.order_scope(p_kind,p_order,'internal');
 if not app_private.can_manage_support_school((j->>'school_id')::uuid) or p_key is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then raise exception 'Admin scuola con 2FA e motivazione richiesti';end if;
 if j->>'status' not in ('delivered','no_show') then raise exception 'Il rimborso amministrativo richiede un ordine concluso';end if;
 perform app_private.assert_no_pending_checkout(p_kind,p_order);
 v_paid:=app_private.order_paid_cents(p_kind,p_order);
 perform app_private.refund_order_credit(p_kind,p_order,null,v_paid,p_key,p_reason);
 select coalesce(jsonb_agg(jsonb_build_object('refund_id',r.id,'account',a.stripe_account_id,'payment_intent',a.stripe_payment_intent_id,'amount_cents',r.amount_cents,'status',r.status)),'[]'::jsonb)
 into outcome from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id where r.request_key=p_key;
 if outcome='[]'::jsonb and not exists(select 1 from public.cash_refund_obligations where request_key=p_key) then raise exception 'Nessun importo residuo da rimborsare';end if;
 perform app_private.notify_order_change(p_kind,p_order,'Rimborso amministrativo richiesto: importi online in elaborazione ai pagatori originali; eventuali contanti devono essere restituiti fisicamente.');
 return jsonb_build_object('online',outcome,'cash_pending',coalesce((select sum(amount_cents) from public.cash_refund_obligations where request_key=p_key),0));
end;$$;
revoke all on function public.request_completed_order_refund(text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.request_completed_order_refund(text,uuid,uuid,text) to authenticated;
create or replace function public.request_full_individual_stripe_refund(p_order_id uuid,p_request_key uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;begin
 j:=public.request_completed_order_refund('individual',p_order_id,p_request_key,p_reason);
 if jsonb_array_length(j->'online')=0 then raise exception 'Nessun pagamento Stripe residuo; verifica la restituzione fisica';end if;
 return (j->'online'->0)||jsonb_build_object('additional_refunds',greatest(0,jsonb_array_length(j->'online')-1));end;$$;
commit;
