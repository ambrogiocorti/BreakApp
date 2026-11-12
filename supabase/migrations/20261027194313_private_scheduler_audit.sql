begin;
create table app_private.scheduler_runs(
 id bigint generated always as identity primary key,
 target text not null check(target in ('push-dispatch','group-refund-dispatch')),
 http_status integer,
 duration_ms integer not null check(duration_ms>=0),
 error_code text check(error_code is null or error_code='network_or_http_error'),
 created_at timestamptz not null default now()
);
create index scheduler_runs_by_time on app_private.scheduler_runs(created_at desc);
alter table app_private.scheduler_runs enable row level security;
revoke all on app_private.scheduler_runs from public,anon,authenticated;
revoke all on sequence app_private.scheduler_runs_id_seq from public,anon,authenticated;
commit;
