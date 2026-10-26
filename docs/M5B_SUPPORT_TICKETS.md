# BreakApp — Centro assistenza e ticket personali

Riferimenti: Prompt Master v1 §10.1, decisione UX: Centro assistenza nel **Profilo**, non nella bottom-navigation.

## Funzionante lato codice e schema

- Ticket da Profilo o dal dettaglio dell'ordine, legati a scuola e opzionalmente a ordine/riga.
- Creazione e messaggi con RPC PostgreSQL; nessuna mutazione arbitraria alle tabelle via Data API.
- Visibilità per autore e Admin della **stessa scuola con 2FA verificata (AAL2)**; solo Admin può cambiare stato.
- Riapertura con motivazione, richiesta pendente e accettazione/rifiuto Admin; storico eventi.
- Allegati **solo JPG, PNG e WebP**, massimo 4 MiB, bucket privato `breakapp-ticket-images`, URL firmati validi per 120 secondi.
- Creazione idempotente via UUID, quota iniziale antiabuso 5 ticket/ora e massimo 20 attivi per account; 30 messaggi ogni 10 minuti.
- UI con elenco richieste, conversazione e allegati. I testi sono renderizzati tramite `textContent`, non HTML arbitrario.

## Limitazioni ancora aperte

1. **Ticket di gruppo**: finché gruppi, partecipanti e ledger non esistono, non inventare la visibilità e i diritti speciali dei gruppi. Il Prompt Master §10.1 rimane da implementare.
2. Mancano notifiche push e notifiche in-app alla risposta (l'utente aggiorna il ticket manualmente).
3. L'upload immagine avviene dopo il messaggio. In caso di errore nella registrazione dei metadati, il file può restare temporaneamente orfano: programmare job di retention/cleanup **solo con policy verificata**, senza eliminare prove dei ticket in uso.
4. Non è installato un sistema antivirus/scansione automatica dei file. I formati MIME consentiti mitigano parte del rischio, ma non certificano il contenuto.
5. Per assistenza sul pagamento di gruppo con pagatori terzi servono ACL per la riga effettivamente pagata; ora le richieste personali su ordini individuali usano l'owner dell'ordine.
6. Non sono ancora implementati SLA, distribuzione ai baristi né statistiche ticket.
7. L'implementazione va collaudata end-to-end con account reali di due scuole prima di dichiararla pronta per un pilota.

## Accettazione

- RLS: altri clienti e altre scuole non leggono ticket/messaggi/foto.
- AAL1: un Admin non vede ticket; AAL2: Admin vede e risponde ai ticket della scuola.
- Idempotenza di creazione e limiti antiabuso.
- Invio messaggio dopo ticket risolto bloccato; richiesta di riapertura e approvazione Admin.
- Bucket *non pubblico*, immagini consentite soltanto JPG/PNG/WebP; nessun PDF/video nei ticket.
- Interfaccia accessibile dal Profilo e da un ordine, **senza** aggiungere Assistenza alla barra inferiore.
