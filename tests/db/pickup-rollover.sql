-- Fasce settimanali e passaggio alla fascia successiva (20261113130000). Database CI usa e getta.
\set ON_ERROR_STOP on
begin;
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('96111111-1111-4111-8111-111111111111','fasce-cliente@test.invalid',now()),
 ('96333333-3333-4333-8333-333333333333','fasce-barista@test.invalid',now()),
 ('96444444-4444-4444-8444-444444444444','fasce-admin@test.invalid',now());
insert into public.schools(id,slug,name,latitude,longitude,cancel_cutoff_minutes,timezone)
 values('96000000-0000-4000-8000-000000000001','fasce-school','Scuola fasce',45,9,0,'Europe/Rome');
insert into public.bars(id,school_id,name) values('96000000-0000-4000-8000-000000000002','96000000-0000-4000-8000-000000000001','Bar fasce');
insert into public.categories(id,school_id,bar_id,name) values('96000000-0000-4000-8000-000000000003','96000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000002','Cibo');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents) values
 ('96000000-0000-4000-8000-000000000004','96000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000002','96000000-0000-4000-8000-000000000003','Panino',250);
-- Il bar e' aperto tutti i giorni dalle 7:50 alle 16:00.
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select '96000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000002',d,'07:50','16:00' from generate_series(0,6) d;
-- Ultima capacita' impostata: 30 pezzi.
insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 values('96000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000002','96000000-0000-4000-8000-000000000004',(now() at time zone 'Europe/Rome')::date-3,30);
insert into public.school_memberships(school_id,user_id) values
 ('96000000-0000-4000-8000-000000000001','96111111-1111-4111-8111-111111111111'),
 ('96000000-0000-4000-8000-000000000001','96333333-3333-4333-8333-333333333333'),
 ('96000000-0000-4000-8000-000000000001','96444444-4444-4444-8444-444444444444');
insert into public.role_assignments(membership_id,role_code)
 select id,case when user_id='96333333-3333-4333-8333-333333333333' then 'bartender'
  when user_id='96444444-4444-4444-8444-444444444444' then 'school_admin' else 'customer' end
 from public.school_memberships where school_id='96000000-0000-4000-8000-000000000001';
create function pg_temp.actor(p_user uuid,p_role text default 'authenticated',p_aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',coalesce(p_user::text,''),true);
 perform set_config('request.jwt.claims',jsonb_build_object('role',p_role,'aal',p_aal,'is_anonymous',false)::text,true);
end;$$;
create function pg_temp.denied(p_sql text) returns boolean language plpgsql as $d$
begin execute p_sql;return false;exception when others then return true;end;$d$;
create function pg_temp.rome(p_day integer,p_time time) returns timestamptz language sql as $$
 select (((now() at time zone 'Europe/Rome')::date+p_day)+p_time) at time zone 'Europe/Rome' $$;

-- Solo l'Admin con 2FA definisce le fasce settimanali, dentro gli orari del bar.
do $$declare b uuid:='96000000-0000-4000-8000-000000000002';begin
 perform pg_temp.actor('96333333-3333-4333-8333-333333333333','authenticated','aal2');
 if not pg_temp.denied(format('select public.add_pickup_templates(%L,array[1]::smallint[],''09:40'',''09:50'')',b)) then raise exception 'Barista added templates';end if;
 perform pg_temp.actor('96444444-4444-4444-8444-444444444444','authenticated','aal1');
 if not pg_temp.denied(format('select public.add_pickup_templates(%L,array[1]::smallint[],''09:40'',''09:50'')',b)) then raise exception 'Admin without 2FA added templates';end if;
 perform pg_temp.actor('96444444-4444-4444-8444-444444444444','authenticated','aal2');
 if not pg_temp.denied(format('select public.add_pickup_templates(%L,array[1]::smallint[],''16:00'',''16:30'')',b)) then raise exception 'Template outside opening hours accepted';end if;
 if not pg_temp.denied(format('select public.add_pickup_templates(%L,array[]::smallint[],''09:40'',''09:50'')',b)) then raise exception 'Template without weekday accepted';end if;
 if public.add_pickup_templates(b,array[0,1,2,3,4,5,6]::smallint[],'09:40','09:50')<>7 then raise exception 'Expected 7 templates';end if;
 perform public.add_pickup_templates(b,array[0,1,2,3,4,5,6]::smallint[],'11:40','12:00');
 perform public.add_pickup_templates(b,array[0,1,2,3,4,5,6]::smallint[],'13:50','16:00');
 if jsonb_array_length(public.list_pickup_templates(b))<>21 then raise exception 'Template list wrong';end if;
 -- Fasce e scorte dei prossimi 14 giorni create subito; capacita' copiata dall'ultima impostata.
 if (select count(*) from public.pickup_windows where bar_id=b and service_date between (now() at time zone 'Europe/Rome')::date and (now() at time zone 'Europe/Rome')::date+14)<>45
 then raise exception 'Expected 45 generated windows, got %',(select count(*) from public.pickup_windows where bar_id=b);end if;
 if (select count(*) from public.daily_stock where bar_id=b and service_date>=(now() at time zone 'Europe/Rome')::date and capacity=30)<>15
 then raise exception 'Daily stock not generated with last capacity';end if;
 -- Rigenerare non duplica nulla.
 if app_private.generate_template_windows(now(),14,b)<>0 then raise exception 'Generation not idempotent';end if;
end;$$;

-- Ordine non ritirato: 9:40 -> 11:40 -> 13:50, poi alla chiusura no-show e rimborso.
do $$declare n integer;o uuid;w1 uuid;w2 uuid;w3 uuid;b uuid:='96000000-0000-4000-8000-000000000002';d date:=(now() at time zone 'Europe/Rome')::date+1;begin
 select id into w1 from public.pickup_windows where bar_id=b and service_date=d and starts_at='09:40';
 select id into w2 from public.pickup_windows where bar_id=b and service_date=d and starts_at='11:40';
 select id into w3 from public.pickup_windows where bar_id=b and service_date=d and starts_at='13:50';
 perform pg_temp.actor('96111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order(b,w1,'[{"product_id":"96000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 perform pg_temp.actor('96333333-3333-4333-8333-333333333333');
 perform public.collect_workflow_balance('individual',o,'cash',gen_random_uuid());
 reset role;
 -- Durante la fascia non succede nulla.
 if app_private.roll_over_missed_pickups(pg_temp.rome(1,'09:45'))<>0 then raise exception 'Moved during its own window';end if;
 n:=app_private.roll_over_missed_pickups(pg_temp.rome(1,'09:51'));
 if n<>1 or (select pickup_window_id from public.orders where id=o)<>w2 then raise exception 'Not moved to 11:40';end if;
 if not exists(select 1 from public.customer_notifications where order_id=o and message like '%11:40–12:00%') then raise exception 'Customer not told about the move';end if;
 n:=app_private.roll_over_missed_pickups(pg_temp.rome(1,'12:00'));
 if n<>1 or (select pickup_window_id from public.orders where id=o)<>w3 then raise exception 'Not moved to 13:50';end if;
 -- Ultima fascia del giorno: resta dov'e'.
 n:=app_private.roll_over_missed_pickups(pg_temp.rome(1,'16:05'));
 if n<>0 or (select pickup_window_id from public.orders where id=o)<>w3 then raise exception 'Moved past the last window';end if;
 if (select status from public.orders where id=o)<>'confirmed' then raise exception 'Status changed by rollover';end if;
 -- Alla chiusura vale la regola esistente: no-show e rimborso al cliente.
 perform pg_temp.actor(null,'service_role');
 perform public.maintain_daily_orders(pg_temp.rome(1,'16:01'));
 reset role;
 if (select status from public.orders where id=o)<>'no_show' then raise exception 'Not closed as no-show';end if;
 if (select sum(amount_cents) from public.cash_refund_obligations where order_id=o)<>250 then raise exception 'Cash refund not created';end if;
end;$$;

-- Un ordine ritirato in tempo non si sposta; un ordine di un altro giorno nemmeno.
do $$declare o uuid;w uuid;b uuid:='96000000-0000-4000-8000-000000000002';d date:=(now() at time zone 'Europe/Rome')::date+2;begin
 select id into w from public.pickup_windows where bar_id=b and service_date=d and starts_at='09:40';
 perform pg_temp.actor('96111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order(b,w,'[{"product_id":"96000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 reset role;
 if app_private.roll_over_missed_pickups(pg_temp.rome(1,'09:51'))<>0 then raise exception 'Moved an order of another day';end if;
 update public.orders set status='delivered' where id=o;
 if app_private.roll_over_missed_pickups(pg_temp.rome(2,'09:51'))<>0 then raise exception 'Moved a delivered order';end if;
end;$$;

-- Rimuovere una fascia settimanale non cancella le fasce gia' create.
do $$declare t uuid;b uuid:='96000000-0000-4000-8000-000000000002';n bigint;begin
 perform pg_temp.actor('96444444-4444-4444-8444-444444444444','authenticated','aal2');
 select (x->>'id')::uuid into t from jsonb_array_elements(public.list_pickup_templates(b)) x limit 1;
 select count(*) into n from public.pickup_windows where bar_id=b;
 perform public.remove_pickup_template(t);
 if jsonb_array_length(public.list_pickup_templates(b))<>20 or (select count(*) from public.pickup_windows where bar_id=b)<>n
 then raise exception 'Template removal wrong';end if;
 perform pg_temp.actor('96111111-1111-4111-8111-111111111111');
 if not pg_temp.denied(format('select public.list_pickup_templates(%L)',b)) then raise exception 'Customer listed templates';end if;
end;$$;

-- Il client non legge ne' scrive la tabella.
set local role authenticated;
do $$begin
 perform set_config('request.jwt.claim.sub','96444444-4444-4444-8444-444444444444',true);
 if not pg_temp.denied('select count(*) from public.pickup_window_templates') then raise exception 'Client read templates';end if;
end;$$;
reset role;
rollback;
