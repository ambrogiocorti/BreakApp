# BreakApp / Edition 03 — Service Desk

## Decisione di prodotto

**Edition 03 sostituisce Studio 02**. La revisione precedente modificava soprattutto token cromatici e le superfici, lasciando invariata la gerarchia visiva. Edition 03 cambia invece la struttura del documento HTML, la navigazione ES-modules, i componenti dinamici delle dashboard e l'organizzazione delle operazioni del bar.

Nessun dato fittizio o pagamento dimostrativo viene introdotto nella UI reale.

## Le sei differenze strutturali verificabili

1. **Shell desktop senza sidebar.** La navigazione persistente verticale sparisce. Al suo posto: masthead globale + barra orizzontale con ruolo/scuola selezionata e cinque destinazioni contestuali. I ruoli con più di cinque destinazioni aprono «Tutte le sezioni» tramite un elemento HTML details e un indice accessibile, riempito da JS soltanto con le route autorizzate. Le route server sono ancora verificate dai controller Supabase.
2. **Super Admin come control room.** Eliminati il banner decorativo, la fila standard di quattro card, il tavolino ridotto e il donut. Ora: intestazione tipografica, roster delle scuole con stato e link, barra percentuale di rete con conteggi reali e ledger numerico laterale. La directory completa conserva una vera tabella per la gestione dati.
3. **Admin scuola come centro operativo.** Invece delle quattro card sopra due box, ora sono presenti feed degli ordini e stato di produzione in un unico flusso, più indicatori numerici laterali. Valori caricati dalle query reali e documentata la finestra degli ultimi 500 ordini.
4. **Barista a due postazioni.** Un pannello contiene ricerca/QR/filtri/quantità da preparare; a fianco una vera coda per le comande. La coda resta divisa per stato, con gli stessi controlli e i medesimi ID. A schermi stretti le postazioni si impilano.
5. **Magazzino con filtro e registro separati.** Selezione bar/data e feedback sul lato, quantità e disponibilità sul lato; nessun cambiamento alle mutazioni dello stock e agli invarianti del database.
6. **Studente: mercato a due colonne.** Scuola, bar e ricerca sopra la pagina; a sinistra categorie e filtro allergeni esplicito, a destra un catalogo di prodotti con prezzo e aggiunta rapida. Su mobile i filtri diventano una rail orizzontale per non sacrificare spazio utile.

L'accesso passa da «card su poster decorativo» a «copertina tipografica + form». Sono rimossi cerchi e forme riempitive; la composizione è sorretta da testo, proporzioni e righe editoriali.

## Linguaggio visivo

- Ink: `#202522`; card/utility `#fdfcf8`; canvas `#f1f0eb`.
- Accento vermiglione: `#bc422d`, limitato a segnalazioni ed elementi attivi.
- Niente pill e ombre casuali: bordi netti, righe, contrasti intenzionali.
- Sans di sistema per i controlli; display serif solo dove ha senso editoriale.
- Una sintassi di spaziatura condivisa, non griglie identiche in ogni area.
- Contrasto e tema scuro gestiti con variabili distinte.
- L'icona B resta **provvisoria**; la creazione di un marchio finale richiede una fase dedicata.

## Modifiche software

- `index.html`: ricostruzione semantica delle panoramiche, catalogo, login e interfacce Barista/Magazzino.
- `src/js/features/shell/workspace.js`: gruppo primario orizzontale + indice completo, senza promuovere permessi.
- `src/js/features/shell/platform-dashboard.js`: roster reale e progress bar numerica al posto dell'SVG circolare.
- `src/css/service-desk.css`: nuovo layout cross-role, mobile, dark e focus.
- `src/js/main.js`: nuovo CSS caricato dopo i fogli storici.
- `tests/e2e/workspace-fixture.mjs`, `tests/e2e/auth.mjs` e `tests/e2e/workspace.mjs`: verifica su CSS effettivo, geometria e navigazione.
- `tests/unit/studio-visual-system.test.mjs` e `tests/unit/dossier-ux.test.mjs`: protezione degli hook e regressioni.
- Manifest, icona PWA e versione cache SW aggiornati senza cambiare funzioni finanziarie.

## Criteri di accettazione

- [ ] BreakApp checks: sintassi, test JavaScript, build, SQL e backup fixtures verdi.
- [ ] Chromium/Firefox/WebKit: visualizzazione login e tutte le route testate su desktop, tablet e telefono simulati.
- [ ] Layout: nessun overflow orizzontale, shell desktop estesa tutta la viewport, controllo reale della rete nel pannello.
- [ ] Sessione AAL2 / MFA / ruoli: stessa capacità di negare sezioni prima e dopo.
- [ ] Verifica manuale di tutte le dashboard con **dati realistici**, casi con centinaia di ordini, temi e zoom al 200%.
- [ ] Revisione con designer e stakeholder prima del rilascio definitivo.

Le verifiche browser automatiche non dimostrano la qualità estetica professionale e non sostituiscono test fisici su device. Pagamenti Stripe TEST, backup, restore e altri gate di vendita rimangono separati.

## Rollback

Tutte le modifiche sono contenute nella PR di Edition 03. Una regressione di layout si risolve tornando al commit precedente a questo merge; il database e le Edge Functions non vengono migrati.
