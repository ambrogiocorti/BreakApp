-- Tenant-scoped financial reports and school announcements. No payer PII exported.
begin;
create or replace function app_private.require_school_report(p_school uuid,p_from date,p_to date)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.can_review_school_offline(p_school) then raise exception 'Report riservato ad Admin scuola con 2FA';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then
  raise exception 'Seleziona un periodo valido, massimo 366 giorni';end if;
end;$$;
revoke all on function app_private.require_school_report(uuid,date,date) from public,anon,authenticated;

create or replace function public.school_order_report_rows(
 p_school uuid,p_from date,p_to date,p_offset integer default 0,p_limit integer default 500
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_zone text;
begin
 perform app_private.require_school_report(p_school,p_from,p_to);
 if p_offset is null or p_offset<0 or p_limit is null or p_limit not between 1 and 1000
 then raise exception 'Paginazione non valida';end if;
 select timezone into v_zone from public.schools where id=p_school;
 with all_orders as (
  select o.id,'individual'::text kind,o.display_no::text reference,o.created_at,
   b.name bar,w.service_date,w.starts_at,o.status,o.total_cents,
   o.payment_status,
   case when o.status in ('cancelled','no_show') or o.payment_status<>'due'
    then 0 else o.total_cents end due_cents
  from public.orders o join public.bars b on b.id=o.bar_id
   join public.pickup_windows w on w.id=o.pickup_window_id
  where o.school_id=p_school and o.created_at>=p_from::timestamp at time zone v_zone
   and o.created_at<(p_to+1)::timestamp at time zone v_zone
  union all
  select o.id,'group','G-'||left(o.id::text,8),o.created_at,b.name,w.service_date,w.starts_at,
   o.status,o.total_cents,
   case when coalesce(paid.cents,0)+coalesce(c.amount_cents,0)>=o.total_cents then 'paid' else 'due' end,
   case when o.status in ('cancelled','no_show') then 0 else
    greatest(0,o.total_cents-coalesce(paid.cents,0)-coalesce(c.amount_cents,0)) end
  from public.group_orders o join public.bars b on b.id=o.bar_id
   join public.pickup_windows w on w.id=o.pickup_window_id
   left join public.group_counter_payments c on c.group_order_id=o.id
   left join lateral (select sum(cl.amount_cents) cents from public.group_line_payment_claims cl
    join public.group_order_lines li on li.group_cart_item_id=cl.group_cart_item_id
    where li.group_order_id=o.id and cl.state='paid') paid on true
  where o.school_id=p_school and o.created_at>=p_from::timestamp at time zone v_zone
   and o.created_at<(p_to+1)::timestamp at time zone v_zone
 ) select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]'::jsonb) into v_rows
 from (select * from all_orders order by created_at desc,id offset p_offset limit p_limit) x;
 return v_rows;
end;$$;
revoke all on function public.school_order_report_rows(uuid,date,date,integer,integer) from public,anon,authenticated;
grant execute on function public.school_order_report_rows(uuid,date,date,integer,integer) to authenticated;

create or replace function public.school_financial_report(p_school uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_zone text;v_start timestamptz;v_end timestamptz;v_cash bigint;v_pos bigint;
 v_stripe bigint;v_refunds bigint;v_pending bigint;v_orders bigint;v_groups bigint;
 v_sales bigint;v_conflicts bigint;v_products jsonb;v_name text;
begin
 perform app_private.require_school_report(p_school,p_from,p_to);
 select timezone,name into v_zone,v_name from public.schools where id=p_school;
 v_start:=p_from::timestamp at time zone v_zone;v_end:=(p_to+1)::timestamp at time zone v_zone;
 with receipts as (
  select amount_cents,method from public.counter_payments
   where school_id=p_school and created_at>=v_start and created_at<v_end
  union all select amount_cents,method from public.group_counter_payments
   where school_id=p_school and paid_at>=v_start and paid_at<v_end
  union all select amount_cents,method from public.bar_counter_sales
   where school_id=p_school and created_at>=v_start and created_at<v_end
 ) select coalesce(sum(amount_cents) filter(where method='cash'),0),
   coalesce(sum(amount_cents) filter(where method='external_pos'),0) into v_cash,v_pos from receipts;
 select coalesce(sum(amount_cents),0) into v_stripe from public.payment_attempts
  where school_id=p_school and status='succeeded' and created_at>=v_start and created_at<v_end;
 select coalesce(sum(r.amount_cents) filter(where r.status='succeeded'),0),
   coalesce(sum(r.amount_cents) filter(where r.status in ('pending','processing','review','failed')),0)
  into v_refunds,v_pending from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id
  where a.school_id=p_school and r.created_at>=v_start and r.created_at<v_end;
 select count(*) into v_orders from public.orders where school_id=p_school and created_at>=v_start and created_at<v_end;
 select count(*) into v_groups from public.group_orders where school_id=p_school and created_at>=v_start and created_at<v_end;
 select count(*) into v_sales from public.bar_counter_sales where school_id=p_school and created_at>=v_start and created_at<v_end;
 select count(*) into v_conflicts from public.offline_stock_conflicts where school_id=p_school and status='open';
 with lines as (
  select i.product_id,i.product_name name,i.quantity,i.subtotal_cents cents from public.order_items i
   join public.orders o on o.id=i.order_id where o.school_id=p_school
   and o.status not in ('cancelled','no_show') and o.created_at>=v_start and o.created_at<v_end
  union all select i.product_id,i.name,i.quantity,i.subtotal_cents from public.group_order_lines i
   join public.group_orders o on o.id=i.group_order_id where o.school_id=p_school
   and o.status not in ('cancelled','no_show') and o.created_at>=v_start and o.created_at<v_end
  union all select i.product_id,i.product_name,i.quantity,i.quantity::bigint*i.unit_cents
   from public.bar_counter_sale_items i join public.bar_counter_sales s on s.id=i.sale_id
   where s.school_id=p_school and s.created_at>=v_start and s.created_at<v_end
 ) select coalesce(jsonb_agg(to_jsonb(x) order by x.quantity desc,x.product_id),'[]'::jsonb) into v_products
 from (select product_id,max(name) name,sum(quantity) quantity,sum(cents) amount_cents from lines
  group by product_id order by sum(quantity) desc,product_id limit 100) x;
 return jsonb_build_object('school_id',p_school,'school_name',v_name,'from',p_from,'to',p_to,
  'timezone',v_zone,'cash_cents',v_cash,'external_pos_cents',v_pos,'stripe_gross_cents',v_stripe,
  'stripe_refunded_cents',v_refunds,'stripe_refunds_pending_cents',v_pending,
  'net_recorded_cents',v_cash+v_pos+v_stripe-v_refunds,'individual_orders',v_orders,
  'group_orders',v_groups,'counter_sales',v_sales,'open_stock_conflicts',v_conflicts,
  'products',v_products,'generated_at',now());
end;$$;
revoke all on function public.school_financial_report(uuid,date,date) from public,anon,authenticated;
grant execute on function public.school_financial_report(uuid,date,date) to authenticated;

create table public.school_announcements (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 author_id uuid not null references auth.users(id),
 title text not null check(length(btrim(title)) between 3 and 120),
 body text not null check(length(btrim(body)) between 3 and 800),
 request_key uuid not null,
 created_at timestamptz not null default now(),
 unique(author_id,request_key)
);
create index school_announcements_school on public.school_announcements(school_id,created_at desc);
create index school_announcements_author on public.school_announcements(author_id);
alter table public.school_announcements enable row level security;
revoke all on public.school_announcements from public,anon,authenticated;
do $$
declare v_check text;
begin
 select pg_get_expr(conbin,conrelid) into v_check from pg_constraint
  where conrelid='public.customer_notifications'::regclass and conname='customer_notifications_event_type_check';
 alter table public.customer_notifications drop constraint customer_notifications_event_type_check;
 execute format('alter table public.customer_notifications add constraint customer_notifications_event_type_check check (%s or event_type in (''school_announcement'',''cash_anomaly''))',v_check);
end;$$;
create or replace function public.publish_school_announcement(p_school uuid,p_title text,p_body text,p_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_previous public.school_announcements%rowtype;
begin
 if not app_private.can_review_school_offline(p_school) then raise exception 'Annunci riservati ad Admin scuola con 2FA';end if;
 if p_key is null or p_title is null or p_body is null then raise exception 'Titolo e messaggio obbligatori';end if;
 perform 1 from public.schools where id=p_school for update;
 select * into v_previous from public.school_announcements where author_id=auth.uid() and request_key=p_key;
 if found then
  if v_previous.school_id<>p_school or v_previous.title<>btrim(p_title) or v_previous.body<>btrim(p_body)
  then raise exception 'Idempotenza annuncio non coerente';end if;
  return v_previous.id;
 end if;
 if (select count(*) from public.school_announcements where school_id=p_school and created_at>now()-interval '1 hour')>=5
 then raise exception 'Massimo cinque annunci per ora';end if;
 insert into public.school_announcements(school_id,author_id,title,body,request_key)
 values(p_school,auth.uid(),btrim(p_title),btrim(p_body),p_key) returning id into v_id;
 -- Only tenant membership confers access; browsing a public menu is not membership.
 insert into public.customer_notifications(school_id,user_id,event_type,message)
 select p_school,m.user_id,'school_announcement',btrim(p_title)||': '||btrim(p_body)
 from public.school_memberships m where m.school_id=p_school and m.membership_status='active';
 return v_id;
end;$$;
revoke all on function public.publish_school_announcement(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.publish_school_announcement(uuid,text,text,uuid) to authenticated;

create or replace function app_private.notify_cash_anomaly()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.closed_at is not null and old.closed_at is null and new.counted_cents<>new.expected_cents then
  insert into public.customer_notifications(school_id,user_id,event_type,message)
  select new.school_id,m.user_id,'cash_anomaly','Differenza alla chiusura di cassa: '||
   (new.counted_cents-new.expected_cents)::text||' centesimi. Motivo: '||new.closing_reason
  from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.school_id=new.school_id and m.membership_status='active' and r.role_code='school_admin';
 end if;
 return new;
end;$$;
revoke all on function app_private.notify_cash_anomaly() from public,anon,authenticated;
create trigger cash_anomaly_notice after update on public.cash_sessions
 for each row execute function app_private.notify_cash_anomaly();
commit;
