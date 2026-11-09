-- Il controllo GPS e' opzionale per scuola, ma sempre deciso dal server.
-- Versione sincronizzata con lo storico remoto di breakapp-dev.
-- Default conservativo: tutte le scuole esistenti mantengono la verifica.
alter table public.schools
 add column if not exists require_geolocation boolean not null default true;
grant select(require_geolocation) on public.schools to anon,authenticated;

create or replace function public.set_school_geolocation_required(p_school uuid,p_required boolean)
returns void language plpgsql security definer set search_path=''
as $set_policy$
begin
 if auth.uid() is null or (auth.jwt()->>'aal')<>'aal2' then
  raise exception 'È richiesta autenticazione Admin con 2FA';end if;
 if p_required is null then raise exception 'Scelta obbligo GPS non valida';end if;
 if not exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=p_school and m.user_id=auth.uid()
   and m.membership_status='active' and r.role_code='school_admin') then
  raise exception 'Non sei Admin della scuola selezionata';end if;
 update public.schools set require_geolocation=p_required where id=p_school;
 if not found then raise exception 'Scuola non disponibile';end if;
end;
$set_policy$;
revoke all on function public.set_school_geolocation_required(uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_school_geolocation_required(uuid,boolean) to authenticated;

-- Il trigger di audit gia' presente registra anche questo interruttore.
do $audit_geo$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('app_private.audit_school_settings()'::regprocedure);
 if pg_catalog.strpos(v_def,'''pickup_radius_m'',old.pickup_radius_m')=0
  or pg_catalog.strpos(v_def,'''pickup_radius_m'',new.pickup_radius_m')=0 then
  raise exception 'Audit scuola non compatibile con la migrazione obbligo GPS';end if;
 v_def:=pg_catalog.replace(v_def,'''pickup_radius_m'',old.pickup_radius_m',
  '''pickup_radius_m'',old.pickup_radius_m,''require_geolocation'',old.require_geolocation');
 v_def:=pg_catalog.replace(v_def,'''pickup_radius_m'',new.pickup_radius_m',
  '''pickup_radius_m'',new.pickup_radius_m,''require_geolocation'',new.require_geolocation');
 execute v_def;
end;
$audit_geo$;

-- Entrambi gli ingressi conferma (individuale e gruppo) applicano la
-- preferenza nel DB. Il client puo' omettere la geolocalizzazione soltanto
-- quando la scuola la disabilita. Tutti gli altri controlli restano invariati.
-- Partiamo dai corpi PostgreSQL realmente installati per non sovrascrivere
-- le correzioni piu' recenti a scorte, pagamenti, idempotenza e accuratezza.
do $toggle_geo$
declare v_def text;v_from integer;v_end integer;v_anchor text;v_function text;
begin
 foreach v_function in array array[
  'public.submit_individual_order(uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz)',
  'public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz)'
 ] loop
  v_def:=pg_catalog.pg_get_functiondef(v_function::regprocedure);
  v_from:=pg_catalog.strpos(v_def,'if v_school.latitude is null or v_school.longitude is null');
  v_anchor:=case when v_function like 'public.submit_individual_order%'
   then 'if p_items is null' else 'for v_item in' end;
  if v_from<1 or pg_catalog.strpos(pg_catalog.substr(v_def,v_from),v_anchor)=0
   or pg_catalog.strpos(v_def,'v_school.require_geolocation')>0 then
   raise exception 'Funzione %: blocco GPS non compatibile o gia'' modificato',v_function;
  end if;
  v_end:=v_from+pg_catalog.strpos(pg_catalog.substr(v_def,v_from),v_anchor)-1;
  v_def:=pg_catalog.substr(v_def,1,v_from-1)
    || E'if v_school.require_geolocation then\n '
    || pg_catalog.substr(v_def,v_from,v_end-v_from)
    || E'\nend if;\n '
    || pg_catalog.substr(v_def,v_end);
  execute v_def;
 end loop;
end;
$toggle_geo$;
