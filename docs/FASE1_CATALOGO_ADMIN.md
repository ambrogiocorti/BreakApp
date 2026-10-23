# BreakApp — Attivazione online del catalogo Admin (incremento 03)

Data: 23 ottobre 2026. Nessun ambiente locale richiesto.

## Condizioni iniziali

- Repository: https://github.com/ambrogiocorti/BreakApp
- Anteprima: https://breakapp-smoky.vercel.app/
- **Nuovo** progetto Supabase di BreakApp: https://supabase.com/dashboard/project/ynvswdyirngvdpudcikl
- SQL `01_breakapp_foundations.sql` e `02_first_school_admin.sql` già eseguiti sul **nuovo** progetto.
- L'utente Admin deve aver confermato l'email e possedere una membership attiva con `role_code = 'school_admin'`.

## Da eseguire una volta in Supabase

1. Apri il progetto Supabase con ID **ynvswdyirngvdpudcikl**, non quello di altri progetti.
2. Vai su **SQL Editor → New query**.
3. Apri il file `supabase/sql/03_catalog_admin.sql` dal repository GitHub, clicca **Raw**, copia tutto e incolla nell'editor.
4. Verifica l'intestazione: riguarda soltanto `public.categories` e `public.products`, con indici, vincoli e policy; non elimina dati utente/scuola.
5. Premi **Run**. La transazione è unica: se fallisce, nessuna modifica del file dovrebbe essere committata dal database.
6. In **Authentication → Multi-Factor Authentication**, assicurati che **Authenticator App (TOTP)** sia abilitata (verifica MFA attiva).
7. Nelle impostazioni **Authentication → URL Configuration**, controlla il **Site URL** e aggiungi `https://breakapp-smoky.vercel.app/**` tra i Redirect URLs consentiti per i login che tornano all'app. Non abilitare provider OAuth finché non sono configurati.

## Test direttamente online (nessuna installazione)

1. Apri https://breakapp-smoky.vercel.app/ e accedi con l'Admin creato/assegnato nello SQL 02.
2. Nella sezione **Le tue scuole** verifica il ruolo **Admin scuola**.
3. Nella sezione **Verifica in due passaggi**, premi **Attiva 2FA con QR** se non hai già un autenticatore. Scansiona il QR con l'app Authenticator e conferma con il codice di 6 cifre. Non condividere il QR o il codice.
4. Se l'autenticatore è già presente, inserisci direttamente il codice temporaneo per elevare la sessione a livello AAL2.
5. Nella sezione **Gestisci il catalogo**, scegli scuola e bar, crea una categoria (per esempio `Panini`).
6. Crea un prodotto di prova con prezzo `2,50`. Controlla che sia visualizzato `2,50 €`, poi prova modifica e pulsanti **Nascondi/Riattiva**.
7. Aggiorna la pagina e verifica che il prodotto resti salvato (nessun localStorage usato per il catalogo).
8. Esci e riaccedi: una nuova sessione Admin senza codice 2FA non deve poter scrivere finché non è `aal2`.

## Verifiche di sicurezza consigliate

- Account anonimo: può leggere solo categorie/prodotti attivi appartenenti a scuole/bar attivi; non può inserire o modificare.
- Account cliente: nessuna scrittura in `categories` o `products`.
- Admin senza 2FA: nessuna scrittura anche conoscendo direttamente gli endpoint REST.
- Admin con 2FA: gestisce solo il proprio `school_id`; un bar o una categoria di un'altra scuola non può essere assegnato per via dei vincoli FK compositi.
- Disattivare una categoria la nasconde dal catalogo pubblico; i dati restano nel database.
- Nessun `service_role`/secret è usato dal frontend.

## Stato reale e limiti

Questo incremento fornisce il codice per CRUD catalogo e policy RLS. **La migrazione 03 resta da applicare manualmente** nel nuovo Supabase: il connettore del progetto in questa sessione è associato a un account diverso. Finché 03 non è eseguito, la UI mostra un errore esplicito invece di simulare la persistenza.

Non sono ancora attivi: scorte, allergeni, ordinazioni, pagamento, Stripe, offline di cassa e sincronizzazione, gestione degli altri ruoli. I prodotti creati sono **dati di sviluppo** finché la Fase 2 non include i requisiti merceologici e sanitari completi.
