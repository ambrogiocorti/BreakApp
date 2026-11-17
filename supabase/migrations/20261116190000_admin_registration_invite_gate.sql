-- La registrazione di un account @admin.breakapp.it torna disponibile, ma è
-- sbloccata SOLO da un codice di invito valido emesso dal Super Admin
-- (app_private.school_staff_invites). Creato l'account, il ruolo viene
-- assegnato e l'invito consumato nello stesso passo. Entrambe le funzioni sono
-- riservate al backend: controllano `auth.jwt()->>'role' = 'service_role'` e
-- sollevano «Solo backend» per chiunque altro, quindi anche se esposte via
-- PostgREST non eseguono nulla per anon/authenticated. Vivono in public perché
-- l'edge function le chiama via RPC, che espone solo lo schema public.

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
-- confermato per quell'email e delega a app_private.claim_staff_invite_for, che
-- riverifica il codice, applica la regola «una sola scuola e un solo ruolo»,
-- assegna il ruolo, elimina l'invito e registra l'audit. Solleva un'eccezione se
-- il codice non è valido, così l'edge function può rimuovere l'account appena
-- creato.
create or replace function public.consume_admin_registration_invite(p_email text, p_code text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_email text; v_user uuid; v_result jsonb;
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
 v_result:=app_private.claim_staff_invite_for(v_user,p_code);
 if v_result is null then
  raise exception 'Codice di invito non valido per questo indirizzo.' using errcode='P0001';
 end if;
 return v_result;
end;
$$;
