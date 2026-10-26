-- Eseguire dopo tests/db/orders-smoke.sql, tests/db/catalog-media.sql e migration 07.
-- Test di autorità tenant-scoped, MFA, pause, chiusura e riapertura.
set role authenticated;
-- L'Admin senza AAL2 NON può configurare orari.
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $test_no_mfa$
declare v_denied boolean:=false;
begin
 begin
   perform public.set_bar_weekly_hours(
     'aaaaaaaa-0000-4000-8000-000000000001',
     extract(dow from (now() at time zone 'Europe/Rome')::date+2)::int,
     '[{"starts_at":"10:00","ends_at":"12:00"}]'::jsonb);
 exception when others then v_denied:=true;
 end;
 if not v_denied then raise exception 'AAL1 admin configured hours'; end if;
end;
$test_no_mfa$;
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.set_bar_weekly_hours(
  'aaaaaaaa-0000-4000-8000-000000000001',
  extract(dow from (now() at time zone 'Europe/Rome')::date+2)::int,
  '[{"starts_at":"10:00","ends_at":"12:00"}]'::jsonb
);
do $test_hours$
begin
 if (select count(*) from public.bar_opening_hours
   where bar_id='aaaaaaaa-0000-4000-8000-000000000001')<>1
 then raise exception 'Weekly hours not saved';end if;
end;
$test_hours$;

-- Nuova fascia realmente compresa negli orari.
reset role;
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at)
values(
 'aaaaaaaa-0000-4000-8000-000000000099',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'aaaaaaaa-0000-4000-8000-000000000001',
 (now() at time zone 'Europe/Rome')::date+2,
 '11:20','11:40'
);
update public.daily_stock set capacity=3 where product_id='aaaaaaaa-0000-4000-8000-000000000003';

-- Barista autenticato può mettere in pausa, senza cancellare ordine già consegnato.
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.set_bar_booking_pause(
 'aaaaaaaa-0000-4000-8000-000000000001',true,'Sospensione operativa'
);

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $test_paused$
declare v_denied boolean:=false;
begin
 begin
 perform public.submit_individual_order(
   'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000099',
   '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
   '22222222-0000-4000-8000-000000000099',45.0,9.0,10,now()
 );
 exception when others then
   if position('sospese' in sqlerrm)>0 then v_denied:=true;
   else raise; end if;
 end;
 if not v_denied then raise exception 'Checkout accepted during pause';end if;
end;
$test_paused$;

-- Barista riapre le prenotazioni e l'ordine diventa confermabile.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.set_bar_booking_pause(
 'aaaaaaaa-0000-4000-8000-000000000001',false,''
);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.submit_individual_order(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000099',
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
 '22222222-0000-4000-8000-000000000099',45.0,9.0,10,now()
) as created_order \gset

-- Anteprima reale dell'impatto e chiusura straordinaria.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $test_preview$
declare v_preview jsonb;
begin
 v_preview:=public.preview_bar_closure(
   'aaaaaaaa-0000-4000-8000-000000000001',
   (now() at time zone 'Europe/Rome')::date+2,'11:20','11:40');
 if (v_preview->>'active_orders')::int<>1 or (v_preview->>'paid_cents')::int<>0
 then raise exception 'Closure preview incorrect %',v_preview;end if;
end;
$test_preview$;

-- Barista non può eseguire una chiusura pianificata riservata ad Admin AAL2.
do $test_planned_denied$
declare v_denied boolean:=false;
begin
 begin
 perform public.close_bar_interval('aaaaaaaa-0000-4000-8000-000000000001',
  (now() at time zone 'Europe/Rome')::date+2,'11:20','11:40',
  'planned','Chiusura programmata');
 exception when others then v_denied:=true;
 end;
 if not v_denied then raise exception 'Bartender accepted planned closure';end if;
end;
$test_planned_denied$;

select public.close_bar_interval('aaaaaaaa-0000-4000-8000-000000000001',
  (now() at time zone 'Europe/Rome')::date+2,'11:20','11:40',
  'extraordinary','Guasto al banco') as closure_id \gset

-- La chiusura annulla soltanto l'ordine interessato e restituisce stock.
reset role;
do $test_closure$
begin
 if (select status from public.orders where request_key='22222222-0000-4000-8000-000000000099')
    <>'cancelled' then raise exception 'Affected order not cancelled';end if;
 if (select status from public.orders where customer_id='11111111-1111-4111-8111-111111111111')
    <>'delivered' then raise exception 'Previously delivered order changed';end if;
 if (select allocated from public.daily_stock where product_id='aaaaaaaa-0000-4000-8000-000000000003')<>1
 then raise exception 'Stock was not restored';end if;
 if (select count(*) from public.customer_notifications where user_id='22222222-2222-4222-8222-222222222222')<>1
 then raise exception 'Customer closure notification absent';end if;
end;
$test_closure$;

-- Dopo una riapertura l'ordine annullato non viene ripristinato.
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.reopen_bar_interval(:'closure_id'::uuid);
reset role;
do $test_reopen$
begin
 if exists(select 1 from public.bar_closures where reopened_at is null)
 then raise exception 'Closure not reopened';end if;
 if exists(select 1 from public.orders
   where request_key='22222222-0000-4000-8000-000000000099'
   and status<>'cancelled')
 then raise exception 'Cancelled order resurrected';end if;
end;
$test_reopen$;
