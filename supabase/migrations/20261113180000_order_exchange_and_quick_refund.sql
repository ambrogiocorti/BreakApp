-- BreakApp: rimborso e cambio prodotto dall'ordine concluso (richiesta di
-- Ambrogio del 13/11/2026). Regola: i soldi tornano nello stesso modo in cui
-- sono stati pagati (online -> carta con Stripe, contanti/POS -> contanti al banco).
--
-- 1. Cambio prodotto su un ordine consegnato e pagato: il cliente rende uno o
--    piu' pezzi di un prodotto e ne prende un altro. L'ordine viene aggiornato
--    (righe e totale, con versione salvata) come nelle sostituzioni esistenti:
--    * se il nuovo costa di piu' la differenza si incassa al banco (contanti o
--      POS) come incasso aggiuntivo: entra nel turno di cassa, nel report e
--      crea lo scontrino da emettere con i trigger gia' esistenti;
--    * se costa di meno la differenza torna come e' stata pagata
--      (refund_order_credit: carta con Stripe, altrimenti contanti al banco).
--    Le scorte di oggi del nuovo prodotto scendono come per una vendita; il
--    prodotto reso non torna in magazzino (come nelle sostituzioni gia' preparate).
-- 2. order_cash_refunds_to_return: le restituzioni in contanti ancora da fare
--    per un ordine, cosi' il barista le registra subito nello stesso passaggio.

create table public.order_exchanges(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 bar_id uuid not null references public.bars(id),
 order_id uuid not null references public.orders(id),
 actor_id uuid not null references auth.users(id),
 request_key uuid not null,
 product_out_id uuid references public.products(id),
 product_out_name text not null,
 product_in_id uuid not null references public.products(id),
 product_in_name text not null,
 quantity integer not null check (quantity between 1 and 100),
 out_cents bigint not null check (out_cents>=0),
 in_cents bigint not null check (in_cents>=0),
 amount_cents bigint not null check (amount_cents>=0),
 method text not null check (method in ('none','cash','external_pos','refund')),
 reason text not null check (length(reason) between 8 and 300),
 created_at timestamptz not null default now(),
 unique (actor_id,request_key),
 check ((method='none' and amount_cents=0) or (method in ('cash','external_pos','refund') and amount_cents>0))
);
create index order_exchanges_order on public.order_exchanges(order_id);
create index order_exchanges_school on public.order_exchanges(school_id,created_at);
create index order_exchanges_bar on public.order_exchanges(bar_id);
create index order_exchanges_actor on public.order_exchanges(actor_id);
create index order_exchanges_product_out on public.order_exchanges(product_out_id);
create index order_exchanges_product_in on public.order_exchanges(product_in_id);
alter table public.order_exchanges enable row level security;
revoke all on public.order_exchanges from public,anon,authenticated;

create function public.exchange_order_item(p_order uuid,p_product_out uuid,p_quantity integer,p_product_in uuid,p_method text,p_key uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;v_line public.order_items%rowtype;v_same public.order_items%rowtype;v_in public.products%rowtype;
 v_date date;v_stock public.daily_stock%rowtype;v_out_cents bigint;v_in_cents bigint;v_diff bigint;
 v_method text;v_reason text;x public.order_exchanges%rowtype;
begin
 v_reason:=btrim(coalesce(p_reason,''));
 if p_order is null or p_product_out is null or p_product_in is null or p_key is null
  or p_quantity is null or p_quantity not between 1 and 100
  or length(v_reason) not between 8 and 300 then raise exception 'Cambio non valido: indica prodotti, quantita'' e motivo';end if;
 select * into x from public.order_exchanges where actor_id=auth.uid() and request_key=p_key;
 if found then
  if x.order_id<>p_order then raise exception 'Idempotenza incoerente';end if;
  return jsonb_build_object('status','duplicate','id',x.id,'difference_cents',x.in_cents-x.out_cents,'method',x.method);
 end if;
 select * into o from public.orders where id=p_order for update;
 if not found or not app_private.can_serve_group_bar(o.school_id) then raise exception 'Solo il personale del bar puo'' fare un cambio';end if;
 if o.status<>'delivered' or o.payment_status<>'paid' then raise exception 'Il cambio si fa solo su un ordine consegnato e pagato';end if;
 perform app_private.assert_no_pending_checkout('individual',o.id);
 if p_product_out=p_product_in then raise exception 'Scegli un prodotto diverso';end if;
 select * into v_line from public.order_items where order_id=o.id and product_id=p_product_out and removed_at is null for update;
 if not found then raise exception 'Il prodotto da cambiare non e'' nell''ordine';end if;
 if p_quantity>v_line.quantity then raise exception 'Quantita'' da cambiare superiore a quella ordinata';end if;
 select p.* into v_in from public.products p join public.categories c on c.id=p.category_id and c.is_active
  where p.id=p_product_in and p.bar_id=o.bar_id and p.school_id=o.school_id and p.is_active for share of p;
 if not found then raise exception 'Prodotto nuovo non disponibile in questo bar';end if;
 select * into v_same from public.order_items where order_id=o.id and product_id=p_product_in and removed_at is null for update;
 if found and v_same.unit_cents<>v_in.price_cents then raise exception 'Il nuovo prodotto e'' gia'' nell''ordine con un altro prezzo';end if;
 v_out_cents:=v_line.unit_cents::bigint*p_quantity;v_in_cents:=v_in.price_cents::bigint*p_quantity;v_diff:=v_in_cents-v_out_cents;
 if v_diff>0 then
  if p_method is null or p_method not in ('cash','external_pos') then raise exception 'Scegli come il cliente paga la differenza: contanti o POS';end if;
  v_method:=p_method;
  if v_method='cash' and not exists(select 1 from public.cash_sessions where bar_id=o.bar_id and actor_id=auth.uid() and closed_at is null) then
   raise exception 'Apri il turno di cassa per incassare la differenza in contanti';end if;
 elsif v_diff<0 then v_method:='refund';
 else v_method:='none';end if;
 select (now() at time zone s.timezone)::date into v_date from public.schools s where s.id=o.school_id;
 select * into v_stock from public.daily_stock where bar_id=o.bar_id and product_id=p_product_in and service_date=v_date for update;
 if not found or (v_stock.capacity is not null and v_stock.allocated+p_quantity>v_stock.capacity) then
  raise exception 'Scorte del nuovo prodotto non sufficienti oggi';end if;
 update public.daily_stock set allocated=allocated+p_quantity,updated_at=now() where id=v_stock.id;
 -- Versione precedente dell'ordine, come per modifiche e sostituzioni.
 insert into public.order_versions(order_id,actor_id,snapshot)
 values(o.id,auth.uid(),jsonb_build_object('reason','exchange','items',
  (select jsonb_agg(to_jsonb(i)) from public.order_items i where order_id=o.id and removed_at is null)));
 update public.order_items set removed_at=now() where id=v_line.id;
 if v_line.quantity>p_quantity then
  insert into public.order_items(school_id,bar_id,order_id,product_id,product_name,quantity,unit_cents)
  values(o.school_id,o.bar_id,o.id,v_line.product_id,v_line.product_name,v_line.quantity-p_quantity,v_line.unit_cents);
 end if;
 if v_same.id is not null then update public.order_items set removed_at=now() where id=v_same.id;end if;
 insert into public.order_items(school_id,bar_id,order_id,product_id,product_name,quantity,unit_cents)
 values(o.school_id,o.bar_id,o.id,v_in.id,v_in.name,coalesce(v_same.quantity,0)+p_quantity,v_in.price_cents);
 update public.orders set total_cents=total_cents+v_diff,updated_at=now() where id=o.id;
 insert into public.order_exchanges(school_id,bar_id,order_id,actor_id,request_key,product_out_id,product_out_name,
  product_in_id,product_in_name,quantity,out_cents,in_cents,amount_cents,method,reason)
 values(o.school_id,o.bar_id,o.id,auth.uid(),p_key,p_product_out,v_line.product_name,v_in.id,v_in.name,p_quantity,
  v_out_cents,v_in_cents,abs(v_diff),v_method,left(v_reason,300)) returning * into x;
 if v_diff>0 then
  -- Incasso aggiuntivo al banco: turno di cassa, report e scontrino da emettere.
  insert into public.order_additional_receipts(order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
  values(o.id,o.school_id,o.bar_id,auth.uid(),p_key,v_method,v_diff);
 elsif v_diff<0 then
  -- La differenza torna come e' stata pagata: carta con Stripe o contanti al banco.
  perform app_private.refund_order_credit('individual',o.id,null,-v_diff,p_key,'Cambio prodotto: '||left(v_reason,260));
 end if;
 perform app_private.refresh_individual_balance(o.id);
 perform app_private.notify_order_change('individual',o.id,'Cambio registrato al banco: '||p_quantity||'× '||v_in.name
  ||' al posto di '||v_line.product_name||case when v_diff>0 then '. Differenza pagata al banco.'
   when v_diff<0 then '. La differenza ti viene restituita come hai pagato.' else '.' end);
 return jsonb_build_object('status','recorded','id',x.id,'difference_cents',v_diff,'method',v_method);
end;$$;
revoke all on function public.exchange_order_item(uuid,uuid,integer,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.exchange_order_item(uuid,uuid,integer,uuid,text,uuid,text) to authenticated;

-- Restituzioni in contanti ancora da fare per un ordine (per il personale).
create function public.order_cash_refunds_to_return(p_order uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_school uuid;
begin
 select school_id into v_school from public.orders where id=p_order;
 if v_school is null or not app_private.can_serve_group_bar(v_school) then raise exception 'Ordine non disponibile';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_cents',amount_cents) order by id)
  from public.cash_refund_obligations where order_id=p_order and status='pending'),'[]'::jsonb);
end;$$;
revoke all on function public.order_cash_refunds_to_return(uuid) from public,anon,authenticated;
grant execute on function public.order_cash_refunds_to_return(uuid) to authenticated;
