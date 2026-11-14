-- Cambio prodotto e restituzione contanti dall'ordine concluso (20261113180000). Database CI usa e getta.
\set ON_ERROR_STOP on
begin;
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('95111111-1111-4111-8111-111111111111','cambio-cliente@test.invalid',now()),
 ('95333333-3333-4333-8333-333333333333','cambio-barista@test.invalid',now()),
 ('95444444-4444-4444-8444-444444444444','cambio-admin@test.invalid',now());
insert into public.schools(id,slug,name,latitude,longitude,cancel_cutoff_minutes)
 values('95000000-0000-4000-8000-000000000001','cambio-school','Scuola cambio',45,9,0);
insert into public.bars(id,school_id,name) values('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000001','Bar cambio');
insert into public.categories(id,school_id,bar_id,name) values('95000000-0000-4000-8000-000000000003','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','Cibo');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents) values
 ('95000000-0000-4000-8000-000000000004','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000003','Panino',250),
 ('95000000-0000-4000-8000-000000000005','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000003','Pizza',400),
 ('95000000-0000-4000-8000-000000000006','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000003','Acqua',100),
 ('95000000-0000-4000-8000-000000000008','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000003','Focaccia',250);
insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 select p.school_id,p.bar_id,p.id,(now() at time zone 'Europe/Rome')::date+d,case when p.name='Focaccia' then 0 else 100 end
 from public.products p cross join generate_series(0,1) d where p.bar_id='95000000-0000-4000-8000-000000000002';
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select '95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002',d,'00:00','23:59' from generate_series(0,6) d;
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('95000000-0000-4000-8000-000000000009','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date+1,'12:00','12:15');
insert into public.school_memberships(school_id,user_id) values
 ('95000000-0000-4000-8000-000000000001','95333333-3333-4333-8333-333333333333'),
 ('95000000-0000-4000-8000-000000000001','95444444-4444-4444-8444-444444444444');
insert into public.role_assignments(membership_id,role_code)
 select id,case when user_id='95333333-3333-4333-8333-333333333333' then 'bartender' else 'school_admin' end
 from public.school_memberships where school_id='95000000-0000-4000-8000-000000000001';
create function pg_temp.actor(p_user uuid,p_role text default 'authenticated',p_aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',p_user::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('role',p_role,'aal',p_aal,'is_anonymous',false)::text,true);
end;$$;
create function pg_temp.denied(p_sql text) returns boolean language plpgsql as $d$
begin execute p_sql;return false;exception when others then return true;end;$d$;
create temp table t(o uuid);

-- Ordine di 2 panini (5,00) pagato al POS e consegnato.
do $$declare o uuid;begin
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000009','[{"product_id":"95000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now());
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 perform public.collect_workflow_balance('individual',o,'external_pos',gen_random_uuid());
 update public.orders set status='delivered' where id=o;
 if (select payment_status from public.orders where id=o)<>'paid' then raise exception 'Setup order not paid';end if;
 insert into t values(o);
end;$$;

-- Regole: solo personale, ordine consegnato e pagato, quantita' e scorte, metodo per la differenza.
do $$declare o uuid:=(select o from t);begin
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000006',null,gen_random_uuid(),'Cliente vuole acqua')$q$,o)) then raise exception 'Customer made an exchange';end if;
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',3,'95000000-0000-4000-8000-000000000006',null,gen_random_uuid(),'Troppi pezzi resi')$q$,o)) then raise exception 'Exchanged more than ordered';end if;
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000006',null,gen_random_uuid(),'corto')$q$,o)) then raise exception 'Short reason accepted';end if;
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000008',null,gen_random_uuid(),'Focaccia finita oggi')$q$,o)) then raise exception 'Exchange beyond stock accepted';end if;
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000005',null,gen_random_uuid(),'Pizza senza metodo')$q$,o)) then raise exception 'Higher price without payment method';end if;
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000005','cash',gen_random_uuid(),'Pizza senza cassa aperta')$q$,o)) then raise exception 'Cash difference without open session';end if;
end;$$;

-- Prezzo piu' alto: 1 panino -> 1 pizza, +1,50 in contanti nel turno, nel report e scontrino da emettere.
do $$declare o uuid:=(select o from t);r jsonb;k uuid:=gen_random_uuid();rep jsonb;begin
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 perform public.record_cash_operation('95000000-0000-4000-8000-000000000002',gen_random_uuid(),'open',1000,'',gen_random_uuid());
 r:=public.exchange_order_item(o,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000005','cash',k,'Cliente preferisce la pizza');
 if r->>'status'<>'recorded' or (r->>'difference_cents')::int<>150 or r->>'method'<>'cash' then raise exception 'Exchange up wrong: %',r;end if;
 if (select total_cents from public.orders where id=o)<>650 or (select payment_status from public.orders where id=o)<>'paid' then raise exception 'Order not updated after exchange up';end if;
 if (select string_agg(product_name||' x'||quantity,', ' order by product_name) from public.order_items where order_id=o and removed_at is null)<>'Panino x1, Pizza x1'
 then raise exception 'Order lines wrong after exchange up';end if;
 if not exists(select 1 from public.cash_entries where kind='receipt' and amount_cents=150 and source_key like 'order_additional_receipts:%') then raise exception 'Cash drawer missing the difference';end if;
 if not exists(select 1 from public.fiscal_documents where order_id=o and doc_type='sale' and amount_cents=150 and payment_method='cash') then raise exception 'Receipt to issue missing';end if;
 if (select allocated from public.daily_stock where product_id='95000000-0000-4000-8000-000000000005' and service_date=(now() at time zone 'Europe/Rome')::date)<>1 then raise exception 'Stock of the new product not used';end if;
 if not exists(select 1 from public.order_versions where order_id=o and snapshot->>'reason'='exchange') then raise exception 'Order version not saved';end if;
 -- Ripetere la stessa richiesta non incassa due volte.
 r:=public.exchange_order_item(o,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000005','cash',k,'Cliente preferisce la pizza');
 if r->>'status'<>'duplicate' or (select count(*) from public.order_exchanges where order_id=o)<>1 then raise exception 'Replay not idempotent: %',r;end if;
 perform pg_temp.actor('95444444-4444-4444-8444-444444444444','authenticated','aal2');
 rep:=public.school_financial_report('95000000-0000-4000-8000-000000000001',(now() at time zone 'Europe/Rome')::date,(now() at time zone 'Europe/Rome')::date);
 if (rep->>'cash_cents')::int<>150 or (rep->>'external_pos_cents')::int<>500 then raise exception 'Report wrong: %',rep;end if;
end;$$;

-- Prezzo piu' basso: l'ultimo panino -> acqua, 1,50 da restituire in contanti (pagato al POS), subito registrato.
do $$declare o uuid:=(select o from t);r jsonb;due jsonb;begin
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 r:=public.exchange_order_item(o,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000006',null,gen_random_uuid(),'Cliente vuole solo acqua');
 if (r->>'difference_cents')::int<>-150 or r->>'method'<>'refund' then raise exception 'Exchange down wrong: %',r;end if;
 if (select total_cents from public.orders where id=o)<>500 then raise exception 'Total not reduced';end if;
 if exists(select 1 from public.order_items where order_id=o and removed_at is null and product_name='Panino') then raise exception 'Returned line still in the order';end if;
 due:=public.order_cash_refunds_to_return(o);
 if jsonb_array_length(due)<>1 or (due->0->>'amount_cents')::int<>150 then raise exception 'Cash to return wrong: %',due;end if;
 if (select payment_status from public.orders where id=o)<>'paid' then raise exception 'Order not paid after exchange down';end if;
 perform public.confirm_cash_refund_return((due->0->>'id')::uuid,'Restituiti al banco');
 if jsonb_array_length(public.order_cash_refunds_to_return(o))<>0 then raise exception 'Returned cash still pending';end if;
 if not exists(select 1 from public.cash_entries where kind='withdrawal' and amount_cents=-150) then raise exception 'Cash return not in the drawer';end if;
 -- Il prodotto reso non si puo' cambiare di nuovo.
 if not pg_temp.denied(format($q$select public.exchange_order_item(%L,'95000000-0000-4000-8000-000000000004',1,'95000000-0000-4000-8000-000000000006',null,gen_random_uuid(),'Di nuovo il panino')$q$,o)) then raise exception 'Exchanged a product no longer in the order';end if;
 -- Il cliente non vede le restituzioni di un ordine dal lato staff.
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 if not pg_temp.denied(format('select public.order_cash_refunds_to_return(%L)',o)) then raise exception 'Customer read staff cash returns';end if;
end;$$;

-- Rimborso completo dopo un cambio: torna tutto il denaro rimasto.
do $$declare o uuid:=(select o from t);ref jsonb;begin
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 ref:=public.request_completed_order_refund('individual',o,gen_random_uuid(),'Cliente insoddisfatto del prodotto');
 if app_private.order_paid_cents('individual',o)<>0 then raise exception 'Full refund after exchange left money: %',ref;end if;
end;$$;

-- Pagamento con carta abbandonato: il barista lo vede, il cliente no; si chiude solo dal service role.
do $$declare o uuid;a uuid;r jsonb;begin
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000009','[{"product_id":"95000000-0000-4000-8000-000000000006","quantity":1}]',gen_random_uuid(),45,9,10,now());
 reset role;
 insert into public.payment_attempts(school_id,payer_id,order_id,stripe_account_id,request_key,amount_cents,status,stripe_checkout_session_id)
  values('95000000-0000-4000-8000-000000000001','95111111-1111-4111-8111-111111111111',o,'acct_test123',gen_random_uuid(),100,'requires_action','cs_test_abc') returning id into a;
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 if not pg_temp.denied(format('select public.staff_open_checkout(%L)',o)) then raise exception 'Customer read staff checkout';end if;
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 r:=public.staff_open_checkout(o);
 if not (r->>'open')::boolean or (r->>'amount_cents')::int<>100 or r ? 'session' then raise exception 'Open checkout wrong: %',r;end if;
 r:=public.staff_checkout_to_cancel(o);
 if r->>'session'<>'cs_test_abc' or r->>'account'<>'acct_test123' then raise exception 'Cancel data wrong: %',r;end if;
 if not pg_temp.denied(format('select public.cancel_abandoned_checkout(%L,''cs_test_abc'')',a)) then raise exception 'Barista closed the attempt without Stripe';end if;
 if not pg_temp.denied(format('select public.collect_workflow_balance(''individual'',%L,''external_pos'',gen_random_uuid())',o)) then raise exception 'Counter payment allowed during open checkout';end if;
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333','service_role');
 if not pg_temp.denied(format('select public.cancel_abandoned_checkout(%L,''cs_test_other'')',a)) then raise exception 'Wrong session accepted';end if;
 if public.cancel_abandoned_checkout(a,'cs_test_abc')<>'cancelled' or public.cancel_abandoned_checkout(a,'cs_test_abc')<>'duplicate' then raise exception 'Cancel not idempotent';end if;
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 if (public.staff_open_checkout(o)->>'open')::boolean then raise exception 'Checkout still open';end if;
 perform public.collect_workflow_balance('individual',o,'external_pos',gen_random_uuid());
 if (select payment_status from public.orders where id=o)<>'paid' then raise exception 'Counter payment after release failed';end if;
end;$$;

set local role authenticated;
do $$begin
 perform set_config('request.jwt.claim.sub','95333333-3333-4333-8333-333333333333',true);
 if not pg_temp.denied('select count(*) from public.order_exchanges') then raise exception 'Client read exchanges';end if;
end;$$;
reset role;
rollback;
