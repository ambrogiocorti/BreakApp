# Incremento operativo del 27 ottobre 2026

## Uso

Barista → Cassa: aprire con fondo ricevuto, registrare movimenti motivati, contare fisicamente e confermare chiusura. Una differenza motivata consente il cambio turno. Admin → Cassa aggiunge rettifiche senza riscrivere il conteggio originale.

Offline: attivare/sbloccare il terminale con il PIN, salvare catalogo/manifest del giorno, usare Cassa e terminale. Gli eventi mantengono l'ordine di acquisizione; una revisione pendente ferma la sincronizzazione e conserva i dati locali. Risolvere gli eventi precedenti prima di contabilizzare la chiusura. Le operazioni tardive su un turno chiuso richiedono revisione Admin e restano movimenti successivi alla chiusura originale.

Admin → Report e annunci: periodo, calcolo, export CSV/Excel/PDF. Gli incassi si riferiscono alla registrazione del movimento; i prodotti agli ordini attivi e vendite registrati nel periodo. Rimborsi confermati e pendenti sono separati e possono riferirsi a pagamenti di periodi precedenti. È un rendiconto interno, non un documento fiscale.

Gli annunci raggiungono soltanto appartenenze attive della scuola. Consultare il menu pubblico non conferisce appartenenza. Pubblicazione idempotente, massimo cinque annunci per ora.

## Migrazioni e configurazione

Applicare i file `supabase/migrations/` dopo la baseline storica `supabase/sql/`. Applicati anche a `breakapp-dev` via connettore: il servizio può assegnare timestamp remoti diversi. Riconciliare la cronologia prima di adottare `db push`; non ripetere incrementi già applicati.

Vault custodisce `breakapp_vapid_public`, `breakapp_vapid_private`, `breakapp_vapid_subject`, `breakapp_dispatch_token`, `breakapp_project_url`. Il token in Vault ha precedenza sul fallback Edge `PUSH_DISPATCH_TOKEN`; le chiavi VAPID Edge, se presenti, devono essere coerenti con Vault. Una rotazione VAPID richiede di considerare le sottoscrizioni esistenti.

`breakapp-push-and-refunds` invoca ogni minuto `app_private.run_push_schedule()`. Installazione specifica dell'hosting: `supabase/ops/enable_push_scheduler.sql`, dopo Vault. Il trasporto è HTTP sincrono, con timeout predefiniti dell'hosting: i parametri CURL non sono modificabili dal ruolo disponibile. Il token non transita più nella coda pg_net. Un lock evita sovrapposizioni; ogni destinazione ha un esito indipendente. Payload push generico; dettaglio nel centro notifiche autenticato. Il workflow GitHub è soltanto un fallback manuale facoltativo, da configurare separatamente.

Controlli senza leggere segreti:

```sql
select jobname, schedule, active from cron.job
where jobname = 'breakapp-push-and-refunds';
select target, http_status, duration_ms, error_code, created_at
from app_private.scheduler_runs order by id desc limit 10;
```

Verificati dopo distribuzione e rotazione del token: dispatcher push HTTP 200, cron attivo, nessun riferimento a `net.http_post` nella funzione schedulata e registro inaccessibile ai ruoli client. L'audit conserva 14 giorni e non contiene token, corpi HTTP o dettagli grezzi degli errori. `cron.job_run_details.status='succeeded'` da solo non prova la riuscita delle chiamate: controllare `http_status`. Consegna su telefono fisico non certificata. Il dispatcher rimborsi risponde HTTP 503 finché manca `STRIPE_SECRET_KEY` di test (supportata anche restricted key `rk_test_…`); serve anche `STRIPE_WEBHOOK_SECRET`. Merchant scolastico verificato tramite Stripe: incassi disabilitati, `card_payments=inactive`.

## Preferenze e promemoria

Centro notifiche → Preferenze: salvare le categorie push e gli avvisi di sistema a pagina aperta. Gli avvisi in-app restano disponibili anche quando la categoria push è disattivata. Una preferenza è personale e vale sui propri dispositivi; il consenso del browser resta separato. Gli invii già affidati al provider possono arrivare dopo la modifica. Disattiva push su questo dispositivo esegue una revoca logica sul server e annulla la sottoscrizione nel browser, preservando le consegne precedenti. Lo stesso percorso viene usato al logout.

Il dispatcher genera promemoria a circa 5 minuti dal ritiro, con il saldo individuale o del coordinatore. I membri con proprie righe ancora scoperte ricevono un avviso di pagamento; quelli già saldati no. A circa 15 minuti dall'ultima chiusura della giornata, solo gli ordini pronti e non ritirati ricevono il richiamo; per un gruppo il destinatario è esclusivamente il coordinatore. Non è una nuova autorizzazione al ritiro anticipato. Le chiavi di deduplicazione comprendono ordine, fascia e destinatario; retry e batch successivi non duplicano i promemoria.

Migrazioni aggiunte: `20261027212824_notification_preferences.sql` e `20261027213135_scheduled_pickup_reminders.sql`, applicate anche a breakapp-dev. Il dispatcher ora limita le consegne contemporanee e impone un timeout al provider. Una sesta consegna interrotta termina la coda invece di restare indefinitamente in stato sending.

## Verifiche

- `npm run verify`: sintassi, unit test e build.
- `database.yml`: PostgreSQL 17, RLS, tenant, stock concorrente, gruppi, offline, cassa, report, retry e restore.
- `cash-sessions.sql`: incassi, duplicati, differenze motivate, immutabilità, rettifica, MFA e revoca.
- `reports-announcements.sql`: paginazione, minimizzazione, isolamento, MFA e destinatari.
- `runtime-refund-retries.sql`: segreti non pubblici, backoff e segnalazioni.
- `notification-preferences.sql`: isolamento tra account, categorie, avvisi persistenti, revoca con storico e tentativi esauriti.
- `pickup-reminders.sql`: saldo, destinatari, gruppi saldati, ultima chiusura, batch e deduplicazione.
- `notifications.mjs`: controlli reali del modulo ES in Chromium/Firefox/WebKit, con API di test isolata; salva, rifiuto API, revoca, lettura e logout su desktop/mobile.
- IndexedDB: ordine causale concorrente, salvataggi obsoleti e cambio generazione.
- Export verificati indipendentemente con openpyxl e parser PDF.
- PostgreSQL 17 in GitHub: superati integrazione, concorrenza stock e restore.
- Controllo live: zero tabelle pubbliche senza RLS e zero funzioni privilegiate eseguibili da anon. Applicata anche la precedente revoca SQL 22 mancante sul database remoto.
- Chromium con fixture UI: report autenticato, download Excel, rettifica Admin e larghezza mobile. Le fixture verificano l'interfaccia; l'autorizzazione reale è verificata dai test SQL.

Il test browser controlla anche l'avvio effettivo del JavaScript e il tipo MIME dei moduli. Il server di anteprima deve usare lo stesso `--base /BreakApp/` della build: la sola presenza dell'HTML di login non dimostra che l'app sia partita.

La suite SQL è eseguita localmente anche tramite PGlite; concorrenza fra connessioni e restore richiedono il job PostgreSQL 17. Non costituisce pagamento Stripe o collaudo fisico.

## Rollback

```sql
select cron.unschedule('breakapp-push-and-refunds');
```

Ripristinare il frontend dal precedente commit. Non eliminare registri di cassa, eventi, ricevute, rimborsi o Vault. Con dati reali correggere mediante migrazioni successive e movimenti compensativi. Un rollback delle funzioni deve preservare recupero eventi e cronologia dispositivi.

Per i moduli ancora mancanti vedere `ROADMAP.md`; non dichiarare completa la piattaforma sulla sola base dei test automatici.
