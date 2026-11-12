-- pg_net transports authorization headers; neither its queue nor cron is an app API.
begin;
do $$
declare n text;
begin
 foreach n in array array['net','cron'] loop
  if exists(select 1 from pg_namespace where nspname=n) then
   execute format('revoke all on schema %I from public,anon,authenticated',n);
   execute format('revoke all on all tables in schema %I from public,anon,authenticated',n);
   execute format('revoke all on all sequences in schema %I from public,anon,authenticated',n);
   execute format('revoke all on all functions in schema %I from public,anon,authenticated',n);
  end if;
 end loop;
end;$$;
commit;
