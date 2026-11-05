-- BreakApp: inviti per il personale che non ha ancora fatto il primo accesso.
-- Regole confermate:
--  * l'Admin scuola (2FA) aggiunge, modifica e rimuove baristi e magazzinieri
--    della propria scuola;
--  * solo il Super Admin (2FA) invita altri Admin scuola, per qualunque scuola;
--  * gli studenti si registrano da soli e restano fuori da questo flusso;
--  * ogni account (tranne il Super Admin) ha una sola scuola e un solo ruolo.
-- Un invito è legato a un'email. Al primo accesso con quella email:
--  * se l'email è verificata dal provider (registrazione con conferma, Google,
--    Microsoft) l'account viene collegato automaticamente;
--  * per gli indirizzi interni @admin.breakapp.it, che non ricevono posta e
--    quindi non provano il possesso dell'email, serve anche il codice di
--    attivazione mostrato una sola volta a chi ha creato l'invito.
-- Le autorizzazioni restano sul server: nessuna tabella è esposta al client.
begin;

create table app_private.school_staff_invites(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id) on delete cascade,
 email text not null check(email=lower(btrim(email)) and char_length(email) between 3 and 254),
 role_code text not null check(role_code in ('school_admin','bartender','warehouse_manager')),
 code_hash bytea not null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(email)
);
create index school_staff_invites_school on app_private.school_staff_invites(school_id);
create index school_staff_invites_creator on app_private.school_staff_invites(created_by);
alter table app_private.school_staff_invites enable row level security;
revoke all on app_private.school_staff_invites from public,anon,authenticated;

create table app_private.school_staff_invite_audit(
 id bigint generated always as identity primary key,
 actor_id uuid references auth.users(id) on delete set null,
 school_id uuid not null references public.schools(id) on delete cascade,
 email text not null,
 role_code text not null,
 action text not null check(action in ('invited','updated','code_renewed','removed','claimed','assigned_existing')),
 created_at timestamptz not null default now()
);
create index school_staff_invite_audit_school on app_private.school_staff_invite_audit(school_id);
create index school_staff_invite_audit_actor on app_private.school_staff_invite_audit(actor_id);
alter table app_private.school_staff_invite_audit enable row level security;
revoke all on app_private.school_staff_invite_audit from public,anon,authenticated;

-- Tentativi di codice sbagliati, per account e per ora.
create table app_private.school_staff_claim_attempts(
 user_id uuid not null references auth.users(id) on delete cascade,
 hour_bucket timestamptz not null,
 n integer not null,
 primary key(user_id,hour_bucket)
);
alter table app_private.school_staff_claim_attempts enable row level security;
revoke all on app_private.school_staff_claim_attempts from public,anon,authenticated;

-- Chi può gestire un ruolo in una scuola.
create or replace function app_private.can_manage_school_staff(p_school uuid,p_role text)
returns boolean language sql stable security definer set search_path=''
as $can_staff$
 select p_school is not null and p_role in ('school_admin','bartender','warehouse_manager')
  and (app_private.platform_approved()
   or (p_role in ('bartender','warehouse_manager') and app_private.can_manage_support_school(p_school)));
$can_staff$;
revoke all on function app_private.can_manage_school_staff(uuid,text) from public,anon,authenticated;

create or replace function app_private.normalize_staff_email(p_email text)
returns text language plpgsql immutable set search_path=''
as $norm_email$
declare v text:=lower(btrim(coalesce(p_email,'')));
begin
 if char_length(v)>254 or v!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 then raise exception 'Indirizzo email non valido';end if;
 return v;
end;
$norm_email$;
revoke all on function app_private.normalize_staff_email(text) from public,anon,authenticated;

-- Codice di 12 caratteri esadecimali da una sorgente casuale crittografica.
create or replace function app_private.new_staff_invite_code()
returns text language sql volatile set search_path=''
as $new_code$
 select upper(substr(h,1,4)||'-'||substr(h,5,4)||'-'||substr(h,9,4))
 from (select replace(gen_random_uuid()::text,'-','') h) x;
$new_code$;
revoke all on function app_private.new_staff_invite_code() from public,anon,authenticated;

create or replace function app_private.staff_code_hash(p_code text)
returns bytea language sql immutable set search_path=''
as $code_hash$
 select sha256(convert_to(regexp_replace(upper(coalesce(p_code,'')),'[^0-9A-Z]','','g'),'UTF8'));
$code_hash$;
revoke all on function app_private.staff_code_hash(text) from public,anon,authenticated;

-- Perché un account non può ricevere un ruolo scolastico (null se può).
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
 end;
$refusal$;
revoke all on function app_private.staff_target_refusal(uuid,uuid,text) from public,anon,authenticated;

create or replace function app_private.grant_staff_role(p_user uuid,p_school uuid,p_role text)
returns void language plpgsql security definer set search_path=''
as $grant_role$
declare v_membership uuid;
begin
 insert into public.school_memberships(school_id,user_id,membership_status)
 values(p_school,p_user,'active')
 on conflict(school_id,user_id) do update set membership_status='active'
 returning id into v_membership;
 insert into public.role_assignments(membership_id,role_code)
 values(v_membership,p_role) on conflict(membership_id,role_code) do nothing;
end;
$grant_role$;
revoke all on function app_private.grant_staff_role(uuid,uuid,text) from public,anon,authenticated;

-- Elenco del personale attivo e degli inviti in attesa di una scuola.
create or replace function public.list_school_staff(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $list_staff$
declare v_admin boolean:=app_private.platform_approved();
begin
 if not (v_admin or app_private.can_manage_support_school(p_school))
 then raise exception 'Admin scuola o Super Admin con 2FA richiesto';end if;
 return jsonb_build_object(
  'members',coalesce((select jsonb_agg(jsonb_build_object(
    'user_id',u.id,'email',u.email,'role',r.role_code,'status',m.membership_status
   ) order by u.email,r.role_code)
   from public.school_memberships m
   join auth.users u on u.id=m.user_id
   join public.role_assignments r on r.membership_id=m.id
   where m.school_id=p_school and r.role_code in ('school_admin','bartender','warehouse_manager')
    and not exists(select 1 from app_private.platform_admins pa where pa.user_id=u.id)),'[]'::jsonb),
  'invites',coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'email',i.email,'role',i.role_code,'created_at',i.created_at,'updated_at',i.updated_at,
    'can_edit',app_private.can_manage_school_staff(p_school,i.role_code)
   ) order by i.created_at)
   from app_private.school_staff_invites i where i.school_id=p_school),'[]'::jsonb));
end;
$list_staff$;

-- Aggiunge una persona. Con un account già attivo e senza ruoli assegna subito
-- il ruolo; altrimenti crea un invito e restituisce il codice una sola volta.
create or replace function public.invite_school_staff(p_school uuid,p_email text,p_role text)
returns jsonb language plpgsql security definer set search_path=''
as $invite_staff$
declare v_email text;v_user uuid;v_refusal text;v_code text;
begin
 if not app_private.can_manage_school_staff(p_school,p_role) then
  raise exception 'Non puoi assegnare questo ruolo: gli Admin scuola li aggiunge solo il Super Admin';end if;
 if not exists(select 1 from public.schools where id=p_school and is_active)
 then raise exception 'Scuola inesistente o non attiva';end if;
 v_email:=app_private.normalize_staff_email(p_email);
 if exists(select 1 from app_private.school_staff_invites where email=v_email)
 then raise exception 'Esiste già un invito per questa email';end if;
 -- Qualunque account con questa email, anche non ancora confermato, deve
 -- poter ricevere il ruolo; se è confermato il ruolo si assegna subito.
 for v_user in select id from auth.users where lower(email)=v_email loop
  v_refusal:=app_private.staff_target_refusal(v_user,p_school,p_role);
  if v_refusal is not null then raise exception '%',v_refusal;end if;
 end loop;
 select id into v_user from auth.users where lower(email)=v_email and email_confirmed_at is not null;
 if v_user is not null then
  perform app_private.grant_staff_role(v_user,p_school,p_role);
  insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action)
  values(auth.uid(),v_user,p_school,p_role,'role_assigned');
  insert into app_private.school_staff_invite_audit(actor_id,school_id,email,role_code,action)
  values(auth.uid(),p_school,v_email,p_role,'assigned_existing');
  return jsonb_build_object('status','assigned','email',v_email,'role',p_role);
 end if;
 v_code:=app_private.new_staff_invite_code();
 insert into app_private.school_staff_invites(school_id,email,role_code,code_hash,created_by)
 values(p_school,v_email,p_role,app_private.staff_code_hash(v_code),auth.uid());
 insert into app_private.school_staff_invite_audit(actor_id,school_id,email,role_code,action)
 values(auth.uid(),p_school,v_email,p_role,'invited');
 return jsonb_build_object('status','invited','email',v_email,'role',p_role,'code',v_code);
end;
$invite_staff$;

-- Modifica email o ruolo di un invito non ancora usato; può rinnovare il codice.
create or replace function public.update_school_staff_invite(
 p_invite uuid,p_email text,p_role text,p_renew_code boolean default false
) returns jsonb language plpgsql security definer set search_path=''
as $update_invite$
declare v_row app_private.school_staff_invites%rowtype;v_email text;v_code text;
begin
 select * into v_row from app_private.school_staff_invites where id=p_invite for update;
 if not found then raise exception 'Invito inesistente o già usato';end if;
 if not app_private.can_manage_school_staff(v_row.school_id,v_row.role_code)
  or not app_private.can_manage_school_staff(v_row.school_id,p_role)
 then raise exception 'Non puoi modificare questo invito';end if;
 v_email:=app_private.normalize_staff_email(p_email);
 if v_email<>v_row.email then
  if exists(select 1 from app_private.school_staff_invites where email=v_email)
  then raise exception 'Esiste già un invito per questa email';end if;
  if exists(select 1 from auth.users where lower(email)=v_email and email_confirmed_at is not null)
  then raise exception 'Questa email ha già un account: aggiungila dal modulo Aggiungi';end if;
 end if;
 if coalesce(p_renew_code,false) then v_code:=app_private.new_staff_invite_code();end if;
 update app_private.school_staff_invites set email=v_email,role_code=p_role,
  code_hash=case when v_code is null then code_hash else app_private.staff_code_hash(v_code) end,
  updated_at=now()
 where id=p_invite;
 insert into app_private.school_staff_invite_audit(actor_id,school_id,email,role_code,action)
 values(auth.uid(),v_row.school_id,v_email,p_role,
  case when v_code is not null and v_email=v_row.email and p_role=v_row.role_code then 'code_renewed' else 'updated' end);
 return jsonb_build_object('id',p_invite,'email',v_email,'role',p_role,'code',v_code);
end;
$update_invite$;

create or replace function public.remove_school_staff_invite(p_invite uuid)
returns void language plpgsql security definer set search_path=''
as $remove_invite$
declare v_row app_private.school_staff_invites%rowtype;
begin
 select * into v_row from app_private.school_staff_invites where id=p_invite for update;
 if not found then raise exception 'Invito inesistente o già usato';end if;
 if not app_private.can_manage_school_staff(v_row.school_id,v_row.role_code)
 then raise exception 'Non puoi rimuovere questo invito';end if;
 delete from app_private.school_staff_invites where id=p_invite;
 insert into app_private.school_staff_invite_audit(actor_id,school_id,email,role_code,action)
 values(auth.uid(),v_row.school_id,v_row.email,v_row.role_code,'removed');
end;
$remove_invite$;

-- Collega l'account all'invito. Senza codice funziona solo per email verificate
-- da un provider reale; gli indirizzi @admin.breakapp.it richiedono il codice.
create or replace function app_private.claim_staff_invite_for(p_user uuid,p_code text)
returns jsonb language plpgsql security definer set search_path=''
as $claim_for$
declare v_email text;v_row app_private.school_staff_invites%rowtype;v_refusal text;
begin
 select lower(email) into v_email from auth.users where id=p_user and email_confirmed_at is not null;
 if v_email is null then return null;end if;
 select * into v_row from app_private.school_staff_invites where email=v_email for update;
 if not found then return null;end if;
 if p_code is null then
  if v_email like '%@admin.breakapp.it' then return null;end if;
 elsif v_row.code_hash<>app_private.staff_code_hash(p_code) then
  return null;
 end if;
 if not exists(select 1 from public.schools where id=v_row.school_id and is_active) then return null;end if;
 v_refusal:=app_private.staff_target_refusal(p_user,v_row.school_id,v_row.role_code);
 if v_refusal is not null then return null;end if;
 perform app_private.grant_staff_role(p_user,v_row.school_id,v_row.role_code);
 delete from app_private.school_staff_invites where id=v_row.id;
 insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action)
 values(v_row.created_by,p_user,v_row.school_id,v_row.role_code,'role_assigned');
 insert into app_private.school_staff_invite_audit(actor_id,school_id,email,role_code,action)
 values(p_user,v_row.school_id,v_email,v_row.role_code,'claimed');
 return jsonb_build_object('school_id',v_row.school_id,'role',v_row.role_code);
end;
$claim_for$;
revoke all on function app_private.claim_staff_invite_for(uuid,text) from public,anon,authenticated;

create or replace function public.claim_school_staff_invite(p_code text)
returns jsonb language plpgsql security definer set search_path=''
as $claim_invite$
declare v_user uuid:=auth.uid();v_n integer;v_result jsonb;
begin
 if v_user is null then raise exception 'Accesso richiesto';end if;
 if char_length(coalesce(p_code,''))>40 then raise exception 'Codice non valido';end if;
 select n into v_n from app_private.school_staff_claim_attempts
  where user_id=v_user and hour_bucket=date_trunc('hour',now());
 if coalesce(v_n,0)>=10 then raise exception 'Troppi tentativi. Riprova tra un''ora';end if;
 v_result:=app_private.claim_staff_invite_for(v_user,p_code);
 if v_result is null then
  -- Il conteggio deve restare anche se il chiamante annulla: non sollevare
  -- un'eccezione dopo l'insert, restituisci un esito negativo.
  insert into app_private.school_staff_claim_attempts(user_id,hour_bucket,n)
  values(v_user,date_trunc('hour',now()),1)
  on conflict(user_id,hour_bucket) do update set n=school_staff_claim_attempts.n+1;
  delete from app_private.school_staff_claim_attempts where hour_bucket<now()-interval '1 day';
  return jsonb_build_object('ok',false);
 end if;
 return v_result||jsonb_build_object('ok',true);
end;
$claim_invite$;

-- Collegamento automatico quando l'email risulta verificata. Non deve mai
-- bloccare la registrazione: qualunque problema lascia l'invito in attesa.
create or replace function app_private.claim_staff_invite_on_confirm()
returns trigger language plpgsql security definer set search_path=''
as $on_confirm$
begin
 if new.email_confirmed_at is not null and new.email is not null then
  begin
   perform app_private.claim_staff_invite_for(new.id,null);
  exception when others then null;
  end;
 end if;
 return new;
end;
$on_confirm$;
revoke all on function app_private.claim_staff_invite_on_confirm() from public,anon,authenticated;

drop trigger if exists breakapp_claim_staff_invite on auth.users;
create trigger breakapp_claim_staff_invite
 after insert or update of email_confirmed_at,email on auth.users
 for each row execute function app_private.claim_staff_invite_on_confirm();

revoke all on function public.list_school_staff(uuid),
 public.invite_school_staff(uuid,text,text),
 public.update_school_staff_invite(uuid,text,text,boolean),
 public.remove_school_staff_invite(uuid),
 public.claim_school_staff_invite(text)
from public,anon,authenticated;
grant execute on function public.list_school_staff(uuid),
 public.invite_school_staff(uuid,text,text),
 public.update_school_staff_invite(uuid,text,text,boolean),
 public.remove_school_staff_invite(uuid),
 public.claim_school_staff_invite(text)
to authenticated;
commit;
