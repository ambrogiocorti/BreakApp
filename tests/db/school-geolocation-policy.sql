-- Exercises the school-scoped GPS switch after all migrations.
begin;
reset role;
do $$begin
 if (select require_geolocation from public.schools where id='5ca00000-0000-4000-8000-00000000000a') is distinct from true
 then raise exception 'Existing school lost mandatory GPS default';end if;
 if has_column_privilege('authenticated','public.schools','require_geolocation','update')
 then raise exception 'Client can directly disable school GPS';end if;
end;$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','5ca00000-0000-4000-8000-0000000000a1',true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
do $$declare denied boolean:=false;begin
 begin perform public.set_school_geolocation_required('5ca00000-0000-4000-8000-00000000000a',false);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Admin without 2FA could disable GPS';end if;
end;$$;

select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal2"}',true);
select public.set_school_geolocation_required('5ca00000-0000-4000-8000-00000000000a',false);
do $$declare denied boolean:=false;begin
 if (select require_geolocation from public.schools where id='5ca00000-0000-4000-8000-00000000000a') is distinct from false
 then raise exception 'GPS policy did not persist';end if;
 if not exists(select 1 from app_private.school_settings_audit
  where school_id='5ca00000-0000-4000-8000-00000000000a'
   and previous->>'require_geolocation'='true' and current->>'require_geolocation'='false')
 then raise exception 'GPS toggle was not audited';end if;
 begin perform public.set_school_geolocation_required('5ca00000-0000-4000-8000-00000000000b',false);
 exception when others then denied:=true;end;
 if not denied then raise exception 'School A admin disabled GPS at school B';end if;
end;$$;

reset role;
do $$declare fn text;begin
 fn:=pg_get_functiondef('public.submit_individual_order(uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz)'::regprocedure);
 if strpos(fn,'if v_school.require_geolocation then')=0 then
  raise exception 'Individual order still requires GPS unconditionally';end if;
 fn:=pg_get_functiondef('public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz)'::regprocedure);
 if strpos(fn,'if v_school.require_geolocation then')=0 then
  raise exception 'Group confirmation still requires GPS unconditionally';end if;
end;$$;
rollback;
