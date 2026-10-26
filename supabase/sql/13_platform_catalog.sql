-- BreakApp 13: global catalog management by Super Admin AAL2.
-- Operates in the platform panel without school role grants. No payment changes.
begin;
create table if not exists app_private.platform_catalog_audit (
 id bigint generated always as identity primary key,
 actor_id uuid not null references auth.users(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 bar_id uuid not null references public.bars(id) on delete restrict,
 object_kind text not null check(object_kind in ('category','product')),
 object_id uuid not null,
 operation text not null check(operation in ('created','updated')),
 created_at timestamptz not null default now()
);
alter table app_private.platform_catalog_audit enable row level security;
revoke all on app_private.platform_catalog_audit from public,anon,authenticated;

create or replace function public.platform_save_category(
 p_bar_id uuid,p_category_id uuid,p_name text,p_active boolean default true
) returns uuid language plpgsql security definer set search_path=''
as $category$
declare v_bar public.bars%rowtype;v_id uuid;
begin
 if not app_private.platform_approved() then
  raise exception 'Super Admin e 2FA richiesti';end if;
 if char_length(btrim(coalesce(p_name,''))) not between 2 and 120
    or p_active is null then raise exception 'Categoria non valida';end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active;
 if not found then raise exception 'Bar inesistente o inattivo';end if;
 if p_category_id is null then
  insert into public.categories(school_id,bar_id,name,is_active)
  values(v_bar.school_id,v_bar.id,btrim(p_name),p_active)
  returning id into v_id;
 else
  update public.categories set name=btrim(p_name),is_active=p_active
  where id=p_category_id and school_id=v_bar.school_id and bar_id=v_bar.id
  returning id into v_id;
  if v_id is null then raise exception 'Categoria non presente nel bar';end if;
 end if;
 insert into app_private.platform_catalog_audit(actor_id,school_id,bar_id,object_kind,object_id,operation)
 values(auth.uid(),v_bar.school_id,v_bar.id,'category',v_id,
   case when p_category_id is null then 'created' else 'updated' end);
 return v_id;
end;
$category$;

create or replace function public.platform_save_product(
 p_bar_id uuid,p_product_id uuid,p_category_id uuid,p_name text,
 p_description text,p_price_cents integer,p_ingredients text,
 p_allergens text[],p_active boolean default true
) returns uuid language plpgsql security definer set search_path=''
as $product$
declare v_bar public.bars%rowtype;v_id uuid;
begin
 if not app_private.platform_approved() then
  raise exception 'Super Admin e 2FA richiesti';end if;
 if char_length(btrim(coalesce(p_name,''))) not between 2 and 160
    or char_length(coalesce(p_description,''))>1500
    or p_price_cents is null or p_price_cents<0 or p_price_cents>10000000
    or p_allergens is null or p_active is null
    or char_length(coalesce(p_ingredients,''))>3000
    or (p_active and char_length(btrim(coalesce(p_ingredients,'')))<3)
 then raise exception 'Prodotto non valido: nome, prezzo, ingredienti o allergeni';end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active;
 if not found then raise exception 'Bar inesistente o inattivo';end if;
 if not exists(select 1 from public.categories c
  where c.id=p_category_id and c.bar_id=v_bar.id and c.school_id=v_bar.school_id and c.is_active)
 then raise exception 'Categoria non disponibile per questo bar';end if;
 if p_product_id is null then
  insert into public.products(school_id,bar_id,category_id,name,description,
    price_cents,ingredients,allergens,is_active)
  values(v_bar.school_id,v_bar.id,p_category_id,btrim(p_name),coalesce(p_description,''),
    p_price_cents,btrim(coalesce(p_ingredients,'')),p_allergens,p_active)
  returning id into v_id;
 else
  update public.products set category_id=p_category_id,name=btrim(p_name),
    description=coalesce(p_description,''),price_cents=p_price_cents,
    ingredients=btrim(coalesce(p_ingredients,'')),allergens=p_allergens,
    is_active=p_active
  where id=p_product_id and bar_id=v_bar.id and school_id=v_bar.school_id
  returning id into v_id;
  if v_id is null then raise exception 'Prodotto non presente nel bar';end if;
 end if;
 insert into app_private.platform_catalog_audit(actor_id,school_id,bar_id,object_kind,object_id,operation)
 values(auth.uid(),v_bar.school_id,v_bar.id,'product',v_id,
  case when p_product_id is null then 'created' else 'updated' end);
 return v_id;
end;
$product$;

-- Photos: Super Admin may upload immutable photos only into explicitly
-- active school/bar path. Product path is set by guarded RPC after upload.
create policy breakapp_images_superadmin_insert on storage.objects
for insert to authenticated with check (
 bucket_id='breakapp-product-images'
 and storage.objects.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|png|jpg|jpeg)$'
 and app_private.platform_approved()
 and exists(select 1 from public.bars b join public.schools s on s.id=b.school_id
 where b.school_id::text=split_part(storage.objects.name,'/',1)
 and b.id::text=split_part(storage.objects.name,'/',2)
 and b.is_active and s.is_active)
);

create or replace function public.platform_set_product_image(
 p_bar_id uuid,p_product_id uuid,p_object_path text
) returns void language plpgsql security definer set search_path=''
as $image$
declare v_bar public.bars%rowtype;
begin
 if not app_private.platform_approved() then
  raise exception 'Super Admin e 2FA richiesti';end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active;
 if not found then raise exception 'Bar inesistente';end if;
 if not exists(select 1 from public.products
   where id=p_product_id and bar_id=v_bar.id and school_id=v_bar.school_id)
 then raise exception 'Prodotto inesistente o di altra scuola';end if;
 if p_object_path is not null and (
   p_object_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|png|jpg|jpeg)$'
   or split_part(p_object_path,'/',1)<>v_bar.school_id::text
   or split_part(p_object_path,'/',2)<>v_bar.id::text
   or not exists(select 1 from storage.objects where bucket_id='breakapp-product-images'
     and name=p_object_path)
 ) then raise exception 'Foto prodotto non valida o non caricata';end if;
 update public.products set image_path=p_object_path where id=p_product_id
  and bar_id=v_bar.id and school_id=v_bar.school_id;
 insert into app_private.platform_catalog_audit(actor_id,school_id,bar_id,object_kind,object_id,operation)
 values(auth.uid(),v_bar.school_id,v_bar.id,'product',p_product_id,'updated');
end;
$image$;

revoke all on function public.platform_save_category(uuid,uuid,text,boolean),
 public.platform_save_product(uuid,uuid,uuid,text,text,integer,text,text[],boolean),
 public.platform_set_product_image(uuid,uuid,text)
from public,anon,authenticated;
grant execute on function public.platform_save_category(uuid,uuid,text,boolean),
 public.platform_save_product(uuid,uuid,uuid,text,text,integer,text,text[],boolean),
 public.platform_set_product_image(uuid,uuid,text)
to authenticated;
commit;
