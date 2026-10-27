begin;
alter table public.customer_notifications add column delivery_event_key text unique;
do $$declare v_check text;begin
 select pg_get_expr(conbin,conrelid) into v_check from pg_constraint
 where conrelid='public.customer_notifications'::regclass and conname='customer_notifications_event_type_check';
 alter table public.customer_notifications drop constraint customer_notifications_event_type_check;
 execute format('alter table public.customer_notifications add constraint customer_notifications_event_type_check check (%s or event_type in (''pickup_reminder'',''closing_reminder'',''group_pickup_reminder'',''group_closing_reminder'',''group_confirmed''))',v_check);
end;$$;

create function app_private.notify_new_booking()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='orders' then
  insert into public.customer_notifications(school_id,user_id,order_id,event_type,message,delivery_event_key)
  values(new.school_id,new.customer_id,new.id,'order_status',
   'Ordine confermato. Controlla in app la fascia di ritiro e il saldo.',
   'booking:individual:'||new.id) on conflict(delivery_event_key) do nothing;
 else
  insert into public.customer_notifications(school_id,user_id,group_id,event_type,message,delivery_event_key)
  select new.school_id,m.user_id,new.group_id,'group_confirmed',
   'Ordine di gruppo confermato. Il ritiro dell’intero gruppo spetta al coordinatore.',
   'booking:group:'||new.id||':'||m.user_id from public.group_members m
  where m.group_id=new.group_id and m.status='accepted'
  on conflict(delivery_event_key) do nothing;
 end if;
 return new;
end;$$;
revoke all on function app_private.notify_new_booking() from public,anon,authenticated;
create trigger individual_booking_notice after insert on public.orders
 for each row execute function app_private.notify_new_booking();
create trigger group_booking_notice after insert on public.group_orders
 for each row execute function app_private.notify_new_booking();

-- The clock is injectable only inside the private schema for deterministic DB tests.
create function app_private.enqueue_due_pickup_notices(p_clock timestamptz,p_limit integer)
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 if p_clock is null or p_limit is null or p_limit not between 1 and 1000
 then raise exception 'Limite promemoria non valido';end if;
 if not pg_try_advisory_xact_lock(19861124,71) then return 0;end if;
 with individual_due as (
  select o.*,w.service_date,w.starts_at,s.timezone,
   (w.service_date+w.starts_at) at time zone s.timezone pickup_at
  from public.orders o join public.pickup_windows w on w.id=o.pickup_window_id
  join public.schools s on s.id=o.school_id join public.bars b on b.id=o.bar_id
  where o.status in ('confirmed','preparing','ready') and w.is_active and s.is_active and b.is_active
 ),group_due as (
  select o.*,w.service_date,w.starts_at,s.timezone,
   (w.service_date+w.starts_at) at time zone s.timezone pickup_at,
   greatest(0,o.total_cents-coalesce(p.cents,0)-coalesce(c.amount_cents,0)) due_cents
  from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id
  join public.schools s on s.id=o.school_id join public.bars b on b.id=o.bar_id
  left join public.group_counter_payments c on c.group_order_id=o.id
  left join lateral(select sum(cl.amount_cents) cents from public.group_line_payment_claims cl
   join public.group_order_lines li on li.group_cart_item_id=cl.group_cart_item_id
   where li.group_order_id=o.id and cl.state='paid') p on true
  where o.status in ('confirmed','preparing','ready') and w.is_active and s.is_active and b.is_active
 ),closing as (
  select h.school_id,h.bar_id,((p_clock at time zone s.timezone)::date+max(h.ends_at))
   at time zone s.timezone closes_at
  from public.bar_opening_hours h join public.schools s on s.id=h.school_id
  where h.weekday=extract(dow from p_clock at time zone s.timezone)::integer
  group by h.school_id,h.bar_id,s.timezone
 ),candidates as (
  select o.school_id,o.customer_id user_id,o.id order_id,null::uuid group_id,
   'pickup_reminder'::text event_type,
   'Il ritiro del tuo ordine è previsto tra circa 5 minuti. Saldo da pagare: € '||
    replace(to_char(case when o.payment_status='due' then o.total_cents else 0 end/100.0,'FM9999990.00'),'.',',')||'.' message,
   'pickup:individual:'||o.id||':'||o.pickup_window_id event_key
  from individual_due o where o.pickup_at>p_clock and o.pickup_at<=p_clock+interval '5 minutes'
  union all
  select o.school_id,o.coordinator_id,null,o.group_id,'group_pickup_reminder',
   'Tra circa 5 minuti è previsto il ritiro del gruppo. Saldo residuo: € '||
    replace(to_char(o.due_cents/100.0,'FM9999990.00'),'.',',')||'. Solo tu puoi ritirare e saldare al banco.',
   'pickup:group:'||o.id||':'||o.pickup_window_id||':'||o.coordinator_id
  from group_due o where o.pickup_at>p_clock and o.pickup_at<=p_clock+interval '5 minutes'
  union all
  select o.school_id,l.beneficiary_id,null,o.group_id,'group_pickup_reminder',
   'Il ritiro del gruppo è vicino e alcuni tuoi prodotti risultano ancora da pagare. Puoi pagarli online prima della scansione del coordinatore.',
   'pickup:group:'||o.id||':'||o.pickup_window_id||':'||l.beneficiary_id
  from group_due o join public.group_order_lines l on l.group_order_id=o.id
  join public.group_members m on m.group_id=o.group_id and m.user_id=l.beneficiary_id and m.status='accepted'
  left join public.group_line_payment_claims cl on cl.group_cart_item_id=l.group_cart_item_id
  where o.pickup_at>p_clock and o.pickup_at<=p_clock+interval '5 minutes' and o.due_cents>0
   and l.beneficiary_id<>o.coordinator_id and cl.state is distinct from 'paid' and l.subtotal_cents>0
  group by o.school_id,l.beneficiary_id,o.group_id,o.id,o.pickup_window_id
  union all
  select o.school_id,o.customer_id,o.id,null,'closing_reminder',
   'Il bar chiude tra circa 15 minuti: il tuo ordine pronto non è ancora stato ritirato.',
   'closing:individual:'||o.id||':'||c.closes_at
  from individual_due o join closing c on c.bar_id=o.bar_id and c.school_id=o.school_id
  where o.status='ready' and o.service_date=(p_clock at time zone o.timezone)::date
   and c.closes_at>p_clock and c.closes_at<=p_clock+interval '15 minutes'
  union all
  select o.school_id,o.coordinator_id,null,o.group_id,'group_closing_reminder',
   'Il bar chiude tra circa 15 minuti: il gruppo è pronto. Il ritiro spetta soltanto a te.',
   'closing:group:'||o.id||':'||c.closes_at
  from group_due o join closing c on c.bar_id=o.bar_id and c.school_id=o.school_id
  where o.status='ready' and o.service_date=(p_clock at time zone o.timezone)::date
   and c.closes_at>p_clock and c.closes_at<=p_clock+interval '15 minutes'
 )
 insert into public.customer_notifications(school_id,user_id,order_id,group_id,event_type,message,delivery_event_key)
 select x.school_id,x.user_id,x.order_id,x.group_id,x.event_type,x.message,x.event_key
 from candidates x where not exists(select 1 from public.customer_notifications n where n.delivery_event_key=x.event_key)
 order by x.event_key limit p_limit on conflict(delivery_event_key) do nothing;
 get diagnostics v_count=row_count;
 return v_count;
end;$$;
revoke all on function app_private.enqueue_due_pickup_notices(timestamptz,integer) from public,anon,authenticated,service_role;
create function public.enqueue_pickup_reminders(p_limit integer default 500)
returns integer language plpgsql security definer set search_path='' as $$
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo servizio backend';end if;
 return app_private.enqueue_due_pickup_notices(now(),p_limit);
end;$$;
revoke all on function public.enqueue_pickup_reminders(integer) from public,anon,authenticated;
grant execute on function public.enqueue_pickup_reminders(integer) to service_role;
commit;
