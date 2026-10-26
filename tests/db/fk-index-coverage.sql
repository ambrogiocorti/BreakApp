-- BreakApp Phase A: the disposable CI database must not contain uncovered
-- foreign keys on application tables after migration 23.
reset role;

do $assert_fk_coverage$
declare v_missing text;v_total integer;
begin
  select pg_catalog.string_agg(
    pg_catalog.format('%I.%I (%s) via %I',n.nspname,t.relname,
      (select pg_catalog.string_agg(a.attname,', ' order by k.ordinality)
       from pg_catalog.unnest(c.conkey) with ordinality as k(attnum,ordinality)
       join pg_catalog.pg_attribute a
         on a.attrelid=c.conrelid and a.attnum=k.attnum),
      c.conname),E'\n' order by n.nspname,t.relname,c.conname),
    pg_catalog.count(*)
  into v_missing,v_total
  from pg_catalog.pg_constraint c
  join pg_catalog.pg_class t on t.oid=c.conrelid
  join pg_catalog.pg_namespace n on n.oid=t.relnamespace
  where c.contype='f' and n.nspname in ('public','app_private')
    and not exists (
      select 1
      from pg_catalog.pg_index i
      join pg_catalog.pg_class ix on ix.oid=i.indexrelid
      join pg_catalog.pg_am am on am.oid=ix.relam
      where i.indrelid=c.conrelid and am.amname='btree'
        and i.indisvalid and i.indisready and i.indpred is null
        and i.indnkeyatts >= pg_catalog.array_length(c.conkey,1)
        and not exists (
          select 1
          from pg_catalog.unnest(c.conkey) with ordinality as k(attnum,position)
          where i.indkey[(k.position-1)::integer] is distinct from k.attnum
        )
    );
  if coalesce(v_total,0) > 0 then
    raise exception 'Foreign keys without leading B-tree index (%): %',
      v_total,v_missing;
  end if;
end;
$assert_fk_coverage$;
