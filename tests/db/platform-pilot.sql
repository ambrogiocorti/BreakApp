-- Migration 12, after workspace-role.sql and migration 11. 444 is Super Admin AAL2.
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $deny_customer$
declare denied boolean:=false;
begin
 begin
  perform public.platform_list_school_staff('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 exception when others then denied:=true; end;
 if not denied then raise exception 'Non-admin could list staff';end if;
end;$deny_customer$;

select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $deny_mfa$
declare denied boolean:=false;
begin
 begin
  perform public.platform_list_school_staff('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Super Admin without MFA could list staff';end if;
end;$deny_mfa$;

select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $deny_self$
declare denied boolean:=false;
begin
 begin
  perform public.platform_assign_school_staff(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'admin-a@example.invalid','bartender');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Super Admin granted itself school staff role';end if;
end;$deny_self$;

-- Existing registered and confirmed user test.
update auth.users set email_confirmed_at=now()
where id='22222222-2222-4222-8222-222222222222';
select public.platform_assign_school_staff(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'cliente-b@example.invalid','bartender');
do $check_staff$
declare x jsonb;
begin
 x:=public.platform_list_school_staff('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 if not exists(
  select 1 from jsonb_array_elements(x) item
  where item->>'email'='cliente-b@example.invalid'
  and item->>'role'='bartender') then raise exception 'Staff not assigned/listed';end if;
end;$check_staff$;

-- Allow global AAL2 to manage day calendar without receiving a school role.
select public.set_bar_weekly_hours(
  'aaaaaaaa-0000-4000-8000-000000000001', 
  extract(dow from (now() at time zone 'Europe/Rome')::date+2)::int,
  '[{"starts_at":"10:00","ends_at":"12:00"}]'::jsonb
);
select public.platform_create_pickup_window(
 'aaaaaaaa-0000-4000-8000-000000000001',
 (now() at time zone 'Europe/Rome')::date+2,
 time '10:40',time '10:50'
) as window_id \gset
select set_config('app.pilot_window_id',:'window_id',false);
select public.platform_set_stock(
 'aaaaaaaa-0000-4000-8000-000000000001',
 'aaaaaaaa-0000-4000-8000-000000000003',
 (now() at time zone 'Europe/Rome')::date+2,
 100
);
select public.platform_set_product_foodinfo(
 'aaaaaaaa-0000-4000-8000-000000000003',
 'Farina, acqua, latte',array['gluten','milk']::text[]
);
do $check_operations$
begin
 if not exists(select 1 from public.pickup_windows
   where id=current_setting('app.pilot_window_id')::uuid) then raise exception 'Window not saved';end if;
 if not exists(select 1 from public.daily_stock
   where product_id='aaaaaaaa-0000-4000-8000-000000000003'
   and capacity=100 and service_date=(now() at time zone 'Europe/Rome')::date+2)
 then raise exception 'Stock not saved';end if;
 if not exists(select 1 from public.products
   where id='aaaaaaaa-0000-4000-8000-000000000003'
   and ingredients='Farina, acqua, latte') then raise exception 'Food metadata not saved';end if;
end;$check_operations$;

select public.platform_revoke_school_staff(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '22222222-2222-4222-8222-222222222222','bartender'
);
do $check_revoke$
begin
 if exists(select 1 from public.role_assignments r join public.school_memberships m
 on m.id=r.membership_id where m.user_id='22222222-2222-4222-8222-222222222222'
 and r.role_code='bartender') then raise exception 'Role not revoked';end if;
 if (select count(*) from app_private.platform_staff_audit where role_code='bartender')<>2
 then raise exception 'Role audit missing';end if;
end;$check_revoke$;
reset role;
