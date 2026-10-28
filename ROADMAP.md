# Stato della piattaforma

Aggiornato il 27 ottobre 2026. La specifica privata resta la fonte dei requisiti. Le verifiche automatiche usano database e pagamenti sintetici isolati; il servizio collegato è l'ambiente di sviluppo.

| Area | Implementazione | Verifica |
| --- | --- | --- |
| Account e scuole | RBAC per scuola, TOTP Admin/Super Admin con blocco di ulteriori Authenticator, registrazione senza conferma per il dominio esatto `admin.breakapp.it`, ospiti con link privato e recupero email verificata, import CSV/XLSX, creazione/sospensione/riattivazione scuole e assegnazione personale | RLS, ruoli, ospite non coordinatore, onboarding transazionale; flusso Google/Microsoft con PKCE implementato, attivazione soggetta alle credenziali OAuth dei provider |
| Catalogo e scorte | Prodotti, immagini, ingredienti/allergeni, scorte giornaliere, vendite, conta motivata anche sotto il prenotato, priorità di ritiro e sostituzioni | Ultima unità concorrente; isolamento prodotto/giorno; un ammanco non cancella arbitrariamente gli ordini confermati |
| Ordini | GPS, idempotenza, QR, preparazione/ritiro, preferiti, riordino, modifica atomica, sostituzioni e proposte di orario con consenso | Ordine originale preservato su errore, cutoff, allergeni, nessuno spostamento tacito |
| Grandi ordini | Coda senza stock, presenza Barista, limite attivazioni, riserva di 10 minuti, priorità fascia, nuova fascia o risposta entro 2 ore | Attivazione, scadenze, rifiuto, rilascio e rimborso; nessuna autoconferma sopra soglia |
| Gruppi e finanza | Inviti, coordinatore registrato, carrelli personali, pagamenti di righe anche per altri, prezzi pagati protetti, ritiro unico, supplementi per sostituzioni, rimborsi ai pagatori effettivi | Regali, uscita, scadenza, doppio webhook, differenze di prezzo, saldo e lease QR |
| Promozioni | Coupon percentuali/unitari, bundle con quantità esatte, quote globali/per cliente, prezzi calcolati sul server e applicazione ai gruppi prima dei pagamenti | Prezzi, retry, quote e riconvalida del bundle a conferma/checkout |
| Offline | PIN/cifratura, sequenza causale, tablet condiviso con operatori distinti, limite complessivo 8 ore, manifest odierno individuali/gruppi, contanti residui, revoca e quarantena | Manifest vincolato al server/dispositivo/generazione; doppio incasso rimborsa soltanto i pagamenti successivi al manifest |
| Cassa e chiusure | Turni, conta motivata, chiusura immutabile, rettifiche Admin, chiusure straordinarie e rimborsi, no-show a chiusura senza riciclo delle scorte | Riattivare il bar non resuscita ordini; eventuale penalità riguarda cliente registrato/coordinatore, mai ospite o altri membri |
| Assistenza | Ticket personali e condivisi di gruppo, commenti dei membri, riapertura soggetta ad Admin, immagini private JPG/PNG/WebP | Coordinatore escluso dai ticket/ricevute personali altrui; RLS anche per messaggi e allegati |
| Comunicazioni e report | Push/in-app, preferenze, cron ogni minuto, promemoria ritiro/chiusura, annunci, rendiconti e CSV/XLSX/PDF | Destinatari, backoff, rimborsi elaborati/pendenti e contanti da restituire distinti; ricevute interne separate dai documenti fiscali |
| Backup | Job giornaliero, export PostgreSQL 17, AES-256, archivio esterno al database, verifica e restore su target vuoto | CI esegue cifratura, decifratura, restore e controlli RLS/grant; il job reale richiede due segreti del titolare |

## Attivazioni e collaudi esterni

1. **Stripe:** merchant scolastico abilitato e `STRIPE_SECRET_KEY`/`STRIPE_WEBHOOK_SECRET`; quindi prova reale sandbox di pagamento e rimborso firmato. Non è stato simulato un incasso esterno riuscito.
2. **OAuth:** configurazione Google/Microsoft e URL di redirect del dominio effettivo.
3. **Backup operativo:** `SUPABASE_BACKUP_DB_URL` e `BACKUP_PASSPHRASE` nei segreti GitHub; prova di ripristino del servizio in un progetto separato, comprese configurazioni e file Storage.
4. **Pilota:** telefoni Android/iPhone fisici, stampante/dispositivo fiscale esterno, revoca di dispositivi realmente disconnessi, recupero dopo perdita/reinstallazione, procedure privacy e responsabilità del gestore.
5. **Hosting definitivo:** il sito di test è GitHub Pages; anteprima Vercel e compatibilità Cloudflare restano distinte dalla promozione manuale in produzione.

Queste attivazioni non richiedono di riscrivere i moduli applicativi elencati sopra. La vendita richiede il completamento del collaudo operativo e degli adempimenti del gestore.
