# 001 — Invio schedulato e preferenze personali

Stato: adottato il 27 ottobre 2026.

## Contesto

L'estensione pg_net memorizza gli header delle richieste nella coda. I permessi delle funzioni di trasporto appartengono al provider e non possono essere ristretti dal ruolo del progetto. Un semplice esito positivo di pg_cron non attesta l'esito HTTP del dispatcher. Inoltre, cancellare una sottoscrizione con consegne archiviate incontra i vincoli che proteggono lo storico.

## Decisione

Usare l'estensione HTTP sincrona per chiamare esclusivamente le due funzioni del progetto configurato in Vault, con token risolto durante l'esecuzione. Conservare in una tabella privata solo destinazione ammessa, status HTTP, durata e codice d'errore generico. Serializzare le invocazioni del cron, mantenere indipendenti gli esiti e ruotare il token precedente.

Conservare preferenze personali RLS e API senza parametro user_id. Applicarle sia all'accodamento sia alla selezione delle consegne. Gli avvisi in-app rimangono il registro persistente. Revocare logicamente un endpoint di proprietà senza cancellare lo storico. Consegnare payload di sistema generici per limitare l'esposizione su schermi condivisi.

Generare promemoria tramite una RPC esclusivamente backend e chiavi univoche. L'orologio è del server; l'iniezione del tempo è ammessa soltanto nella funzione privata usata dai test. I destinatari di gruppo seguono i ruoli e il saldo corrente; nessun token QR o dettaglio di altri pagatori entra nel messaggio.

## Conseguenze

I timeout HTTP predefiniti dell'hosting non sono modificabili dal ruolo corrente. Le consegne vengono quindi limitate per batch e inviate in parallelo con timeout del provider. Un errore di rete può richiedere il replay del lavoro dopo il lease; l'assenza di ricezione non prova l'assenza dell'evento. Il pilota deve misurare volumi e ritardi reali su Android e iOS.

La disattivazione non può richiamare un invio già affidato a un provider. La priorità del token Vault rende atomica la rotazione per i servizi schedulati; un eventuale fallback manuale deve ricevere separatamente il token aggiornato tramite il gestore dei segreti.
