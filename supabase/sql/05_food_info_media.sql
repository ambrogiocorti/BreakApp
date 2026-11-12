-- BreakApp - catalogo alimentare e fotografie (incremento 05).
-- Migrazione non distruttiva: nessun prodotto o immagine viene eliminato.
begin;

alter table public.products
  add column if not exists ingredients text not null default '',
  add column if not exists allergens text[] not null default '{}'::text[],
  add column if not exists image_path text;

alter table public.products
  add constraint products_ingredients_length check (char_length(ingredients) <= 3000),
  add constraint products_allergen_codes check (
    allergens <@ array[
      'gluten','crustaceans','eggs','fish','peanuts','soy','milk','nuts',
      'celery','mustard','sesame','sulphites','lupin','molluscs'
    ]::text[]
  ),
  add constraint products_image_tenant_scope check (
    image_path is null or (
      image_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|png|jpg|jpeg)$'
      and split_part(image_path,'/',1) = school_id::text
      and split_part(image_path,'/',2) = bar_id::text
    )
  );

-- Aggiornamento campi ammessi solo a chi già supera RLS Admin e MFA.
grant update (ingredients,allergens,image_path) on public.products to authenticated;

-- Un bucket pubblico è necessario solo per rendere visibili le fotografie dei prodotti.
-- Scrittura protetta per scuola e bar, immagini <= 2 MB e MIME limitati.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
 'breakapp-product-images','breakapp-product-images',true,2097152,
 array['image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do update set
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists breakapp_images_admin_insert on storage.objects;
create policy breakapp_images_admin_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'breakapp-product-images'
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|png|jpg|jpeg)$'
  and (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1
    from public.school_memberships m
    join public.role_assignments r on r.membership_id=m.id
    join public.bars b on b.school_id=m.school_id
    where m.school_id::text = split_part(storage.objects.name,'/',1)
      and b.id::text = split_part(storage.objects.name,'/',2)
      and b.is_active
      and m.user_id = (select auth.uid())
      and m.membership_status='active'
      and r.role_code='school_admin'
  )
);
-- Public bucket objects readable, but not writable, by all clients.
drop policy if exists breakapp_images_public_select on storage.objects;
create policy breakapp_images_public_select on storage.objects
for select to anon,authenticated
using (bucket_id='breakapp-product-images');

-- No UPDATE policy: ogni immagine ha un nome univoco immutabile.
-- Delete limitato ad Admin con 2FA dello stesso bar.
drop policy if exists breakapp_images_admin_delete on storage.objects;
create policy breakapp_images_admin_delete on storage.objects
for delete to authenticated
using (
  bucket_id='breakapp-product-images'
  and (select auth.jwt()->>'aal')='aal2'
  and exists(
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id=m.id
    join public.bars b on b.school_id=m.school_id
    where m.school_id::text=split_part(storage.objects.name,'/',1)
      and b.id::text=split_part(storage.objects.name,'/',2)
      and m.user_id=(select auth.uid())
      and m.membership_status='active'
      and r.role_code='school_admin'
  )
);
commit;