# BreakApp — Registro decisioni UX/UI

**Aggiornamento:** 2026-10-25. **Stato:** 66/66 decisioni confermate dal committente.
Questo registro contiene SOLO decisioni di interfaccia emerse dal questionario. Il **Prompt Master v1** rimane prevalente per requisiti, sicurezza, permessi, pagamenti, scorte e offline. La repository e' pubblica: non committare qui segreti o dati personali. Una preferenza UI non autorizza nuove regole di business.

| # | Ambito | Scelta | Decisione confermata |
|---:|---|:---:|---|
| 1 | Accesso | B | Login split-screen desktop; su mobile solo modulo; nessuna landing iniziale |
| 2 | Studente | A | Apertura direttamente sul catalogo dopo accesso |
| 3 | Navigazione mobile | A | Barra inferiore nelle schermate principali |
| 4 | Catalogo | C | Categorie in alto e schede prodotto fotografiche |
| 5 | Dettaglio prodotto | A | Pannello dal basso con ingredienti, allergeni, prezzo e quantita' |
| 6 | Carrello | A | Barra blu contestuale, visibile quando non vuoto |
| 7 | Checkout individuale | B | Quattro passaggi: carrello, ritiro, pagamento, riepilogo |
| 8 | Ordine cliente | C | Biglietto digitale + tracciamento stato; QR secondo condizioni |
| 9 | Home barista | B | Dashboard operativa con ordini e azioni rapide |
| 10 | Ordini barista | B | Elenco compatto ordinato per priorita', con ricerca e filtri |
| 11 | Vendita al banco | C | Prodotti a sinistra e carrello a destra su tablet/desktop |
| 12 | Dashboard Admin scuola | C | KPI, avvisi, azioni rapide e navigazione laterale |
| 13 | Menu Admin scuola | B | Navigazione laterale organizzata in aree espandibili |
| 14 | Magazzino | C | Tabella filtrabile, data scorte, avvisi, movimenti e rettifiche |
| 15 | Super Admin | C | Centro di controllo globale con selettore contesto scuola |
| 16 | Stile generale | B | Moderno ed elegante, bianco/nero/blu, ombre leggere |
| 17 | Tipo logo | C | Identita' visiva ispirata al bar scolastico |
| 18 | Simbolo logo | D | Simbolo originale che combina pausa e cibo; approvazione finale necessaria |
| 19 | Selezione scuola | A | Ricerca + geolocalizzazione consensuale + scuole recenti |
| 20 | Scelta ritiro | C | Giorni suggeriti, calendario completo e schede fasce disponibili |
| 21 | Notifiche | C | Campanella, pannello rapido, cronologia e avvisi contestuali |
| 22 | Studente desktop | B | Navigazione laterale; su smartphone resta barra inferiore |
| 23 | Offline barista | A | Indicatore discreto nella barra superiore; dettagli su tocco, allarmi critici evidenti |
| 24 | Scuola e ruolo | B | Ultimo contesto valido e cambio dal profilo; MFA Admin invariata |
| 25 | Dettaglio ordine barista | C | Pagina dedicata con dettagli e azioni |
| 26 | Scanner QR barista | C | Fotocamera, ricerca manuale e anteprima ordine integrati |
| 27 | Chiusura cassa | A | Procedura guidata: riepilogo, conteggio, differenze, conferma |
| 28 | Home coordinatore gruppo | B | Dashboard di gruppo con riepiloghi e sezioni espandibili |
| 29 | Home partecipante gruppo | B | Schede "Il mio ordine" e "Il gruppo" |
| 30 | Pagamenti di gruppo | B | Pagina dedicata: propri articoli e articoli di altri; pagamento per righe intere |
| 31 | Conferma gruppo | A | Riepilogo completo prima della conferma esplicita |
| 32 | Gestione inviti | C | Pannello rapido dal basso, link e accesso a gestione partecipanti |
| 33 | Ingresso con invito | A | Benvenuto e verifica geolocalizzazione obbligatoria all'ingresso |
| 34 | Attesa ingresso gruppo | B | Anteprima gruppo con stato di approvazione e accesso riservato bloccato |
| 35 | Approvazioni partecipanti | C | Pannello rapido dal basso per coordinatore |
| 36 | Avanzamento partecipanti | B | Barra progresso "Ho finito" + elenco dettagliato |
| 37 | Modifiche ordine individuale | B | Carrello di modifica, catalogo, confronto economico prima di confermare |
| 38 | Sostituzioni | C | Avviso espandibile nel dettaglio ordine, con ingredienti/allergeni |
| 39 | Ritardi | A | Avviso e tre azioni nel dettaglio ordine |
| 40 | Assistenza | C | Ticket da dettaglio ordine e centro ticket nel Profilo; **mai nel menu inferiore** |
| 41 | Profilo | B | Sezioni Account, BreakApp, Supporto e Sessione |
| 42 | Bottom-nav studente | A | Menu, Ordini, Gruppi, Profilo |
| 43 | Pagina Gruppi | B | Schede Attivi e Conclusi, ruolo indicato |
| 44 | Creazione gruppo | A | Tre passaggi: info, ritiro, partecipazione |
| 45 | Dopo creazione gruppo | B | Apri subito pannello inviti; chiusura porta alla dashboard |
| 46 | Aggiunta prodotti gruppo | A | Catalogo normale in modalita' gruppo, contesto sempre visibile |
| 47 | "Ho finito" | B | Riepilogo e conferma; riapertura finche' consentita |
| 48 | Ritiro gruppo | C | Pagina dedicata; QR esclusivo coordinatore |
| 49 | Approvazione grandi ordini barista | A | Schede Ordini e Da approvare |
| 50 | Attesa approvazione cliente | C | Tracciamento richiesta, coda, valutazione, decisione |
| 51 | Chiusura straordinaria personale | C | Pannello rapido dalla dashboard, poi conferma impatto |
| 52 | Chiusura straordinaria cliente | C | Avvisi in catalogo, dettaglio ordine e notifiche |
| 53 | Annullamento cliente | C | Pannello dal basso con conseguenze e rimborso |
| 54 | Pausa prenotazioni | B | Centro stato servizio nella dashboard barista |
| 55 | Catalogo con prenotazioni in pausa | A | Avviso in alto; consultazione libera; conferma ordini bloccata nel perimetro |
| 56 | Calendario Admin | C | Viste mese, settimana ed elenco |
| 57 | Orari ricorrenti | C | Planner settimanale, copia orari, validazione sovrapposizioni |
| 58 | Festivita' e chiusure programmate | A | Modifica direttamente selezionando una data nel calendario |
| 59 | Catalogo Admin | C | Tabella o griglia, ricerca e filtri |
| 60 | Editor prodotto | A | Pagina unica: generale, prezzo, ingredienti/allergeni, immagine, pubblicazione |
| 61 | Categorie Admin | B | Elenco riordinabile, stato e conteggio prodotti |
| 62 | Promozioni | C | Attive, Programmate, Archivio con filtri e statistiche |
| 63 | Personale | C | Centro gestione con filtri, ruoli, assegnazioni e scheda collaboratore |
| 64 | Pagamenti Admin | C | Centro finanziario con KPI, Transazioni, Rimborsi e Anomalie |
| 65 | Statistiche e report | C | Panoramica, Prodotti, Ordini, Report; export quando previsto |
| 66 | Animazioni | B | Microinterazioni discrete; reduced motion e accessibilita' |

## Vincoli trasversali confermati

- Il sito deve aprirsi sull'**accesso**, NON su una homepage promozionale.
- UI in italiano, tema chiaro/scuro/automatico, layout mobile-first, adattamento tablet/desktop.
- Nessuna schermata deve fingere disponibilita', pagamenti, stato di ordini o rimborsi non realmente verificati dal backend.
- L'assistenza non e' una voce nella barra inferiore dello studente.
- Lo scanner QR **non** consegna automaticamente: occorrono controlli server, saldo zero e azione barista esplicita.
- I dati di pagamenti di terzi e i QR di gruppo non devono essere esposti a utenti non autorizzati.
- Il logo illustrato nei mockup **non e' un logo definitivo approvato**.
- Il questionario UX e' CHIUSO: le prossime scelte tecniche di routine sono responsabilita' dell'implementazione, senza riaprire i 66 punti.

## Gerarchia decisionale
1. Prompt Master v1 (requisiti confermati: fonte primaria).
2. Questo documento per dettagli UX non in conflitto con il Prompt Master.
3. ADR tecnici per decisioni implementative.
4. Roadmap e acceptance test per il sequenziamento.
