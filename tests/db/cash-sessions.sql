-- Real PostgreSQL regression: receipts, physical count, immutable close and offline revocation.
begin;
reset role;
insert into public.role_assignments(membership_id,role_code)
values('aaaaaaaa-0000-4000-8000-000000000004','bartender') on conflict do nothing;
update public.daily_stock set capacity=allocated+100 where
 product_id='aaaaaaaa-0000-4000-8000-000000000003' and service_date=(now() at time zone 'Europe/Rome')::date;
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
 '32000000-0000-4000-8000-000000000001','open',10000,'','32000000-0000-4000-8000-000000000002');
select public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
 '32000000-0000-4000-8000-000000000001','open',10000,'','32000000-0000-4000-8000-000000000002');
select public.record_online_bar_cash_sale('aaaaaaaa-0000-4000-8000-000000000001',
 '[{"product_id":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1}]',
 '32000000-0000-4000-8000-000000000003','Vendita test turno');
select public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
 '32000000-0000-4000-8000-000000000001','withdrawal',500,'Acquisto materiali per il bar','32000000-0000-4000-8000-000000000004');
select public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
 '32000000-0000-4000-8000-000000000001','withdrawal',500,'Acquisto materiali per il bar','32000000-0000-4000-8000-000000000004');
do $$
declare j jsonb;v_expected bigint;v_price bigint;denied boolean:=false;
begin
 j:=public.cash_workspace('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 select price_cents into v_price from public.products where id='aaaaaaaa-0000-4000-8000-000000000003';
 select (x->>'current_expected_cents')::bigint into v_expected from jsonb_array_elements(j->'sessions') x
  where x->>'id'='32000000-0000-4000-8000-000000000001';
 if v_expected<>10000+v_price-500 then raise exception 'Cash expected wrong or receipt duplicated';end if;
 begin
  perform public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
   '32000000-0000-4000-8000-000000000001','close',v_expected-100,'','32000000-0000-4000-8000-000000000005');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Unexplained discrepancy accepted';end if;
 perform public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
  '32000000-0000-4000-8000-000000000001','close',v_expected-100,
  'Differenza fisica verificata con il collega','32000000-0000-4000-8000-000000000005');
end;$$;
reset role;
do $$
declare denied boolean:=false;
begin
 begin update public.cash_sessions set counted_cents=0 where id='32000000-0000-4000-8000-000000000001';
 exception when others then denied:=true;end;
 if not denied then raise exception 'Confirmed closing mutated';end if;
 if (select count(*) from public.cash_entries where session_id='32000000-0000-4000-8000-000000000001')<>2
 then raise exception 'Duplicate cash entry';end if;
end;$$;
set role authenticated;
select set_config('request.jwt.claim.sub','adadadad-5555-4555-8555-555555555555',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $$declare denied boolean:=false;begin
 begin perform public.cash_workspace('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');exception when others then denied:=true;end;
 if not denied then raise exception 'Cash Admin without MFA accepted';end if;
end;$$;
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.record_cash_operation('aaaaaaaa-0000-4000-8000-000000000001',
 '32000000-0000-4000-8000-000000000001','adjustment',100,'Verifica del conteggio e rettifica successiva','32000000-0000-4000-8000-000000000006');
do $$declare denied boolean:=false;begin
 begin perform public.cash_workspace('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');exception when others then denied:=true;end;
 if not denied then raise exception 'Cross-school cash leak';end if;
end;$$;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
select public.transfer_my_offline_device('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '32000000-0000-4000-8000-000000000007') as cash_lease \gset
select set_config('test.cash_generation',(:'cash_lease'::jsonb->>'generation'),false);
select public.stage_my_offline_event('32000000-0000-4000-8000-000000000007',
 current_setting('test.cash_generation')::bigint,'32000000-0000-4000-8000-000000000008',
 'shift_change',now(),'{"bar_id":"aaaaaaaa-0000-4000-8000-000000000001","session_id":"32000000-0000-4000-8000-000000000009","action":"open","amount_cents":2000,"reason":""}') as cash_stage \gset
select public.reconcile_my_cash_shift_event((:'cash_stage'::jsonb->>'id')::uuid);
reset role;
-- Remove the role while offline. The upload must be preserved, never posted.
delete from public.role_assignments where membership_id='aaaaaaaa-0000-4000-8000-000000000004' and role_code='bartender';
set role authenticated;
select public.stage_my_offline_event('32000000-0000-4000-8000-000000000007',
 current_setting('test.cash_generation')::bigint,'32000000-0000-4000-8000-000000000010',
 'shift_change',now(),'{"bar_id":"aaaaaaaa-0000-4000-8000-000000000001","session_id":"32000000-0000-4000-8000-000000000009","action":"close","amount_cents":2000,"reason":""}') as revoked_cash_stage \gset
select public.reconcile_my_cash_shift_event((:'revoked_cash_stage'::jsonb->>'id')::uuid);
do $$declare denied boolean:=false;begin
 begin perform public.stage_my_offline_event('32000000-0000-4000-8000-000000000007',
  current_setting('test.cash_generation')::bigint,'32000000-0000-4000-8000-000000000010',
  'shift_change',now(),'{"action":"open","amount_cents":999999}');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Reused event ID accepted altered cash contents';end if;
end;$$;
reset role;
do $$begin
 if (select closed_at from public.cash_sessions where id='32000000-0000-4000-8000-000000000009') is not null
 then raise exception 'Revoked operator cash event was posted';end if;
 if not exists(select 1 from public.offline_events_inbox where request_key='32000000-0000-4000-8000-000000000010' and status='quarantined')
 then raise exception 'Revoked operator physical event was lost';end if;
 if not exists(select 1 from public.customer_notifications where event_type='cash_anomaly' and user_id='adadadad-5555-4555-8555-555555555555')
 then raise exception 'Cash discrepancy not notified to Admin';end if;
end;$$;
rollback;
