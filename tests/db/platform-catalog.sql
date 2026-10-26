-- Super Admin catalog tests; PostgreSQL integration fixture with user 4444 as platform admin.
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $normal_user_cannot_mutate$
declare denied boolean:=false;
begin
 begin
  perform public.platform_save_category('aaaaaaaa-0000-4000-8000-000000000001',
   null,'Injected category',true);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Ordinary client created global category';end if;
end;$normal_user_cannot_mutate$;

select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $aal1_cannot_mutate$
declare denied boolean:=false;
begin
 begin
  perform public.platform_save_category('aaaaaaaa-0000-4000-8000-000000000001',
   null,'AAL1 category',true);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Super Admin without MFA created category';end if;
end;$aal1_cannot_mutate$;

select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.platform_save_category(
 'aaaaaaaa-0000-4000-8000-000000000001',
 null,'Bevande pilota',true) as new_category \gset
select set_config('app.test_catalog_category',:'new_category',false);
select public.platform_save_product(
 'aaaaaaaa-0000-4000-8000-000000000001',
 null,:'new_category'::uuid,'Acqua naturale 50cl',
 'Bottiglietta di acqua naturale',100,'Acqua',
 array[]::text[],true
) as new_product \gset
select set_config('app.test_catalog_product',:'new_product',false);

do $validate_created$
begin
 if not exists(select 1 from public.products where
  id=current_setting('app.test_catalog_product')::uuid
  and price_cents=100 and ingredients='Acqua' and is_active=true)
 then raise exception 'New product not saved correctly';end if;
end;$validate_created$;

select public.platform_save_product(
 'aaaaaaaa-0000-4000-8000-000000000001',
 :'new_product'::uuid,:'new_category'::uuid,'Acqua naturale 50cl',
 'Bottiglietta senza zuccheri aggiunti',120,'Acqua',
 array[]::text[],true
);
do $assert_update$
begin
 if (select price_cents from public.products where id=current_setting('app.test_catalog_product')::uuid)<>120
 then raise exception 'Price not updated';end if;
end;$assert_update$;

-- Attempt to change a product through the wrong bar: must be rejected.
reset role;
insert into public.schools(id,slug,name)
values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','secondary-school-test','Secondary Test');
insert into public.bars(id,school_id,name)
values('bbbbbbbb-0000-4000-8000-000000000001',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Secondary Bar');
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $wrong_tenant$
declare denied boolean:=false;
begin
 begin
  perform public.platform_save_product(
   'bbbbbbbb-0000-4000-8000-000000000001',
   current_setting('app.test_catalog_product')::uuid,
   current_setting('app.test_catalog_category')::uuid,
   'Tamper with other tenant','Una descrizione',100,'Ingredienti',
   array[]::text[],true);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Updated product from different bar';end if;
end;$wrong_tenant$;

do $reject_bad_data$
declare denied boolean:=false;
begin
 begin
  perform public.platform_save_product('aaaaaaaa-0000-4000-8000-000000000001',
  current_setting('app.test_catalog_product')::uuid,
  current_setting('app.test_catalog_category')::uuid,
  'Unsafe food','',100,'',array[]::text[],true);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Published product without ingredients';end if;
 denied:=false;
 begin
  perform public.platform_set_product_image('aaaaaaaa-0000-4000-8000-000000000001',
   current_setting('app.test_catalog_product')::uuid,
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-0000-4000-8000-000000000099.jpg');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Accepted nonexistent photo';end if;
end;$reject_bad_data$;

select public.platform_save_category(
 'aaaaaaaa-0000-4000-8000-000000000001',
 :'new_category'::uuid,'Bevande pilota',false);
do $no_hidden_category_sales$
declare denied boolean:=false;
begin
 begin
  perform public.platform_save_product(
   'aaaaaaaa-0000-4000-8000-000000000001',
   null,current_setting('app.test_catalog_category')::uuid,
   'Product in hidden category','',100,'Ingredienti',array[]::text[],true);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Published product in hidden category';end if;
end;$no_hidden_category_sales$;
reset role;
do $audit_and_integrity$
begin
 if (select count(*) from app_private.platform_catalog_audit
  where object_id=current_setting('app.test_catalog_product')::uuid)<2
 then raise exception 'Global catalog audit missing';end if;
 if exists(select 1 from public.products
  where id=current_setting('app.test_catalog_product')::uuid and price_cents<>120)
 then raise exception 'Catalog price modified unexpectedly';end if;
end;$audit_and_integrity$;
