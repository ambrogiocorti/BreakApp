-- Integration stress gate: two truly independent PostgreSQL sessions race
-- for the last single unit of physical stock. CI-only disposable database.
-- dblink is installed only in this test database, never in Supabase live.
reset role;
create extension if not exists dblink;

insert into auth.users(id,email) values
 ('55555555-5555-4555-8555-555555555555','race-a@example.invalid'),
 ('66666666-6666-4666-8666-666666666666','race-b@example.invalid')
on conflict(id) do nothing;

-- Exactly ONE additional unit remains, regardless of previously committed tests.
update public.daily_stock set capacity=allocated+1
where school_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
 and product_id='aaaaaaaa-0000-4000-8000-000000000003'
 and service_date=(now() at time zone 'Europe/Rome')::date+2;

do $guard_stock$
begin
 if (select count(*) from public.daily_stock
     where school_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
       and product_id='aaaaaaaa-0000-4000-8000-000000000003'
       and service_date=(now() at time zone 'Europe/Rome')::date+2)<>1 then
   raise exception 'Missing test stock fixture';
 end if;
end;
$guard_stock$;

-- A small pause after the stock row has been locked makes overlap observable.
create function public.test_last_stock_race_delay()
returns trigger language plpgsql set search_path=''
as $pause$
begin
 if new.request_key in (
   '55555555-0000-4000-8000-000000000001'::uuid,
   '66666666-0000-4000-8000-000000000001'::uuid
 ) then
   perform pg_catalog.pg_sleep(1);
 end if;
 return new;
end;
$pause$;
create trigger test_last_stock_race_pause before insert on public.orders
for each row execute function public.test_last_stock_race_delay();

create temporary table race_results(worker text,order_id uuid);

select dblink_connect('race_a','dbname=postgres host=127.0.0.1 user=postgres password=postgres');
select dblink_connect('race_b','dbname=postgres host=127.0.0.1 user=postgres password=postgres');
select dblink_exec('race_a','set role authenticated');
select dblink_exec('race_b','set role authenticated');
select dblink_exec('race_a','set "request.jwt.claim.sub" = ''55555555-5555-4555-8555-555555555555''');
select dblink_exec('race_b','set "request.jwt.claim.sub" = ''66666666-6666-4666-8666-666666666666''');
select dblink_exec('race_a','set "request.jwt.claims" = ''{"aal":"aal1","is_anonymous":false}''');
select dblink_exec('race_b','set "request.jwt.claims" = ''{"aal":"aal1","is_anonymous":false}''');

select dblink_send_query('race_a',$remote$
 select public.submit_individual_order(
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
  'aaaaaaaa-0000-4000-8000-000000000005'::uuid,
  '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
  '55555555-0000-4000-8000-000000000001'::uuid,
  45.0,9.0,10,now()) as order_id
$remote$);
select dblink_send_query('race_b',$remote$
 select public.submit_individual_order(
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
  'aaaaaaaa-0000-4000-8000-000000000005'::uuid,
  '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]'::jsonb,
  '66666666-0000-4000-8000-000000000001'::uuid,
  45.0,9.0,10,now()) as order_id
$remote$);

-- fail_on_error=false records the expected losing transaction without abort.
insert into race_results select 'a',order_id
 from dblink_get_result('race_a',false) as t(order_id uuid);
insert into race_results select 'b',order_id
 from dblink_get_result('race_b',false) as t(order_id uuid);
select dblink_error_message('race_a') as race_a_error \gset
select dblink_error_message('race_b') as race_b_error \gset
select set_config('app.race_a_error', :'race_a_error', false);
select set_config('app.race_b_error', :'race_b_error', false);
select dblink_disconnect('race_a');
select dblink_disconnect('race_b');

drop trigger test_last_stock_race_pause on public.orders;
drop function public.test_last_stock_race_delay();

do $assert_race$
declare v_winners integer;v_losing_error text;
begin
 select count(*) into v_winners from race_results;
 if v_winners <> 1 then
   raise exception 'Expected 1 successful order out of 2 concurrent buyers; observed %',v_winners;
 end if;
 v_losing_error := case when current_setting('app.race_a_error')='OK'
  then current_setting('app.race_b_error')
  else current_setting('app.race_a_error') end;
 if position('Scorte insufficienti' in v_losing_error)=0 then
   raise exception 'Losing request must fail with stock guard, got: %',v_losing_error;
 end if;
 if (select allocated=capacity from public.daily_stock
    where product_id='aaaaaaaa-0000-4000-8000-000000000003'
      and school_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and service_date=(now() at time zone 'Europe/Rome')::date+2) is distinct from true then
   raise exception 'Stock allocation differs from capacity after race';
 end if;
 if (select count(*) from public.orders where request_key in
      ('55555555-0000-4000-8000-000000000001',
       '66666666-0000-4000-8000-000000000001'))<>1 then
   raise exception 'Concurrency created duplicate order records';
 end if;
end;
$assert_race$;
