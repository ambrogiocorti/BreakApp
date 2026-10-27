-- Hosted Supabase only, after Vault provisioning and migration secure_push_runtime.
-- Contains no credentials. The database resolves its own token from Vault.
create extension if not exists pg_cron;
create extension if not exists pg_net;
create or replace function app_private.run_push_schedule()
returns void language plpgsql security definer set search_path='' as $$
declare v_token text;v_url text;
begin
 select decrypted_secret into v_token from vault.decrypted_secrets where name='breakapp_dispatch_token';
 select decrypted_secret into v_url from vault.decrypted_secrets where name='breakapp_project_url';
 if length(coalesce(v_token,''))<32 or v_url is null then raise exception 'Scheduler non configurato';end if;
 perform net.http_post(url:=v_url||'/functions/v1/push-dispatch',
  headers:=jsonb_build_object('content-type','application/json','x-breakapp-dispatch-token',v_token),
  body:='{}'::jsonb,timeout_milliseconds:=20000);
 perform net.http_post(url:=v_url||'/functions/v1/group-refund-dispatch',
  headers:=jsonb_build_object('content-type','application/json','x-breakapp-dispatch-token',v_token),
  body:='{}'::jsonb,timeout_milliseconds:=20000);
end;$$;
revoke all on function app_private.run_push_schedule() from public,anon,authenticated,service_role;
select cron.schedule('breakapp-push-and-refunds','* * * * *','select app_private.run_push_schedule();');
