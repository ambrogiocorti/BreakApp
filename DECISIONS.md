# Decisioni tecniche

## Requisiti conservati

Frontend vanilla, tenant isolation, autorizzazioni server, TOTP Admin, denaro in centesimi, rimborso al pagatore originale, un dispositivo offline per Barista, autonomia massima otto ore, blocco dopo cinque minuti di inattività e cinque minuti dopo cinque PIN errati. Nessuna attivazione fittizia di Stripe.

## 27 ottobre 2026

- Scelta implementativa: un turno aperto per bar; il passaggio richiede il conteggio del precedente. Incassi senza turno restano espliciti. Più casse fisiche nello stesso bar richiederanno una risorsa cassa dedicata.
- Conteggio confermato immutabile; rettifiche come nuovi movimenti Admin con 2FA e motivazione.
- Eventi offline cifrati con sequenza IndexedDB atomica. Una revisione non contabilizzata conserva i dati anche sul dispositivo.
- Cronologia delle generazioni dei dispositivi per attribuire la scuola originale ai dati pendenti; revoca senza cancellazione dell'attività fisica.
- VAPID e token del cron in Supabase Vault. Recupero segreti solo backend; cron ospitato ogni minuto, nessun segreto nel repository/frontend.
- Rimborso confermato dal webhook firmato. Retry limitati e distanziati; errori definitivi/esauriti segnalati ad Admin e pagatore.
- CSV neutralizza formule; XLSX conserva testo letterale e importi numerici. Report senza identità pagatori o token QR.
- Vercel resta anteprima; GitHub Pages sito di test già esistente; compatibilità Cloudflare mantenuta.
- Il cron usa HTTP sincrono con URL di progetto verificato: nessun token permanente nella coda pg_net. Audit privato di soli esito, durata e destinazione; conservazione 14 giorni. Token ruotato dopo la sostituzione.
- Le preferenze appartengono all'utente e filtrano le push per ordini, gruppi, assistenza e annunci; gli avvisi in-app rimangono persistenti. Disattivare un dispositivo conserva lo storico di consegna.
- Promemoria con chiavi univoche per ordine/fascia/destinatario; chiusura del gruppo notificata solo al coordinatore. Orari interpretati nel fuso della scuola, usando l'ultima chiusura giornaliera.

## Completamento dei flussi del 27 ottobre 2026

- Coda di approvazione e riserva sono separate: assenza del Barista non alloca scorte. Lease di dieci minuti, priorità di ritiro e risposta di due ore dopo l'ultima fascia.
- Modifiche atomiche con versioni, supplementi interi per gruppo e crediti attribuiti ai pagatori originali. Restituzioni cash fisiche registrate separatamente.
- Snapshot offline server con elenco privato dei pagamenti già presenti, per attribuire con certezza l'eccedenza online. Operatori condividono il tablet mantenendo PIN, archivio e coda distinti; le otto ore non ripartono.
- Conta fisica motivata anche sotto il prenotato; priorità di ritiro e sostituzioni sulle righe scoperte. Non si annullano indiscriminatamente gli ordini confermati.
- Ospiti identificati da tabella protetta; link privato casuale conservato solo come hash, scadenza proposta di 30 giorni. Identità ospite esclusa da coordinamento e incarichi.
- Coupon/bundle server-side con quote e ricontrollo delle quantità dopo le modifiche; mai applicazione retroattiva a righe già pagate.
- Ticket condivisi commentabili dai membri accettati; prodotti, pagamenti e ricevute personali restano riservati al rispettivo titolare.
- No-show automatici a chiusura senza rimettere prodotti in magazzino; penalità proposta disabilitata per default, mai applicata a ospiti o altri membri del gruppo.
- Backup PostgreSQL 17 cifrati prima dell'uscita dal runner. Restore rifiutato su target non vuoto; configurazione dei segreti e prova del servizio reale restano attivazioni del titolare.

- Il recupero email degli ospiti collega un'identità email verificata all'ID ospite originale; non trasferisce ordini, pagamenti o ruoli. Consenso esplicito nel profilo verificato, link privato ruotato al recupero e collegamento rimovibile. La sicurezza del cambio email degli account registrati resta invariata.

## 30 ottobre 2026 — Incassi e rimborsi

- Merchant Stripe Connect TEST associato alla scuola pilota dopo verifica diretta di capability attive. Nessuna modifica ai conti live e nessun passaggio di tentativi di pagamento preesistenti.
- Admin scuola (con 2FA) e Barista possono richiedere un rimborso individuale concluso dalla scheda ordine; l'UUID resta un riferimento tecnico non visibile all'operatore. Autorizzazioni e motivazione sono validate lato PostgreSQL.
- I pagamenti Stripe sono rimborsati ai pagatori effettivi e risultano completati soltanto dopo conferma del provider/webhook; contanti e POS esterno richiedono un'uscita fisica registrata con turno aperto, conferma e motivazione. Il software non esegue storni su POS esterni.
- L'elenco operativo mostra soltanto le restituzioni pendenti e applica controllo di scuola/ruolo; l'anonimo non può invocare la nuova RPC. Il collaudo E2E con carta di test, webhook e rimborso resta una verifica bloccante per la vendita.

## 6 novembre 2026 — Correzioni dal report di valutazione

- «Una scuola e un ruolo per account» è un vincolo del database: un'appartenenza per account e un ruolo per appartenenza (indici unici). Il Super Admin non ha appartenenze: agisce su tutte le scuole tramite `platform_admins`.
- La vecchia assegnazione del Super Admin e la creazione di una scuola passano dagli stessi controlli degli inviti; se il primo Admin non ha un account riceve un invito con codice. `school_assign_staff` è ritirata. Revocare l'ultimo ruolo rimuove anche l'appartenenza.
- Decisione di Ambrogio: lo studente ordina solo dal bar della propria scuola. La prima prenotazione o il primo gruppo lo collegano come cliente; ordini, gruppi e ingressi in altre scuole sono rifiutati dal database (anche per il personale). Uno studente collegato come cliente non può diventare personale con lo stesso account.
- GitHub Pages ignora `_headers`: la CSP è inserita in un tag `<meta>` durante la build. `frame-ancestors` e le altre intestazioni restano da applicare con un hosting che le supporti.
- Admin scuola: «Personale» e «Promozioni» hanno una voce di menu; limite delle richieste, mancati ritiri e classi sono in «Impostazioni scuola». «Richieste» resta per approvazioni, modifiche e rimborsi. Un selettore con una sola scuola non viene mostrato.
- Le migrazioni del repository hanno le stesse versioni dello storico Supabase (vedi `docs/SUPABASE_MIGRATIONS.md`).

## 7 novembre 2026 — Accesso ai gruppi e diagnosi pagamenti

- Modifica richiesta e confermata: per entrare in un gruppo con invito valido non serve essere fisicamente vicino alla scuola né autorizzare il GPS. Rimangono invariati i controlli di invito, scadenza, capienza, approvazione, sessione e ruoli.
- Il coordinatore deve verificare la propria posizione al momento della conferma definitiva dell'ordine di gruppo, con raggio e precisione verificati dalla RPC server; gli ordini individuali continuano a richiedere la posizione al momento dell'invio. Non si introduce una verifica GPS per il pagamento anticipato delle singole righe del gruppo.
- Compatibilità API: `join_group_draft` mantiene temporaneamente i cinque parametri esistenti, che diventano facoltativi nel comportamento e vengono inviati come `null` dai nuovi client. Nessuna modifica alla verifica di `confirm_group_order`.
- I checkout individuali e di gruppo leggono ora la motivazione restituita dalla Edge Function, quando disponibile, al posto del messaggio generico HTTP non-2xx. Non vengono stampati payload grezzi né credenziali.

## 8 novembre 2026 — Contesto scuola/ruolo e scuola DEMO

- Il contesto di lavoro deriva solo dalle appartenenze verificate dal database: un account legato a una scuola (personale o studente) riceve soltanto il contesto di quella scuola. Prima uno studente di una scuola poteva aprire l'area Cliente della scuola che compare per prima in ordine alfabetico (per esempio la DEMO), e un Admin riceveva contesti Cliente di altre scuole. Gli account non ancora legati a una scuola mantengono l'elenco delle scuole attive finché la prima prenotazione non li lega lato server.
- Nuova colonna `schools.is_demo` (sola lettura per i client). Nella scuola DEMO compare sempre l'avviso «Ambiente dimostrativo — pagamenti di prova, nessun addebito reale.».
- Causa dell'errore `Edge Function returned a non-2xx status code` nella DEMO: la scuola non ha un merchant Stripe TEST in `school_stripe_merchants`, quindi `begin_individual_stripe_checkout` rifiuta con «Merchant Stripe non abilitato» (HTTP 409). La correzione è l'attivazione Stripe TEST da parte dell'Admin della DEMO, con un account collegato separato; non si riutilizza il merchant di ITSOS Marie Curie.
- Lo stato del merchant scolastico (`charges_enabled`, `payouts_enabled`, `details_submitted`) si aggiorna dall'evento Connect firmato `account.updated` tramite la RPC `apply_signed_stripe_account_status`, riservata a `service_role`. La RPC aggiorna soltanto un account già associato a una scuola (non crea né sposta associazioni), ignora duplicati e snapshot più vecchi dell'ultimo applicato e traccia ogni cambio in `app_private.stripe_merchant_status_audit`. Prima questi valori si impostavano a mano. Perché funzioni, l'endpoint webhook TEST deve ascoltare anche `account.updated` per gli account collegati.
- Posizione della scuola: l'Admin con 2FA modificava già latitudine, longitudine e raggio. Si aggiungono l'indirizzo visualizzato (`schools.address`, RPC `set_school_address` con gli stessi controlli), il pulsante «Usa la posizione di questo dispositivo» (stessa soglia di precisione dei clienti) e un collegamento esterno a OpenStreetMap per controllare il punto. Ogni modifica a posizione e regole è tracciata da un trigger in `app_private.school_settings_audit`. Una mappa interattiva nella pagina non è inclusa: richiederebbe un fornitore di mappe e una modifica della CSP.

## 8 novembre 2026 — Tolleranza di precisione GPS per scuola

- Decisione di Ambrogio: la precisione GPS richiesta alla conferma non è più fissa a 100 m; la decide l'Admin di ogni scuola in «Posizione e regole» (da 10 a 1000 m, default 100 m). La DEMO è impostata a 1000 m.
- Il server la applica in `submit_individual_order` e `confirm_group_order`; resta invariato il controllo distanza + precisione entro il raggio della scuola. La modifica passa da `set_school_location_accuracy` (Admin della scuola con 2FA) ed è registrata nello storico delle impostazioni.

## 9 novembre 2026 — Banco del barista più rapido

- Richiesta di Ambrogio: niente rifacimento grafico generale; solo la schermata del barista deve essere più intuitiva e veloce.
- Ordine confermato: il pulsante principale è «Pronto» (un tocco); «In preparazione» resta come scelta secondaria.
- Ordine pronto da pagare al banco: «Incassa e consegna» con «Contanti» o «POS» e **una sola conferma** con l'importo reale. Il client esegue le stesse due chiamate di prima (registra l'incasso, poi la consegna); il server continua a rifiutare la consegna di un ordine non pagato. Stessa cosa nella finestra della scansione QR.
- Nella conferma il pulsante «Conferma» ha il focus: Invio o Spazio confermano. Nel campo di ricerca «numero + Invio» porta all'ordine e mette il focus sul suo pulsante principale.
- Nessuna regola di pagamento, consegna o scorte cambia.
