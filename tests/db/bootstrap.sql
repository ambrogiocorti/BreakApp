-- Database PostgreSQL vuoto usato SOLO in GitHub CI.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz);
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
create or replace function auth.jwt() returns jsonb language sql stable as
$$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb); $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;
grant execute on function auth.jwt() to authenticated,anon;

-- Mock minimale dello schema Supabase Storage per il test migrazioni locali.
create schema storage;
create table storage.buckets(
  id text primary key, name text not null, public boolean not null default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects(
  id uuid primary key default gen_random_uuid(), bucket_id text not null,
  name text not null, unique(bucket_id,name)
);
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated;
grant select,insert,delete on storage.objects to authenticated;
grant select on storage.objects to anon;

-- Simulate the Realtime publication present in hosted Supabase projects.
create publication supabase_realtime;
