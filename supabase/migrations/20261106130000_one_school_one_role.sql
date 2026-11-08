-- BreakApp: «una scuola e un ruolo per account» garantito dal database.
-- Regola confermata (5/11/2026): ogni account, tranne il Super Admin, ha una
-- sola scuola e un solo ruolo. Il Super Admin non riceve ruoli scolastici:
-- agisce su tutte le scuole tramite app_private.platform_admins.
-- Finora la regola era applicata solo dalle funzioni degli inviti
-- (staff_target_refusal); qui diventa un vincolo, e le vecchie funzioni di
-- assegnazione passano dagli stessi controlli degli inviti.
begin;

-- I dati esistenti devono già rispettare la regola: non correggiamo nulla
-- in automatico, ci fermiamo con un messaggio chiaro.
do $check_existing$
begin
 if exists(select 1 from public.school_memberships group by user_id having count(*)>1)
 then raise exception 'Esistono account con più di una scuola: correggili prima di applicare il vincolo';end if;
 if exists(select 1 from public.role_assignments group by membership_id having count(*)>1)
 then raise exception 'Esistono account con più di un ruolo: correggili prima di applicare il vincolo';end if;
end;
$check_existing$;

-- Una sola appartenenza per account e un solo ruolo per appartenenza:
-- insieme danno «una scuola e un ruolo». Gli indici unici reggono anche
-- inserimenti concorrenti.
create unique index school_memberships_one_school_per_user
 on public.school_memberships(user_id);
create unique index role_assignments_one_role_per_membership
 on public.role_assignments(membership_id);
comment on index public.school_memberships_one_school_per_user is
 'Regola confermata: ogni account (Super Admin escluso, non ha appartenenze) ha una sola scuola.';
comment on index public.role_assignments_one_role_per_membership is
 'Regola confermata: ogni account ha un solo ruolo nella propria scuola.';

-- Un'appartenenza non cambia account o scuola: si rimuove e se ne crea un'altra.
create or replace function app_private.freeze_membership_identity()
returns trigger language plpgsql set search_path=''
as $freeze$
begin
 if new.user_id<>old.user_id or new.school_id<>old.school_id then
  raise exception 'Un''appartenenza non può cambiare account o scuola' using errcode='23514';
 end if;
 return new;
end;
$freeze$;
revoke all on function app_private.freeze_membership_identity() from public,anon,authenticated;
create trigger breakapp_freeze_membership_identity
 before update of user_id,school_id on public.school_memberships
 for each row execute function app_private.freeze_membership_identity();

-- Il controllo comune ora considera anche un'appartenenza senza ruolo in
-- un'altra scuola (non dovrebbe esistere, ma il vincolo la rifiuterebbe con
-- un messaggio tecnico).
create or replace function app_private.staff_target_refusal(p_user uuid,p_school uuid,p_role text)
returns text language sql stable security definer set search_path=''
as $refusal$
 select case
  when exists(select 1 from app_private.platform_admins where user_id=p_user)
   then 'Un Super Admin non può ricevere ruoli scolastici'
  when exists(select 1 from app_private.guest_access_keys where user_id=p_user)
   then 'Un account ospite non può diventare personale della scuola'
  when exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
   where m.user_id=p_user and m.school_id=p_school and r.role_code=p_role)
   then 'Questa persona ha già questo ruolo'
  when exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
   where m.user_id=p_user)
   then 'Questa persona ha già un ruolo: ogni account ha una sola scuola e un solo ruolo'
  when exists(select 1 from public.school_memberships m where m.user_id=p_user and m.school_id<>p_school)
   then 'Questa persona è già collegata a un''altra scuola: ogni account ha una sola scuola'
 end;
$refusal$;
revoke all on function app_private.staff_target_refusal(uuid,uuid,text) from public,anon,authenticated;

-- Vecchia assegnazione del Super Admin: stessi controlli e stesso esito degli
-- inviti. Con un account già confermato assegna il ruolo; altrimenti crea un
-- invito e restituisce il codice una sola volta.
create or replace function public.platform_assign_school_staff(
 p_school_id uuid,p_email text,p_role text
) returns jsonb language plpgsql security definer set search_path=''
as $assign_staff$
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_role is null or p_role not in ('school_admin','bartender','warehouse_manager')
 then raise exception 'Ruolo personale non valido';end if;
 return public.invite_school_staff(p_school_id,p_email,p_role)||jsonb_build_object('school_id',p_school_id);
end;
$assign_staff$;
revoke all on function public.platform_assign_school_staff(uuid,text,text) from public,anon,authenticated;
grant execute on function public.platform_assign_school_staff(uuid,text,text) to authenticated;

-- Vecchia assegnazione dell'Admin scuola: non è più usata dall'interfaccia
-- (che usa invite_school_staff) e non applicava la regola. La ritiriamo.
revoke all on function public.school_assign_staff(uuid,text,text) from public,anon,authenticated;
create or replace function public.school_assign_staff(p_school uuid,p_email text,p_role text)
returns void language plpgsql security definer set search_path=''
as $retired$
begin
 raise exception 'Funzione ritirata: usa invite_school_staff';
end;
$retired$;
revoke all on function public.school_assign_staff(uuid,text,text) from public,anon,authenticated;

-- Creazione di una scuola: il primo Admin passa dagli stessi controlli. Se
-- non ha ancora un account riceve un invito; l'esito torna all'interfaccia
-- per mostrare il codice di attivazione.
create or replace function public.platform_onboard_school(p_slug text,p_name text,p_bar_name text,p_latitude double precision,p_longitude double precision,p_mode text,p_admin_email text)
returns jsonb language plpgsql security definer set search_path=''
as $onboard$
declare v_school uuid;v_bar uuid;v_admin jsonb;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin con 2FA richiesto';end if;
 if p_latitude is null or p_longitude is null or p_mode not in ('active','ready_made') then raise exception 'Posizione e modalità richieste';end if;
 insert into public.schools(slug,name,latitude,longitude) values(lower(btrim(p_slug)),btrim(p_name),p_latitude,p_longitude) returning id into v_school;
 insert into public.bars(school_id,name,preparation_mode) values(v_school,btrim(p_bar_name),p_mode) returning id into v_bar;
 insert into public.bar_service_state(school_id,bar_id,accepting_orders,reason) values(v_school,v_bar,false,'Completa menu, orari, fasce e scorte prima di aprire il servizio');
 v_admin:=public.platform_assign_school_staff(v_school,p_admin_email,'school_admin');
 insert into app_private.school_onboarding_audit(school_id,actor_id,action,details) values(v_school,auth.uid(),'created',jsonb_build_object('bar_id',v_bar));
 return jsonb_build_object('school_id',v_school,'bar_id',v_bar,'admin',v_admin);
end;
$onboard$;
revoke all on function public.platform_onboard_school(text,text,text,double precision,double precision,text,text) from public,anon,authenticated;
grant execute on function public.platform_onboard_school(text,text,text,double precision,double precision,text,text) to authenticated;

-- Revoca: senza ruolo l'appartenenza non serve più e impedirebbe di
-- collegare la persona a un'altra scuola. La rimuoviamo insieme al ruolo.
create or replace function public.platform_revoke_school_staff(p_school_id uuid,p_user_id uuid,p_role text)
returns void language plpgsql security definer set search_path=''
as $revoke_staff$
declare v_membership uuid;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_role not in ('school_admin','bartender','warehouse_manager') or p_role is null
 then raise exception 'Ruolo non valido';end if;
 select id into v_membership from public.school_memberships
 where school_id=p_school_id and user_id=p_user_id for update;
 if not found then raise exception 'Assegnazione inesistente';end if;
 delete from public.role_assignments
 where membership_id=v_membership and role_code=p_role;
 if not found then raise exception 'Ruolo già non assegnato';end if;
 delete from public.school_memberships m where m.id=v_membership
  and not exists(select 1 from public.role_assignments r where r.membership_id=m.id);
 insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action)
 values(auth.uid(),p_user_id,p_school_id,p_role,'role_revoked');
end;
$revoke_staff$;
revoke all on function public.platform_revoke_school_staff(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.platform_revoke_school_staff(uuid,uuid,text) to authenticated;
commit;
