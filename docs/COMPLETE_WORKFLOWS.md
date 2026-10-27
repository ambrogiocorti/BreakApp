# Flussi completi: uso e verifiche

## Cliente e coordinatore

Da **Richieste e gestione ordini** si seguono approvazioni, modifiche, sostituzioni, nuovi orari e contanti da ricevere. Le proposte riportano ingredienti e allergeni. Solo il titolare dell'ordine o il coordinatore può decidere. Rifiutare una sostituzione rimuove la riga e avvia il credito dovuto; non rispondere entro il ritiro ha lo stesso effetto. Un ritardo senza risposta conserva la fascia originale.

Una modifica automatica protegge l'ordine precedente fino alla riuscita della transazione. Se l'ordine è in preparazione attiva, oppure la modifica aumenta il carrello sopra le soglie, decide il Barista. Un aumento su ordine già pagato richiede solo il saldo aggiuntivo; una diminuzione genera rimborsi sui pagamenti originali. I checkout in corso devono prima ricevere un esito firmato.

Il coupon individuale si inserisce alla conferma. Il coordinatore applica il coupon al gruppo prima che inizi qualsiasi pagamento. Il bundle richiede multipli esatti delle quantità definite per i componenti scontati; gli altri prodotti conservano il listino. Quota globale/per cliente e prezzi sono verificati sul server. Le quote di una bozza attiva sono impegnate; cancellazione/scadenza libera l'utilizzo. I prezzi delle righe già pagate restano protetti.

Dal menu si salvano i preferiti; nello storico si può riordinare con prezzi e disponibilità attuali e nuova conferma GPS.

## Barista e Admin

Il Barista seleziona il bar e attiva **Sono in servizio e disponibile per le approvazioni**. La presenza scade dopo due minuti senza heartbeat. Una coda non attiva non riserva scorte; l'attivazione riserva per dieci minuti. L'Admin configura il numero massimo di richieste attive. La priorità segue fascia di ritiro, creazione e ID. Scadenza dell'ultima fascia: il cliente dispone di due ore per scegliere; altrimenti annullamento e rimborso.

Le sostituzioni e i ritardi si propongono nella stessa schermata. Nei gruppi i membri sono informati e decide il coordinatore. Per una differenza positiva su riga pagata viene creato un supplemento intero, pagabile da qualsiasi membro online prima della scansione. Al bancone il residuo rimane del coordinatore. Per una riga saldata in contanti, il credito diventa un obbligo di restituzione fisica.

L'Admin può chiedere il rimborso di un ordine concluso: il sistema ripartisce gli importi sui pagatori originali. Un credito cash non risulta restituito finché il personale non registra il movimento fisico con turno aperto e motivazione. I rendiconti distinguono richiesta di rimborso, conferma Stripe e contanti restituiti.

Le chiusure straordinarie includono ordini individuali e gruppi, anche pagati, limitatamente all'intervallo scelto. La riapertura non ripristina gli ordini annullati. Alla chiusura giornaliera il cron registra i mancati ritiri, avvia i rimborsi e non rimette prodotti deperibili in magazzino. La penalità è disabilitata per default e configurabile dall'Admin in minuti; interessa soltanto il cliente registrato o il coordinatore. Eventi di consegna offline già in verifica sospendono la decisione automatica.

## Scorte insufficienti

Il Magazziniere può registrare una conta reale inferiore alle allocazioni, con motivazione. Il sistema mantiene il dato fisico e lo storico; i normali aggiornamenti non possono eludere il vincolo. Le vendite offline già avvenute vengono contabilizzate. La disponibilità è assegnata prima ai ritiri più vicini e, a parità, agli ordini più vecchi.

Per una riga confermata scoperta si apre una proposta di rimozione; il Barista può sostituirla con un'alternativa esplicita. Il cliente accetta oppure riceve il credito dovuto. La riga coinvolta è gestita interamente per evitare consegne implicite parziali. Una richiesta grande ancora non approvata può essere rifiutata per mancanza di scorte. Il prodotto/giorno torna prenotabile quando capacità e allocazioni lo consentono; gli altri prodotti/giorni continuano a funzionare.

## Ospiti e nuove scuole

L'ospite inserisce nome, scuola e classe; il servizio crea un'identità Supabase e restituisce una sola volta il link privato con token casuale di 256 bit. Sul database rimane l'hash. Il link scade dopo 30 giorni; nel browser viene rimosso dall'indirizzo appena acquisito. L'email opzionale va verificata prima del recupero. Il link privato non è l'invito al gruppo. L'ospite può partecipare e pagare ma non creare/coordinare un gruppo o ricevere incarichi del personale.

Il Super Admin con 2FA crea scuola, primo bar e primo Admin già registrato con email verificata. Il bar nasce con prenotazioni sospese: l'Admin completa menu, orari, fasce, scorte e configurazione del merchant, poi apre il servizio. L'Admin può richiedere agli ospiti una delle classi importate. Il servizio limita i tentativi per origine e globalmente (300/minuto e 1000/giorno). Classi CSV/XLSX: prima colonna, massimo 2 MB e 1000 nomi; nessuna valutazione di formule o macro. Le scuole si possono sospendere/riattivare senza cancellare lo storico.

## Tablet condiviso e offline

Ogni Barista configura online sul tablet il proprio account, dispositivo e PIN. Offline sceglie un operatore già configurato e sblocca esclusivamente il relativo archivio cifrato. Cambiare operatore non riavvia le otto ore. La sincronizzazione richiede l'autenticazione online dello stesso operatore. Cassa, catalogo, manifest e coda restano separati per identità/scuola.

Il manifest contiene solo ordini pronti del giorno e il residuo al momento della copia. Il server conserva snapshot, generazione e pagamenti già presenti. La consegna richiede QR corrispondente e, nella modalità già pronto, attesa della fascia. Il gruppo viene consegnato interamente al coordinatore. Al sync, il contante effettivamente ricevuto rimane nel ledger; l'eccedenza Stripe è rimborsata solo ai pagatori dei pagamenti arrivati dopo lo snapshot. Ambiguità, revoca o dati discordanti restano in quarantena e nella coda locale fino a decisione e contabilizzazione Admin.

Un browser non garantisce recupero dopo cancellazione dei dati, perdita o danno del tablet. Prima di logout o cambio dispositivo verificare la coda; le prove fisiche di perdita/reinstallazione appartengono al pilota.

## Assistenza e privacy

Nel centro assistenza si può associare un gruppo e scegliere conversazione condivisa o privata. I riferimenti a prodotti e pagamenti sono disponibili solo nel ticket privato e verificati contro il titolare sul server. Un coordinatore non ottiene accesso alle ricevute o ai ticket personali degli altri. Tutti i membri accettati possono commentare i ticket condivisi e chiedere riapertura; l'Admin decide risoluzione e riapertura. Le stesse RLS si applicano a messaggi, cronologia e fotografie private JPG/PNG/WebP, massimo 4 MB.

## Distribuzione e verifiche

Le sei migrazioni `20261027214803`..`20261027222100` si applicano dopo la baseline e gli incrementi precedenti. Non rieseguire file già registrati nel progetto. Il connettore può assegnare un timestamp remoto differente: riconciliare la cronologia prima di usare `supabase db push`.

Distribuire `guest-access`, `push-dispatch` e `stripe-full-refund`. Queste Edge Functions gestiscono internamente l'autenticazione prevista dal rispettivo ingresso; il dispatcher verifica il token Vault, il rimborso verifica la sessione e il guest endpoint scambia un link privato con una sessione verificata. Il cron esistente richiama manutenzione approvazioni, proposte e chiusure prima degli invii push.

`npm run verify` controlla sintassi, unit test e build. `complete-workflows.sql` esercita transazioni, ruoli, scorte, differenze, veri riferimenti ai pagatori, coupon, ospiti, onboarding, ticket/RLS, no-show e sovrapposizione contanti/Stripe in un database isolato. I test Playwright importano i moduli ES reali con API fixture, su Chromium, Firefox e WebKit desktop/mobile. La suite PostgreSQL 17 comprende anche la concorrenza sull'ultima unità e il ripristino dei backup cifrati.

La conferma di un pagamento esterno resta dipendente dal webhook Stripe firmato. Le conferme interne e i report non sostituiscono un documento fiscale.
