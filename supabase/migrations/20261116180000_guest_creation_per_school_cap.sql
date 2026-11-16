-- Rafforza l'anti-abuso sulla creazione degli accessi ospite (punto 3 del report
-- di sicurezza del 16/11/2026).
--
-- Contesto: `claim_guest_creation` limita già le richieste per impronta
-- (10/minuto) e a livello globale (300/minuto, 1000/giorno). L'impronta è però
-- derivata dall'header `x-forwarded-for`, che un client può falsificare, quindi
-- un singolo attaccante può monopolizzare il budget globale e inondare di ordini
-- falsi il bar di UNA scuola.
--
-- Qui aggiungiamo un tetto giornaliero PER SCUOLA dentro `create_guest_access`
-- (che conosce la scuola e gira solo lato backend con il service_role). Il
-- conteggio riusa la tabella `app_private.guest_rate_limits` con una chiave di
-- ambito per-scuola e il bucket giornaliero. Se superato, la funzione solleva
-- un'eccezione: la Edge Function `guest-access` annulla già la creazione e
-- cancella l'utente auth appena creato.
--
-- Nessuna regola di isolamento tra scuole viene toccata: l'ospite resta legato
-- a una sola scuola e a un solo ruolo (customer).

create or replace function public.create_guest_access(p_user uuid,p_school uuid,p_name text,p_class text,p_hash text)
returns void language plpgsql security definer set search_path='' as $$
declare m uuid;v_school_day integer;begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'Solo backend';end if;
 if not exists(select 1 from public.schools where id=p_school and is_active) then raise exception 'Scuola non disponibile';end if;
 if exists(select 1 from public.schools where id=p_school and require_guest_class) and not exists(select 1 from public.school_classes where school_id=p_school and name=btrim(p_class) and active) then raise exception 'Scegli una classe attiva della scuola';end if;
 -- Tetto giornaliero per singola scuola (anti-flood di un bar specifico).
 insert into app_private.guest_rate_limits(fingerprint,minute_bucket,n)
  values('school-day:'||p_school::text,date_trunc('day',now()),1)
  on conflict(fingerprint,minute_bucket) do update set n=guest_rate_limits.n+1
  returning guest_rate_limits.n into v_school_day;
 if v_school_day>200 then raise exception 'Limite giornaliero di accessi ospite per questa scuola raggiunto' using errcode='P0001';end if;
 insert into app_private.guest_access_keys(user_id,school_id,name,class_name,token_hash) values(p_user,p_school,btrim(p_name),btrim(p_class),p_hash);
 insert into public.school_memberships(school_id,user_id,membership_status) values(p_school,p_user,'active') returning id into m;
 insert into public.role_assignments(membership_id,role_code) values(m,'customer');
end;$$;
