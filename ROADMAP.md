# Stato della piattaforma

Aggiornato il 3 novembre 2026. La specifica privata resta la fonte dei requisiti. Le verifiche automatiche usano database e pagamenti sintetici isolati; il servizio collegato è l'ambiente di sviluppo. La pagina Gruppi ha un'interfaccia responsive dedicata; nessun ruolo amministrativo è stato assegnato agli account social usati per il test.

| Area | Implementazione | Verifica |
| --- | --- | --- |
| Account e scuole | RBAC per scuola, TOTP Admin/Super Admin con blocco di ulteriori Authenticator, registrazione senza conferma per il dominio esatto `admin.breakapp.it`, ospiti con link privato e recupero email verificata, import CSV/XLSX, creazione/sospensione/riattivazione scuole e assegnazione personale | RLS, ruoli, ospite non coordinatore, onboarding transazionale; accessi Google e Microsoft confermati manualmente il 29 ottobre, senza funzioni Admin per gli account privi di ruolo |
| Catalogo e scorte | Prodotti, immagini, ingredienti/allergeni, scorte giornaliere, vendite, conta motivata anche sotto il prenotato, priorità di ritiro e sostituzioni | Ultima unità concorrente; isolamento prodotto/giorno; un ammanco non cancella arbitrariamente gli ordini confermati |
| Ordini | GPS, idempotenza, QR, preparazione/ritiro, preferiti, riordino, modifica atomica, sostituzioni e proposte di orario con consenso | Ordine originale preservato su errore, cutoff, allergeni, nessuno spostamento tacito |
| Grandi ordini | Coda senza stock, presenza Barista, limite attivazioni, riserva di 10 minuti, priorità fascia, nuova fascia o risposta entro 2 ore | Attivazione, scadenze, rifiuto, rilascio e rimborso; nessuna autoconferma sopra soglia |
| Gruppi e finanza | Inviti, coordinatore registrato, carrelli personali, pagamenti di righe anche per altri, prezzi pagati protetti, ritiro unico, supplementi per sostituzioni, rimborsi ai pagatori effettivi | Regali, uscita, scadenza, doppio webhook, differenze di prezzo, saldo e lease QR |
| Pagamenti e rimborsi | Stripe Connect TEST per ITSOS Marie Curie attivato e collegato; Checkout individuale/gruppi, webhook firmati e dispatcher rimborsi; richiesta rimborso per Admin scuola/Barista direttamente dall'ordine, senza UUID; restituzioni cash/POS separate con turno cassa, motivazione e conferma | Merchant `charges_enabled=true`, `card_payments=active`, requisiti zero; test di codice, PostgreSQL e multibrowser superati su PR #58. Mancano acquisto con carta di test, riconciliazione webhook, rimborso Stripe e prova fisica della restituzione contanti/POS |
| Promozioni | Coupon percentuali/unitari, bundle con quantità esatte, quote globali/per cliente, prezzi calcolati sul server e applicazione ai gruppi prima dei pagamenti | Prezzi, retry, quote e riconvalida del bundle a conferma/checkout |
| Offline | PIN/cifratura, sequenza causale, tablet condiviso con operatori distinti, limite complessivo 8 ore, manifest odierno individuali/gruppi, contanti residui, revoca e quarantena | Manifest vincolato al server/dispositivo/generazione; doppio incasso rimborsa soltanto i pagamenti successivi al manifest |
| Cassa e chiusure | Turni, conta motivata, chiusura immutabile, rettifiche Admin, chiusure straordinarie e rimborsi, no-show a chiusura senza riciclo delle scorte | Riattivare il bar non resuscita ordini; eventuale penalità riguarda cliente registrato/coordinatore, mai ospite o altri membri |
| Assistenza | Ticket personali e condivisi di gruppo, commenti dei membri, riapertura soggetta ad Admin, immagini private JPG/PNG/WebP | Coordinatore escluso dai ticket/ricevute personali altrui; RLS anche per messaggi e allegati |
| Comunicazioni e report | Push/in-app, preferenze, cron ogni minuto, promemoria ritiro/chiusura, annunci, rendiconti e CSV/XLSX/PDF | Destinatari, backoff, rimborsi elaborati/pendenti e contanti da restituire distinti; ricevute interne separate dai documenti fiscali |
| Backup | Job giornaliero, export PostgreSQL 17, AES-256, archivio esterno al database, verifica e restore su target vuoto | **Primo backup reale riuscito** su GitHub il 03/11 (run #41654538860); **restore SQL manuale riuscito** in Docker con PostgreSQL Supabase 17 e conteggi/RLS verificati. Mancano copia dei byte Storage, prova di ripristino completa dei servizi e conferma del job schedulato successivo |

## Gate di rilascio Stripe e Storage — 3 novembre 2026

- Il progetto BreakApp ha attualmente **0 payment_attempts, 0 payment_refunds e 0 eventi** nella inbox del webhook: il test Stripe Checkout → webhook → rimborso rimane obbligatorio.
- L'account Stripe accessibile al connettore durante l'audit è `acct_1UMbXXCs978fOWHz`, con **zero merchant Connect**; non coincide con l'account merchant scolastico configurato in BreakApp (`acct_1UVx5F2RLtxMJCNo`). Non operare sull'account sbagliato.
- Aggiunti `scripts/check-stripe-readiness.mjs`, workflow manuale `Stripe TEST Connect readiness` e prove automatiche di riconoscimento di account Connect e webhook specifici: il workflow richiede una **chiave TEST di sola lettura** della piattaforma Stripe proprietaria del merchant. Vedere `docs/STRIPE_SANDBOX_RELEASE_GATE.md`.
- `storage.objects` conta **0 oggetti** nei due bucket attuali (`breakapp-product-images`, `breakapp-ticket-images`). Non ci sono file binari caricati da salvare oggi; prima del caricamento di allegati reali occorre automatizzare il backup cifrato dei byte Storage e provarne il recupero.

## Implementazione del dossier UX — 3 novembre 2026

L'analisi esterna del 30 ottobre individua debiti di design, operatività e conformità. Questo incremento realizza interventi senza modificare le 171 decisioni funzionali confermate:

| Area | Intervento | Stato e verifica |
| --- | --- | --- |
| Banco Barista | Ordini individuali in colonne per stato, filtro per fascia, ricerca anche per prodotto, elenco aggregato dei pezzi da preparare, archivio degli ordini conclusi con rimborso | Codice in PR #60; integrazione reale e test di flusso ancora da completare sul dispositivo del bar |
| Aggiornamento ordini | Tabella `orders` aggiunta alla publication Supabase Realtime con RLS esistenti, sottoscrizioni per scuola e aggiornamento di riserva ogni 15 secondi | Migrazione applicata e verificata su progetto di test; verificare riconnessioni su reti scolastiche reali |
| Menu cliente | Card mobile compatte, pulsante rapido + su carrello reale, foto/fallback, etichette allergeni, filtro dei prodotti con allergene dichiarato e avvertenza | L'assenza di un allergene dichiarato **non** implica sicurezza per allergici; serve responsabilità e validazione del gestore |
| Prenotazioni | Due passaggi effettivi (fascia di ritiro, riepilogo), coupon etichettato e trasparenza sulla richiesta GPS | Resta obbligatoria la stessa verifica lato server; nessuna modifica alle regole di prossimità |
| Design e navigazione | Eliminato il reset globale della classe `.pilot-card`, tokens tema chiaro/scuro, icona intestazione, stati italiani, navigazione Admin raggruppata e conferme staff in dialog | Nessun brand o logo definitivo approvato; mantenuto nome temporaneo per compatibilità |

**Non ancora implementato / richiede decisione o consulenza:** verifica UIBM/EUIPO ed eventuale rebranding; trattamento fiscale dei corrispettivi e integrazione registratore telematico; informativa privacy minori, geolocalizzazione e DPIA se necessaria; gestione genitori; borsellino prepagato e relativi obblighi PSD2; consegna in classe; pacchetto sugli store; report sprechi; test su iPhone/Android e prova Stripe completa pagamento-webhook-rimborso.

Il dossier è una revisione esterna, **non** una modifica automatica dei requisiti già confermati.

## Attivazioni e collaudi esterni

1. **Stripe — merchant TEST attivato, collaudo end-to-end ancora necessario:** il nuovo merchant sandbox `acct_1UVx5F2RLtxMJCNo` è collegato a ITSOS Marie Curie, con `charges_enabled=true`, `payouts_enabled=true`, `card_payments=active`, requisiti mancanti zero (verifica Stripe del 30 ottobre). Il vecchio account di test non è stato cancellato; non esistono tentativi di pagamento pregressi da trasferire al momento del cambio. Checkout, webhook firmati, rimborsi e CORS delle Edge Functions sono predisposti in TEST. Non risultano ancora prove end-to-end di incasso, riconciliazione webhook e rimborso su un ordine BreakApp: non dichiarare conclusa questa verifica né confondere il merchant sandbox con l'abilitazione live.
2. **OAuth — completato per il sito di test:** Google e Microsoft configurati e verificati manualmente con ritorno autenticato su BreakApp il 29 ottobre.
3. **Backup operativo:** `SUPABASE_BACKUP_DB_URL` e `BACKUP_PASSPHRASE` nei segreti GitHub; prova di ripristino del servizio in un progetto separato, comprese configurazioni e file Storage.
4. **Pilota:** telefoni Android/iPhone fisici, stampante/dispositivo fiscale esterno, revoca di dispositivi realmente disconnessi, recupero dopo perdita/reinstallazione, procedure privacy e responsabilità del gestore.
5. **Hosting definitivo:** il sito di test è GitHub Pages; anteprima Vercel e compatibilità Cloudflare restano distinte dalla promozione manuale in produzione.

Queste attivazioni non richiedono di riscrivere i moduli applicativi elencati sopra. La vendita richiede il completamento del collaudo operativo e degli adempimenti del gestore.
