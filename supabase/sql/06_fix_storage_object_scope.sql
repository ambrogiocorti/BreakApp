-- Repair policies already deployed with ambiguous unqualified name.
-- The first migration was applied before this correction.
begin;
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
