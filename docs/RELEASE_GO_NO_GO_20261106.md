# BreakApp — Decisione di rilascio per venerdì 6 novembre 2026

**Destinazione:** primo cliente / scuola pilota. **Ambiente attuale:** GitHub Pages + Supabase di sviluppo, Stripe TEST. **Stato aggiornato al 4 novembre:** **NO-GO per transazioni reali e uso commerciale senza limitazioni**.

Il Prompt Master (171 decisioni) resta vincolante: questa scheda verifica il rilascio, non riduce né modifica tacitamente i requisiti. Il via libera è distinto per **demo**, **pilota controllato senza incassi reali** e **esercizio commerciale con pagamenti**. Non basta una build verde.

## Evidenza tecnica verificata

| Controllo | Evidenza | Stato |
|---|---|---|
| Frontend e backend | PR #60 integrata, test JavaScript/build, database PostgreSQL e multibrowser CI superati il 3/11 | Verde per test automatici |
| Banco | Paginazione separata degli ordini attivi, controlli anti-race delle sessioni: PR #61 integrata in `main`, JS e multibrowser verdi | Collaudo reale al bar ancora necessario |
| Host pubblico | GitHub Pages disponibile; workflow uptime positivo il 3/11 | Verde per disponibilità **statica** |
| Autorizzazioni | RLS ordini attiva, cron autorizzato; test SQL isolati | Verifica intertenant con utenti reali ancora pendente |
| Cron | `breakapp-push-and-refunds` attivo ogni minuto, ultimi audit dei due endpoint HTTP 200 | Endpoint raggiungibili; consegna push non verificata su telefono |
| Stripe TEST | Il 04/11 Checkout individuale da 2,50 EUR, webhook firmato e rimborso sono riusciti in sandbox; prova via RPC/QA, non tramite interfacce complete. Le PR #76 e #77 sono distribuite in sviluppo: eventi tardivi e fuori ordine sono coperti da test automatici; un reinvio reale di `refund.updated` è stato riconciliato e il duplicato accettato. | **NO-GO** per pagamenti reali: completare le prove firmate degli esiti falliti e i collaudi UI/gruppi prima del rilascio |
| Backup giornaliero | **Database:** run reale #41654538860 decifrata e ripristinata su Supabase-Postgres 17 isolato, con verifiche SQL; **Storage:** backup reale e prova di recovery in streaming riusciti il 03/11 (run #41709597575, 2 bucket, 1 oggetto da 5.661 byte, SHA-256 verificato, artifact AES-256 #13266617186, conservazione fino al 03/12/2026) | Database ripristinato; Storage realmente acquisito e cifrato. **Schedulazione:** run database #41807385492 e Storage #41809932298 riuscite il 04/11. **Ancora da provare:** ripristino file in un progetto distinto, configurazione completa servizi Supabase e copia indipendente |
| Privacy e fiscale | Documentazione ancora da finalizzare con il cliente e professionisti competenti | **NO-GO** per esercizio commerciale non delimitato |
| Prove fisiche | Android, iPhone, terminale bar, Wi-Fi degradato, offline e revoche non certificate | **NO-GO** per operatività non supervisionata |
| Hosting | Su richiesta del titolare, per ora si usa GitHub Pages. Funzioni Stripe e push DEV verificate con origin GitHub e origin estranea. | Un eventuale dominio personalizzato tramite Register.it, i relativi redirect e il collaudo sono da verificare separatamente; promozione manuale |
| Merchant multipli | Il collegamento a Stripe Checkout è in TEST; l'onboarding attuale riguarda un solo merchant dimostrativo e le chiavi LIVE sono rifiutate. | Da implementare e verificare per ogni gestore/scuola prima degli incassi reali |
| Demo scuola | Scuola di prova separata con due prodotti fittizi, scorte e fasce dal 05 all'11/11; UI verificata fino al riepilogo. Creazione e idempotenza dell'ordine provate tramite transazione SQL annullata, con identità e posizione di test. | Conferma UI con GPS reale e ciclo di pagamento non verificati sulla demo; merchant Stripe non associato |

## Operazioni obbligatorie con dati e dispositivi del titolare

### A. Backup: prima di ogni dato reale del cliente

1. Aprire GitHub `ambrogiocorti/BreakApp` → **Settings → Secrets and variables → Actions**.
2. Configurare **`SUPABASE_BACKUP_DB_URL`**: URL PostgreSQL di connessione server/session pooler ottenuto dal progetto Supabase corretto, senza pubblicarlo né copiarlo nel codice.
3. Configurare **`BACKUP_PASSPHRASE`**: frase casuale custodita in password manager, lunghezza almeno 32 caratteri e separata dalla copia cifrata.
4. **Eseguito il 03/11/2026:** `Encrypted daily database backup` ha prodotto un artifact `.dump.gpg` cifrato, decifrato e validato con `pg_restore --list`, con esito GitHub `success`. Conservare la prova e verificare anche la prossima esecuzione automatica.
5. **Eseguito dal titolare il 03/11/2026:** restore PostgreSQL 17 su container Docker isolato, transazionale e senza errori, seguiti da query di controllo sui conteggi e RLS (vedere la riga Backup). La prova non include login, isolamento intertenant applicativo, file Storage né servizi Supabase completi. Effettuare copia separata dei **byte Storage** e documentare come ripristinare Auth/OAuth, DNS, Edge, Vault, Stripe e variabili.
6. Registrare responsabile, data, dimensione, RPO/RTO e risultato del ripristino; senza queste evidenze il gate resta rosso.

Non inserire URL, password o passphrase in chat, issue, commit o screenshot.

### B. Stripe TEST: un flusso finanziario completo

**Aggiornamento del 04/11:** le correzioni per `refund.failed` e `checkout.session.async_payment_failed` sono nel codice e nell'ambiente DEV; la destinazione TEST è iscritta a entrambi gli eventi. Test PostgreSQL e webhook sintetici coprono duplicati e consegne fuori ordine. Un evento reale `refund.updated` firmato è stato reinviato e verificato dal dispatcher, e i duplicati sono stati accettati senza creare un altro rimborso. Mancano ancora prove firmate reali dei due esiti di fallimento e un collaudo end-to-end dei gruppi. La sola iscrizione agli eventi non risolve il problema.

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
- Verifica Stripe TEST: `docs/STRIPE_SANDBOX_RELEASE_GATE.md`
- Prove di avvio: `docs/PILOT_START_CHECKLIST.md`
- Backup/restore: `docs/BACKUP_RESTORE_PHASE_A.md`
- Attivazioni esterne: `docs/EXTERNAL_ACTIVATION_GATES.md`
