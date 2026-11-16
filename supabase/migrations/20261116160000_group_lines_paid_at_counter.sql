-- Righe del gruppo saldate al banco.
-- Prima: lo stato di ogni riga veniva solo dai pagamenti online (Stripe), così
-- dopo un incasso al banco (contanti o POS) le righe restavano «Da pagare»
-- anche con ordine consegnato e saldo a zero. Ora una riga senza pagamento
-- online risulta «Pagata al banco» se l'ordine ha un incasso al banco o è
-- stato consegnato, e «Chiusa» se l'ordine è annullato o non ritirato.
-- Il blocco del doppio pagamento resta in begin_group_stripe_checkout.
create or replace function public.group_payable_lines(p_group_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_group public.group_drafts%rowtype;v_user uuid:=auth.uid();
 v_lines jsonb;v_order public.group_orders%rowtype;v_closed text;
begin
 if v_user is null then raise exception 'Accedi per vedere le righe pagabili';end if;
 select * into v_group from public.group_drafts where id=p_group_id;
 if not found or v_group.status not in ('draft','confirmed','approval_pending') or
  not exists(select 1 from public.group_members where group_id=p_group_id
   and user_id=v_user and status='accepted')
 then raise exception 'Gruppo non accessibile';end if;
 select * into v_order from public.group_orders where group_id=p_group_id;
 if found then
  if v_order.status='delivered'
   or exists(select 1 from public.group_counter_payments where group_order_id=v_order.id)
   or exists(select 1 from public.order_additional_receipts where group_order_id=v_order.id)
   or exists(select 1 from public.order_counter_discounts where group_order_id=v_order.id)
  then v_closed:='counter_paid';
  elsif v_order.status in ('cancelled','no_show') then v_closed:='closed';
  end if;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'line_id',i.id,'product_name',i.product_name,'quantity',i.quantity,
  'unit_cents',i.unit_price_cents,
  'amount_cents',i.quantity::bigint*i.unit_price_cents,
  'beneficiary_id',case when v_user=v_group.coordinator_id then i.user_id else null end,
  'payment_state',coalesce(cl.state,v_closed,'available'))
  order by i.product_name,i.id),'[]'::jsonb) into v_lines
 from public.group_cart_items i join public.group_members m
 on m.group_id=i.group_id and m.user_id=i.user_id and m.status='accepted'
 left join public.group_line_payment_claims cl on cl.group_cart_item_id=i.id
 where i.group_id=p_group_id and i.removed_at is null;
 return v_lines||coalesce((select jsonb_agg(jsonb_build_object('line_id',sp.id,
   'product_name',sp.description,'quantity',1,'unit_cents',sp.amount_cents,
   'amount_cents',sp.amount_cents,
   'payment_state',case when sp.state='available' then coalesce(v_closed,'available') else sp.state end))
  from public.order_supplements sp where v_order.id is not null
   and sp.group_order_id=v_order.id and sp.state<>'cancelled'),'[]'::jsonb);
end;$function$;

revoke all on function public.group_payable_lines(uuid) from public,anon;
grant execute on function public.group_payable_lines(uuid) to authenticated;
