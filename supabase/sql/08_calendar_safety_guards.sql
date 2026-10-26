-- BreakApp 08: correzioni conservative su annullamenti e fasce prenotate.
-- Compatibile con 07 già applicata: nessuna modifica ai dati presenti.
begin;
create or replace function public.close_bar_interval(
 p_bar_id uuid,p_date date,p_start time,p_end time,
 p_kind text,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $closure$
declare v_bar public.bars%rowtype;v_day date;v_order record;v_item record;
 v_closure uuid;v_tz text;
begin
 if p_date is null or p_start is null or p_end is null or p_start>=p_end
   or p_kind not in ('planned','extraordinary') or p_kind is null
   or char_length(btrim(coalesce(p_reason,''))) not between 3 and 500 then
   raise exception 'Dati di chiusura non validi';
 end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active for update;
 if not found then raise exception 'Bar non trovato';end if;
 if not app_private.can_operate_bar(v_bar.school_id,p_kind='planned') then
  raise exception 'Non autorizzato alla chiusura'; end if;
 select timezone into v_tz from public.schools where id=v_bar.school_id;
 v_day:=(now() at time zone v_tz)::date;
 if p_date<v_day or p_date>v_day+365 then
  raise exception 'La chiusura deve riguardare una data presente o futura';end if;
 if exists(select 1 from public.bar_closures c
  where c.bar_id=v_bar.id and c.service_date=p_date and c.reopened_at is null
  and c.starts_at<p_end and c.ends_at>p_start)
 then raise exception 'Esiste già una chiusura sovrapposta';end if;

 -- Blocca le righe ordine nello stesso ordine prima di mutare alcunché.
 for v_order in
  select o.* from public.orders o
   join public.pickup_windows w on w.id=o.pickup_window_id
  where o.bar_id=p_bar_id and w.service_date=p_date
    and w.starts_at<p_end and w.ends_at>p_start
    and o.status not in ('delivered','cancelled','no_show')
  order by o.id for update of o
 loop
  if p_kind='planned' then
   raise exception 'Sono presenti ordini attivi: usa una chiusura straordinaria con valutazione impatto';
  end if;
  if v_order.payment_status='paid' and v_order.total_cents>0 then
   raise exception 'Ordine pagato presente: chiusura bloccata finché i rimborsi non sono automatizzati';
  end if;
 end loop;

 insert into public.bar_closures(school_id,bar_id,service_date,starts_at,ends_at,closure_type,reason,created_by)
 values(v_bar.school_id,v_bar.id,p_date,p_start,p_end,p_kind,btrim(p_reason),auth.uid())
 returning id into v_closure;

 if p_kind='extraordinary' then
   for v_order in
     select o.* from public.orders o
      join public.pickup_windows w on w.id=o.pickup_window_id
     where o.bar_id=p_bar_id and w.service_date=p_date
       and w.starts_at<p_end and w.ends_at>p_start
       and o.status not in ('delivered','cancelled','no_show')
     order by o.id for update of o
   loop
     -- Le scorte di prodotti già preparati/pronti non vengono ricaricate
     -- automaticamente: potrebbero essere deperibili o fisicamente consumate.
     if v_order.status='confirmed' then
     for v_item in
       select i.product_id,i.quantity,w.service_date from public.order_items i
       join public.pickup_windows w on w.id=v_order.pickup_window_id
       where i.order_id=v_order.id order by i.product_id
     loop
       update public.daily_stock
         set allocated=allocated-v_item.quantity,updated_at=now()
       where school_id=v_bar.school_id and bar_id=v_bar.id
          and service_date=v_item.service_date and product_id=v_item.product_id;
     end loop;
     else
       insert into public.order_audit(order_id,school_id,actor_id,action)
       values(v_order.id,v_bar.school_id,auth.uid(),'prepared_stock_preserved_after_closure');
     end if;
     update public.orders set status='cancelled',updated_at=now() where id=v_order.id;
     insert into public.order_audit(order_id,school_id,actor_id,action)
      values(v_order.id,v_bar.school_id,auth.uid(),'extraordinary_closure_cancelled');
     insert into public.customer_notifications(school_id,user_id,order_id,event_type,message)
      values(v_bar.school_id,v_order.customer_id,v_order.id,'closure_order_cancelled',
        'Ordine #'||v_order.display_no||' annullato per chiusura straordinaria del bar.');
   end loop;
 end if;
 insert into public.bar_service_events(school_id,bar_id,actor_id,action,details)
 values(v_bar.school_id,v_bar.id,auth.uid(),'closure_created',
   jsonb_build_object('closure_id',v_closure,'kind',p_kind,'date',p_date,
      'starts_at',p_start,'ends_at',p_end,'reason',p_reason));
 return v_closure;
end;
$closure$;


create or replace function app_private.guard_pickup_window_service()
returns trigger language plpgsql set search_path=''
as $guard_slot$
begin
 if tg_op='UPDATE' and old.is_active and not new.is_active and exists (
   select 1 from public.orders o where o.pickup_window_id=old.id
   and o.status not in ('delivered','cancelled','no_show')
 ) then
   raise exception 'La fascia ha ordini attivi: usa il workflow con valutazione impatti';
 end if;
 if new.is_active and (
  not exists(select 1 from public.bar_opening_hours h where h.bar_id=new.bar_id
   and h.weekday=extract(dow from new.service_date)::int
   and h.starts_at<=new.starts_at and h.ends_at>=new.ends_at)
  or exists(select 1 from public.bar_closures c where c.bar_id=new.bar_id
   and c.service_date=new.service_date and c.reopened_at is null
   and c.starts_at<new.ends_at and c.ends_at>new.starts_at)
 ) then raise exception 'Fascia non valida: bar chiuso o fuori dagli orari';end if;
 return new;
end;
$guard_slot$;


commit;
