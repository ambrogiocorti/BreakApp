-- Registro scontrini (20261112220000). Database CI usa e getta.
\set ON_ERROR_STOP on
begin;
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('95111111-1111-4111-8111-111111111111','fiscale-cliente@test.invalid',now()),
 ('95333333-3333-4333-8333-333333333333','fiscale-barista@test.invalid',now()),
 ('95444444-4444-4444-8444-444444444444','fiscale-admin@test.invalid',now());
insert into public.schools(id,slug,name,latitude,longitude,cancel_cutoff_minutes)
 values('95000000-0000-4000-8000-000000000001','fiscale-school','Scuola fiscale',45,9,0);
insert into public.bars(id,school_id,name) values('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000001','Bar fiscale');
insert into public.categories(id,school_id,bar_id,name) values('95000000-0000-4000-8000-000000000003','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','Cibo');
insert into public.products(id,school_id,bar_id,category_id,name,price_cents) values
 ('95000000-0000-4000-8000-000000000004','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000003','Panino',250);
insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 select p.school_id,p.bar_id,p.id,(now() at time zone 'Europe/Rome')::date+d,100 from public.products p cross join generate_series(0,1) d
 where p.bar_id='95000000-0000-4000-8000-000000000002';
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select '95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002',d,'00:00','23:59' from generate_series(0,6) d;
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('95000000-0000-4000-8000-000000000007','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date+1,'12:00','12:15'),
 ('95000000-0000-4000-8000-000000000009','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002',(now() at time zone 'Europe/Rome')::date,'00:01','23:58');
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


-- Incasso al banco: una riga 'sale' con importo, metodo e prodotti; il replay non la duplica.
do $$declare o uuid;f public.fiscal_documents%rowtype;ref jsonb;ob uuid;begin
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000007','[{"product_id":"95000000-0000-4000-8000-000000000004","quantity":2}]',gen_random_uuid(),45,9,10,now());
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 perform public.collect_workflow_balance('individual',o,'cash','95000000-0000-4000-8000-0000000000a1');
 perform public.collect_workflow_balance('individual',o,'cash','95000000-0000-4000-8000-0000000000a1');
 if (select count(*) from public.fiscal_documents where order_id=o)<>1 then raise exception 'Expected one fiscal document';end if;
 select * into f from public.fiscal_documents where order_id=o;
 if f.doc_type<>'sale' or f.payment_method<>'cash' or f.amount_cents<>500 or f.order_total_cents<>500 or f.status<>'to_issue'
  or f.lines->0->>'name'<>'Panino' or (f.lines->0->>'quantity')::int<>2 or (f.lines->0->>'unit_cents')::int<>250
 then raise exception 'Sale document wrong: %',to_jsonb(f);end if;
 -- Rimborso in contanti: la riga 'return' nasce solo quando i soldi sono davvero restituiti.
 update public.orders set status='delivered' where id=o;
 ref:=public.request_completed_order_refund('individual',o,gen_random_uuid(),'Verifica scontrino di reso');
 if exists(select 1 from public.fiscal_documents where order_id=o and doc_type='return') then raise exception 'Return issued before cash went back';end if;
 select id into ob from public.cash_refund_obligations where order_id=o;
 insert into public.cash_sessions(id,school_id,bar_id,actor_id,opening_cents)
  values(gen_random_uuid(),'95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','95333333-3333-4333-8333-333333333333',0);
 perform public.confirm_cash_refund_return(ob,'Restituiti al banco');
 if (select amount_cents from public.fiscal_documents where order_id=o and doc_type='return' and payment_method='cash')<>500 then raise exception 'Cash return document missing';end if;
end;$$;

-- Pagamento online e rimborso Stripe confermato.
do $$declare o uuid;pa uuid;begin
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 o:=public.submit_individual_order('95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000007','[{"product_id":"95000000-0000-4000-8000-000000000004","quantity":1}]',gen_random_uuid(),45,9,10,now());
 reset role;
 insert into public.payment_attempts(school_id,payer_id,order_id,stripe_account_id,request_key,amount_cents,currency,status)
  values('95000000-0000-4000-8000-000000000001','95111111-1111-4111-8111-111111111111',o,'acct_fiscaltest',gen_random_uuid(),250,'eur','processing') returning id into pa;
 if exists(select 1 from public.fiscal_documents where order_id=o) then raise exception 'Document before payment succeeded';end if;
 update public.payment_attempts set status='succeeded' where id=pa;
 update public.payment_attempts set updated_at=now() where id=pa;
 if (select count(*) from public.fiscal_documents where order_id=o and doc_type='sale' and payment_method='card' and amount_cents=250)<>1 then raise exception 'Card sale document wrong';end if;
 insert into public.payment_refunds(payment_id,request_key,amount_cents,status,reason) values(pa,gen_random_uuid(),100,'pending','Prova');
 if exists(select 1 from public.fiscal_documents where order_id=o and doc_type='return') then raise exception 'Return before Stripe confirmed';end if;
 update public.payment_refunds set status='succeeded' where payment_id=pa;
 if (select amount_cents from public.fiscal_documents where order_id=o and doc_type='return' and payment_method='card')<>100 then raise exception 'Card return document wrong';end if;
end;$$;

-- Chi puo' vedere e segnare: barista e Admin con 2FA si'; cliente e Admin senza 2FA no.
do $$declare l jsonb;d uuid;today date:=(now() at time zone 'Europe/Rome')::date;begin
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 if not pg_temp.denied(format('select public.list_fiscal_documents(%L,%L,%L)','95000000-0000-4000-8000-000000000001',today,today)) then raise exception 'Customer listed receipts';end if;
 perform pg_temp.actor('95444444-4444-4444-8444-444444444444','authenticated','aal1');
 if not pg_temp.denied(format('select public.list_fiscal_documents(%L,%L,%L)','95000000-0000-4000-8000-000000000001',today,today)) then raise exception 'Admin without 2FA listed receipts';end if;
 perform pg_temp.actor('95444444-4444-4444-8444-444444444444','authenticated','aal2');
 if not pg_temp.denied(format('select public.list_fiscal_documents(%L,%L,%L)','95000000-0000-4000-8000-000000000001',today-100,today)) then raise exception 'Period above 3 months accepted';end if;
 l:=public.list_fiscal_documents('95000000-0000-4000-8000-000000000001',today,today,'to_issue');
 if jsonb_array_length(l)<>4 or l->0->>'reference' not like '#%' then raise exception 'Admin list wrong: %',l;end if;
 perform pg_temp.actor('95333333-3333-4333-8333-333333333333');
 d:=(l->0->>'id')::uuid;
 perform public.mark_fiscal_document(d,true);
 perform public.mark_fiscal_document(d,true);
 if (select status||issue_channel from public.fiscal_documents where id=d)<>'issuedbar_register' then raise exception 'Mark issued failed';end if;
 if jsonb_array_length(public.list_fiscal_documents('95000000-0000-4000-8000-000000000001',today,today,'to_issue'))<>3 then raise exception 'Issued still listed as to issue';end if;
 perform public.mark_fiscal_document(d,false);
 if (select status from public.fiscal_documents where id=d)<>'to_issue' or (select issued_at from public.fiscal_documents where id=d) is not null then raise exception 'Reopen failed';end if;
 perform pg_temp.actor('95111111-1111-4111-8111-111111111111');
 if not pg_temp.denied(format('select public.mark_fiscal_document(%L,true)',d)) then raise exception 'Customer marked a receipt';end if;
end;$$;

-- Il client non legge ne' scrive la tabella.
set local role authenticated;
do $$begin
 perform set_config('request.jwt.claim.sub','95333333-3333-4333-8333-333333333333',true);
 if not pg_temp.denied('select count(*) from public.fiscal_documents') then raise exception 'Client read fiscal documents';end if;
end;$$;
reset role;
rollback;
