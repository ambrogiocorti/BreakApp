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
