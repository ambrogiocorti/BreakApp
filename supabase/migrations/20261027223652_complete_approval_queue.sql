begin;
alter table public.schools add column max_active_approvals integer not null default 3
 check(max_active_approvals between 1 and 30);
alter table public.orders add column stock_reserved boolean not null default true;
alter table public.group_orders add column stock_reserved boolean not null default true;
alter table public.orders drop constraint orders_status_check;
alter table public.orders add constraint orders_status_check check(status in
 ('confirmed','preparing','ready','delivered','cancelled','no_show','approval_queued','approval_active','awaiting_reschedule'));
alter table public.group_orders drop constraint group_orders_status_check;
alter table public.group_orders add constraint group_orders_status_check check(status in
 ('confirmed','preparing','ready','delivered','cancelled','no_show','approval_queued','approval_active','awaiting_reschedule'));
alter table public.group_drafts drop constraint group_drafts_status_check;
alter table public.group_drafts add constraint group_drafts_status_check
 check(status in ('draft','expired','cancelled','confirmed','approval_pending'));
create table public.staff_service_presence(
 user_id uuid not null references auth.users(id) on delete cascade,
 school_id uuid not null references public.schools(id) on delete cascade,
 bar_id uuid not null references public.bars(id) on delete cascade,
 valid_until timestamptz not null,primary key(user_id,bar_id)
);
create index presence_bar on public.staff_service_presence(bar_id,valid_until);
create index presence_school on public.staff_service_presence(school_id);
create table public.order_approvals(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),bar_id uuid not null references public.bars(id),
 order_id uuid unique references public.orders(id),group_order_id uuid unique references public.group_orders(id),
 owner_id uuid not null references auth.users(id),pickup_window_id uuid not null references public.pickup_windows(id),
 state text not null default 'queued' check(state in ('queued','active','awaiting_reschedule','approved','rejected','expired','cancelled')),
 lease_until timestamptz,response_until timestamptz,
 decision_by uuid references auth.users(id),reason text not null default '',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check((order_id is null)<>(group_order_id is null))
);
create index approvals_bar_queue on public.order_approvals(bar_id,state,created_at);
create index approvals_school on public.order_approvals(school_id);
create index approvals_owner on public.order_approvals(owner_id);
create index approvals_window on public.order_approvals(pickup_window_id);
create index approvals_decision_actor on public.order_approvals(decision_by);
alter table public.staff_service_presence enable row level security;
alter table public.order_approvals enable row level security;
revoke all on public.staff_service_presence,public.order_approvals from public,anon,authenticated;

create function app_private.order_scope(p_kind text,p_id uuid,p_access text default 'owner')
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if p_kind='individual' then
  select jsonb_build_object('id',id,'school_id',school_id,'bar_id',bar_id,'owner_id',customer_id,
   'window_id',pickup_window_id,'status',status,'total_cents',total_cents,'stock_reserved',stock_reserved,
   'group_id',null,'payment_status',payment_status) into j from public.orders where id=p_id for update;
 elsif p_kind='group' then
  select jsonb_build_object('id',id,'school_id',school_id,'bar_id',bar_id,'owner_id',coordinator_id,
   'window_id',pickup_window_id,'status',status,'total_cents',total_cents,'stock_reserved',stock_reserved,
   'group_id',group_id) into j from public.group_orders where id=p_id for update;
 else raise exception 'Tipo ordine non valido';end if;
 if j is null then raise exception 'Ordine non disponibile';end if;
 if p_access='internal' then return j;end if;
 if auth.uid() is null or p_access not in ('owner','staff','either') then raise exception 'Accesso non valido';end if;
 if (p_access in ('owner','either') and (j->>'owner_id')::uuid=auth.uid()) or
  (p_access in ('staff','either') and app_private.can_serve_group_bar((j->>'school_id')::uuid))
 then return j;end if;
 raise exception 'Non autorizzato a questo ordine';
end;$$;
revoke all on function app_private.order_scope(text,uuid,text) from public,anon,authenticated,service_role;
create function app_private.order_lines(p_kind text,p_id uuid)
returns table(line_id uuid,product_id uuid,quantity integer,unit_cents integer,beneficiary_id uuid,cart_id uuid)
language sql stable set search_path='' as $$
 select i.id,i.product_id,i.quantity,i.unit_cents,o.customer_id,null::uuid from public.order_items i
 join public.orders o on o.id=i.order_id where p_kind='individual' and i.order_id=p_id
 union all select i.id,i.product_id,i.quantity,i.unit_cents,i.beneficiary_id,i.group_cart_item_id
 from public.group_order_lines i where p_kind='group' and i.group_order_id=p_id;
$$;
revoke all on function app_private.order_lines(text,uuid) from public,anon,authenticated,service_role;
create function app_private.window_bookable(p_window uuid,p_bar uuid,p_clock timestamptz)
returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.pickup_windows w join public.schools s on s.id=w.school_id
 join public.bars b on b.id=w.bar_id where w.id=p_window and w.bar_id=p_bar and w.is_active
 and s.is_active and b.is_active and (w.service_date+w.starts_at) at time zone s.timezone>p_clock
 and w.service_date<=(p_clock at time zone s.timezone)::date+s.booking_horizon_days
 and exists(select 1 from public.bar_opening_hours h where h.bar_id=w.bar_id
  and h.weekday=extract(dow from w.service_date) and h.starts_at<=w.starts_at and h.ends_at>=w.ends_at)
 and not exists(select 1 from public.bar_closures c where c.bar_id=w.bar_id and c.service_date=w.service_date
  and c.reopened_at is null and c.starts_at<w.ends_at and c.ends_at>w.starts_at));
$$;
revoke all on function app_private.window_bookable(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;

create function app_private.refund_order_online(p_kind text,p_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare x record;v_remaining bigint;
begin
 if p_kind='group' then
  perform app_private.queue_group_line_refund(l.cart_id,p_reason) from app_private.order_lines(p_kind,p_id) l;
 else
  for x in select * from public.payment_attempts where order_id=p_id and status='succeeded' order by id for update loop
   select x.amount_cents-coalesce(sum(amount_cents) filter(where status in ('pending','processing','review','succeeded')),0)
   into v_remaining from public.payment_refunds where payment_id=x.id;
   if v_remaining>0 then
    insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason)
    values(x.id,p_id,v_remaining,'pending',left(p_reason,300)) on conflict(payment_id,request_key) do nothing;
   end if;
  end loop;
 end if;
end;$$;
revoke all on function app_private.refund_order_online(text,uuid,text) from public,anon,authenticated,service_role;

create function app_private.release_order_stock(p_kind text,p_id uuid,p_preserve_prepared boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;x record;v_date date;
begin
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if not (j->>'stock_reserved')::boolean then return;end if;
 select service_date into v_date from public.pickup_windows where id=(j->>'window_id')::uuid;
 if not (p_preserve_prepared and j->>'status' in ('preparing','ready','delivered','no_show')) then
  for x in select product_id,sum(quantity)::integer quantity from app_private.order_lines(p_kind,p_id)
   group by product_id order by product_id loop
   update public.daily_stock set allocated=allocated-x.quantity,updated_at=now()
   where bar_id=(j->>'bar_id')::uuid and product_id=x.product_id and service_date=v_date and allocated>=x.quantity;
   if not found then raise exception 'Scorte da riconciliare prima del rilascio';end if;
  end loop;
 end if;
 if p_kind='individual' then update public.orders set stock_reserved=false where id=p_id;
 else update public.group_orders set stock_reserved=false where id=p_id;end if;
end;$$;
revoke all on function app_private.release_order_stock(text,uuid,boolean) from public,anon,authenticated,service_role;

create function app_private.end_approval(p_approval uuid,p_state text,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare a public.order_approvals%rowtype;k text;v_id uuid;j jsonb;
begin
 select * into a from public.order_approvals where id=p_approval for update;
 if a.state not in ('queued','active','awaiting_reschedule') then return;end if;
 k:=case when a.order_id is null then 'group' else 'individual' end;v_id:=coalesce(a.order_id,a.group_order_id);
 j:=app_private.order_scope(k,v_id,'internal');
 perform app_private.release_order_stock(k,v_id,false);
 if k='individual' then update public.orders set status='cancelled',updated_at=now() where id=v_id;
 else update public.group_orders set status='cancelled',updated_at=now() where id=v_id;
  update public.group_drafts set status='cancelled',updated_at=now() where id=(j->>'group_id')::uuid;end if;
 perform app_private.refund_order_online(k,v_id,p_reason);
 update public.order_approvals set state=p_state,lease_until=null,response_until=null,
  reason=left(p_reason,500),decision_by=auth.uid(),updated_at=now() where id=a.id;
 insert into public.customer_notifications(school_id,user_id,order_id,group_id,event_type,message)
 values(a.school_id,a.owner_id,a.order_id,(j->>'group_id')::uuid,'order_status',
  'Richiesta grande ordine terminata: '||p_reason||'. Gli eventuali rimborsi sono avviati verso i pagatori originali.');
end;$$;
revoke all on function app_private.end_approval(uuid,text,text) from public,anon,authenticated,service_role;

create function app_private.process_approval_queue(p_bar uuid,p_clock timestamptz default now())
returns integer language plpgsql security definer set search_path='' as $$
declare a public.order_approvals%rowtype;w public.pickup_windows%rowtype;nw uuid;x record;
 k text;v_id uuid;v_active integer;v_max integer;v_available boolean;v_count integer:=0;s public.daily_stock%rowtype;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('approval:'||p_bar::text,0)) then return 0;end if;
 select sc.max_active_approvals into v_max from public.schools sc join public.bars b on b.school_id=sc.id where b.id=p_bar;
 for a in select * from public.order_approvals where bar_id=p_bar and state in ('queued','active','awaiting_reschedule')
  order by id for update skip locked loop
  k:=case when a.order_id is null then 'group' else 'individual' end;v_id:=coalesce(a.order_id,a.group_order_id);
  if (a.state='active' and a.lease_until<=p_clock) or (a.state='awaiting_reschedule' and a.response_until<=p_clock) then
   perform app_private.end_approval(a.id,'expired','Tempo di risposta scaduto');continue;end if;
  select * into w from public.pickup_windows where id=a.pickup_window_id;
  if a.state<>'awaiting_reschedule' and (w.service_date+w.starts_at) at time zone
   (select timezone from public.schools where id=a.school_id)<=p_clock then
   perform app_private.release_order_stock(k,v_id,false);
   select z.id into nw from public.pickup_windows z where z.bar_id=p_bar and z.service_date=w.service_date
    and app_private.window_bookable(z.id,p_bar,p_clock) order by z.starts_at limit 1;
   update public.order_approvals set state=case when nw is null then 'awaiting_reschedule' else 'queued' end,
    pickup_window_id=coalesce(nw,pickup_window_id),lease_until=null,
    response_until=case when nw is null then p_clock+interval '2 hours' end,updated_at=now() where id=a.id;
   if k='individual' then update public.orders set pickup_window_id=coalesce(nw,pickup_window_id),
    status=case when nw is null then 'awaiting_reschedule' else 'approval_queued' end where id=v_id;
   else update public.group_orders set pickup_window_id=coalesce(nw,pickup_window_id),
    status=case when nw is null then 'awaiting_reschedule' else 'approval_queued' end where id=v_id;
    update public.group_drafts set pickup_window_id=coalesce(nw,pickup_window_id) where id=(select group_id from public.group_orders where id=v_id);end if;
   insert into public.customer_notifications(school_id,user_id,order_id,group_id,event_type,message)
   values(a.school_id,a.owner_id,a.order_id,(select group_id from public.group_orders where id=a.group_order_id),'order_status',
    case when nw is null then 'Non ci sono altre fasce oggi: scegli una nuova data/fascia o annulla entro 2 ore.'
    else 'La richiesta in attesa è stata spostata alla prossima fascia della stessa giornata.' end);
  end if;
 end loop;
 -- A lease counts only while its owner still has an active staff role.
 if not exists(select 1 from public.staff_service_presence p join public.school_memberships m
  on m.user_id=p.user_id and m.school_id=p.school_id and m.membership_status='active'
  join public.role_assignments r on r.membership_id=m.id and r.role_code='bartender'
  where p.bar_id=p_bar and p.valid_until>p_clock) then return 0;end if;
 select count(*) into v_active from public.order_approvals where bar_id=p_bar and state='active';
 for a in select q.* from public.order_approvals q join public.pickup_windows qw on qw.id=q.pickup_window_id
  where q.bar_id=p_bar and q.state='queued' and app_private.window_bookable(qw.id,p_bar,p_clock)
  order by qw.service_date,qw.starts_at,q.created_at,q.id for update of q skip locked loop
  exit when v_active>=v_max;
  k:=case when a.order_id is null then 'group' else 'individual' end;v_id:=coalesce(a.order_id,a.group_order_id);
  select * into w from public.pickup_windows where id=a.pickup_window_id;
  v_available:=true;
  for x in select product_id,sum(quantity)::integer quantity from app_private.order_lines(k,v_id) group by product_id order by product_id loop
   select * into s from public.daily_stock where bar_id=p_bar and product_id=x.product_id and service_date=w.service_date for update;
   if not found or (s.capacity is not null and s.allocated+x.quantity>s.capacity) or
    exists(select 1 from public.offline_stock_conflicts c where c.bar_id=p_bar and c.product_id=x.product_id
     and c.service_date=w.service_date and c.status='open') then v_available:=false;end if;
  end loop;
  if not v_available then perform app_private.end_approval(a.id,'rejected','Scorte non disponibili all’attivazione');continue;end if;
  for x in select product_id,sum(quantity)::integer quantity from app_private.order_lines(k,v_id) group by product_id order by product_id loop
   update public.daily_stock set allocated=allocated+x.quantity,updated_at=now()
   where bar_id=p_bar and product_id=x.product_id and service_date=w.service_date;
  end loop;
  update public.order_approvals set state='active',lease_until=p_clock+interval '10 minutes',updated_at=now() where id=a.id;
  if k='individual' then update public.orders set status='approval_active',stock_reserved=true where id=v_id;
  else update public.group_orders set status='approval_active',stock_reserved=true where id=v_id;end if;
  v_active:=v_active+1;v_count:=v_count+1;
 end loop;
 return v_count;
end;$$;
revoke all on function app_private.process_approval_queue(uuid,timestamptz) from public,anon,authenticated,service_role;

create function app_private.enqueue_order_approval(p_kind text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 j:=app_private.order_scope(p_kind,p_id,'internal');
 insert into public.order_approvals(school_id,bar_id,owner_id,pickup_window_id,order_id,group_order_id)
 values((j->>'school_id')::uuid,(j->>'bar_id')::uuid,(j->>'owner_id')::uuid,(j->>'window_id')::uuid,
  case when p_kind='individual' then p_id end,case when p_kind='group' then p_id end);
 perform app_private.process_approval_queue((j->>'bar_id')::uuid);
end;$$;
revoke all on function app_private.enqueue_order_approval(text,uuid) from public,anon,authenticated,service_role;

create function public.set_staff_service_presence(p_bar uuid,p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_school uuid;
begin
 select school_id into v_school from public.bars where id=p_bar and is_active;
 if p_present is null or not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.user_id=auth.uid() and m.school_id=v_school and m.membership_status='active' and r.role_code='bartender')
 then raise exception 'Barista della scuola richiesto';end if;
 if p_present then insert into public.staff_service_presence(user_id,school_id,bar_id,valid_until)
  values(auth.uid(),v_school,p_bar,now()+interval '2 minutes') on conflict(user_id,bar_id) do update set valid_until=excluded.valid_until;
 else delete from public.staff_service_presence where user_id=auth.uid() and bar_id=p_bar;end if;
 perform app_private.process_approval_queue(p_bar);
end;$$;
create function public.set_approval_capacity(p_school uuid,p_limit integer)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.can_review_school_offline(p_school) or p_limit is null or p_limit not between 1 and 30
 then raise exception 'Admin con 2FA e limite 1–30 richiesti';end if;
 update public.schools set max_active_approvals=p_limit where id=p_school;
end;$$;
create function public.list_order_approvals(p_school uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 if p_school is not null and not app_private.can_serve_group_bar(p_school) then raise exception 'Personale non autorizzato';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.service_date,x.starts_at,x.created_at),'[]'::jsonb) into j
 from(select q.*,w.service_date,w.starts_at from public.order_approvals q join public.pickup_windows w on w.id=q.pickup_window_id
  where (p_school is null and q.owner_id=auth.uid()) or q.school_id=p_school
  order by q.created_at desc limit 200) x;
 return j;
end;$$;
create function public.decide_order_approval(p_request uuid,p_approve boolean,p_reason text default '')
returns void language plpgsql security definer set search_path='' as $$
declare a public.order_approvals%rowtype;k text;v_id uuid;v_mode text;
begin
 select * into a from public.order_approvals where id=p_request for update;
 if not found or not app_private.can_serve_group_bar(a.school_id) or p_approve is null
 then raise exception 'Personale non autorizzato';end if;
 perform app_private.process_approval_queue(a.bar_id);
 select * into a from public.order_approvals where id=p_request for update;
 if a.state<>'active' or a.lease_until<=now() then raise exception 'Richiesta non attiva o scaduta';end if;
 if not p_approve then perform app_private.end_approval(a.id,'rejected',coalesce(nullif(btrim(p_reason),''),'Richiesta rifiutata dal Barista'));
 else
  select preparation_mode into v_mode from public.bars where id=a.bar_id;
  if a.order_id is not null then update public.orders set status=case when v_mode='ready_made' then 'ready' else 'confirmed' end,updated_at=now() where id=a.order_id;
  else update public.group_orders set status=case when v_mode='ready_made' then 'ready' else 'confirmed' end,updated_at=now() where id=a.group_order_id;
   update public.group_drafts set status='confirmed' where id=(select group_id from public.group_orders where id=a.group_order_id);end if;
  update public.order_approvals set state='approved',decision_by=auth.uid(),lease_until=null,updated_at=now() where id=a.id;
 end if;
 perform app_private.process_approval_queue(a.bar_id);
end;$$;
create function public.respond_approval_schedule(p_request uuid,p_window uuid default null,p_cancel boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare a public.order_approvals%rowtype;
begin
 select * into a from public.order_approvals where id=p_request for update;
 if not found or a.owner_id<>auth.uid() or a.state not in ('queued','active','awaiting_reschedule')
 then raise exception 'Richiesta non disponibile';end if;
 if p_cancel then perform app_private.end_approval(a.id,'cancelled','Annullata dal cliente');
 else
  if a.state<>'awaiting_reschedule' or a.response_until<=now() or not app_private.window_bookable(p_window,a.bar_id,now())
  then raise exception 'Nuova fascia non valida o risposta scaduta';end if;
  update public.order_approvals set state='queued',pickup_window_id=p_window,response_until=null,updated_at=now() where id=a.id;
  if a.order_id is not null then update public.orders set pickup_window_id=p_window,status='approval_queued' where id=a.order_id;
  else update public.group_orders set pickup_window_id=p_window,status='approval_queued' where id=a.group_order_id;
   update public.group_drafts set pickup_window_id=p_window where id=(select group_id from public.group_orders where id=a.group_order_id);end if;
 end if;
 perform app_private.process_approval_queue(a.bar_id);
end;$$;
create function public.maintain_approval_queues()
returns integer language plpgsql security definer set search_path='' as $$
declare x record;n integer:=0;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo backend';end if;
 for x in select distinct bar_id from public.order_approvals where state in ('queued','active','awaiting_reschedule') loop
  n:=n+app_private.process_approval_queue(x.bar_id);end loop;
 return n;
end;$$;
revoke all on function public.set_staff_service_presence(uuid,boolean),public.set_approval_capacity(uuid,integer),
 public.list_order_approvals(uuid),public.decide_order_approval(uuid,boolean,text),public.respond_approval_schedule(uuid,uuid,boolean)
 from public,anon,authenticated;
grant execute on function public.set_staff_service_presence(uuid,boolean),public.set_approval_capacity(uuid,integer),
 public.list_order_approvals(uuid),public.decide_order_approval(uuid,boolean,text),public.respond_approval_schedule(uuid,uuid,boolean) to authenticated;
revoke all on function public.maintain_approval_queues() from public,anon,authenticated;
grant execute on function public.maintain_approval_queues() to service_role;
-- Checkout implementations follow below and keep the existing public signatures.
create or replace function public.submit_individual_order(
  p_bar_id uuid, p_window_id uuid, p_items jsonb, p_request_key uuid,
  p_latitude double precision, p_longitude double precision,
  p_accuracy_m double precision, p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_window public.pickup_windows%rowtype;
  v_school public.schools%rowtype;
  v_bar public.bars%rowtype;
  v_product record;
  v_stock public.daily_stock%rowtype;
  v_item record;
  v_count integer;
  v_units integer := 0;
  v_total bigint := 0;
  v_distance double precision;
  v_requires boolean:=false;
begin
  if v_user is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' then
    raise exception 'Per prenotare è richiesto un account registrato';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-orders:'||v_user::text,0));
  if p_request_key is null or p_bar_id is null or p_window_id is null then
    raise exception 'Richiesta incompleta';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text||':'||p_request_key::text,0));
  select id into v_order from public.orders
    where customer_id=v_user and request_key=p_request_key;
  if found then return v_order; end if;

  select * into v_window from public.pickup_windows
    where id=p_window_id and bar_id=p_bar_id and is_active for share;
  if not found then raise exception 'Fascia di ritiro non disponibile'; end if;
  select * into v_bar from public.bars where id=p_bar_id and school_id=v_window.school_id and is_active for share;
  if not found then raise exception 'Bar non disponibile'; end if;
  select * into v_school from public.schools where id=v_window.school_id and is_active for share;
  if not found then raise exception 'Scuola non disponibile'; end if;

  if v_window.service_date < (now() at time zone v_school.timezone)::date
    or v_window.service_date > (now() at time zone v_school.timezone)::date + v_school.booking_horizon_days
    or (v_window.service_date + v_window.starts_at) at time zone v_school.timezone <= now() then
      raise exception 'La fascia di ritiro è scaduta oppure fuori periodo';
  end if;

  -- Geolocalizzazione client-side non è prova antifrode infallibile.
  -- Richiede consenso, coordinate valide, accuratezza e osservazione recente.
  if v_school.latitude is null or v_school.longitude is null then
    raise exception 'La scuola non ha ancora configurato la posizione per le prenotazioni';
  end if;
  if p_latitude is null or p_longitude is null or
    p_latitude not between -90 and 90 or p_longitude not between -180 and 180 or
    p_accuracy_m is null or p_accuracy_m < 0 or p_accuracy_m > 100 or
    p_observed_at is null or p_observed_at < now()-interval '2 minutes' or p_observed_at > now()+interval '15 seconds' then
    raise exception 'Posizione non verificabile o non sufficientemente precisa';
  end if;
  v_distance := 6371000 * 2 * pg_catalog.asin(least(1.0::double precision,
    pg_catalog.sqrt(
      pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_latitude-v_school.latitude)/2),2)
      + pg_catalog.cos(pg_catalog.radians(v_school.latitude))*pg_catalog.cos(pg_catalog.radians(p_latitude))
      * pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_longitude-v_school.longitude)/2),2)
    )));
  if v_distance + p_accuracy_m > v_school.pickup_radius_m then
    raise exception 'Posizione esterna al raggio consentito dalla scuola';
  end if;

  if p_items is null or jsonb_typeof(p_items)<>'array'
    or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'Carrello non valido';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
    where x.product_id is null or x.quantity is null or x.quantity<=0 or x.quantity>1000) then
    raise exception 'Quantità non valida';
  end if;
  if (select count(*) from public.orders
    where customer_id=v_user and status in ('confirmed','preparing','ready','approval_queued','approval_active','awaiting_reschedule')
    and payment_status='due') >= v_school.max_unpaid_orders_per_customer then
    raise exception 'Hai già raggiunto il limite di ordini non pagati';
  end if;

  -- LOCK dei prodotti e dei magazzini sempre in ordine UUID, previene overbooking.
  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
    group by x.product_id order by x.product_id
  loop
    if v_item.quantity > 1000 then raise exception 'Quantità troppo elevata per una riga'; end if;
    select p.id,p.name,p.price_cents into v_product
      from public.products p join public.categories c
       on c.id=p.category_id and c.school_id=p.school_id and c.bar_id=p.bar_id
      where p.id=v_item.product_id and p.bar_id=p_bar_id and p.school_id=v_school.id
        and p.is_active and c.is_active
      for share of p;
    if not found then raise exception 'Prodotto non più disponibile'; end if;
    select * into v_stock from public.daily_stock
      where product_id=v_item.product_id and bar_id=p_bar_id
        and school_id=v_school.id and service_date=v_window.service_date for update;
    if not found then raise exception 'Scorte non configurate per la data selezionata'; end if;

    v_units:=v_units+v_item.quantity;
    v_total:=v_total+v_item.quantity::bigint*v_product.price_cents;
    if v_total>999999999 then raise exception 'Importo troppo elevato'; end if;
  end loop;
  if (v_school.approval_product_threshold is not null and v_units>v_school.approval_product_threshold)
    or (v_school.approval_amount_threshold_cents is not null and
         v_total>v_school.approval_amount_threshold_cents) then
    v_requires:=true;
  end if;

  insert into public.orders(school_id,bar_id,customer_id,pickup_window_id,request_key,
    status,payment_method,payment_status,total_cents,stock_reserved)
  values (v_school.id,p_bar_id,v_user,p_window_id,p_request_key,
    case when v_requires then 'approval_queued' when v_bar.preparation_mode='ready_made' then 'ready' else 'confirmed' end,
    'at_pickup',case when v_total=0 then 'paid' else 'due' end,v_total,not v_requires)
  returning id into v_order;

  for v_item in
    select x.product_id,sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer)
    group by x.product_id order by x.product_id
  loop
    select p.name,p.price_cents into v_product from public.products p where p.id=v_item.product_id;
    if not v_requires then
     update public.daily_stock set allocated=allocated+v_item.quantity,updated_at=now()
      where product_id=v_item.product_id and bar_id=p_bar_id and service_date=v_window.service_date;
    end if;
    insert into public.order_items(school_id,bar_id,order_id,product_id,product_name,quantity,unit_cents)
    values(v_school.id,p_bar_id,v_order,v_item.product_id,v_product.name,v_item.quantity,v_product.price_cents);
  end loop;
  insert into public.order_audit(order_id,school_id,actor_id,action)
  values(v_order,v_school.id,v_user,'created');
  if v_requires then perform app_private.enqueue_order_approval('individual',v_order);end if;
  return v_order;
end;
$$;

create or replace function public.confirm_group_order(
 p_group_id uuid,p_request_key uuid,p_accept_unready boolean,
 p_latitude double precision,p_longitude double precision,
 p_accuracy_m double precision,p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $group_confirm$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_school public.schools%rowtype;v_window public.pickup_windows%rowtype;
 v_bar public.bars%rowtype;v_order uuid;v_item record;v_product record;
 v_stock public.daily_stock%rowtype;v_total bigint:=0;v_units integer:=0;
 v_requires boolean:=false;v_distance double precision;v_count integer:=0;v_not_ready integer;
begin
 if not app_private.is_registered_group_user(v_user)
   or p_group_id is null or p_request_key is null or p_accept_unready is null
 then raise exception 'Conferma gruppo non valida';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>v_user
 then raise exception 'Solo il coordinatore può confermare';end if;
 select id into v_order from public.group_orders
 where group_id=p_group_id;
 if found then
  if v_group.status in ('confirmed','approval_pending') and exists(select 1 from public.group_orders
   where id=v_order and request_key=p_request_key)
  then return v_order;end if;
  raise exception 'Gruppo già confermato con altra richiesta';
 end if;
 if v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Bozza gruppo non più confermabile';end if;
 if exists(select 1 from public.group_members where group_id=p_group_id and status='pending')
 then raise exception 'Risolvi prima le richieste di ingresso pendenti';end if;
 select count(*) into v_not_ready from public.group_members
 where group_id=p_group_id and status='accepted' and not ready;
 if v_not_ready>0 and not p_accept_unready
 then raise exception 'Alcuni partecipanti non hanno terminato: richiedi conferma esplicita';end if;

 select * into v_window from public.pickup_windows where id=v_group.pickup_window_id
 and school_id=v_group.school_id and bar_id=v_group.bar_id and is_active for share;
 if not found then raise exception 'La fascia è scaduta: scegline una nuova';end if;
 select * into v_school from public.schools where id=v_group.school_id and is_active for share;
 select * into v_bar from public.bars where id=v_group.bar_id
  and school_id=v_group.school_id and is_active for share;
 if v_school.id is null or v_bar.id is null
 then raise exception 'Scuola o bar non attivi';end if;
 if v_window.service_date<(now() at time zone v_school.timezone)::date
  or v_window.service_date>(now() at time zone v_school.timezone)::date+v_school.booking_horizon_days
  or (v_window.service_date+v_window.starts_at) at time zone v_school.timezone<=now()
 then raise exception 'La fascia non è più prenotabile: scegline una nuova';end if;
 -- GPS is mandatory again at final coordinator confirmation.
 if v_school.latitude is null or v_school.longitude is null
  or p_latitude is null or p_longitude is null
  or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
  or p_accuracy_m is null or p_accuracy_m<0 or p_accuracy_m>100
  or p_observed_at is null or p_observed_at<now()-interval '2 minutes'
  or p_observed_at>now()+interval '15 seconds'
 then raise exception 'Posizione del coordinatore non verificabile';end if;
 v_distance:=6371000*2*pg_catalog.asin(least(1.0::double precision,
  pg_catalog.sqrt(pg_catalog.power(pg_catalog.sin(
    pg_catalog.radians(p_latitude-v_school.latitude)/2),2)
   +pg_catalog.cos(pg_catalog.radians(v_school.latitude))
    *pg_catalog.cos(pg_catalog.radians(p_latitude))
    *pg_catalog.power(pg_catalog.sin(
      pg_catalog.radians(p_longitude-v_school.longitude)/2),2))));
 if v_distance+p_accuracy_m>v_school.pickup_radius_m
 then raise exception 'Coordinatore fuori dal raggio consentito';end if;

 -- All product/stock rows are checked and locked in UUID order.
 for v_item in
  select i.product_id,sum(i.quantity)::integer as quantity
  from public.group_cart_items i
   join public.group_members m on m.group_id=i.group_id and m.user_id=i.user_id
  where i.group_id=p_group_id and i.removed_at is null and m.status='accepted'
  group by i.product_id order by i.product_id
 loop
  v_count:=v_count+1;
  if v_item.quantity>1000 then raise exception 'Quantità prodotto troppo elevata';end if;
  select p.id,p.name,p.price_cents into v_product
  from public.products p join public.categories c
   on c.id=p.category_id and c.school_id=p.school_id and c.bar_id=p.bar_id
  where p.id=v_item.product_id and p.school_id=v_group.school_id
   and p.bar_id=v_group.bar_id and p.is_active and c.is_active for share of p;
  if not found then raise exception 'Prodotto % non più disponibile',v_item.product_id;end if;
  select * into v_stock from public.daily_stock
   where school_id=v_group.school_id and bar_id=v_group.bar_id
    and product_id=v_item.product_id and service_date=v_window.service_date for update;
  if not found then raise exception 'Scorte non configurate per %',v_product.name;end if;

  v_units:=v_units+v_item.quantity;
 end loop;
 if v_count=0 then raise exception 'Il gruppo non contiene prodotti';end if;
 -- Online-paid lines retain their contractual quote; unpaid lines take the
 -- current catalog price. Pending signed checkout claims retain their quote.
 select coalesce(sum(i.quantity::bigint*
   case when cl.state in ('pending','paid','refund_pending') then i.unit_price_cents
   else p.price_cents end),0)
 into v_total
 from public.group_cart_items i
 join public.group_members m on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 join public.products p on p.id=i.product_id
 left join public.group_line_payment_claims cl on cl.group_cart_item_id=i.id
 where i.group_id=p_group_id and i.removed_at is null;
 if v_total>999999999 then raise exception 'Importo del gruppo troppo elevato';end if;
 if (v_school.approval_product_threshold is not null
  and v_units>v_school.approval_product_threshold)
  or (v_school.approval_amount_threshold_cents is not null
   and v_total>v_school.approval_amount_threshold_cents)
 then v_requires:=true;end if;

 insert into public.group_orders(group_id,school_id,bar_id,pickup_window_id,
  coordinator_id,request_key,status,total_cents,stock_reserved)
 values(p_group_id,v_group.school_id,v_group.bar_id,v_group.pickup_window_id,
  v_user,p_request_key,
  case when v_requires then 'approval_queued' when v_bar.preparation_mode='ready_made' then 'ready' else 'confirmed' end,
  v_total,not v_requires) returning id into v_order;
 -- Snapshot per person, with latest unpaid price, after product locks.
 insert into public.group_order_lines(group_order_id,group_cart_item_id,
  beneficiary_id,product_id,name,quantity,unit_cents)
 select v_order,i.id,i.user_id,i.product_id,p.name,i.quantity,
   case when cl.state in ('pending','paid','refund_pending') then i.unit_price_cents
     else p.price_cents end
 from public.group_cart_items i join public.group_members m
  on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 join public.products p on p.id=i.product_id
 left join public.group_line_payment_claims cl on cl.group_cart_item_id=i.id
 where i.group_id=p_group_id and i.removed_at is null;
 update public.group_cart_items i set unit_price_cents=l.unit_cents
 from public.group_order_lines l
 where l.group_order_id=v_order and l.group_cart_item_id=i.id;
 for v_item in select product_id,sum(quantity)::integer quantity
   from public.group_order_lines where group_order_id=v_order
   group by product_id order by product_id loop
  if not v_requires then
  update public.daily_stock set allocated=allocated+v_item.quantity,updated_at=now()
  where school_id=v_group.school_id and bar_id=v_group.bar_id
   and product_id=v_item.product_id and service_date=v_window.service_date;
  end if;
 end loop;
 update public.group_drafts set status=case when v_requires then 'approval_pending' else 'confirmed' end,accepting_members=false,updated_at=now()
 where id=p_group_id;
 insert into public.group_order_audit(group_order_id,actor_id,action,details)
 values(v_order,v_user,'confirmed',jsonb_build_object('units',v_units,'total_cents',v_total));
 if v_requires then perform app_private.enqueue_order_approval('group',v_order);end if;
 return v_order;
end;$group_confirm$;

create or replace function public.begin_group_stripe_checkout(
 p_group_id uuid,p_line_ids uuid[],p_request_key uuid
) returns jsonb language plpgsql security definer set search_path=''
as $group_checkout$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_merchant public.school_stripe_merchants%rowtype;
 v_attempt public.payment_attempts%rowtype;v_line record;v_amount bigint:=0;
 v_id uuid;v_ids uuid[];v_order public.group_orders%rowtype;v_count integer:=0;
begin
 if v_user is null or p_group_id is null or p_request_key is null or
   p_line_ids is null or cardinality(p_line_ids) not between 1 and 50 or
   exists(select 1 from unnest(p_line_ids) x where x is null) or
   (select count(distinct x) from unnest(p_line_ids) x)<>cardinality(p_line_ids)
 then raise exception 'Righe e idempotenza pagamento non validi';end if;
 if exists(select 1 from app_private.platform_admins where user_id=v_user)
 then raise exception 'Super Admin escluso dai pagamenti';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status not in ('draft','confirmed','approval_pending') or
  (v_group.status='draft' and v_group.updated_at<now()-interval '24 hours') or
  not exists(select 1 from public.group_members where group_id=p_group_id
   and user_id=v_user and status='accepted')
 then raise exception 'Non puoi pagare questo gruppo';end if;
 if v_group.status in ('confirmed','approval_pending') then
  select * into v_order from public.group_orders where group_id=p_group_id for update;
  if not found or v_order.status not in ('confirmed','preparing','ready','approval_queued','approval_active','awaiting_reschedule')
   or v_order.pickup_lease_until>now()
   or exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)
  then raise exception 'Pagamento online bloccato durante il ritiro';end if;
 end if;
 select * into v_merchant from public.school_stripe_merchants
 where school_id=v_group.school_id and charges_enabled;
 if not found then raise exception 'Merchant scolastico Stripe non abilitato';end if;

 select * into v_attempt from public.payment_attempts
 where payer_id=v_user and request_key=p_request_key for update;
 if found then
  select coalesce(array_agg(a.group_cart_item_id order by a.group_cart_item_id),
    '{}'::uuid[]) into v_ids from public.payment_item_allocations a where a.payment_id=v_attempt.id;
  if v_attempt.group_id<>p_group_id or v_attempt.stripe_account_id<>v_merchant.stripe_account_id
   or v_ids<>(select array_agg(x order by x) from unnest(p_line_ids) x)
  then raise exception 'Chiave idempotenza riutilizzata per altro pagamento';end if;
  return jsonb_build_object('attempt_id',v_attempt.id,
   'amount_cents',v_attempt.amount_cents,'currency','eur',
   'stripe_account_id',v_attempt.stripe_account_id,
   'existing_session',v_attempt.stripe_checkout_session_id);
 end if;

 -- Group row serializes cart mutation, confirmation and all simultaneous claims.
 for v_line in
  select i.id,i.user_id,i.quantity,i.unit_price_cents,i.product_id,
   p.price_cents as current_price
  from public.group_cart_items i
  join public.group_members m on m.group_id=i.group_id and m.user_id=i.user_id
    and m.status='accepted'
  join public.products p on p.id=i.product_id and p.school_id=v_group.school_id
   and p.bar_id=v_group.bar_id and p.is_active
  where i.group_id=p_group_id and i.removed_at is null and i.id=any(p_line_ids)
  order by i.id for update of i for share of p
 loop
  v_count:=v_count+1;
  if exists(select 1 from public.group_line_payment_claims where group_cart_item_id=v_line.id)
  then raise exception 'Riga già pagata o con checkout in corso';end if;
  if v_group.status='draft' and v_line.unit_price_cents<>v_line.current_price
  then raise exception 'Prezzo aggiornato: il proprietario deve verificare il carrello';end if;
  v_amount:=v_amount+v_line.quantity::bigint*v_line.unit_price_cents;
 end loop;
 if v_count<>cardinality(p_line_ids)
  or v_amount<=0 or v_amount>999999999
 then raise exception 'Righe non valide o non pagabili';end if;
 insert into public.payment_attempts(school_id,payer_id,group_id,request_key,
  stripe_account_id,amount_cents,status,expires_at)
 values(v_group.school_id,v_user,p_group_id,p_request_key,
  v_merchant.stripe_account_id,v_amount,'initiated',now()+interval '40 minutes')
 returning id into v_id;
 insert into public.payment_item_allocations(payment_id,group_cart_item_id,
  beneficiary_id,amount_cents)
 select v_id,i.id,i.user_id,i.quantity::bigint*i.unit_price_cents
 from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null and i.id=any(p_line_ids);
 insert into public.group_line_payment_claims(group_cart_item_id,payment_id,
  payer_id,beneficiary_id,amount_cents,state)
 select i.id,v_id,v_user,i.user_id,i.quantity::bigint*i.unit_price_cents,'pending'
 from public.group_cart_items i where i.group_id=p_group_id and i.removed_at is null and i.id=any(p_line_ids);
 return jsonb_build_object('attempt_id',v_id,'amount_cents',v_amount,'currency','eur',
  'stripe_account_id',v_merchant.stripe_account_id,'existing_session',null);
end;$group_checkout$;

create or replace function public.finalize_verified_group_checkout(
 p_event_id text,p_account text,p_session text,p_intent text,
 p_attempt uuid,p_amount bigint,p_currency text,p_paid boolean,p_payload jsonb
) returns text language plpgsql security definer set search_path=''
as $group_paid$
declare v_attempt public.payment_attempts%rowtype;v_group public.group_drafts%rowtype;
 v_order public.group_orders%rowtype;v_claims bigint;v_sum bigint;v_decision text;
 v_processed boolean;v_group_id uuid;
begin
 if auth.jwt()->>'role'<>'service_role'
 then raise exception 'Solo webhook server può certificare denaro';end if;
 if p_event_id !~ '^evt_[A-Za-z0-9]+$' or
    p_account !~ '^acct_[A-Za-z0-9]+$' or
    p_session !~ '^cs_(test|live)_[A-Za-z0-9]+$' or
    p_intent !~ '^pi_[A-Za-z0-9]+$' or p_attempt is null or
    p_currency<>'eur' or not p_paid or p_amount<=0
 then raise exception 'Dati webhook gruppo non validi';end if;
 select processed_at is not null into v_processed from app_private.stripe_webhook_inbox
 where event_id=p_event_id;
 if found and v_processed then return 'duplicate';end if;
 -- Keep the same serialized group lock order as checkout and confirmation.
 select group_id into v_group_id from public.payment_attempts where id=p_attempt;
 if v_group_id is null then raise exception 'Tentativo gruppo non trovato';end if;
 select * into v_group from public.group_drafts where id=v_group_id for update;
 select * into v_order from public.group_orders where group_id=v_group.id for update;
 select * into v_attempt from public.payment_attempts where id=p_attempt for update;
 if not found or v_attempt.group_id<>v_group.id or
  v_attempt.stripe_account_id<>p_account or
  v_attempt.stripe_checkout_session_id<>p_session or
  v_attempt.amount_cents<>p_amount or v_attempt.currency<>p_currency
 then raise exception 'Checkout gruppo non coerente con il ledger';end if;
 if not exists(select 1 from public.school_stripe_merchants
  where school_id=v_group.school_id and stripe_account_id=p_account)
 then raise exception 'Merchant del gruppo non valido';end if;
 select count(*),coalesce(sum(amount_cents),0) into v_claims,v_sum
 from public.group_line_payment_claims where payment_id=p_attempt and state='pending';
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload)
 values(p_event_id,p_account,'checkout.session.completed',p_payload)
 on conflict(event_id) do nothing;
 if v_attempt.status='succeeded' then v_decision:='duplicate_payment';
 elsif v_attempt.status='cancelled' or v_claims=0 or v_sum<>v_attempt.amount_cents
 then v_decision:='review';
 elsif v_group.status not in ('draft','confirmed','approval_pending') or
   exists(select 1 from public.group_line_payment_claims cl
     join public.group_cart_items i on i.id=cl.group_cart_item_id
     where cl.payment_id=p_attempt and i.removed_at is not null) or
   (v_order.id is not null and (v_order.status in ('cancelled','delivered','no_show')
    or v_order.pickup_lease_until>now()
    or exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)))
 then v_decision:='refund_required';
 else v_decision:='succeeded';end if;
 if v_decision<>'duplicate_payment' then
  update public.payment_attempts set
   stripe_payment_intent_id=p_intent,
   status=case when v_decision in ('succeeded','refund_required') then 'succeeded' else 'review' end,
   updated_at=now() where id=p_attempt;
 end if;
 if v_decision in ('succeeded','refund_required') then
  update public.group_line_payment_claims set state='paid',paid_at=now()
   where payment_id=p_attempt and state='pending';
 end if;
 if v_decision='refund_required' then
  perform app_private.queue_group_line_refund(cl.group_cart_item_id,'Pagamento tardivo dopo chiusura finestra')
  from public.group_line_payment_claims cl
  where cl.payment_id=p_attempt and cl.state='paid';
 end if;
 update app_private.stripe_webhook_inbox set processed_at=now() where event_id=p_event_id;
 return v_decision;
end;$group_paid$;

create or replace function app_private.notify_new_booking()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='orders' then
  insert into public.customer_notifications(school_id,user_id,order_id,event_type,message,delivery_event_key)
  values(new.school_id,new.customer_id,new.id,'order_status',
   case when new.status like 'approval_%' then 'Richiesta inviata: attende approvazione del Barista; non è ancora un ordine confermato.' else 'Ordine confermato. Controlla in app la fascia di ritiro e il saldo.' end,
   'booking:individual:'||new.id) on conflict(delivery_event_key) do nothing;
 else
  insert into public.customer_notifications(school_id,user_id,group_id,event_type,message,delivery_event_key)
  select new.school_id,m.user_id,new.group_id,'group_confirmed',
   case when new.status like 'approval_%' then 'Richiesta di gruppo inviata al Barista per approvazione.' else 'Ordine di gruppo confermato. Il ritiro dell’intero gruppo spetta al coordinatore.' end,
   'booking:group:'||new.id||':'||m.user_id from public.group_members m
  where m.group_id=new.group_id and m.status='accepted'
  on conflict(delivery_event_key) do nothing;
 end if;
 return new;
end;$$;
commit;
