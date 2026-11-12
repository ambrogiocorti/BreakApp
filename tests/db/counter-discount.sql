-- Sconto per chi paga al banco (20261112090000). Database CI usa e getta.
\set ON_ERROR_STOP on
begin;
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('91111111-1111-4111-8111-111111111111','sconto-cliente@test.invalid',now()),
 ('93333333-3333-4333-8333-333333333333','sconto-barista@test.invalid',now()),
 ('94444444-4444-4444-8444-444444444444','sconto-admin@test.invalid',now());
insert into public.schools(id,slug,name,latitude,longitude,cancel_cutoff_minutes)
 values('91000000-0000-4000-8000-000000000001','sconto-school','Scuola sconto',45,9,0);
insert into public.bars(id,school_id,name) values('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','Bar sconto');
insert into public.categories(id,school_id,bar_id,name) values('91000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','Cibo');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents) values
 ('91000000-0000-4000-8000-000000000004','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000003','Panino',250);
insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 select p.school_id,p.bar_id,p.id,(now() at time zone 'Europe/Rome')::date+d,100 from public.products p cross join generate_series(0,1) d
 where p.bar_id='91000000-0000-4000-8000-000000000002';
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select '91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002',d,'00:00','23:59' from generate_series(0,6) d;
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('91000000-0000-4000-8000-000000000007','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date+1,'12:00','12:15'),
 ('91000000-0000-4000-8000-000000000009','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date,'00:01','23:58');
insert into public.school_memberships(school_id,user_id) values
 ('91000000-0000-4000-8000-000000000001','93333333-3333-4333-8333-333333333333'),
 ('91000000-0000-4000-8000-000000000001','94444444-4444-4444-8444-444444444444');
insert into public.role_assignments(membership_id,role_code)
 select id,case when user_id='93333333-3333-4333-8333-333333333333' then 'bartender' else 'school_admin' end
 from public.school_memberships where school_id='91000000-0000-4000-8000-000000000001';
create function pg_temp.actor(p_user uuid,p_role text default 'authenticated',p_aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',p_user::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('role',p_role,'aal',p_aal,'is_anonymous',false)::text,true);
end;$$;
create function pg_temp.denied(p_sql text) returns boolean language plpgsql as $d$
begin execute p_sql;return false;exception when others then return true;end;$d$;

-- Default 0: nessuno sconto, il banco incassa il residuo pieno.
do $$begin
 if (select counter_discount_bps from public.schools where id='91000000-0000-4000-8000-000000000001')<>0 then raise exception 'Default discount is not zero';end if;
 if app_private.counter_discount_cents(250,500)<>13 or app_private.counter_discount_cents(250,0)<>0
  or app_private.counter_discount_cents(1,1000)<>0 or app_private.counter_discount_cents(0,1000)<>0
  or app_private.counter_discount_cents(1000,1000)<>100 then raise exception 'Discount rounding incorrect';end if;
end;$$;

-- Solo l'Admin della scuola con 2FA imposta lo sconto, entro 0-10%.
do $$begin
 perform pg_temp.actor('93333333-3333-4333-8333-333333333333','authenticated','aal2');
 if not pg_temp.denied($q$select public.set_school_price_policy('91000000-0000-4000-8000-000000000001','counter_discount',500)$q$) then raise exception 'Barista set the discount';end if;
 perform pg_temp.actor('94444444-4444-4444-8444-444444444444','authenticated','aal1');
 if not pg_temp.denied($q$select public.set_school_price_policy('91000000-0000-4000-8000-000000000001','counter_discount',500)$q$) then raise exception 'Admin without 2FA set the discount';end if;
 perform pg_temp.actor('94444444-4444-4444-8444-444444444444','authenticated','aal2');
 if not pg_temp.denied($q$select public.set_school_price_policy('91000000-0000-4000-8000-000000000001','counter_discount',1001)$q$) then raise exception 'Discount above 10%% accepted';end if;
 if not pg_temp.denied($q$select public.set_school_price_policy('91000000-0000-4000-8000-000000000001','counter_discount',-1)$q$) then raise exception 'Negative discount accepted';end if;
 perform public.set_school_price_policy('91000000-0000-4000-8000-000000000001','counter_discount',500);
 if (select counter_discount_bps from public.schools where id='91000000-0000-4000-8000-000000000001')<>500 then raise exception 'Discount not saved';end if;
 if not exists(select 1 from app_private.school_settings_audit where school_id='91000000-0000-4000-8000-000000000001'
  and (previous->>'counter_discount_bps')::int=0 and (current->>'counter_discount_bps')::int=500) then raise exception 'Discount change not audited';end if;
end;$$;

-- Incasso al banco: 2,50 euro con sconto 5% = 2,37 incassati e 0,13 di sconto.
do $$declare o uuid;d jsonb;r jsonb;rep jsonb;ref jsonb;begin
 perform pg_temp.actor('91111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000007','[{"product_id":"91000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 d:=public.workflow_order_details('individual',o);
 if (d->>'due_cents')::int<>250 or (d->>'counter_due_cents')::int<>237 or (d->>'counter_discount_bps')::int<>500 then raise exception 'Customer details wrong: %',d;end if;
 perform pg_temp.actor('93333333-3333-4333-8333-333333333333');
 r:=public.collect_workflow_balance('individual',o,'external_pos','91000000-0000-4000-8000-0000000000a1');
 if (r->>'amount_cents')::int<>237 or (r->>'discount_cents')::int<>13 then raise exception 'Counter collection wrong: %',r;end if;
 if (select amount_cents from public.order_additional_receipts where order_id=o)<>237 then raise exception 'Receipt is not the real money';end if;
 if (select amount_cents from public.order_counter_discounts where order_id=o)<>13 then raise exception 'Discount row missing';end if;
 if app_private.order_paid_cents('individual',o)<>250 or (select payment_status from public.orders where id=o)<>'paid' then raise exception 'Discounted order not settled';end if;
 -- Replay idempotente: stesso incasso, nessuna riga in piu'.
 r:=public.collect_workflow_balance('individual',o,'external_pos','91000000-0000-4000-8000-0000000000a1');
 if r->>'status'<>'duplicate' or (r->>'discount_cents')::int<>13 or (select count(*) from public.order_counter_discounts where order_id=o)<>1 then raise exception 'Replay not idempotent: %',r;end if;
 -- Report: denaro reale e sconti separati.
 perform pg_temp.actor('94444444-4444-4444-8444-444444444444','authenticated','aal2');
 rep:=public.school_financial_report('91000000-0000-4000-8000-000000000001',(now() at time zone 'Europe/Rome')::date,(now() at time zone 'Europe/Rome')::date);
 if (rep->>'external_pos_cents')::int<>237 or (rep->>'counter_discounts_cents')::int<>13 or (rep->>'net_recorded_cents')::int<>237 then raise exception 'Report wrong: %',rep;end if;
 -- Rimborso a ordine concluso: si restituisce solo il denaro incassato, lo sconto viene stornato.
 update public.orders set status='delivered' where id=o;
 ref:=public.request_completed_order_refund('individual',o,gen_random_uuid(),'Verifica rimborso con sconto al banco');
 if (ref->>'cash_pending')::int<>237 then raise exception 'Refund returned more than collected: %',ref;end if;
 if app_private.order_counter_discount_net('individual',o)<>0 or app_private.order_paid_cents('individual',o)<>0
  or (select payment_status from public.orders where id=o)<>'refund_pending' then raise exception 'Refund did not balance';end if;
end;$$;

-- Annullamento prima del ritiro di un ordine gia' saldato al banco.
do $$declare o uuid;begin
 perform pg_temp.actor('91111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000007','[{"product_id":"91000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now());
 perform pg_temp.actor('93333333-3333-4333-8333-333333333333');
 perform public.collect_workflow_balance('individual',o,'external_pos',gen_random_uuid());
 if (select amount_cents from public.order_additional_receipts where order_id=o)<>475 then raise exception 'Two items: expected 475 collected';end if;
 perform app_private.cancel_workflow_order('individual',o,'Prova annullamento con sconto',gen_random_uuid());
 if (select sum(amount_cents) from public.cash_refund_obligations where order_id=o)<>475
  or app_private.order_counter_discount_net('individual',o)<>0 or app_private.order_paid_cents('individual',o)<>0
 then raise exception 'Cancellation refund with discount wrong';end if;
end;$$;

-- Offline: il manifest porta l'importo scontato e il server lo ritrova.
do $$declare o uuid;o2 uuid;device uuid:=gen_random_uuid();receipt jsonb;m jsonb;e jsonb;r jsonb;begin
 perform pg_temp.actor('91111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000007','[{"product_id":"91000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 o2:=public.submit_individual_order('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000007','[{"product_id":"91000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 update public.orders set status='ready',pickup_window_id='91000000-0000-4000-8000-000000000009' where id in (o,o2);
 update public.daily_stock set allocated=allocated-2 where product_id='91000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date+1;
 update public.daily_stock set allocated=allocated+2 where product_id='91000000-0000-4000-8000-000000000004' and service_date=(now() at time zone 'Europe/Rome')::date;
 perform pg_temp.actor('93333333-3333-4333-8333-333333333333');
 receipt:=public.transfer_my_offline_device('91000000-0000-4000-8000-000000000001',device);
 perform public.record_cash_operation('91000000-0000-4000-8000-000000000002',gen_random_uuid(),'open',1000,'',gen_random_uuid());
 m:=public.offline_ready_order_manifest('91000000-0000-4000-8000-000000000001');
 if not exists(select 1 from jsonb_array_elements(m->'orders') x where x->>'id'=o::text
  and (x->>'due_cents')::int=250 and (x->>'counter_due_cents')::int=237 and (x->>'counter_discount_bps')::int=500)
 then raise exception 'Manifest lacks discounted amount: %',m;end if;
 -- Il listino pieno al posto dell'importo scontato va in revisione.
 e:=public.stage_my_offline_event(device,(receipt->>'generation')::bigint,gen_random_uuid(),'cash_pickup',now(),
  jsonb_build_object('order_id',o2,'pickup_token',(select pickup_token from public.orders where id=o2),
   'bar_id','91000000-0000-4000-8000-000000000002','snapshot_id',m->>'snapshot_id','collected_cents',250));
 r:=public.reconcile_my_offline_pickup_event((e->>'id')::uuid);
 if r->>'status'<>'quarantined' then raise exception 'Full price offline cash not quarantined: %',r;end if;
 e:=public.stage_my_offline_event(device,(receipt->>'generation')::bigint,gen_random_uuid(),'cash_pickup',now(),
  jsonb_build_object('order_id',o,'pickup_token',(select pickup_token from public.orders where id=o),
   'bar_id','91000000-0000-4000-8000-000000000002','snapshot_id',m->>'snapshot_id','collected_cents',237));
 r:=public.reconcile_my_offline_pickup_event((e->>'id')::uuid);
 if r->>'status'<>'applied' or (r->>'refund_pending')::boolean then raise exception 'Offline discounted pickup not applied: %',r;end if;
 if (select amount_cents from public.order_additional_receipts where order_id=o)<>237
  or (select amount_cents from public.order_counter_discounts where order_id=o)<>13
  or app_private.order_paid_cents('individual',o)<>250 then raise exception 'Offline discount ledger wrong';end if;
 if not exists(select 1 from public.cash_entries where source_key like 'order_additional_receipts:%' and amount_cents=237)
 then raise exception 'Cash drawer did not receive the real amount';end if;
end;$$;

-- Regola 'price_increase': tutti i prezzi salgono, nessuno sconto al banco.
do $$declare s uuid:='91000000-0000-4000-8000-000000000001';pr uuid:='91000000-0000-4000-8000-000000000004';np uuid;begin
 perform pg_temp.actor('94444444-4444-4444-8444-444444444444','authenticated','aal2');
 if app_private.marked_up_price_cents(250,1000)<>275 or app_private.marked_up_price_cents(250,1150)<>280
  or app_private.marked_up_price_cents(100,150)<>105 or app_private.marked_up_price_cents(0,2000)<>0
  or app_private.marked_up_price_cents(250,0)<>250 then raise exception 'Markup rounding incorrect';end if;
 if not pg_temp.denied(format('select public.set_school_price_policy(%L,''price_increase'',2001)',s)) then raise exception 'Markup above 20%% accepted';end if;
 if not pg_temp.denied(format('select public.set_school_price_policy(%L,''none'',500)',s)) then raise exception 'None with percentage accepted';end if;
 if not pg_temp.denied(format('select public.set_school_price_policy(%L,''surcharge'',500)',s)) then raise exception 'Unknown policy accepted';end if;
 perform public.set_school_price_policy(s,'price_increase',1000);
 if (select counter_discount_bps from public.schools where id=s)<>0 then raise exception 'Discount kept with markup';end if;
 if (select price_cents from public.products where id=pr)<>275 or (select base_price_cents from public.products where id=pr)<>250
 then raise exception 'Markup not applied to product';end if;
 if not exists(select 1 from app_private.school_settings_audit where school_id=s and current->>'price_policy'='price_increase'
  and (current->>'price_markup_bps')::int=1000) then raise exception 'Markup change not audited';end if;
 -- L'Admin scrive il prezzo del bar, anche uguale al prezzo rincarato attuale.
 update public.products set price_cents=275,base_price_cents=275 where id=pr;
 if (select price_cents from public.products where id=pr)<>305 or (select base_price_cents from public.products where id=pr)<>275
 then raise exception 'Edited base price not marked up';end if;
 update public.products set name='Panino buono' where id=pr;
 if (select price_cents from public.products where id=pr)<>305 then raise exception 'Unrelated edit changed price';end if;
 insert into public.products(school_id,bar_id,category_id,name,price_cents)
  values(s,'91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000003','Acqua',100) returning id into np;
 if (select price_cents from public.products where id=np)<>110 then raise exception 'New product not marked up';end if;
 -- Tornando a 'none' il bar ritrova i suoi prezzi.
 perform public.set_school_price_policy(s,'none',0);
 if (select price_cents from public.products where id=pr)<>275 or (select base_price_cents from public.products where id=pr) is not null
  or (select price_cents from public.products where id=np)<>100 then raise exception 'Prices not restored';end if;
 if (select counter_discount_bps+price_markup_bps from public.schools where id=s)<>0 then raise exception 'None kept a percentage';end if;
end;$$;

-- Il client non legge ne' scrive la tabella degli sconti.
set local role authenticated;
do $$begin
 perform set_config('request.jwt.claim.sub','91111111-1111-4111-8111-111111111111',true);
 if not pg_temp.denied('select count(*) from public.order_counter_discounts') then raise exception 'Client read counter discounts';end if;
 if not pg_temp.denied($q$insert into public.order_counter_discounts(order_id,school_id,bar_id,source_key,discount_bps,amount_cents)
  select id,school_id,bar_id,'client:x',500,10 from public.orders limit 1$q$) then raise exception 'Client wrote counter discounts';end if;
end;$$;
reset role;
rollback;
