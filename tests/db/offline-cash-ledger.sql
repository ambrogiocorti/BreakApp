-- Itemized cash sales, offline lease, replay, stock conflicts and audit.
reset role;
update public.daily_stock set capacity=allocated+30
where product_id='aaaaaaaa-0000-4000-8000-000000000003'
 and bar_id='aaaaaaaa-0000-4000-8000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $catalog$
declare c jsonb;
begin
 c:=public.offline_bartender_catalog('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 if jsonb_array_length(c->'products')=0 or jsonb_array_length(c->'bars')=0
 then raise exception 'Offline catalog missing';end if;
end;$catalog$;
select public.record_online_bar_cash_sale(
 'aaaaaaaa-0000-4000-8000-000000000001',
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
 '33333333-0000-4000-8000-000000000399','Vendita contanti') as online_sale \gset
select set_config('app.sale_online',
 (:'online_sale'::jsonb->>'sale_id'),false);
select public.record_online_bar_cash_sale(
 'aaaaaaaa-0000-4000-8000-000000000001',
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
 '33333333-0000-4000-8000-000000000399','Vendita contanti') as same_online \gset
select set_config('app.online_repeated',(:'same_online'::jsonb->>'status'),false);
do $dedupe_online$
begin
 if current_setting('app.online_repeated')<>'duplicate'
 then raise exception 'Online cash sale not idempotent';end if;
end;$dedupe_online$;
-- Fixture gets the lease ID server-side; staff never reads the private lease table.
reset role;
select set_config('app.offline_sale_device',
 (select device_id::text from public.staff_offline_leases
  where barista_id='33333333-3333-4333-8333-333333333333'),false);
select set_config('app.offline_sale_generation',
 (select generation::text from public.staff_offline_leases
  where barista_id='33333333-3333-4333-8333-333333333333'),false);
select set_config('app.offline_stock_old',
 (select allocated::text from public.daily_stock
  where product_id='aaaaaaaa-0000-4000-8000-000000000003'
    and bar_id='aaaaaaaa-0000-4000-8000-000000000001'),false);
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.stage_my_offline_event(
 current_setting('app.offline_sale_device')::uuid,
 current_setting('app.offline_sale_generation')::bigint,
 '33333333-0000-4000-8000-000000000400','counter_sale',now(),
 '{"bar_id":"aaaaaaaa-0000-4000-8000-000000000001","method":"cash",
 "amount_cents":250,"note":"Banco offline",
 "items":[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003",
 "quantity":1,"unit_cents":250}]}'::jsonb) as event \gset
select set_config('app.offline_sale_event',
 (:'event'::jsonb->>'id'),false);
select public.reconcile_my_offline_cash_event(
 current_setting('app.offline_sale_event')::uuid) as posted \gset
select set_config('app.offline_sale_posted',(:'posted'::jsonb->>'status'),false);
reset role;
do $posted$
begin
 if current_setting('app.offline_sale_posted')<>'applied'
   or (select status from public.offline_events_inbox where id=
    current_setting('app.offline_sale_event')::uuid)<>'applied'
 then raise exception 'Valid lease offline cash was not posted';end if;
 if (select allocated from public.daily_stock
  where bar_id='aaaaaaaa-0000-4000-8000-000000000001'
  and product_id='aaaaaaaa-0000-4000-8000-000000000003')
  <>current_setting('app.offline_stock_old')::integer+1
 then raise exception 'Offline sale stock not allocated';end if;
end;$posted$;
-- Force an inventory shortage: cash is still real, stock becomes conflicted.
update public.daily_stock set capacity=allocated
where bar_id='aaaaaaaa-0000-4000-8000-000000000001'
 and product_id='aaaaaaaa-0000-4000-8000-000000000003';
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.stage_my_offline_event(
 current_setting('app.offline_sale_device')::uuid,
 current_setting('app.offline_sale_generation')::bigint,
 '33333333-0000-4000-8000-000000000401','counter_sale',now(),
 '{"bar_id":"aaaaaaaa-0000-4000-8000-000000000001","method":"cash",
 "amount_cents":250,"items":[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003",
 "quantity":1,"unit_cents":250}]}'::jsonb) as conflict_event \gset
select set_config('app.offline_conflict_event',
 (:'conflict_event'::jsonb->>'id'),false);
select public.reconcile_my_offline_cash_event(
 current_setting('app.offline_conflict_event')::uuid) as pending \gset
select set_config('app.offline_pending',(:'pending'::jsonb->>'status'),false);
do $quarantine$
begin
 if current_setting('app.offline_pending')<>'quarantined'
 then raise exception 'Stock shortage offline should be quarantined';end if;
end;$quarantine$;
select set_config('request.jwt.claim.sub','adadadad-5555-4555-8555-555555555555',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.review_school_offline_event(
 current_setting('app.offline_conflict_event')::uuid,true,
 'Contanti verificati fisicamente dal responsabile') as review;
select public.apply_approved_offline_cash_event(
 current_setting('app.offline_conflict_event')::uuid) as applied \gset
select set_config('app.offline_conflict_posted',(:'applied'::jsonb->>'status'),false);
reset role;
do $conflict$
begin
 if current_setting('app.offline_conflict_posted')<>'applied' or
   (select count(*) from public.offline_stock_conflicts
    where offline_event_id=current_setting('app.offline_conflict_event')::uuid
      and status='open')<>1
 then raise exception 'Cash lost or stock conflict not created';end if;
 if (select status from public.bar_counter_sales
  where offline_event_id=current_setting('app.offline_conflict_event')::uuid)<>'stock_conflict'
 then raise exception 'Sale conflict flag missing';end if;
end;$conflict$;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $blocking$
declare denied boolean:=false;
begin
 begin
  perform public.record_online_bar_cash_sale(
  'aaaaaaaa-0000-4000-8000-000000000001',
  '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
  '33333333-0000-4000-8000-000000000402','');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Conflicted stock sold again';end if;
end;$blocking$;
select set_config('app.offline_conflict_id',
 (public.list_school_stock_conflicts('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')->0->>'id'),false);
reset role;
select set_config('app.offline_restock',
 (select (allocated+10)::text from public.daily_stock
  where bar_id='aaaaaaaa-0000-4000-8000-000000000001'
  and product_id='aaaaaaaa-0000-4000-8000-000000000003'),false);
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.resolve_offline_stock_conflict(
 current_setting('app.offline_conflict_id')::uuid,
 current_setting('app.offline_restock')::integer,
 'Verifica fisica rifornimento e priorità prenotazioni');
reset role;
do $resolved$
begin
 if exists(select 1 from public.offline_stock_conflicts where status='open'
  and offline_event_id=current_setting('app.offline_conflict_event')::uuid)
 then raise exception 'Inventory conflict not resolved';end if;
 if not exists(select 1 from public.offline_stock_conflict_audit a join
  public.offline_stock_conflicts c on c.id=a.conflict_id
  where c.offline_event_id=current_setting('app.offline_conflict_event')::uuid)
 then raise exception 'Missing inventory resolution audit';end if;
end;$resolved$;
