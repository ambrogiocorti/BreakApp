# BreakApp — Decisione di rilascio per venerdì 6 novembre 2026

**Destinazione:** primo cliente / scuola pilota. **Ambiente attuale:** GitHub Pages + Supabase di sviluppo, Stripe TEST. **Stato al 3 novembre:** **NO-GO per transazioni reali e uso commerciale senza limitazioni**.

Il Prompt Master (171 decisioni) resta vincolante: questa scheda verifica il rilascio, non riduce né modifica tacitamente i requisiti. Il via libera è distinto per **demo**, **pilota controllato senza incassi reali** e **esercizio commerciale con pagamenti**. Non basta una build verde.

## Evidenza tecnica verificata

| Controllo | Evidenza | Stato |
|---|---|---|
| Frontend e backend | PR #60 integrata, test JavaScript/build, database PostgreSQL e multibrowser CI superati il 3/11 | Verde per test automatici |
| Banco | Coda per stato/fascia; P0 paginazione separata degli ordini aperti nel branch di rilascio | Richiede merge CI e collaudo reale |
| Host pubblico | GitHub Pages disponibile; workflow uptime positivo il 3/11 | Verde per disponibilità **statica** |
| Autorizzazioni | RLS ordini attiva, cron autorizzato; test SQL isolati | Verifica intertenant con utenti reali ancora pendente |
| Cron | `breakapp-push-and-refunds` attivo ogni minuto, ultimi audit dei due endpoint HTTP 200 | Endpoint raggiungibili; consegna push non verificata su telefono |
| Stripe TEST | Merchant collegato alla scuola e marcato attivo; zero `payment_attempts` e zero `payment_refunds` al 3/11 | **NO-GO:** mancano prova Checkout → webhook firmato → ledger → rimborso |
| Backup giornaliero | Primo backup reale cifrato **riuscito il 03/11/2026**, run #41654538860, archivio `breakapp-20261103T143157Z.dump.gpg` autenticato e leggibile; artifact GitHub conservato fino al 03/12/2026. Le esecuzioni precedenti erano fallite per credenziali errate/mancanti | **Parziale:** ripristino su database isolato, byte Storage, conservazione esterna e successiva esecuzione schedulata ancora da verificare |
| Privacy e fiscale | Documentazione ancora da finalizzare con il cliente e professionisti competenti | **NO-GO** per esercizio commerciale non delimitato |
| Prove fisiche | Android, iPhone, terminale bar, Wi-Fi degradato, offline e revoche non certificate | **NO-GO** per operatività non supervisionata |
| Hosting definitivo | Stack confermato Cloudflare Pages; attualmente GitHub Pages per test e anteprime Vercel | Da configurare, collaudare e promuovere manualmente |

## Operazioni obbligatorie con dati e dispositivi del titolare

### A. Backup: prima di ogni dato reale del cliente

1. Aprire GitHub `ambrogiocorti/BreakApp` → **Settings → Secrets and variables → Actions**.
2. Configurare **`SUPABASE_BACKUP_DB_URL`**: URL PostgreSQL di connessione server/session pooler ottenuto dal progetto Supabase corretto, senza pubblicarlo né copiarlo nel codice.
3. Configurare **`BACKUP_PASSPHRASE`**: frase casuale custodita in password manager, lunghezza almeno 32 caratteri e separata dalla copia cifrata.
4. **Eseguito il 03/11/2026:** `Encrypted daily database backup` ha prodotto un artifact `.dump.gpg` cifrato, decifrato e validato con `pg_restore --list`, con esito GitHub `success`. Conservare la prova e verificare anche la prossima esecuzione automatica.
5. Eseguire **restore su progetto/database separato e vuoto**, controllando dati, RLS, privilegi, ordini e ledger. Effettuare copia separata dei **byte Storage** e documentare come ripristinare Auth/OAuth, DNS, Edge, Vault, Stripe e variabili.
6. Registrare responsabile, data, dimensione, RPO/RTO e risultato del ripristino; senza queste evidenze il gate resta rosso.

Non inserire URL, password o passphrase in chat, issue, commit o screenshot.

### B. Stripe TEST: un flusso finanziario completo

1. Admin scuola configura fascia di ritiro reale/futura e prodotto con stock effettivo; Cliente distinto dal Super Admin, entro raggio GPS, conferma un ordine.
2. Verificare sessione Stripe Checkout con carta di TEST, connessione all'account merchant atteso, importo in centesimi e singolo PaymentIntent.
3. Verificare webhook firmato ricevuto dal backend, transazione nel ledger, singolo incasso, stato ordine; ripetere webhook e timeout per provare idempotenza.
4. Barista conclude l'ordine e usa **Rimborsa** con motivo/conferma. Verificare `refund.updated`, pagamento originario e stato finale senza doppi rimborsi.
5. Ripetere un ordine di gruppo multipagatore e una cancellazione durante checkout. Solo dopo questi risultati valutare configurazione LIVE e responsabilità del merchant.

Mai abilitare Stripe LIVE o accettare denaro reale sulla sola prova di una card TEST.

### C. Esercizio nella scuola pilota

- Admin scuola con 2FA, Barista, Magazziniere e Cliente **distinti**; conferma RLS con **due scuole test isolate** e account di ruoli diversi.
- Due dispositivi fisici (Android e iOS), turno di cassa, rete lenta e assenza rete, offline autorizzato/revoca su altro dispositivo, sincronizzazione senza doppio incasso, controlli su scorte concurrenti e ultimo pezzo.
- Push a PWA chiusa e permessi negati, QR e fallback manuale, sostituzioni, gruppi e rimborsi contanti/POS esterno **solo dopo reale restituzione**.
- Gestore del bar valida ingredienti, allergeni e aggiornamenti; la piattaforma non certifica diete né emissione del documento fiscale.
- Responsabili approvano informativa privacy, nomine, conservazione, ruoli titolare/responsabile, procedure di incident response, fiscalità, contratto, assistenza e prezzo. Verificare distintività commerciale del nome.

## Criteri di decisione

- **Demo dimostrativa**: consentita in sandbox, dati fittizi, nessun incasso reale, comunicazione esplicita dei limiti.
- **Pilota supervisionato**: solo con consenso del cliente e perimetro scritto; nessun dato scolastico reale senza backup, privacy e controllo accessi. Le funzioni non collaudate vanno disabilitate a livello operativo/accordo, non dichiarate complete.
- **Vendita e produzione**: richiede **tutti** i gate P0 verdi, evidenze del test Stripe e restore, validazione del gestore, pubblicazione separata, monitoraggio, assistenza/rollback e verbale di accettazione firmato.

**Decisione attuale: NO-GO per vendita come piattaforma completamente pronta.** Riesaminare dopo le prove e la configurazione dei servizi esterni; non usare i risultati dei test sintetici per indicare incassi, notifiche o backup reali riusciti.

## Link operativi

- Primo backup reale riuscito: https://github.com/ambrogiocorti/BreakApp/actions/runs/41654538860 (artifact https://github.com/ambrogiocorti/BreakApp/actions/runs/41654538860/artifacts/13238692432)
- Stato e roadmap: `ROADMAP.md`
- Prove di avvio: `docs/PILOT_START_CHECKLIST.md`
- Backup/restore: `docs/BACKUP_RESTORE_PHASE_A.md`
- Attivazioni esterne: `docs/EXTERNAL_ACTIVATION_GATES.md`
