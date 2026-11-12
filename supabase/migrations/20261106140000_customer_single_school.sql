-- BreakApp: uno studente ordina solo dal bar della propria scuola.
-- Decisione di Ambrogio (6/11/2026). Gli ospiti erano già legati alla loro
-- scuola; gli studenti registrati invece non avevano un'appartenenza e
-- potevano ordinare in qualunque scuola (restava solo il controllo della
-- posizione). Ora la prima prenotazione o il primo gruppo collega lo
-- studente alla scuola come cliente; da quel momento ordini e gruppi in
-- altre scuole sono rifiutati dal database. Il personale ordina solo nella
-- propria scuola. Il Super Admin non ordina (regola già esistente).
-- I controlli sono trigger: valgono per ogni funzione che crea ordini o gruppi.
begin;

-- Collega l'account alla scuola se non ne ha ancora una; altrimenti verifica
-- che sia la stessa. Restituisce l'appartenenza.
create or replace function app_private.bind_customer_school(p_user uuid,p_school uuid)
returns uuid language plpgsql security definer set search_path=''
as $bind$
declare v_membership uuid;v_school uuid;
begin
 if p_user is null or p_school is null then raise exception 'Scuola e account richiesti';end if;
 if exists(select 1 from app_private.platform_admins where user_id=p_user) then return null;end if;
 select id,school_id into v_membership,v_school from public.school_memberships where user_id=p_user;
 if v_membership is null then
  insert into public.school_memberships(school_id,user_id,membership_status)
  values(p_school,p_user,'active')
  on conflict(user_id) do nothing
  returning id into v_membership;
  if v_membership is not null then
   insert into public.role_assignments(membership_id,role_code) values(v_membership,'customer');
   return v_membership;
  end if;
  -- Un'altra richiesta concorrente l'ha appena collegato: rileggi.
  select id,school_id into v_membership,v_school from public.school_memberships where user_id=p_user;
 end if;
 if v_school<>p_school then
  raise exception 'Puoi ordinare solo dal bar della tua scuola' using errcode='42501';
 end if;
 return v_membership;
end;
$bind$;
revoke all on function app_private.bind_customer_school(uuid,uuid) from public,anon,authenticated;

create or replace function app_private.enforce_order_school()
returns trigger language plpgsql security definer set search_path=''
as $order_school$
begin
 perform app_private.bind_customer_school(new.customer_id,new.school_id);
 return new;
end;
$order_school$;
revoke all on function app_private.enforce_order_school() from public,anon,authenticated;
create trigger breakapp_order_own_school
 before insert on public.orders
 for each row execute function app_private.enforce_order_school();

create or replace function app_private.enforce_group_draft_school()
returns trigger language plpgsql security definer set search_path=''
as $draft_school$
begin
 perform app_private.bind_customer_school(new.coordinator_id,new.school_id);
 return new;
end;
$draft_school$;
revoke all on function app_private.enforce_group_draft_school() from public,anon,authenticated;
create trigger breakapp_group_draft_own_school
 before insert on public.group_drafts
 for each row execute function app_private.enforce_group_draft_school();

create or replace function app_private.enforce_group_member_school()
returns trigger language plpgsql security definer set search_path=''
as $member_school$
declare v_school uuid;
begin
 select school_id into v_school from public.group_drafts where id=new.group_id;
 if v_school is not null then perform app_private.bind_customer_school(new.user_id,v_school);end if;
 return new;
end;
$member_school$;
revoke all on function app_private.enforce_group_member_school() from public,anon,authenticated;
create trigger breakapp_group_member_own_school
 before insert on public.group_members
 for each row execute function app_private.enforce_group_member_school();
commit;
