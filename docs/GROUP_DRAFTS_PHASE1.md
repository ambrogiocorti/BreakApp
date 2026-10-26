# BreakApp — Ordini di gruppo, incremento bozze (migrazione 14)

Il Prompt Master 5.1–5.3 prevede coordinatore solo registrato, partecipanti anche anonimi, ingresso con GPS, modalità invito pubblico o ad approvazione, carrelli individuali, progressi separati e **nessuna prenotazione di scorte durante la bozza**.

## Realizzato

- `create_group_draft`: idempotenza tramite `request_key`, limite gruppi attivi, validazione scuola, bar e fascia; Super Admin escluso dal ruolo Cliente.
- `join_group_draft`: controllo GPS con accuratezza ≤ 100 m e timestamp recente, distanza rispetto al raggio della scuola, controllo invito/limite di membri, un'unica verifica all'ingresso. Niente richiesta GPS per la modifica del carrello.
- Modalità partecipazione con approvazione o accesso diretto, `review_group_member` accessibile soltanto al coordinatore.
- `replace_group_personal_cart`: solo righe del proprio utente; prodotti del bar selezionato, prezzi correnti, nessuna riserva stock e nessun pagamento. Dopo «Ho finito» la modifica richiede riapertura.
- `group_draft_details`: coordinatore vede stato dei partecipanti; ciascun altro partecipante vede **solo il proprio** carrello e aggregati del gruppo, senza dettagli personali di altri.
- La bozza è non modificabile dopo 24h d'inattività; solo mutazioni significative aggiornano l'ultima attività. La scadenza cron automatica e il promemoria a -1h verranno collegati al dispatcher notifiche.
- UI Cliente «Gruppi»: crea, entra, GPS, copia invito, partecipazioni, approvazioni, carrello e «Ho finito». Sono operazioni RPC reali.

## Non ancora implementato / da non promettere

1. La conferma definitiva del coordinatore con GPS ripetuto, stock atomico e cutoff non è ancora operativa; non compare un pulsante fittizio.
2. Pagamenti online preventivi di righe proprie o altrui, ledger dei pagatori effettivi, refund/race/lock scan 10m sono assenti finché Stripe non sarà integrato.
3. Invito rigenerabile, sospensione accessi, trasferimento coordinatore, uscita partecipanti e scioglimento bozza richiedono altre RPC.
4. Nessuna consegna, QR di gruppo, fiscalità, notification push o cron attivi.
5. `group_cart_items` è volontariamente non esposto direttamente a PostgREST: solo RPC autorizzate e RLS default-deny.
6. Il GPS del browser non è prova antifrode assoluta.

La presenza della schermata **non significa che si possano ordinare o pagare prodotti di gruppo**. È una fase di preparazione salvata sul database, reale e testabile ma non ancora spendibile al bar.

## QA

`tests/db/group-drafts.sql` verifica idempotenza, GPS fuori raggio, approvazione, isolamento diretto delle tabelle, regole «Ho finito», aggregate privacy, scorte non allocate e impossibilità per Super Admin di creare gruppi.

Eseguire test E2E con due account distinti e un Barista sulla piattaforma GitHub Pages prima di esporre la funzione al pubblico.
