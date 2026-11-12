-- BreakApp: sconto per chi paga al banco (decisione di Ambrogio del 12/11/2026).
--
-- Il bar non puo' applicare una commissione a chi paga con carta (art. 62
-- Codice del Consumo, d.lgs. 11/2010 art. 3 c. 4). Si usa la strada opposta:
-- il listino resta il prezzo pieno (pagato anche online con Stripe) e l'Admin
-- della scuola puo' concedere uno sconto da 0 a 10% a chi salda al banco in
-- contanti o con il POS del bar. Default 0: nulla cambia finche' l'Admin non
-- lo decide.
--
-- Modello contabile: il totale dell'ordine non cambia. Quando il banco incassa
-- il residuo, registra l'incasso reale (residuo meno sconto) e, a parte, una
-- riga di sconto in public.order_counter_discounts. Lo sconto conta come
-- importo saldato in app_private.order_paid_cents ma non entra mai in cassa.
-- Nei rimborsi la parte scontata viene stornata (riga negativa) e si
-- restituisce solo il denaro realmente incassato.
-- Le funzioni sostituite partono dai corpi installati il 12/11/2026.
--
-- Aggiornamento 12/11/2026 pomeriggio: l'Admin sceglie una di tre regole
-- (schools.price_policy): 'none' nessuno sconto e nessun rincaro;
-- 'counter_discount' sconto 0,5-10% a chi paga al banco; 'price_increase'
-- tutti i prezzi del bar aumentano della percentuale scelta (0,5-20%), per
-- chiunque e con qualsiasi metodo di pagamento, cosi' il bar recupera la
-- commissione Stripe senza un sovrapprezzo vietato sulla carta. Il prezzo
-- deciso dal bar resta in products.base_price_cents; price_cents e' il prezzo
-- mostrato e incassato, arrotondato per eccesso ai 5 centesimi.

alter table public.schools add column if not exists counter_discount_bps integer not null default 0;
alter table public.schools add constraint schools_counter_discount_range
 check (counter_discount_bps between 0 and 1000);
alter table public.schools add column if not exists price_policy text not null default 'none';
alter table public.schools add column if not exists price_markup_bps integer not null default 0;
alter table public.schools add constraint schools_price_policy_valid
 check (price_policy in ('none','counter_discount','price_increase')
  and price_markup_bps between 0 and 2000
  and (price_policy='counter_discount' or counter_discount_bps=0)
  and (price_policy='price_increase' or price_markup_bps=0));
grant select(counter_discount_bps,price_policy,price_markup_bps) on public.schools to anon,authenticated;

-- Prezzo deciso dal bar, valorizzato solo quando la scuola applica il rincaro.
alter table public.products add column if not exists base_price_cents integer
 check (base_price_cents between 0 and 10000000);
grant update(base_price_cents) on public.products to authenticated;

create table public.order_counter_discounts(
 id uuid primary key default gen_random_uuid(),
 order_id uuid references public.orders(id),
 group_order_id uuid references public.group_orders(id),
 school_id uuid not null references public.schools(id),
 bar_id uuid not null references public.bars(id),
 actor_id uuid references auth.users(id),
 source_key text not null unique check (length(source_key) between 3 and 120),
 discount_bps integer not null check (discount_bps between 0 and 1000),
 amount_cents bigint not null check (amount_cents<>0),
 created_at timestamptz not null default now(),
 check (num_nonnulls(order_id,group_order_id)=1)
);
create index order_counter_discounts_order on public.order_counter_discounts(order_id);
create index order_counter_discounts_group on public.order_counter_discounts(group_order_id);
create index order_counter_discounts_school on public.order_counter_discounts(school_id,created_at);
create index order_counter_discounts_bar on public.order_counter_discounts(bar_id);
create index order_counter_discounts_actor on public.order_counter_discounts(actor_id);
alter table public.order_counter_discounts enable row level security;
revoke all on public.order_counter_discounts from public,anon,authenticated;

-- Sconto in centesimi, arrotondato al centesimo; mai pari o superiore al residuo.
create function app_private.counter_discount_cents(p_due bigint,p_bps integer)
returns bigint language sql immutable set search_path='' as $$
 select case when coalesce(p_due,0)<=0 or coalesce(p_bps,0)<=0 then 0::bigint
  else least(p_due-1,(p_due*p_bps+5000)/10000)::bigint end;
$$;
revoke all on function app_private.counter_discount_cents(bigint,integer) from public,anon,authenticated;

create function app_private.order_counter_discount_net(p_kind text,p_id uuid)
returns bigint language sql stable set search_path='' as $$
 select coalesce(sum(amount_cents),0)::bigint from public.order_counter_discounts
 where (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id);
$$;
revoke all on function app_private.order_counter_discount_net(text,uuid) from public,anon,authenticated;

-- Lo sconto concesso al banco conta come saldato (non come incasso).
create or replace function app_private.order_paid_cents(p_kind text, p_id uuid)
 returns bigint language sql stable set search_path to ''
as $function$
 with scope as(select group_id from public.group_orders where p_kind='group' and id=p_id),
 online as(select a.amount_cents-coalesce((select sum(r.amount_cents) from public.payment_refunds r where r.payment_id=a.id),0) cents
  from public.payment_attempts a where a.status='succeeded' and
   ((p_kind='individual' and a.order_id=p_id) or (p_kind='group' and a.group_id=(select group_id from scope)))),
 receipts as(select amount_cents cents from public.counter_payments where p_kind='individual' and order_id=p_id
  union all select amount_cents from public.group_counter_payments where p_kind='group' and group_order_id=p_id
  union all select amount_cents from public.order_additional_receipts where
   (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)
  union all select amount_cents from public.order_counter_discounts where
   (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)),
 cash_refunds as(select amount_cents cents from public.cash_refund_obligations where
  (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id))
 select greatest(0,coalesce((select sum(cents) from online),0)+coalesce((select sum(cents) from receipts),0)-coalesce((select sum(cents) from cash_refunds),0))::bigint;
$function$;

-- Incasso al banco del residuo (singolo o gruppo) con lo sconto della scuola.
create or replace function public.collect_workflow_balance(p_kind text, p_order uuid, p_method text, p_key uuid)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare j jsonb;v_due bigint;v_bps integer;v_discount bigint;v_cash bigint;
 v_existing public.order_additional_receipts%rowtype;o public.group_orders%rowtype;
begin
 j:=app_private.order_scope(p_kind,p_order,'staff');
 if p_method is null or p_method not in ('cash','external_pos') or p_key is null or j->>'status' not in ('confirmed','preparing','ready') then raise exception 'Incasso non valido';end if;
 select * into v_existing from public.order_additional_receipts where actor_id=auth.uid() and request_key=p_key;
 if found then if coalesce(v_existing.order_id,v_existing.group_order_id)<>p_order or v_existing.method<>p_method then raise exception 'Idempotenza incoerente';end if;
  return jsonb_build_object('status','duplicate','id',v_existing.id,'amount_cents',v_existing.amount_cents,
   'discount_cents',coalesce((select amount_cents from public.order_counter_discounts where source_key='receipt:'||v_existing.id),0));end if;
 if p_kind='group' then select * into o from public.group_orders where id=p_order;
  if o.pickup_lease_actor is distinct from auth.uid() or o.pickup_lease_until is null or o.pickup_lease_until<=now() then raise exception 'Scansiona il QR del coordinatore prima di incassare';end if;end if;
 perform app_private.assert_no_pending_checkout(p_kind,p_order);
 v_due:=(j->>'total_cents')::bigint-app_private.order_paid_cents(p_kind,p_order);
 if v_due<=0 then raise exception 'Ordine già saldato';end if;
 select counter_discount_bps into v_bps from public.schools where id=(j->>'school_id')::uuid;
 v_discount:=app_private.counter_discount_cents(v_due,v_bps);
 v_cash:=v_due-v_discount;
 insert into public.order_additional_receipts(order_id,group_order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
 values(case when p_kind='individual' then p_order end,case when p_kind='group' then p_order end,
 (j->>'school_id')::uuid,(j->>'bar_id')::uuid,auth.uid(),p_key,p_method,v_cash) returning * into v_existing;
 if v_discount>0 then
  insert into public.order_counter_discounts(order_id,group_order_id,school_id,bar_id,actor_id,source_key,discount_bps,amount_cents)
  values(v_existing.order_id,v_existing.group_order_id,v_existing.school_id,v_existing.bar_id,auth.uid(),'receipt:'||v_existing.id,v_bps,v_discount);
 end if;
 if p_kind='individual' then perform app_private.refresh_individual_balance(p_order);end if;
 return jsonb_build_object('status','recorded','id',v_existing.id,'amount_cents',v_cash,'discount_cents',v_discount);
end;$function$;

-- Rimborsi: prima Stripe (invariato), poi la parte non online viene divisa
-- in proporzione tra sconto (stornato, nessun denaro) e denaro da restituire.
create or replace function app_private.refund_order_credit(p_kind text, p_id uuid, p_line uuid, p_amount bigint, p_key uuid, p_reason text)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare x record;j jsonb;v_left bigint:=p_amount;v_available bigint;v_piece bigint;v_cash bigint;v_disc bigint;v_disc_piece bigint;v_cash_piece bigint;
begin
 if p_amount<=0 then return;end if;
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if exists(select 1 from public.payment_refunds where request_key=p_key) or exists(select 1 from public.cash_refund_obligations where request_key=p_key)
  or exists(select 1 from public.order_counter_discounts where source_key='refund:'||p_key) then return;end if;
 for x in select a.* from public.payment_attempts a where a.status='succeeded' and
  ((p_kind='individual' and a.order_id=p_id) or (p_kind='group' and a.group_id=(j->>'group_id')::uuid and
   (p_line is null or exists(select 1 from public.payment_item_allocations al
    left join public.order_supplements sp on sp.id=al.supplement_id
    where al.payment_id=a.id and (al.group_cart_item_id=(select group_cart_item_id from public.group_order_lines where id=p_line)
      or sp.group_line_id=p_line))))) order by a.created_at desc,a.id for update loop
  select greatest(0,x.amount_cents-coalesce(sum(amount_cents),0)) into v_available from public.payment_refunds where payment_id=x.id;
  if p_kind='group' and p_line is not null then
   select least(v_available,coalesce(sum(al.amount_cents),0)) into v_available from public.payment_item_allocations al
   left join public.order_supplements sp on sp.id=al.supplement_id where al.payment_id=x.id and
    (al.group_cart_item_id=(select group_cart_item_id from public.group_order_lines where id=p_line) or sp.group_line_id=p_line);
  end if;
  v_piece:=least(v_left,v_available);
  if v_piece>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
   values(x.id,p_key,v_piece,'pending',left(p_reason,300),jsonb_build_object('kind',p_kind,'order_id',p_id,'line_id',p_line));v_left:=v_left-v_piece;end if;
  exit when v_left=0;
 end loop;
 if v_left>0 then
  select coalesce(sum(cents),0) into v_cash from(
   select amount_cents cents from public.counter_payments where p_kind='individual' and order_id=p_id
   union all select amount_cents from public.group_counter_payments where p_kind='group' and group_order_id=p_id
   union all select amount_cents from public.order_additional_receipts where (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)) q;
  v_cash:=v_cash-coalesce((select sum(amount_cents) from public.cash_refund_obligations where
   (p_kind='individual' and order_id=p_id) or (p_kind='group' and group_order_id=p_id)),0);
  v_disc:=greatest(0,app_private.order_counter_discount_net(p_kind,p_id));
  if v_cash+v_disc<v_left then raise exception 'Credito da riconciliare: nessuna modifica economica applicata';end if;
  v_disc_piece:=case when v_disc=0 then 0 else least(v_disc,round(v_left::numeric*v_disc/(v_cash+v_disc))::bigint) end;
  v_cash_piece:=v_left-v_disc_piece;
  if v_cash_piece>v_cash then v_cash_piece:=v_cash;v_disc_piece:=v_left-v_cash;end if;
  if v_disc_piece>0 then
   insert into public.order_counter_discounts(order_id,group_order_id,school_id,bar_id,actor_id,source_key,discount_bps,amount_cents)
   values(case when p_kind='individual' then p_id end,case when p_kind='group' then p_id end,
    (j->>'school_id')::uuid,(j->>'bar_id')::uuid,auth.uid(),'refund:'||p_key,0,-v_disc_piece);
  end if;
  if v_cash_piece>0 then insert into public.cash_refund_obligations(school_id,owner_id,order_id,group_order_id,request_key,amount_cents,reason)
   values((j->>'school_id')::uuid,(j->>'owner_id')::uuid,case when p_kind='individual' then p_id end,
    case when p_kind='group' then p_id end,p_key,v_cash_piece,left(p_reason,300));end if;
 end if;
 if p_kind='individual' then perform app_private.refresh_individual_balance(p_id);end if;
end;$function$;

-- Dettagli ordine: residuo pieno (online) e importo da incassare al banco.
create or replace function public.workflow_order_details(p_kind text, p_order uuid)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare j jsonb;v_lines jsonb;v_due bigint;v_bps integer;begin
 j:=app_private.order_scope(p_kind,p_order,'either');
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('name',case when p_kind='individual'
  then (select product_name from public.order_items where id=x.line_id) else (select name from public.group_order_lines where id=x.line_id) end)),'[]'::jsonb)
 into v_lines from app_private.order_lines(p_kind,p_order) x where quantity>0;
 v_due:=greatest(0,(j->>'total_cents')::bigint-app_private.order_paid_cents(p_kind,p_order));
 select counter_discount_bps into v_bps from public.schools where id=(j->>'school_id')::uuid;
 return j||jsonb_build_object('lines',v_lines,'paid_cents',app_private.order_paid_cents(p_kind,p_order),'due_cents',v_due,
  'counter_discount_bps',coalesce(v_bps,0),'counter_due_cents',v_due-app_private.counter_discount_cents(v_due,v_bps),
  'counter_discount_cents',greatest(0,app_private.order_counter_discount_net(p_kind,p_order)));
end;$function$;

-- Manifest offline: ogni ordine porta lo sconto e l'importo da incassare,
-- cosi' il tablet senza rete chiede la cifra giusta e il server la ritrova.
create or replace function public.offline_ready_order_manifest(p_school uuid)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare j jsonb;groups jsonb;l public.staff_offline_leases%rowtype;v_id uuid;v_bps integer;begin
 if not app_private.has_barista_role(p_school,auth.uid()) then raise exception 'Barista richiesto';end if;
 select * into l from public.staff_offline_leases where barista_id=auth.uid() and school_id=p_school and revoked_at is null and expires_at>now();
 if not found then raise exception 'Autorizza il dispositivo prima del manifest';end if;
 select counter_discount_bps into v_bps from public.schools where id=p_school;v_bps:=coalesce(v_bps,0);
 j:=app_private.legacy_individual_manifest(p_school);
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'kind','group','bar_id',o.bar_id,'display_no','G-'||left(o.id::text,8),
 'pickup_token',o.pickup_token,'total_cents',o.total_cents,'due_cents',greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id)),
 'counter_discount_bps',v_bps,
 'counter_due_cents',greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id))-app_private.counter_discount_cents(greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id)),v_bps),
 'payment_status',case when app_private.order_paid_cents('group',o.id)>=o.total_cents then 'paid' else 'due' end,
 'server_updated_at',o.updated_at,'can_pickup_at',case when b.preparation_mode='ready_made' then (w.service_date+w.starts_at) at time zone s.timezone else now() end)), '[]'::jsonb)
 into groups from public.group_orders o join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id join public.bars b on b.id=o.bar_id
 where o.school_id=p_school and o.status='ready' and w.service_date=(now() at time zone s.timezone)::date;
 j:=jsonb_set(j,'{orders}',coalesce((select jsonb_agg(x||jsonb_build_object('kind','individual','due_cents',d.due,
 'counter_discount_bps',v_bps,'counter_due_cents',d.due-app_private.counter_discount_cents(d.due,v_bps),
 'can_pickup_at',(select case when b.preparation_mode='ready_made' then (w.service_date+w.starts_at) at time zone s.timezone else now() end from public.orders o join public.bars b on b.id=o.bar_id join public.pickup_windows w on w.id=o.pickup_window_id join public.schools s on s.id=o.school_id where o.id=(x->>'id')::uuid)))
 from jsonb_array_elements(j->'orders') x
 cross join lateral (select greatest(0,(x->>'total_cents')::bigint-app_private.order_paid_cents('individual',(x->>'id')::uuid)) due) d),'[]'::jsonb)||groups);
 insert into app_private.offline_manifests(barista_id,school_id,device_id,generation,payload,paid_payment_ids) values(auth.uid(),p_school,l.device_id,l.generation,j,
 array(select a.id from public.payment_attempts a where a.school_id=p_school and a.status='succeeded' and
  (a.order_id in(select (x->>'id')::uuid from jsonb_array_elements(j->'orders') x where x->>'kind'='individual')
   or a.group_id in(select o.group_id from public.group_orders o where o.id in(select (x->>'id')::uuid from jsonb_array_elements(j->'orders') x where x->>'kind'='group'))))) returning id into v_id;
 return j||jsonb_build_object('snapshot_id',v_id);
end;$function$;

-- Ritiro offline singolo: l'importo atteso e lo sconto vengono dal manifest
-- (manifest precedenti: nessuno sconto).
create or replace function app_private.post_snapshot_individual_pickup(p_event uuid, p_force boolean)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare e public.offline_events_inbox%rowtype;l public.staff_offline_leases%rowtype;m app_private.offline_manifests%rowtype;
 o public.orders%rowtype;snap jsonb;v_amount bigint;v_due bigint;v_excess bigint;v_piece bigint;v_available bigint;a record;
 v_bps integer;v_discount bigint;
begin
 select * into e from public.offline_events_inbox where id=p_event for update;
 if e.event_kind<>'cash_pickup' then raise exception 'Tipo evento non valido';end if;
 if e.status='applied' then return jsonb_build_object('status','duplicate');end if;
 if p_force then
  if e.status<>'approved' or not app_private.can_review_school_offline(e.school_id) then raise exception 'Revisione Admin con 2FA richiesta';end if;
 else
  if e.barista_id<>auth.uid() or not app_private.has_barista_role(e.school_id,auth.uid()) then raise exception 'Autore richiesto';end if;
  select * into l from public.staff_offline_leases where barista_id=e.barista_id for update;
  if l.device_id is distinct from e.device_id or l.generation<>e.lease_generation or l.revoked_at is not null or l.expires_at<=now()
   or e.local_recorded_at is null or e.local_recorded_at<l.issued_at or e.local_recorded_at>least(l.expires_at,e.received_at+interval '2 minutes')
  then return jsonb_build_object('status','quarantined','reason','Lease revocato/scaduto o tempo non verificabile');end if;
 end if;
 select * into m from app_private.offline_manifests where id=(e.payload->>'snapshot_id')::uuid and barista_id=e.barista_id and school_id=e.school_id
  and device_id=e.device_id and generation=e.lease_generation;
 if not found then return jsonb_build_object('status','quarantined','reason','Manifest server non verificabile');end if;
 select x into snap from jsonb_array_elements(m.payload->'orders') x where x->>'id'=e.payload->>'order_id' and x->>'kind'='individual';
 select * into o from public.orders where id=(e.payload->>'order_id')::uuid for update;
 v_amount:=(e.payload->>'collected_cents')::bigint;
 if snap is null or o.school_id<>e.school_id or o.pickup_token::text<>e.payload->>'pickup_token' or o.status<>'ready'
  or o.total_cents<>(snap->>'total_cents')::bigint or v_amount<>coalesce(snap->>'counter_due_cents',snap->>'due_cents')::bigint
  or (not p_force and e.local_recorded_at<(snap->>'can_pickup_at')::timestamptz)
 then return jsonb_build_object('status','quarantined','reason','QR, fascia, importo o stato diverso dal manifest');end if;
 perform app_private.assert_no_pending_checkout('individual',o.id);
 v_bps:=coalesce((snap->>'counter_discount_bps')::integer,0);
 v_due:=greatest(0,o.total_cents-app_private.order_paid_cents('individual',o.id));
 v_discount:=case when v_amount>0 then app_private.counter_discount_cents(v_due,v_bps) else 0 end;
 v_excess:=greatest(0,v_amount-(v_due-v_discount));
 if v_amount=0 and v_due>0 then return jsonb_build_object('status','quarantined','reason','Saldo non completo');end if;
 if v_amount>0 then
  if v_excess>0 and not p_force and (select coalesce(sum(pa.amount_cents),0) from public.payment_attempts pa where pa.order_id=o.id and pa.status='succeeded' and pa.id<>all(m.paid_payment_ids))<v_excess
   then return jsonb_build_object('status','quarantined','reason','Eccedenza non attribuibile con certezza ai pagatori successivi al manifest');end if;
  insert into public.order_additional_receipts(order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
  values(o.id,o.school_id,o.bar_id,e.barista_id,e.id,'cash',v_amount);
  if v_discount>0 then
   insert into public.order_counter_discounts(order_id,school_id,bar_id,actor_id,source_key,discount_bps,amount_cents)
   values(o.id,o.school_id,o.bar_id,e.barista_id,'offline:'||e.id,v_bps,v_discount);
  end if;
  for a in select * from public.payment_attempts where order_id=o.id and status='succeeded'
   and (p_force or id<>all(m.paid_payment_ids)) order by updated_at desc,id for update loop
   exit when v_excess=0;
   select greatest(0,a.amount_cents-coalesce(sum(amount_cents),0)) into v_available from public.payment_refunds where payment_id=a.id;
   v_piece:=least(v_excess,v_available);
   if v_piece>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
    values(a.id,e.id,v_piece,'pending','Doppio incasso gruppo: contanti offline e Stripe',jsonb_build_object('kind','individual','order_id',o.id));v_excess:=v_excess-v_piece;end if;
  end loop;
  if v_excess>0 then raise exception 'Eccedenza non riconciliata: revisione necessaria';end if;
 end if;
 insert into public.offline_order_pickups(offline_event_id,order_id,school_id,actor_id,collected_cents) values(e.id,o.id,o.school_id,e.barista_id,v_amount);
 update public.orders set status='delivered',payment_status='paid',updated_at=now() where id=o.id;
 insert into public.order_audit(order_id,school_id,actor_id,action) values(o.id,o.school_id,e.barista_id,'offline:delivered');
 update public.offline_events_inbox set status='applied',review_reason='Consegna gruppo riconciliata',reviewed_at=now() where id=e.id;
 return jsonb_build_object('status','applied','order_id',o.id,'refund_pending',v_amount>v_due-v_discount);
end;$function$;

create or replace function app_private.post_offline_group_pickup(p_event uuid, p_force boolean)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare e public.offline_events_inbox%rowtype;l public.staff_offline_leases%rowtype;m app_private.offline_manifests%rowtype;
 o public.group_orders%rowtype;snap jsonb;v_amount bigint;v_due bigint;v_excess bigint;v_piece bigint;v_available bigint;a record;
 v_bps integer;v_discount bigint;
begin
 select * into e from public.offline_events_inbox where id=p_event for update;
 if e.event_kind<>'group_pickup' then raise exception 'Tipo evento non valido';end if;
 if e.status='applied' then return jsonb_build_object('status','duplicate');end if;
 if p_force then
  if e.status<>'approved' or not app_private.can_review_school_offline(e.school_id) then raise exception 'Revisione Admin con 2FA richiesta';end if;
 else
  if e.barista_id<>auth.uid() or not app_private.has_barista_role(e.school_id,auth.uid()) then raise exception 'Autore richiesto';end if;
  select * into l from public.staff_offline_leases where barista_id=e.barista_id for update;
  if l.device_id is distinct from e.device_id or l.generation<>e.lease_generation or l.revoked_at is not null or l.expires_at<=now()
   or e.local_recorded_at is null or e.local_recorded_at<l.issued_at or e.local_recorded_at>least(l.expires_at,e.received_at+interval '2 minutes')
  then return jsonb_build_object('status','quarantined','reason','Lease revocato/scaduto o tempo non verificabile');end if;
 end if;
 select * into m from app_private.offline_manifests where id=(e.payload->>'snapshot_id')::uuid and barista_id=e.barista_id and school_id=e.school_id
  and device_id=e.device_id and generation=e.lease_generation;
 if not found then return jsonb_build_object('status','quarantined','reason','Manifest server non verificabile');end if;
 select x into snap from jsonb_array_elements(m.payload->'orders') x where x->>'id'=e.payload->>'order_id' and x->>'kind'='group';
 select * into o from public.group_orders where id=(e.payload->>'order_id')::uuid for update;
 v_amount:=(e.payload->>'collected_cents')::bigint;
 if snap is null or o.school_id<>e.school_id or o.pickup_token::text<>e.payload->>'pickup_token' or o.status<>'ready'
  or o.total_cents<>(snap->>'total_cents')::bigint or v_amount<>coalesce(snap->>'counter_due_cents',snap->>'due_cents')::bigint
  or (not p_force and e.local_recorded_at<(snap->>'can_pickup_at')::timestamptz)
 then return jsonb_build_object('status','quarantined','reason','QR, fascia, importo o stato diverso dal manifest');end if;
 perform app_private.assert_no_pending_checkout('group',o.id);
 v_bps:=coalesce((snap->>'counter_discount_bps')::integer,0);
 v_due:=greatest(0,o.total_cents-app_private.order_paid_cents('group',o.id));
 v_discount:=case when v_amount>0 then app_private.counter_discount_cents(v_due,v_bps) else 0 end;
 v_excess:=greatest(0,v_amount-(v_due-v_discount));
 if v_amount=0 and v_due>0 then return jsonb_build_object('status','quarantined','reason','Saldo non completo');end if;
 if v_amount>0 then
  if v_excess>0 and not p_force and (select coalesce(sum(pa.amount_cents),0) from public.payment_attempts pa where pa.group_id=o.group_id and pa.status='succeeded' and pa.id<>all(m.paid_payment_ids))<v_excess
   then return jsonb_build_object('status','quarantined','reason','Eccedenza non attribuibile con certezza ai pagatori successivi al manifest');end if;
  insert into public.order_additional_receipts(group_order_id,school_id,bar_id,actor_id,request_key,method,amount_cents)
  values(o.id,o.school_id,o.bar_id,e.barista_id,e.id,'cash',v_amount);
  if v_discount>0 then
   insert into public.order_counter_discounts(group_order_id,school_id,bar_id,actor_id,source_key,discount_bps,amount_cents)
   values(o.id,o.school_id,o.bar_id,e.barista_id,'offline:'||e.id,v_bps,v_discount);
  end if;
  for a in select * from public.payment_attempts where group_id=o.group_id and status='succeeded'
   and (p_force or id<>all(m.paid_payment_ids)) order by updated_at desc,id for update loop
   exit when v_excess=0;
   select greatest(0,a.amount_cents-coalesce(sum(amount_cents),0)) into v_available from public.payment_refunds where payment_id=a.id;
   v_piece:=least(v_excess,v_available);
   if v_piece>0 then insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason,workflow_context)
    values(a.id,e.id,v_piece,'pending','Doppio incasso gruppo: contanti offline e Stripe',jsonb_build_object('kind','group','order_id',o.id));v_excess:=v_excess-v_piece;end if;
  end loop;
  if v_excess>0 then raise exception 'Eccedenza non riconciliata: revisione necessaria';end if;
 end if;
 insert into public.offline_group_pickups(offline_event_id,group_order_id,manifest_id,actor_id,collected_cents) values(e.id,o.id,m.id,e.barista_id,v_amount);
 update public.group_orders set status='delivered',pickup_lease_until=null,pickup_lease_actor=null,updated_at=now() where id=o.id;
 insert into public.group_order_audit(group_order_id,actor_id,action,details) values(o.id,e.barista_id,'offline:delivered',jsonb_build_object('event_id',e.id,'cash_cents',v_amount,'discount_cents',v_discount));
 update public.offline_events_inbox set status='applied',review_reason='Consegna gruppo riconciliata',reviewed_at=now() where id=e.id;
 return jsonb_build_object('status','applied','group_order_id',o.id,'refund_pending',v_amount>v_due-v_discount);
end;$function$;

-- Dettaglio gruppo: stesso importo da incassare al banco mostrato al coordinatore e al banco.
do $group_details$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('public.group_order_details(uuid)'::regprocedure);
 if pg_catalog.strpos(v_def,'''pickup_window_id'',v_order.pickup_window_id,')=0 then
  raise exception 'group_order_details non compatibile con la migrazione sconto al banco';end if;
 v_def:=pg_catalog.replace(v_def,'''pickup_window_id'',v_order.pickup_window_id,',
  '''counter_discount_bps'',(select counter_discount_bps from public.schools where id=v_order.school_id),'
  ||'''counter_due_cents'',greatest(0,v_order.total_cents-app_private.order_paid_cents(''group'',v_order.id))'
  ||'-app_private.counter_discount_cents(greatest(0,v_order.total_cents-app_private.order_paid_cents(''group'',v_order.id)),'
  ||'(select counter_discount_bps from public.schools where id=v_order.school_id)),'
  ||'''pickup_window_id'',v_order.pickup_window_id,');
 execute v_def;
end;
$group_details$;

-- Report: gli sconti al banco sono un dato a parte; l'incasso netto resta il denaro reale.
do $report$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('public.school_financial_report(uuid,date,date)'::regprocedure);
 if pg_catalog.strpos(v_def,'''individual_orders'',v_orders,')=0 then
  raise exception 'school_financial_report non compatibile con la migrazione sconto al banco';end if;
 v_def:=pg_catalog.replace(v_def,'''individual_orders'',v_orders,',
  '''counter_discounts_cents'',coalesce((select sum(amount_cents) from public.order_counter_discounts where school_id=p_school and created_at>=v_start and created_at<v_end),0),'
  ||'''individual_orders'',v_orders,');
 execute v_def;
end;
$report$;

-- Lo storico delle impostazioni registra anche lo sconto.
do $audit_discount$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('app_private.audit_school_settings()'::regprocedure);
 if pg_catalog.strpos(v_def,'''pickup_radius_m'',old.pickup_radius_m')=0
  or pg_catalog.strpos(v_def,'''pickup_radius_m'',new.pickup_radius_m')=0 then
  raise exception 'Audit scuola non compatibile con la migrazione sconto al banco';end if;
 v_def:=pg_catalog.replace(v_def,'''pickup_radius_m'',old.pickup_radius_m',
  '''pickup_radius_m'',old.pickup_radius_m,''counter_discount_bps'',old.counter_discount_bps');
 v_def:=pg_catalog.replace(v_def,'''pickup_radius_m'',new.pickup_radius_m',
  '''pickup_radius_m'',new.pickup_radius_m,''counter_discount_bps'',new.counter_discount_bps');
 execute v_def;
end;
$audit_discount$;

-- Rincaro percentuale arrotondato per eccesso ai 5 centesimi (comodo in contanti).
create or replace function app_private.marked_up_price_cents(p_base bigint,p_bps integer)
returns bigint language sql immutable set search_path=''
as $$ select case when p_base is null or p_base<=0 or coalesce(p_bps,0)<=0 then p_base
 else ((p_base*(10000+p_bps)+49999)/50000)*5 end $$;
revoke all on function app_private.marked_up_price_cents(bigint,integer) from public,anon,authenticated;

-- Ogni scrittura di un prodotto passa da qui: il valore inserito dall'Admin e'
-- il prezzo del bar; con il rincaro attivo price_cents viene ricalcolato.
-- Una scrittura che non cambia ne' prezzo ne' prezzo base ricalcola dal prezzo
-- base gia' salvato (serve quando l'Admin cambia la regola).
create or replace function app_private.apply_product_price_policy()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_input bigint;v_bps integer;
begin
 if tg_op='INSERT' then v_input:=coalesce(new.base_price_cents,new.price_cents);
 elsif new.base_price_cents is distinct from old.base_price_cents and new.base_price_cents is not null then
  v_input:=new.base_price_cents;
 elsif new.price_cents is distinct from old.price_cents then v_input:=new.price_cents;
 else v_input:=coalesce(old.base_price_cents,old.price_cents);end if;
 select case when s.price_policy='price_increase' then s.price_markup_bps else 0 end into v_bps
 from public.schools s where s.id=new.school_id;
 if coalesce(v_bps,0)>0 then
  new.base_price_cents:=v_input;
  new.price_cents:=app_private.marked_up_price_cents(v_input,v_bps);
 else
  new.base_price_cents:=null;new.price_cents:=v_input;
 end if;
 return new;
end;
$$;
revoke all on function app_private.apply_product_price_policy() from public,anon,authenticated;
create trigger products_price_policy before insert or update on public.products
 for each row execute function app_private.apply_product_price_policy();

-- Il Super Admin salva il prezzo del bar anche dal pannello pilota.
do $pilot_price$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('public.platform_save_product(uuid,uuid,uuid,text,text,integer,text,text[],boolean)'::regprocedure);
 if pg_catalog.strpos(v_def,'price_cents=p_price_cents,')=0 then
  raise exception 'platform_save_product non compatibile con la migrazione prezzi';end if;
 v_def:=pg_catalog.replace(v_def,'price_cents=p_price_cents,','price_cents=p_price_cents,base_price_cents=p_price_cents,');
 execute v_def;
end;
$pilot_price$;

-- Lo storico delle impostazioni registra anche la regola prezzi.
do $audit_policy$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('app_private.audit_school_settings()'::regprocedure);
 v_def:=pg_catalog.replace(v_def,'''counter_discount_bps'',old.counter_discount_bps',
  '''counter_discount_bps'',old.counter_discount_bps,''price_policy'',old.price_policy,''price_markup_bps'',old.price_markup_bps');
 v_def:=pg_catalog.replace(v_def,'''counter_discount_bps'',new.counter_discount_bps',
  '''counter_discount_bps'',new.counter_discount_bps,''price_policy'',new.price_policy,''price_markup_bps'',new.price_markup_bps');
 if pg_catalog.strpos(v_def,'old.price_markup_bps')=0 or pg_catalog.strpos(v_def,'new.price_markup_bps')=0 then
  raise exception 'Audit scuola non compatibile con la migrazione prezzi';end if;
 execute v_def;
end;
$audit_policy$;

-- Solo l'Admin della scuola con 2FA sceglie la regola. Cambiando regola i
-- prezzi dei prodotti vengono ricalcolati subito; gli ordini gia' fatti
-- mantengono il prezzo con cui sono stati creati.
create or replace function public.set_school_price_policy(p_school uuid,p_policy text,p_bps integer)
returns void language plpgsql security definer set search_path=''
as $set_policy$
begin
 if auth.uid() is null or (auth.jwt()->>'aal')<>'aal2' then
  raise exception 'È richiesta autenticazione Admin con 2FA';end if;
 if not exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=p_school and m.user_id=auth.uid()
   and m.membership_status='active' and r.role_code='school_admin') then
  raise exception 'Non sei Admin della scuola selezionata';end if;
 if p_policy='none' then
  if coalesce(p_bps,0)<>0 then raise exception 'Senza sconto né rincaro la percentuale deve essere 0';end if;
 elsif p_policy='counter_discount' then
  if p_bps is null or p_bps not between 50 and 1000 then
   raise exception 'Sconto non valido: da 0,5 a 10%%';end if;
 elsif p_policy='price_increase' then
  if p_bps is null or p_bps not between 50 and 2000 then
   raise exception 'Aumento non valido: da 0,5 a 20%%';end if;
 else raise exception 'Regola prezzi non valida';end if;
 update public.schools set price_policy=p_policy,
  counter_discount_bps=case when p_policy='counter_discount' then p_bps else 0 end,
  price_markup_bps=case when p_policy='price_increase' then p_bps else 0 end
 where id=p_school;
 if not found then raise exception 'Scuola non disponibile';end if;
 update public.products set price_cents=price_cents where school_id=p_school;
end;
$set_policy$;
revoke all on function public.set_school_price_policy(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.set_school_price_policy(uuid,text,integer) to authenticated;
