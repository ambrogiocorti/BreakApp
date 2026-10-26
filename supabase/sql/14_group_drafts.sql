-- BreakApp 14 - Group DRAFTS only. NO payments and NO stock reservation.
-- Confirmed groups, multi-payer ledger/refunds, 10m pickup leases require
-- separate atomic payment/fulfilment migrations. Never fake those states.
begin;

create table public.group_drafts(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null,
 bar_id uuid not null,
 pickup_window_id uuid not null references public.pickup_windows(id) on delete restrict,
 coordinator_id uuid not null references auth.users(id) on delete restrict,
 request_key uuid not null,
 title text not null check(char_length(btrim(title)) between 3 and 100),
 status text not null default 'draft' check(status in ('draft','expired','cancelled')),
 requires_approval boolean not null default false,
 accepting_members boolean not null default true,
 max_members integer check(max_members is null or max_members between 1 and 100),
 invite_token uuid not null unique default gen_random_uuid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(coordinator_id,request_key),
 foreign key(school_id,bar_id) references public.bars(school_id,id) on delete restrict
);
create index group_drafts_coordinator on public.group_drafts(coordinator_id,updated_at desc);
create index group_drafts_expiry on public.group_drafts(updated_at) where status='draft';

create table public.group_members(
 group_id uuid not null references public.group_drafts(id) on delete restrict,
 user_id uuid not null references auth.users(id) on delete restrict,
 status text not null check(status in ('pending','accepted','rejected')),
 ready boolean not null default false,
 joined_at timestamptz not null default now(),
 approved_at timestamptz,
 primary key(group_id,user_id)
);
create index group_members_by_user on public.group_members(user_id,status);

create table public.group_cart_items(
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null,
 user_id uuid not null,
 product_id uuid not null references public.products(id) on delete restrict,
 product_name text not null,
 unit_price_cents integer not null check(unit_price_cents>=0),
 quantity integer not null check(quantity between 1 and 1000),
 created_at timestamptz not null default now(),
 unique(group_id,user_id,product_id),
 foreign key(group_id,user_id) references public.group_members(group_id,user_id) on delete restrict
);
create index group_cart_by_group on public.group_cart_items(group_id,user_id);

alter table public.group_drafts enable row level security;
alter table public.group_members enable row level security;
alter table public.group_cart_items enable row level security;
revoke all on public.group_drafts,public.group_members,public.group_cart_items
 from public,anon,authenticated;
-- All accesses are via explicit security-definer RPCs with auth/role/tenant
-- checks, not direct PostgREST, preventing accidental invite-token exposure.

create or replace function app_private.is_registered_group_user(p_user uuid)
returns boolean language sql stable security definer set search_path=''
as $registered$
 select p_user is not null
   and not exists(select 1 from app_private.platform_admins pa where pa.user_id=p_user)
   and coalesce((select auth.jwt()->>'is_anonymous'),'false')<>'true';
$registered$;
revoke all on function app_private.is_registered_group_user(uuid)
 from public,anon,authenticated;

create or replace function public.create_group_draft(
 p_bar_id uuid,p_window_id uuid,p_request_key uuid,p_title text,
 p_requires_approval boolean default false,p_max_members integer default null
) returns uuid language plpgsql security definer set search_path=''
as $create_group$
declare v_user uuid:=auth.uid();v_id uuid;v_window public.pickup_windows%rowtype;
 v_school public.schools%rowtype;
begin
 if not app_private.is_registered_group_user(v_user) then
   raise exception 'Solo clienti registrati possono coordinare gruppi';end if;
 if p_bar_id is null or p_window_id is null or p_request_key is null or
   p_requires_approval is null or
   char_length(btrim(coalesce(p_title,''))) not between 3 and 100 or
   (p_max_members is not null and p_max_members not between 1 and 100)
 then raise exception 'Parametri gruppo non validi';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'group:'||v_user::text||':'||p_request_key::text,0));
 select id into v_id from public.group_drafts
  where coordinator_id=v_user and request_key=p_request_key;
 if found then return v_id;end if;
 select * into v_window from public.pickup_windows
 where id=p_window_id and bar_id=p_bar_id and is_active;
 if not found then raise exception 'Fascia non valida';end if;
 select * into v_school from public.schools where id=v_window.school_id and is_active;
 if not found or not exists(select 1 from public.bars where id=p_bar_id
    and school_id=v_window.school_id and is_active)
 then raise exception 'Scuola o bar non disponibili';end if;
 if v_window.service_date<(now() at time zone v_school.timezone)::date
  or (v_window.service_date+v_window.starts_at) at time zone v_school.timezone <= now()
  or v_window.service_date>(now() at time zone v_school.timezone)::date+v_school.booking_horizon_days
 then raise exception 'Fascia scaduta o non prenotabile';end if;
 if (select count(*) from public.group_drafts
     where coordinator_id=v_user and status='draft'
       and updated_at>now()-interval '24 hours')>=10
 then raise exception 'Troppe bozze gruppo attive';end if;
 insert into public.group_drafts(school_id,bar_id,pickup_window_id,coordinator_id,
  request_key,title,requires_approval,max_members)
 values(v_window.school_id,p_bar_id,p_window_id,v_user,p_request_key,
  btrim(p_title),p_requires_approval,p_max_members)
 returning id into v_id;
 insert into public.group_members(group_id,user_id,status,ready,approved_at)
 values(v_id,v_user,'accepted',false,now());
 return v_id;
end;
$create_group$;

create or replace function public.join_group_draft(
 p_invite_token uuid,p_latitude double precision,p_longitude double precision,
 p_accuracy_m double precision,p_observed_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $join_group$
declare v_user uuid:=auth.uid();v_group public.group_drafts%rowtype;
 v_school public.schools%rowtype;v_status text;v_distance double precision;
begin
 if v_user is null or p_invite_token is null then
  raise exception 'Accedi come partecipante per aprire l''invito';end if;
 select * into v_group from public.group_drafts where invite_token=p_invite_token for update;
 if not found then raise exception 'Invito non valido';end if;
 if v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
   or not v_group.accepting_members then
  raise exception 'Il gruppo non accetta nuovi ingressi';end if;
 select status into v_status from public.group_members
  where group_id=v_group.id and user_id=v_user;
 if found then
  if v_status='rejected' then raise exception 'Ingresso rifiutato';end if;
  return v_group.id;
 end if;
 if v_group.max_members is not null and
  (select count(*) from public.group_members where group_id=v_group.id
   and status in ('accepted','pending'))>=v_group.max_members
 then raise exception 'Gruppo al completo';end if;
 select * into v_school from public.schools where id=v_group.school_id and is_active;
 if not found or v_school.latitude is null or v_school.longitude is null
 then raise exception 'Posizione scuola non configurata';end if;
 if p_latitude is null or p_longitude is null or
   p_latitude not between -90 and 90 or p_longitude not between -180 and 180
   or p_accuracy_m is null or p_accuracy_m<0 or p_accuracy_m>100
   or p_observed_at is null or p_observed_at<now()-interval '2 minutes'
   or p_observed_at>now()+interval '15 seconds'
 then raise exception 'Posizione non verificabile';end if;
 v_distance:=6371000 * 2 * pg_catalog.asin(least(1.0::double precision,
   pg_catalog.sqrt(
   pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_latitude-v_school.latitude)/2),2)
   +pg_catalog.cos(pg_catalog.radians(v_school.latitude))*pg_catalog.cos(pg_catalog.radians(p_latitude))
   *pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_longitude-v_school.longitude)/2),2))));
 if v_distance+p_accuracy_m>v_school.pickup_radius_m then
   raise exception 'Per partecipare devi essere entro il raggio scolastico';end if;
 insert into public.group_members(group_id,user_id,status)
 values(v_group.id,v_user,case when v_group.requires_approval then 'pending' else 'accepted' end);
 update public.group_drafts set updated_at=now() where id=v_group.id;
 return v_group.id;
end;
$join_group$;

create or replace function public.review_group_member(
 p_group_id uuid,p_member_id uuid,p_approve boolean
) returns void language plpgsql security definer set search_path=''
as $review_group$
declare v_group public.group_drafts%rowtype;
begin
 if auth.uid() is null or p_approve is null then raise exception 'Decisione non valida';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.coordinator_id<>auth.uid() or v_group.status<>'draft'
  or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Solo il coordinatore può valutare ingressi';end if;
 update public.group_members
  set status=case when p_approve then 'accepted' else 'rejected' end,
      approved_at=now()
 where group_id=p_group_id and user_id=p_member_id and status='pending';
 if not found then raise exception 'Nessuna richiesta pendente';end if;
 update public.group_drafts set updated_at=now() where id=p_group_id;
end;
$review_group$;

create or replace function public.replace_group_personal_cart(
 p_group_id uuid,p_items jsonb
) returns void language plpgsql security definer set search_path=''
as $cart_group$
declare v_group public.group_drafts%rowtype;v_user uuid:=auth.uid();
 v_item record;v_product record;
begin
 if v_user is null or p_group_id is null or p_items is null or
  jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100
 then raise exception 'Carrello non valido';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Bozza gruppo non modificabile';end if;
 if not exists(select 1 from public.group_members
  where group_id=p_group_id and user_id=v_user and status='accepted' and not ready)
 then raise exception 'Non sei autorizzato a modificare questo carrello';end if;
 if exists(select 1 from jsonb_to_recordset(p_items)
   as x(product_id uuid,quantity integer)
   where x.product_id is null or x.quantity is null or x.quantity not between 1 and 1000)
 then raise exception 'Quantità non valide';end if;
 if (select count(distinct x.product_id) from jsonb_to_recordset(p_items)
    as x(product_id uuid,quantity integer))<>(select count(*) from jsonb_array_elements(p_items))
 then raise exception 'Non duplicare righe prodotto';end if;
 -- Draft lines never reserve stock and never represent a settled payment.
 for v_item in select x.product_id,x.quantity from jsonb_to_recordset(p_items)
 as x(product_id uuid,quantity integer) order by x.product_id loop
  select p.name,p.price_cents into v_product from public.products p
   join public.categories c on c.id=p.category_id and c.is_active
    and c.school_id=p.school_id and c.bar_id=p.bar_id
   where p.id=v_item.product_id and p.bar_id=v_group.bar_id
      and p.school_id=v_group.school_id and p.is_active;
  if not found then raise exception 'Prodotto non disponibile in questo bar';end if;
 end loop;
 delete from public.group_cart_items where group_id=p_group_id and user_id=v_user;
 insert into public.group_cart_items(group_id,user_id,product_id,product_name,unit_price_cents,quantity)
 select p_group_id,v_user,p.id,p.name,p.price_cents,x.quantity
 from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
 join public.products p on p.id=x.product_id;
 update public.group_drafts set updated_at=now() where id=p_group_id;
end;
$cart_group$;

create or replace function public.set_group_personal_ready(
 p_group_id uuid,p_ready boolean
) returns void language plpgsql security definer set search_path=''
as $set_ready$
declare v_group public.group_drafts%rowtype;
begin
 if auth.uid() is null or p_ready is null then raise exception 'Stato non valido';end if;
 select * into v_group from public.group_drafts where id=p_group_id for update;
 if not found or v_group.status<>'draft' or v_group.updated_at<now()-interval '24 hours'
 then raise exception 'Bozza gruppo non modificabile';end if;
 update public.group_members set ready=p_ready
  where group_id=p_group_id and user_id=auth.uid() and status='accepted';
 if not found then raise exception 'Non sei un partecipante approvato';end if;
 update public.group_drafts set updated_at=now() where id=p_group_id;
end;
$set_ready$;

create or replace function public.group_draft_details(p_group_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $details$
declare v_group public.group_drafts%rowtype;v_user uuid:=auth.uid();
 v_role text;v_ready boolean;v_totals jsonb;v_my_lines jsonb;v_members jsonb;
begin
 if v_user is null then raise exception 'Accesso richiesto';end if;
 select * into v_group from public.group_drafts where id=p_group_id;
 if not found then raise exception 'Gruppo non trovato';end if;
 select status,ready into v_role,v_ready from public.group_members
   where group_id=p_group_id and user_id=v_user;
 if v_role is null then raise exception 'Non fai parte di questo gruppo';end if;
 select jsonb_build_object('count',coalesce(sum(i.quantity),0),
    'total_cents',coalesce(sum(i.quantity::bigint*i.unit_price_cents),0))
 into v_totals from public.group_cart_items i where i.group_id=p_group_id;
 select coalesce(jsonb_agg(jsonb_build_object('product_id',i.product_id,
   'name',i.product_name,'quantity',i.quantity,
   'unit_price_cents',i.unit_price_cents) order by i.product_name),'[]'::jsonb)
 into v_my_lines from public.group_cart_items i where i.group_id=p_group_id
   and i.user_id=v_user;
 if v_group.coordinator_id=v_user then
  select coalesce(jsonb_agg(jsonb_build_object(
    'member_id',m.user_id,'status',m.status,'ready',m.ready,
    'line_count',(select coalesce(sum(i.quantity),0) from public.group_cart_items i
      where i.group_id=m.group_id and i.user_id=m.user_id)
  ) order by m.joined_at),'[]'::jsonb)
  into v_members from public.group_members m where m.group_id=p_group_id;
 else
  select jsonb_build_object('accepted',(select count(*) from public.group_members
   where group_id=p_group_id and status='accepted'),
   'ready',(select count(*) from public.group_members
   where group_id=p_group_id and status='accepted' and ready))
   into v_members;
 end if;
 return jsonb_build_object('id',v_group.id,'title',v_group.title,
 'school_id',v_group.school_id,'bar_id',v_group.bar_id,
 'pickup_window_id',v_group.pickup_window_id,'status',v_group.status,
 'my_status',v_role,'my_ready',v_ready,'coordinator',v_group.coordinator_id=v_user,
 'invite_token',case when v_group.coordinator_id=v_user then v_group.invite_token else null end,
 'requires_approval',v_group.requires_approval,'accepting_members',v_group.accepting_members,
 'max_members',v_group.max_members,'expires_at',v_group.updated_at+interval '24 hours',
 'totals',v_totals,'my_items',v_my_lines,'members',v_members);
end;
$details$;

create or replace function public.list_my_group_drafts()
returns jsonb language sql stable security definer set search_path=''
as $list_drafts$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',g.id,'title',g.title,'status',g.status,
 'coordinator',g.coordinator_id=auth.uid(),
 'updated_at',g.updated_at,'expires_at',g.updated_at+interval '24 hours',
 'my_status',m.status) order by g.updated_at desc),'[]'::jsonb)
 from public.group_members m join public.group_drafts g on g.id=m.group_id
 where m.user_id=(select auth.uid());
$list_drafts$;

revoke all on function public.create_group_draft(uuid,uuid,uuid,text,boolean,integer),
 public.join_group_draft(uuid,double precision,double precision,double precision,timestamptz),
 public.review_group_member(uuid,uuid,boolean),
 public.replace_group_personal_cart(uuid,jsonb),
 public.set_group_personal_ready(uuid,boolean),
 public.group_draft_details(uuid),
 public.list_my_group_drafts()
 from public,anon,authenticated;
grant execute on function public.create_group_draft(uuid,uuid,uuid,text,boolean,integer),
 public.join_group_draft(uuid,double precision,double precision,double precision,timestamptz),
 public.review_group_member(uuid,uuid,boolean),
 public.replace_group_personal_cart(uuid,jsonb),
 public.set_group_personal_ready(uuid,boolean),
 public.group_draft_details(uuid),
 public.list_my_group_drafts() to authenticated;
commit;
