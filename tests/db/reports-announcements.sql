begin;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','adadadad-5555-4555-8555-555555555555',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $$
declare j jsonb;r jsonb;denied boolean:=false;first_id uuid;again_id uuid;
begin
 j:=public.school_financial_report('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',current_date-1,current_date+1);
 if j->>'school_id'<>'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' or
  (j->>'cash_cents')::bigint<0 or (j->>'group_orders')::bigint<0 then raise exception 'Report shape incorrect';end if;
 r:=public.school_order_report_rows('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',current_date-1,current_date+1,0,2);
 if jsonb_typeof(r)<>'array' or jsonb_array_length(r)>2 then raise exception 'Report pagination failed';end if;
 if exists(select 1 from jsonb_array_elements(r) x where x?'payer_id' or x?'customer_id' or x?'pickup_token')
 then raise exception 'Report exposes private payer/customer data';end if;
 begin perform public.school_financial_report('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',current_date,current_date);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Cross-school financial report leaked';end if;
 denied:=false;
 begin perform public.school_financial_report('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',current_date,current_date-1);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Invalid period accepted';end if;
 first_id:=public.publish_school_announcement('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Annuncio di test',
  'Il servizio del bar inizia alle ore previste','33000000-0000-4000-8000-000000000001');
 again_id:=public.publish_school_announcement('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Annuncio di test',
  'Il servizio del bar inizia alle ore previste','33000000-0000-4000-8000-000000000001');
 if first_id<>again_id then raise exception 'Duplicate announcement';end if;
end;$$;
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $$declare denied boolean:=false;begin
 begin perform public.school_financial_report('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',current_date,current_date);
 exception when others then denied:=true;end;
 if not denied then raise exception 'MFA not enforced on report';end if;
end;$$;
reset role;
do $$begin
 if (select count(*) from public.school_announcements where request_key='33000000-0000-4000-8000-000000000001')<>1
 then raise exception 'Announcement duplicated';end if;
 if exists(select 1 from public.customer_notifications n where event_type='school_announcement' and
   not exists(select 1 from public.school_memberships m where m.school_id=n.school_id and m.user_id=n.user_id and m.membership_status='active'))
 then raise exception 'Announcement recipient belongs to another tenant';end if;
end;$$;
rollback;
