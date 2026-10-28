# Interfaccia di lavoro — 28 ottobre 2026

Il Super Admin dispone di una panoramica dedicata, una directory delle scuole con ricerca per scuola o bar e filtro per stato, una configurazione a schede e una pagina separata per creare scuole. Le operazioni esistenti conservano i rispettivi controlli server e la verifica AAL2.

La navigazione condivisa usa icone SVG, sidebar desktop, barra compatta, titoli univoci e navigazione inferiore su telefono e tablet. Il contenuto scorre indipendentemente dalle barre. Le schede di configurazione supportano frecce, Home ed End e mantengono i valori inseriti quando si cambia scheda. I temi e la preferenza di movimento ridotto sono rispettati.

La directory carica pagine complete dal server; gli indicatori distinguono scuole abilitate, sospese e bar attivi nelle scuole abilitate. La percentuale mostrata rappresenta scuole abilitate sul totale, non la disponibilità operativa del servizio. In caso di errore i dati precedenti vengono rimossi. Sospensione e riattivazione richiedono una motivazione nella finestra dedicata.

La panoramica dell’Admin scuola mantiene un perimetro esplicito: ultimi 500 ordini individuali, catalogo, fasce configurate ed esportazione CSV esistente. Nessuna statistica di crescita o incasso viene inventata.

`tests/e2e/workspace.mjs` carica markup e controller effettivi con API isolate e verifica desktop, tablet e telefono su Chromium, Firefox e WebKit. Copre ricerca, filtri, cambi di stato, selezione della scuola, schede da tastiera, temi, errore e recupero, cambio ruolo e logout con richieste ancora pendenti. I dati di test non entrano nel pacchetto pubblicato.
