-- BreakApp Phase A: cover foreign-key referencing columns with usable B-tree indexes.
-- Applies to public and app_private tables. An existing *leading-prefix* B-tree
-- index (including a unique index) is reused; no duplicate index is created.
-- Review write/lock impact before running on a live database with real traffic.
begin;

do $fk_coverage$
declare
  v_fk record;
  v_covered boolean;
  v_index_name text;
  v_created integer := 0;
begin
  for v_fk in
    select c.conrelid, c.conname, c.conkey,
           n.nspname as schema_name, t.relname as table_name,
           (
             select pg_catalog.string_agg(pg_catalog.format('%I', a.attname),
                                          ', ' order by k.ordinality)
             from pg_catalog.unnest(c.conkey) with ordinality as k(attnum, ordinality)
             join pg_catalog.pg_attribute a
               on a.attrelid=c.conrelid and a.attnum=k.attnum
           ) as column_list
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid=c.conrelid
    join pg_catalog.pg_namespace n on n.oid=t.relnamespace
    where c.contype='f'
      and n.nspname in ('public','app_private')
      and t.relkind in ('r','p')
    order by n.nspname,t.relname,c.conname
  loop
    select exists (
      select 1
      from pg_catalog.pg_index i
      join pg_catalog.pg_class ix on ix.oid=i.indexrelid
      join pg_catalog.pg_am am on am.oid=ix.relam
      where i.indrelid=v_fk.conrelid
        and am.amname='btree'
        and i.indisvalid and i.indisready
        and i.indpred is null
        and i.indnkeyatts >= pg_catalog.array_length(v_fk.conkey,1)
        and not exists (
          select 1
          from pg_catalog.unnest(v_fk.conkey) with ordinality as k(attnum,position)
          where i.indkey[(k.position-1)::integer] is distinct from k.attnum
        )
    ) into v_covered;

    if not v_covered then
      v_index_name := pg_catalog.format(
        'idx_fk_%s_%s',
        pg_catalog.left(v_fk.table_name,32),
        pg_catalog.left(
          pg_catalog.md5(v_fk.schema_name||'.'||v_fk.table_name||'.'||v_fk.conname),12)
      );
      execute pg_catalog.format('create index if not exists %I on %I.%I (%s)',
        v_index_name,v_fk.schema_name,v_fk.table_name,v_fk.column_list);
      v_created := v_created + 1;
    end if;
  end loop;
  raise notice 'BreakApp FK coverage: % new index(es) added',v_created;
end;
$fk_coverage$;

commit;
