# BreakApp — Studio 02 / Design system

## Obiettivo

Ridisegnare l'intera PWA con un'identità editoriale riconoscibile e mantenere intatti gli schemi di autorizzazione, autenticazione, scorte, ordini, Stripe, Supabase e operazioni offline. Non e un mockup, ma la composizione grafica della vera applicazione.

## Linguaggio visivo

Studio 02 e un sistema Editorial Hospitality: estetica calda e contemporanea, rigore operativo, elementi chiaramente gerarchizzati.

- Identità: verde profondo #193a31; sidebar #18392f.
- Accento: terracotta #a6442f (circa 5.96:1 contro carta #fffefa).
- Piano dei contenuti: carta #f5f3ed; superfici #fffefa; confini #dde0d6.
- Testo: #192d27; descrizioni #64736e.
- Titoli editoriali (poster login, introduzioni): serif di sistema; resto interfaccia: sans di sistema.
- Icone: kit SVG gia nel repository; nessun font remoto o asset di terzi.
- Il marchio B. continua a essere un segnaposto; non viene imposto un logo definitivo.

## Struttura e sistemi

| Interfaccia | Nuova impaginazione | Stato funzionale |
| --- | --- | --- |
| Accesso | Layout asimmetrico con form e poster tipografico, non un'altra card blu | OAuth, email, MFA intatti |
| Navigazione desktop | Sidebar scura, gruppi e selettore contesto distinti | RBAC e route guard immutati |
| Navigazione mobile | Dock persistente e pannello Altre sezioni | Logica esistente intatta |
| Super Admin | Introduzione editoriale, metriche, tavola scuole, azioni | Dati server-side invariati |
| Admin scuola | Titolo gerarchico, lead giornata, ordini e stati | Stati/permessi invariati |
| Catalogo | Filtri ben separati, schede prodotto food-first, allergeni | Prezzi e disponibilita server-side invariati |
| Banco | Corsie di lavorazione, priorita visive, azioni di ritiro | Workflow reali invariati |
| Magazzino e form | Campi, righe e pannelli coerenti | CRUD/autorizzazioni invariati |

## Accessibilita e performance

- Interazione tramite tastiera e focus visibile; font nativi e nessuna nuova dipendenza.
- Tema chiaro/scuro/sistema con colori specifici per ciascuna modalita.
- Nessuna metrica inventata, grafico finto, banner promozionale o sfondo animato.
- Griglie che si riconfigurano sotto 1250, 1023, 950, 760 e 550 pixel.
- Rispetto di prefers-reduced-motion e target touch.
- UI sviluppata con CSS scritto ad hoc, senza React o component library.

## Artefatti modificati

- src/css/studio.css: nuovi token, shell, catalogo, dashboard e UI operative.
- src/js/main.js: importato Studio 02 dopo gli altri CSS.
- index.html: nuovo poster d'accesso e gerarchia delle due panoramiche.
- tests/unit/studio-visual-system.test.mjs: protezione dei selettori e dei flussi.

## Verifiche

CI: BreakApp checks e Multibrowser responsive smoke su tre motori browser.
Da validare su apparecchi reali: 320px, zoom 200%, screen reader, dashboard dense, light/dark/system, ruolo Cliente, Barista, Magazzino, Admin e Super Admin. Nessun controllo automatico certifica da solo il giudizio di un designer.

Il redesign non conferisce stato go-live a pagamenti, privacy, backup, fiscalita, hardware o isolamento multi-tenant che richiedano ancora collaudo reale. I requisiti funzionali precedentemente confermati restano vincolanti.
