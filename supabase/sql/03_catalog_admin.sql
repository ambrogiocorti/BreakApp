-- BreakApp - Fase 1/2: catalogo reale, accesso amministrativo con MFA.
-- ESEGUIRE SOLO nel progetto BreakApp https://ynvswdyirngvdpudcikl.supabase.co
-- Dopo 01_breakapp_foundations.sql e 02_first_school_admin.sql.
-- Eseguire in Supabase Dashboard > SQL Editor (ruolo postgres).
-- Script incrementale: non cancella scuole/bar/utenti, nessuna operazione di cassa.

begin;

-- Vincolo multitenant: un bar deve sempre appartenere alla stessa scuola.
create unique index if not exists bars_school_id_id_uk
  on public.bars(school_id, id);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, bar_id, id),
  unique (bar_id, name),
  constraint categories_bar_tenant_fk foreign key (school_id, bar_id)
    references public.bars(school_id, id) on delete restrict
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  bar_id uuid not null,
  category_id uuid not null,
  name text not null check (char_length(btrim(name)) between 2 and 160),
  description text not null default '' check (char_length(description) <= 1500),
  price_cents integer not null check (price_cents between 0 and 10000000),
  currency text not null default 'EUR' check (currency = 'EUR'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_bar_tenant_fk foreign key (school_id, bar_id)
    references public.bars(school_id, id) on delete restrict,
  constraint products_category_tenant_fk
    foreign key (school_id, bar_id, category_id)
    references public.categories(school_id, bar_id, id) on delete restrict
);

create index if not exists categories_school_bar_idx
  on public.categories (school_id, bar_id, sort_order);
create index if not exists products_school_bar_idx
  on public.products (school_id, bar_id, category_id);

-- Cambiare tenant/bar a record esistenti non è consentito nemmeno a un Admin;
-- così un UPDATE su una scuola non può spostare dati su un'altra.
create or replace function app_private.enforce_catalog_tenant_immutable()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.school_id is distinct from old.school_id
    or new.bar_id is distinct from old.bar_id then
    raise exception 'Non è consentito spostare elementi tra scuole o bar';
  end if;
  return new;
end;
$$;

drop trigger if exists categories_lock_tenant on public.categories;
create trigger categories_lock_tenant before update on public.categories
  for each row execute function app_private.enforce_catalog_tenant_immutable();
drop trigger if exists products_lock_tenant on public.products;
create trigger products_lock_tenant before update on public.products
  for each row execute function app_private.enforce_catalog_tenant_immutable();
revoke all on function app_private.enforce_catalog_tenant_immutable()
  from public, anon, authenticated;

-- Prezzi interi in centesimi; il timestamp è governato dal database.
create or replace function app_private.catalog_touch_product()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists products_touch_updated_at on public.products;
create trigger products_touch_updated_at before update on public.products
  for each row execute function app_private.catalog_touch_product();
revoke all on function app_private.catalog_touch_product()
  from public, anon, authenticated;

alter table public.categories enable row level security;
alter table public.products enable row level security;

revoke all on public.categories, public.products from public, anon, authenticated;
grant select on public.categories, public.products to anon, authenticated;
grant insert on public.categories, public.products to authenticated;
-- Niente DELETE; non si possono alterare tenant, valuta, id o timestamp.
grant update (name, sort_order, is_active) on public.categories to authenticated;
grant update (category_id, name, description, price_cents, is_active)
  on public.products to authenticated;

-- Visibilità anonima limitata a scuole, bar e categorie attivi.
drop policy if exists categories_read_public on public.categories;
create policy categories_read_public on public.categories
for select to anon, authenticated using (
  is_active
  and exists (
    select 1 from public.bars b join public.schools s on s.id = b.school_id
    where b.id = categories.bar_id and b.school_id = categories.school_id
      and b.is_active and s.is_active
  )
);

drop policy if exists products_read_public on public.products;
create policy products_read_public on public.products
for select to anon, authenticated using (
  is_active
  and exists (
    select 1
    from public.categories c
    join public.bars b on b.id = c.bar_id and b.school_id = c.school_id
    join public.schools s on s.id = b.school_id
    where c.id = products.category_id
      and c.bar_id = products.bar_id and c.school_id = products.school_id
      and c.is_active and b.is_active and s.is_active
  )
);

-- L'Admin può visualizzare anche le categorie/prodotti disattivati,
-- ma soltanto della propria scuola e con JWT MFA aal2.
drop policy if exists categories_admin_read on public.categories;
create policy categories_admin_read on public.categories
for select to authenticated using (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = categories.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
);

drop policy if exists products_admin_read on public.products;
create policy products_admin_read on public.products
for select to authenticated using (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = products.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
);

drop policy if exists categories_admin_insert on public.categories;
create policy categories_admin_insert on public.categories
for insert to authenticated with check (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = categories.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
);

drop policy if exists categories_admin_update on public.categories;
create policy categories_admin_update on public.categories
for update to authenticated
using (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = categories.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
)
with check (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = categories.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
);

drop policy if exists products_admin_insert on public.products;
create policy products_admin_insert on public.products
for insert to authenticated with check (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = products.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
);

drop policy if exists products_admin_update on public.products;
create policy products_admin_update on public.products
for update to authenticated
using (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = products.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
)
with check (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.school_memberships m
    join public.role_assignments r on r.membership_id = m.id
    where m.school_id = products.school_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'active'
      and r.role_code = 'school_admin'
  )
);

commit;
