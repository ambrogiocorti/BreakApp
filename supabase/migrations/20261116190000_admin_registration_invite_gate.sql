-- La registrazione di un account @admin.breakapp.it torna disponibile, ma è
-- sbloccata SOLO da un codice di invito valido emesso dal Super Admin
-- (app_private.school_staff_invites). Creato l'account, il ruolo viene
-- assegnato e l'invito consumato nello stesso passo. Entrambe le funzioni sono
-- riservate al backend (service_role) e vivono in public perché l'edge function
-- le chiama via RPC PostgREST, che espone solo lo schema public.

-- Verifica senza effetti collaterali: l'email è @admin.breakapp.it e il codice
-- corrisponde a un invito pendente per una scuola attiva. Usata prima di creare
-- l'account per non generare utenti quando il codice è errato.
create or replace function public.admin_registration_invite_valid(p_email text, p_code text)
 returns boolean
 language plpgsql
 stable
 security definer
 set search_path to ''
as $$
declare v_email text; v_row app_private.school_staff_invites%rowtype;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then
  raise exception 'Solo backend' using errcode='42501';
 end if;
 begin
  v_email:=app_private.normalize_staff_email(p_email);
 exception when others then return false;
 end;
 if v_email !~ '^[^@[:space:]]+@admin\.breakapp\.it$' or coalesce(btrim(p_code),'')='' then
  return false;
 end if;
 select * into v_row from app_private.school_staff_invites where email=v_email;
 if not found or v_row.code_hash<>app_private.staff_code_hash(p_code) then
  return false;
 end if;
 return exists(select 1 from public.schools where id=v_row.school_id and is_active);
end;
$$;

-- Consuma l'invito per l'account @admin.breakapp.it già creato: trova l'utente
-- confermato per quell'email, riverifica il codice, applica la regola «una sola
-- scuola e un solo ruolo», assegna il ruolo, elimina l'invito e registra l'audit.
create or replace function public.consume_admin_registration_invite(p_email text, p_code text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_email text; v_user uuid; v_row app_private.school_staff_invites%rowtype; v_refusal text;
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then
  raise exception 'Solo backend' using errcode='42501';
 end if;
 v_email:=app_private.normalize_staff_email(p_email);
 if v_email !~ '^[^@[:space:]]+@admin\.breakapp\.it$' then
  raise exception 'Solo gli indirizzi @admin.breakapp.it si registrano con codice di invito.' using errcode='P0001';
 end if;
 if coalesce(btrim(p_code),'')='' then
  raise exception 'Codice di invito obbligatorio.' using errcode='P0001';
 end if;
 select id into v_user from auth.users where lower(email)=v_email and email_confirmed_at is not null;
 if v_user is null then
  raise exception 'Account amministratore non trovato o non confermato.' using errcode='P0001';
 end if;
 select * into v_row from app_private.school_staff_invites where email=v_email for update;
 if not found or v_row.code_hash<>app_private.staff_code_hash(p_code) then
  raise exception 'Codice di invito non valido per questo indirizzo.' using errcode='P0001';
 end if;
 if not exists(select 1 from public.schools where id=v_row.school_id and is_active) then
  raise exception 'La scuola associata all''invito non è attiva.' using errcode='P0001';
 end if;
 v_refusal:=app_private.staff_target_refusal(v_user,v_row.school_id,v_row.role_code);
 if v_refusal is not null then
  raise exception '%',v_refusal using errcode='P0001';
 end if;
 perform app_private.grant_staff_role(v_user,v_row.school_id,v_row.role_code);
 delete from app_private.school_staff_invites where id=v_row.id;
 insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action)
  values(v_row.created_by,v_user,v_row.school_id,v_row.role_code,'role_assigned');
 insert into app_private.school_staff_invite_audit(actor_id,school_id,email,role_code,action)
  values(v_user,v_row.school_id,v_email,v_row.role_code,'claimed');
 return jsonb_build_object('school_id',v_row.school_id,'role',v_row.role_code);
end;
$$;

revoke all on function public.admin_registration_invite_valid(text,text) from public, anon, authenticated;
revoke all on function public.consume_admin_registration_invite(text,text) from public, anon, authenticated;
grant execute on function public.admin_registration_invite_valid(text,text) to service_role;
grant execute on function public.consume_admin_registration_invite(text,text) to service_role;
