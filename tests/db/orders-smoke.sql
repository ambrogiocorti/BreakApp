-- Integrazione base 01 + 03 + 04: eseguire dopo le migrazioni.
-- Nessun dato viene inserito nel Supabase reale.
insert into public.schools(id,slug,name,latitude,longitude)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','scuola-test-a','Scuola Test A',45.0,9.0),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','scuola-test-b','Scuola Test B',46.0,10.0);
insert into public.bars(id,school_id,name)
values('aaaaaaaa-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Bar A'),
('bbbbbbbb-0000-4000-8000-000000000001','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Bar B');
insert into public.categories(id,school_id,bar_id,name)
values('aaaaaaaa-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
'aaaaaaaa-0000-4000-8000-000000000001','Panini');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents)
values('aaaaaaaa-0000-4000-8000-000000000003',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
'aaaaaaaa-0000-4000-8000-000000000001',
'aaaaaaaa-0000-4000-8000-000000000002','Panino',250);
insert into auth.users(id,email)
values('11111111-1111-4111-8111-111111111111','cliente-a@example.invalid'),
('22222222-2222-4222-8222-222222222222','cliente-b@example.invalid'),
('33333333-3333-4333-8333-333333333333','barista-a@example.invalid');
insert into public.school_memberships(id,school_id,user_id)
values('aaaaaaaa-0000-4000-8000-000000000004',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
'33333333-3333-4333-8333-333333333333');
insert into public.role_assignments(membership_id,role_code)
values('aaaaaaaa-0000-4000-8000-000000000004','bartender');
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at)
values('aaaaaaaa-0000-4000-8000-000000000005',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
'aaaaaaaa-0000-4000-8000-000000000001',
(now() at time zone 'Europe/Rome')::date+2,
time '10:50',time '11:10');
insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
'aaaaaaaa-0000-4000-8000-000000000001',
'aaaaaaaa-0000-4000-8000-000000000003',
(now() at time zone 'Europe/Rome')::date+2,1);

-- Il primo cliente ordina l'unico panino rimasto.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.submit_individual_order(
  'aaaaaaaa-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000005',
  '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
  '11111111-0000-4000-8000-000000000001',
  45.0,9.0,10,now()
) as order_id \gset

do $$
begin
 if (select count(*) from public.orders where customer_id=auth.uid()) <> 1 then
  raise exception 'Ordine cliente assente';
 end if;
end; $$;
-- Ripetizione identica: deve dare la stessa riga e non riservare stock ancora.
select public.submit_individual_order(
  'aaaaaaaa-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000005',
  '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
  '11111111-0000-4000-8000-000000000001',
  45.0,9.0,10,now()
) as repeat_id \gset
select case when :'order_id'=:'repeat_id' then 'OK idempotence'
  else (1/0)::text end as check_idempotence;

-- Con ordini attivi l'Admin non può cambiare l'orario con un UPDATE diretto.
reset role;
do $
declare denied boolean:=false;
begin
 begin
   update public.pickup_windows set starts_at=time '10:51'
   where id='aaaaaaaa-0000-4000-8000-000000000005';
 exception when others then
   if position('La fascia ha ordini attivi' in sqlerrm)>0 then denied:=true;
   else raise; end if;
 end;
 if not denied then raise exception 'Fascia modificata nonostante ordine attivo'; end if;
end; $;
set role authenticated;

-- Altro cliente: non può vedere ordine di A e non deve superare stock=1.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$
declare v_failed boolean:=false;
begin
  if (select count(*) from public.orders) <> 0 then
    raise exception 'RLS customer leak';
  end if;
  begin
    perform public.submit_individual_order(
      'aaaaaaaa-0000-4000-8000-000000000001',
      'aaaaaaaa-0000-4000-8000-000000000005',
      '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
      '22222222-0000-4000-8000-000000000002',
      45.0,9.0,10,now());
  exception when others then
    if position('Scorte insufficienti' in sqlerrm)>0 then
      v_failed:=true;
    else
      raise;
    end if;
  end;
  if not v_failed then raise exception 'Overbooking consentito'; end if;
end; $$;

-- Il barista della scuola A può preparare/incassare/consegnare.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.advance_individual_order(:'order_id'::uuid,'ready');
select public.record_individual_counter_payment(
  :'order_id'::uuid,'cash','33333333-0000-4000-8000-000000000001');
select public.advance_individual_order(:'order_id'::uuid,'delivered');
-- Risultato finale reale per l'ordine e una sola allocazione stock.
reset role;
do $$
begin
 if (select status from public.orders where customer_id=
   '11111111-1111-4111-8111-111111111111')<>'delivered' then
   raise exception 'La consegna non è registrata';
 end if;
 if (select allocated from public.daily_stock where product_id=
   'aaaaaaaa-0000-4000-8000-000000000003')<>1 then
   raise exception 'Allocazione stock errata';
 end if;
 if (select count(*) from public.counter_payments)<>1 then
   raise exception 'Incasso non idempotente';
 end if;
end; $$;

-- Solo un Admin della scuola con AAL2 può configurare posizione e prenotazioni.
insert into auth.users(id,email)
values('44444444-4444-4444-8444-444444444444','admin-a@example.invalid');
insert into public.school_memberships(id,school_id,user_id)
values('aaaaaaaa-0000-4000-8000-000000000006',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','44444444-4444-4444-8444-444444444444');
insert into public.role_assignments(membership_id,role_code)
values('aaaaaaaa-0000-4000-8000-000000000006','school_admin');
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $$
declare denied boolean:=false;
begin
 begin
   perform public.configure_school_booking(
     'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',45,9,1000,30,10,3,null,null);
 exception when others then
   if position('2FA' in sqlerrm)>0 then denied:=true; else raise; end if;
 end;
 if not denied then raise exception 'Admin without MFA changed configuration'; end if;
end; $$;
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.configure_school_booking(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',45,9,900,30,10,3,null,null);
reset role;
do $$
begin
 if (select pickup_radius_m from public.schools where id=
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>900 then
  raise exception 'Admin configuration was not saved';
 end if;
end; $$;
