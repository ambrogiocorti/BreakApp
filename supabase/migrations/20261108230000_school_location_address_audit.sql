-- BreakApp: indirizzo visualizzato della scuola e tracciamento delle modifiche
-- a posizione e regole (richiesta dell'8/11/2026). L'Admin scuola con 2FA
-- modificava già latitudine, longitudine e raggio con configure_school_booking,
-- ma senza indirizzo né storico. Un trigger registra ogni modifica, da qualunque
-- funzione arrivi, con autore, valori precedenti e nuovi.
alter table public.schools add column if not exists address text;
alter table public.schools add constraint schools_address_length
 check (address is null or char_length(address) between 3 and 200);
grant select(address) on public.schools to anon,authenticated;

create table if not exists app_private.school_settings_audit(
 id bigint generated always as identity primary key,
 school_id uuid not null references public.schools(id) on delete restrict,
 actor_id uuid,
 previous jsonb not null,
 current jsonb not null,
 created_at timestamptz not null default now()
);
create index if not exists school_settings_audit_school_idx
 on app_private.school_settings_audit(school_id,created_at desc);
alter table app_private.school_settings_audit enable row level security;
revoke all on app_private.school_settings_audit from public,anon,authenticated;

create or replace function app_private.audit_school_settings()
returns trigger language plpgsql security definer set search_path=''
as $audit_settings$
declare v_old jsonb;v_new jsonb;
begin
 v_old:=jsonb_build_object('latitude',old.latitude,'longitude',old.longitude,
  'pickup_radius_m',old.pickup_radius_m,'address',old.address,
  'booking_horizon_days',old.booking_horizon_days,'cancel_cutoff_minutes',old.cancel_cutoff_minutes,
  'max_unpaid_orders_per_customer',old.max_unpaid_orders_per_customer,
  'approval_product_threshold',old.approval_product_threshold,
  'approval_amount_threshold_cents',old.approval_amount_threshold_cents);
 v_new:=jsonb_build_object('latitude',new.latitude,'longitude',new.longitude,
  'pickup_radius_m',new.pickup_radius_m,'address',new.address,
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
create trigger breakapp_audit_school_settings
 after update on public.schools
 for each row execute function app_private.audit_school_settings();

-- Indirizzo: stessa autorizzazione delle regole (Admin della scuola con 2FA).
create or replace function public.set_school_address(p_school_id uuid,p_address text)
returns void language plpgsql security definer set search_path=''
as $set_address$
declare v_address text:=nullif(btrim(coalesce(p_address,'')),'');
begin
 if auth.uid() is null or (auth.jwt()->>'aal')<>'aal2' then
  raise exception 'È richiesta autenticazione Admin con 2FA';end if;
 if not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
   where m.school_id=p_school_id and m.user_id=auth.uid()
   and m.membership_status='active' and r.role_code='school_admin')
 then raise exception 'Non sei Admin della scuola selezionata';end if;
 if v_address is not null and char_length(v_address) not between 3 and 200 then
  raise exception 'Indirizzo non valido: da 3 a 200 caratteri';end if;
 update public.schools set address=v_address where id=p_school_id;
 if not found then raise exception 'Scuola non disponibile';end if;
end;
$set_address$;
revoke all on function public.set_school_address(uuid,text) from public,anon,authenticated;
grant execute on function public.set_school_address(uuid,text) to authenticated;
