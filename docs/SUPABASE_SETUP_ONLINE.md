# BreakApp — Configurazione Supabase da un secondo account (solo online)

Questa guida serve a creare un **nuovo progetto dedicato a BreakApp** in un
**account Supabase differente**. Non occorre usare il computer come server,
installare PostgreSQL o lanciare la PWA in locale.

## 1. Crea il progetto nel nuovo account

1. Apri https://supabase.com/dashboard in una finestra privata del browser e
   accedi al **nuovo account Supabase**.
2. Se necessario crea una nuova organizzazione; premi **New project**.
3. Nome: `breakapp-dev`. Scegli una password database robusta e conservala
   nel tuo password manager. Preferisci una regione UE vicina agli utenti,
   compatibilmente con le opzioni realmente disponibili.
4. Attendi che lo stato del progetto sia pronto. Non usare i database di
   5AHub, tornei o altre applicazioni.

## 2. Esegui lo SQL di base

1. Dal nuovo progetto apri **SQL Editor > New query**.
2. Copia tutto `supabase/sql/01_breakapp_foundations.sql` e premi **Run**.
3. In **Table Editor** verifica le cinque tabelle `public`:
   `schools`, `bars`, `profiles`, `school_memberships`, `role_assignments`.
4. In **Authentication > Policies** verifica che RLS sia abilitata per
   tutte. `app_private.platform_admins` non è esposta alla Data API.

Lo script crea solo le fondamenta: directory pubblica di scuole/bar attivi,
profilo personale privato, appartenenze/ruoli visibili solo al titolare.
**Nessun utente può scrivere ruoli, scuole o appartenenze dal client.**

## 3. Configura Supabase Auth

1. **Authentication > Providers > Email**: mantieni email/password attivo,
   con conferma email richiesta. Inizialmente non attivare provider esterni.
2. **Authentication > URL Configuration**:
   - **Site URL:** `https://breakapp-smoky.vercel.app`
   - **Redirect URLs:** aggiungi `https://breakapp-smoky.vercel.app/**`
3. Controlla il funzionamento della posta di conferma. Per uso reale con
   molti utenti va configurato un SMTP adeguato: l'invio standard integrato
   ha limiti e non costituisce infrastruttura email di produzione.

Quando vorrai abilitare Google/Microsoft, andranno configurati anche i
rispettivi client OAuth in Google Cloud/Microsoft Entra e i provider nella
dashboard Supabase; **non** inserire mai i segreti OAuth nel frontend.

## 4. Recupera SOLO i due valori pubblici

In **Project Settings > API Keys** (o sezione equivalente del dashboard):

- **Project URL**: `https://TUO-PROJECT-REF.supabase.co`
- **Publishable key**: comincia con `sb_publishable_`

Non confondere la publishable key con `sb_secret_`, `service_role`, JWT
secret, password del DB oppure access token personali. Quelli **non devono
mai** essere pubblicati in GitHub, nella chat o in variabili `VITE_*`.

## 5. Collega Vercel (senza ambiente locale)

1. Vai a https://vercel.com/dashboard e seleziona il progetto `breakapp`.
2. Apri **Settings > Environment Variables** e inserisci:

   | Key | Value | Ambiente |
   | --- | --- | --- |
   | `VITE_SUPABASE_URL` | URL del nuovo progetto | `Production` |
   | `VITE_SUPABASE_PUBLISHABLE_KEY` | chiave `sb_publishable_…` | `Production` |

3. La pubblicazione Vercel attuale è tecnicamente `Production` su Vercel,
   ma è **solo l'ambiente di prova di BreakApp**. Aggiungi `Preview` quando
   attiveremo deploy per branch.
4. Apri **Deployments**, scegli l'ultimo deploy e **Redeploy**. Le variabili
   `VITE_*` vengono incorporate durante la build: senza redeploy la pagina
   continuerà a mostrare "Supabase non collegato".

## 6. Prova il flusso online

1. Apri `https://breakapp-smoky.vercel.app/` con l'account autorizzato
   ad accedere alla preview Vercel (SSO/Deployment Protection può richiederlo).
2. Inserisci un'email di test e una password robusta; scegli Registrati.
3. Conferma il link arrivato per email, torna al sito ed effettua il login.
4. Controlla sul nuovo Supabase **Authentication > Users**: l'utente deve
   esistere. In **Table Editor > profiles** deve comparire il suo `id`.
5. Prima di predisporre una dashboard Admin, esegui eventualmente il file
   `supabase/sql/02_first_school_admin.sql` dal **SQL Editor** dopo aver
   sostituito l'email e i dati della scuola.

## 7. Verifiche di sicurezza nel SQL Editor

```sql
select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in (
    'schools', 'bars', 'profiles', 'school_memberships', 'role_assignments'
  )
order by tablename;

select (select count(*) from auth.users) as auth_users,
       (select count(*) from public.profiles) as profiles;
```

Tutte e cinque le tabelle devono mostrare `rowsecurity = true`.
Queste query nel SQL Editor usano privilegi amministrativi e **non** provano
da sole l'isolamento dei dati: nelle prossime milestone testeremo le policy
con due utenti e due scuole distinte, incluse negazioni di accesso.

## Limiti espliciti di questo incremento

- L'autenticazione email e la creazione dei profili saranno testabili solo
  dopo che avrai configurato le due variabili e avremo effettuato il redeploy.
- Lo schema non implementa ancora dashboard Admin, 2FA obbligatoria,
  onboarding dei membri, ordini, scorte, pagamenti, offline o Stripe.
- Non assegnare ruoli tramite `user_metadata`: i ruoli stanno nel DB e si
  assegnano con percorsi server-side protetti, non tramite il browser.
- Eseguire SQL manualmente crea un primo baseline versionato in repository,
  ma **non equivale** a una migrazione già tracciata dalla CLI Supabase.
  Il passaggio al registro migrazioni sarà gestito separatamente e con
  attenzione a non rieseguire DDL distruttivi.
