# BreakApp — Desktop Workspace con navigazione RBAC (release UI v2)

## Problema risolto

La versione precedente rendeva tutte le sezioni nella stessa pagina in verticale: login, catalogo, ordini, Admin, magazzino e assistenza. Il menu desktop era un pannello piccolo e identico per ogni ruolo. Questo non è un gestionale usabile.

## Nuova architettura

- **Desktop ≥1024 px**: sidebar fissa a sinistra per tutta l'altezza, con logo, contesto attivo, sezioni autorizzate e logout. Barra superiore con titolo e ruolo. Area di lavoro indipendente, in cui viene visualizzata una sola schermata per volta.
- **Tablet e mobile**: navigazione inferiore per il ruolo attivo, massimo tre sezioni principali più pulsante «Altro» quando sono disponibili più destinazioni. Nel Profilo è presente il selettore scuola/ruolo; su desktop è anche nella sidebar.
- **Routing**: hash URL `#menu`, `#orders`, `#admin-overview`, ecc. consente deep-link e navigazione Indietro; la funzione di routing non sblocca componenti ancora nascosti dai loro controller.
- **Ultimo contesto**: la preferenza locale salva soltanto la chiave di una scelta validata dal server. Ad ogni login il contesto è ricostruito da membership Supabase e dalle scuole attive, con verifica AAL2 per Admin/Super Admin.
- **Isolamento**: CSS/navigazione non sono una barriera di sicurezza. RLS, funzioni RPC e permessi Supabase continuano a controllare ogni accesso e modifica.

## Navigazione per ruolo

| Ruolo | Voci effettivamente navigabili |
|---|---|
| Cliente | Menu, I miei ordini, Gruppi (bozze), Profilo (assistenza raggiungibile da Profilo/ordine) |
| Barista | Ordini da preparare, Servizio e orari, Assistenza, Profilo |
| Magazziniere | Scorte giornaliere, Profilo |
| Admin scuola (AAL2) | Panoramica, Gestione ordini, Catalogo, Magazzino, Impostazioni bar, Calendario, Centro ticket, Profilo |
| Super Admin (AAL2) | Piattaforma, Profilo |

Non vengono create pagine finte per Stripe, conferma/pagamenti di gruppo, gestione globale scuole, cassa/offline e notifiche: sono ancora requisiti del Prompt Master non completati.

## Funzionalità reali aggiunte

- **Dashboard Admin**: letture dei dati di ordini, prodotti, fasce e pause della scuola corrente tramite RLS; importi in centesimi. Limite trasparente dei primi 500 ordini per non presentare le metriche come rendiconto fiscale.
- **Magazziniere**: scelta bar e giorno, lettura reale stock e prodotti, modifica della capacità consentita dalla policy magazziniere; limite inferiore alle unità già allocate; disponibilità illimitata specifica.
- **Super Admin**: attestazione del proprio ruolo dal backend, presenza del pannello globale soltanto con `aal2`; directory reale di scuole/bar. Le operazioni di configurazione globale non sono simulate.
- **Cambio ruolo**: se uno stesso utente è Cliente in una scuola e Barista/Admin/Magazziniere in un'altra, l'interfaccia si adatta alla scelta, senza attribuire ruoli nuovi.

## Limitazioni e QA

- Attendere un collaudo visivo con sessioni reali di Cliente, Barista, Magazziniere, Admin e Super Admin. I test di build non dimostrano la corretta usabilità su tutti i device.
- Non è ancora completo il design di Kanban/realtime Barista, né quello del centro dati Admin avanzato.
- Il modulo Magazzino ora modifica la capacità per data; storico riconciliazione/giustificativi, movimentazioni fisiche e operazioni offline richiedono incrementi backend dedicati.
- Il modulo Super Admin mostra informazioni pubblicamente esposte dal modello di scuole/bar, filtrate da ruolo e RLS. Non esiste ancora CRUD globale delegabile da questa UI.
- I moduli esistenti possono ancora avere proprie sotto-schermate e form lunghi; il layout globale non li impila più tutti in una pagina.
- Gli utenti potranno selezionare un contesto Admin prima del completamento AAL2 ma vedranno esclusivamente Profilo/2FA. Nessun privilegio di scrittura viene concesso dal browser.

## Verifiche automatiche

- `tests/unit/role-workspace.test.mjs`: matrice ruolo-vista e contesto autenticato;
- `tests/unit/workspace-layout.test.mjs`: layout e navigazione;
- `tests/db/workspace-role.sql`: ruolo globale e AAL2;
- CI Vite e test regressioni catalogo, ordini, prenotazioni e assistenza.

La migrazione `10_workspace_platform_identity.sql` riguarda solo le attestazioni server del ruolo Super Admin e non sposta né cancella dati.
