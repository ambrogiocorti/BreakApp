-- BreakApp: tolleranza di precisione GPS decisa dall'Admin di ogni scuola
-- (decisione di Ambrogio del 8/11/2026). Prima era fissa a 100 m dentro
-- submit_individual_order e confirm_group_order. Il default resta 100 m; la
-- DEMO parte da 1000 m. Il controllo distanza + precisione <= raggio resta.
alter table public.schools add column if not exists location_accuracy_m integer not null default 100;
alter table public.schools add constraint schools_location_accuracy_range
 check (location_accuracy_m between 10 and 1000);
grant select(location_accuracy_m) on public.schools to anon,authenticated;

update public.schools set location_accuracy_m=1000 where is_demo;

-- Lo storico delle impostazioni registra anche la tolleranza.
create or replace function app_private.audit_school_settings()
returns trigger language plpgsql security definer set search_path=''
as $audit_settings$
declare v_old jsonb;v_new jsonb;
begin
 v_old:=jsonb_build_object('latitude',old.latitude,'longitude',old.longitude,
  'pickup_radius_m',old.pickup_radius_m,'address',old.address,
  'location_accuracy_m',old.location_accuracy_m,
  'booking_horizon_days',old.booking_horizon_days,'cancel_cutoff_minutes',old.cancel_cutoff_minutes,
  'max_unpaid_orders_per_customer',old.max_unpaid_orders_per_customer,
  'approval_product_threshold',old.approval_product_threshold,
  'approval_amount_threshold_cents',old.approval_amount_threshold_cents);
 v_new:=jsonb_build_object('latitude',new.latitude,'longitude',new.longitude,
  'pickup_radius_m',new.pickup_radius_m,'address',new.address,
  'location_accuracy_m',new.location_accuracy_m,
  'booking_horizon_days',new.booking_horizon_days,'cancel_cutoff_minutes',new.cancel_cutoff_minutes,
  'max_unpaid_orders_per_customer',new.max_unpaid_orders_per_customer,
  'approval_product_threshold',new.approval_product_threshold,
  'approval_amount_threshold_cents',new.approval_amount_threshold_cents);
 if v_old is distinct from v_new then
  insert into app_private.school_settings_audit(school_id,actor_id,previous,current)
  values(new.id,auth.uid(),v_old,v_new);
 end if;
 return new;
end;
$audit_settings$;
revoke all on function app_private.audit_school_settings() from public,anon,authenticated;

-- Stessa autorizzazione delle altre regole: Admin della scuola con 2FA.
create or replace function public.set_school_location_accuracy(p_school_id uuid,p_accuracy_m integer)
returns void language plpgsql security definer set search_path=''
as $set_accuracy$
begin
 if auth.uid() is null or (auth.jwt()->>'aal')<>'aal2' then
  raise exception 'È richiesta autenticazione Admin con 2FA';end if;
 if not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
   where m.school_id=p_school_id and m.user_id=auth.uid()
   and m.membership_status='active' and r.role_code='school_admin')
 then raise exception 'Non sei Admin della scuola selezionata';end if;
 if p_accuracy_m is null or p_accuracy_m not between 10 and 1000 then
  raise exception 'Tolleranza non valida: da 10 a 1000 metri';end if;
 update public.schools set location_accuracy_m=p_accuracy_m where id=p_school_id;
 if not found then raise exception 'Scuola non disponibile';end if;
end;
$set_accuracy$;
revoke all on function public.set_school_location_accuracy(uuid,integer) from public,anon,authenticated;
grant execute on function public.set_school_location_accuracy(uuid,integer) to authenticated;

-- Le due funzioni di conferma usano la tolleranza della scuola al posto dei
-- 100 m fissi. Si sostituisce solo quel confronto nel corpo attuale, e la
-- migrazione fallisce se il testo atteso non c'è (nessuna modifica parziale).
do $accuracy$
declare v_def text;
begin
 v_def:=pg_catalog.pg_get_functiondef('public.submit_individual_order(uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz)'::regprocedure);
 if pg_catalog.strpos(v_def,'p_accuracy_m > 100')=0 then
  raise exception 'submit_individual_order: controllo di precisione non trovato';end if;
 execute pg_catalog.replace(v_def,'p_accuracy_m > 100','p_accuracy_m > v_school.location_accuracy_m');
 v_def:=pg_catalog.pg_get_functiondef('public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz)'::regprocedure);
 if pg_catalog.strpos(v_def,'p_accuracy_m>100')=0 then
  raise exception 'confirm_group_order: controllo di precisione non trovato';end if;
 execute pg_catalog.replace(v_def,'p_accuracy_m>100','p_accuracy_m>v_school.location_accuracy_m');
end;
$accuracy$;
