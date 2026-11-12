-- Hosted Supabase only, after Vault provisioning and migration secure_push_runtime.
-- Contains no credentials. The database resolves its own token from Vault.
-- Synchronous HTTP deliberately avoids storing authentication headers in pg_net's queue.
create extension if not exists pg_cron;
create extension if not exists http with schema extensions;
create table if not exists app_private.scheduler_runs (
 id bigint generated always as identity primary key,
 target text not null check(target in ('push-dispatch','group-refund-dispatch')),
 http_status integer,
 duration_ms integer not null check(duration_ms>=0),
 error_code text check(error_code is null or error_code='network_or_http_error'),
 created_at timestamptz not null default now()
);
alter table app_private.scheduler_runs enable row level security;
revoke all on app_private.scheduler_runs from public,anon,authenticated,service_role;
create or replace function app_private.run_push_schedule()
returns void language plpgsql security definer set search_path='' as $$
declare v_token text;v_url text;v_target text;v_status integer;v_start timestamptz;
begin
 if not pg_try_advisory_xact_lock(19861124,70) then return;end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where name='breakapp_dispatch_token';
 select decrypted_secret into v_url from vault.decrypted_secrets where name='breakapp_project_url';
 if length(coalesce(v_token,''))<32 or v_url !~ '^https://[a-z0-9]{20}\.supabase\.co$' or v_url is null
 then raise exception 'Scheduler non configurato';end if;
 foreach v_target in array array['push-dispatch','group-refund-dispatch'] loop
  v_start:=clock_timestamp();v_status:=null;
  begin
   select r.status into v_status from extensions.http(row('POST',
    v_url||'/functions/v1/'||v_target,
    array[row('x-breakapp-dispatch-token',v_token)::extensions.http_header],
    'application/json','{}')::extensions.http_request) r;
   insert into app_private.scheduler_runs(target,http_status,duration_ms,error_code)
   values(v_target,v_status,greatest(0,extract(epoch from clock_timestamp()-v_start)*1000)::integer,
    case when v_status between 200 and 299 then null else 'network_or_http_error' end);
  exception when others then
   -- Do not persist SQLERRM, response bodies or headers: they may contain credentials.
   insert into app_private.scheduler_runs(target,http_status,duration_ms,error_code)
   values(v_target,null,greatest(0,extract(epoch from clock_timestamp()-v_start)*1000)::integer,
    'network_or_http_error');
  end;
 end loop;
 delete from app_private.scheduler_runs where created_at<now()-interval '14 days';
end;$$;
revoke all on function app_private.run_push_schedule() from public,anon,authenticated,service_role;
select cron.schedule('breakapp-push-and-refunds','* * * * *','select app_private.run_push_schedule();');
