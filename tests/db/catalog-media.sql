-- Test catalogo alimentare e permessi Storage dopo orders-smoke.sql.
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);

update public.products set
 ingredients='Farina di frumento, acqua, latte',
 allergens=array['gluten','milk']::text[],
 image_path='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-0000-4000-8000-000000000009.jpg'
where id='aaaaaaaa-0000-4000-8000-000000000003';

do $check_metadata$
begin
  if not exists(select 1 from public.products
    where id='aaaaaaaa-0000-4000-8000-000000000003'
    and 'gluten'=any(allergens) and char_length(ingredients)>0) then
    raise exception 'Food info not saved';
  end if;
end;
$check_metadata$;

select jsonb_build_object(
 'uid',auth.uid(),
 'aal',auth.jwt()->>'aal',
 'has_admin',exists(select 1 from public.school_memberships m
 join public.role_assignments r on r.membership_id=m.id
 join public.bars b on b.school_id=m.school_id
 where m.school_id::text='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
 and b.id::text='aaaaaaaa-0000-4000-8000-000000000001'
 and b.is_active and m.user_id=auth.uid()
 and m.membership_status='active' and r.role_code='school_admin'),
 'path_ok', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-0000-4000-8000-000000000009.jpg' ~
 '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|png|jpg|jpeg)$'
) as debug_storage_policy;

insert into storage.objects(bucket_id,name)
values('breakapp-product-images',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-0000-4000-8000-000000000009.jpg');

do $check_cross$
declare blocked boolean:=false;
begin
  begin
    insert into storage.objects(bucket_id,name) values('breakapp-product-images',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/bbbbbbbb-0000-4000-8000-000000000001/aaaaaaaa-0000-4000-8000-000000000010.jpg');
  exception when insufficient_privilege then blocked:=true;
  end;
  if not blocked then raise exception 'Cross-tenant Storage upload allowed'; end if;
end;
$check_cross$;

do $check_codes$
declare blocked boolean:=false;
begin
  begin
    update public.products set allergens=array['unknown']::text[]
      where id='aaaaaaaa-0000-4000-8000-000000000003';
  exception when check_violation then blocked:=true;
  end;
  if not blocked then raise exception 'Unknown allergen accepted'; end if;
end;
$check_codes$;

-- Un admin senza AAL2 non può caricare.
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $check_mfa$
declare blocked boolean:=false;
begin
  begin
    insert into storage.objects(bucket_id,name) values('breakapp-product-images',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-0000-4000-8000-000000000001/aaaaaaaa-0000-4000-8000-000000000011.jpg');
  exception when insufficient_privilege then blocked:=true;
  end;
  if not blocked then raise exception 'AAL1 Admin upload allowed'; end if;
end;
$check_mfa$;
reset role;
