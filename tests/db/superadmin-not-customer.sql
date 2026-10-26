-- Dopo tests/db/workspace-role.sql: l'account 4444 è Super Admin globale.
-- Dati fittizi esclusivamente nel database PostgreSQL temporaneo CI.
begin;

do $reject_superadmin_insert$
declare v_denied boolean:=false;
begin
 begin
  insert into public.orders(
    school_id,bar_id,customer_id,pickup_window_id,request_key,status,total_cents
  ) values (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'aaaaaaaa-0000-4000-8000-000000000001',
    '44444444-4444-4444-8444-444444444444',
    'aaaaaaaa-0000-4000-8000-000000000005',
    '44444444-0000-4000-8000-000000000011','confirmed',100
  );
 exception when sqlstate '42501' then
  if position('Super Admin' in sqlerrm)>0 then v_denied:=true;
  else raise;end if;
 end;
 if not v_denied then
  raise exception 'Super Admin could place a customer order';
 end if;
end;
$reject_superadmin_insert$;

do $normal_customer_still_allowed$
declare v_id uuid;
begin
 insert into public.orders(
   school_id,bar_id,customer_id,pickup_window_id,request_key,status,total_cents
 ) values (
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'aaaaaaaa-0000-4000-8000-000000000001',
   '22222222-2222-4222-8222-222222222222',
   'aaaaaaaa-0000-4000-8000-000000000005',
   '22222222-0000-4000-8000-000000000012','confirmed',100
 ) returning id into v_id;
 if v_id is null then raise exception 'Normal customer insert blocked';end if;
end;
$normal_customer_still_allowed$;
rollback;
