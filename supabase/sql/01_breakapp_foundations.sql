-- BreakApp, Fase 1: primo schema da eseguire SOLO nel nuovo progetto Supabase.
-- Percorso online: Supabase Dashboard > SQL Editor > New query > Run.
-- Questo script NON importa il prototipo di Fase 0 e NON crea ordini o pagamenti.
-- Non eseguire su database esistenti di altre applicazioni.

begin;

-- Le funzioni privilegiate non devono essere raggiungibili dalla Data API.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (char_length(btrim(name)) between 2 and 160),
  timezone text not null default 'Europe/Rome',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.bars (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 2 and 160),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) <= 120),
  created_at timestamptz not null default now()
);

-- Una persona può appartenere a più scuole, con ruoli diversi.
create table if not exists public.school_memberships (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_status text not null default 'active'
    check (membership_status in ('pending', 'active', 'suspended')),
  created_at timestamptz not null default now(),
  unique (school_id, user_id)
);

create table if not exists public.role_assignments (
  membership_id uuid not null references public.school_memberships(id) on delete cascade,
  role_code text not null check (role_code in (
    'school_admin', 'warehouse_manager', 'bartender', 'customer'
  )),
  created_at timestamptz not null default now(),
  primary key (membership_id, role_code)
);

-- Il Super Admin è globale, non un ruolo selezionabile dal client.
create table if not exists app_private.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists bars_school_idx on public.bars(school_id);
create index if not exists school_memberships_user_idx
  on public.school_memberships(user_id, school_id);

-- RLS attiva su TUTTE le tabelle; senza policy di scrittura il client
-- non può assegnarsi una scuola, un ruolo o elevare i privilegi.
alter table public.schools enable row level security;
alter table public.bars enable row level security;
alter table public.profiles enable row level security;
alter table public.school_memberships enable row level security;
alter table public.role_assignments enable row level security;
alter table app_private.platform_admins enable row level security;

revoke all on public.schools from public, anon, authenticated;
revoke all on public.bars from public, anon, authenticated;
revoke all on public.profiles from public, anon, authenticated;
revoke all on public.school_memberships from public, anon, authenticated;
revoke all on public.role_assignments from public, anon, authenticated;
revoke all on app_private.platform_admins from public, anon, authenticated;

grant select on public.schools, public.bars to anon, authenticated;
grant select on public.profiles, public.school_memberships,
  public.role_assignments to authenticated;

drop policy if exists schools_public_directory on public.schools;
create policy schools_public_directory on public.schools
  for select to anon, authenticated using (is_active);

drop policy if exists bars_public_directory on public.bars;
create policy bars_public_directory on public.bars
  for select to anon, authenticated using (
    is_active and exists (
      select 1 from public.schools s
      where s.id = bars.school_id and s.is_active
    )
  );

drop policy if exists profiles_read_self on public.profiles;
create policy profiles_read_self on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists memberships_read_self on public.school_memberships;
create policy memberships_read_self on public.school_memberships
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists roles_read_self on public.role_assignments;
create policy roles_read_self on public.role_assignments
  for select to authenticated using (
    exists (
      select 1 from public.school_memberships m
      where m.id = role_assignments.membership_id
        and m.user_id = (select auth.uid())
        and m.membership_status = 'active'
    )
  );

-- Creazione automatica del profilo a ogni registrazione Supabase Auth.
-- Il metadata inserito dall'utente NON conferisce mai ruoli.
create or replace function app_private.create_profile_from_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function app_private.create_profile_from_auth()
  from public, anon, authenticated;

drop trigger if exists on_breakapp_user_created on auth.users;
create trigger on_breakapp_user_created
  after insert on auth.users
  for each row execute function app_private.create_profile_from_auth();

-- Utile se alcuni utenti sono stati creati prima di eseguire lo schema.
insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;

commit;
