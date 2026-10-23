# Fase 2 — Primo menu pubblico reale

Il menu si trova in **https://breakapp-smoky.vercel.app/#menu** e non richiede autenticazione.

## Funzioni attivate

- Scelta scuola e bar sui record `schools` e `bars` visibili tramite RLS.
- Lettura di `categories` e `products` solo con `is_active = true`.
- Ricerca per nome o descrizione e filtro per categoria attiva.
- Prezzi letti in centesimi dal database e convertiti in euro.
- Nessun bottone Acquista/Prenota: **le scorte specifiche per data e fascia non sono state ancora implementate**.
- Aggiornamento manuale dal server tramite pulsante «Aggiorna menu».
- Messaggi chiari in caso di catalogo vuoto, errore di rete o indisponibilità.

## Prova online

1. Accedi a BreakApp con account Admin, completa 2FA e crea una categoria «Panini».
2. Crea un prodotto «Focaccia» a 2,50 €, con descrizione.
3. Scorri alla sezione **Menu scolastico** senza effettuare il logout: il menu pubblico deve visualizzare il prodotto dopo «Aggiorna menu».
4. Apri lo stesso URL in una finestra anonima: il prodotto deve apparire anche senza autenticazione.
5. Prova ricerca «focaccia» e filtro categoria «Panini».
6. Nascondi il prodotto dall'area Admin, premi «Aggiorna menu»: non deve comparire.
7. Riattiva il prodotto e ripeti la verifica.
8. Se possiedi due scuole, verifica la segregazione cambiando scuola e bar.

## Limiti prima dell'MVP commerciale

I prodotti attualmente non includono ancora allergeni strutturati, immagini,
ingredienti, scorte per giornata o stato di acquisto. Le prenotazioni richiedono
prima una transazione backend per la gestione atomica delle riserve e dei prezzi;
il menu online **non** dichiara disponibilità né espone un checkout.

## Verifiche automatiche

`npm run verify` verifica sintassi, test unitari e build. I test `menu.test.mjs`
confermano che prodotti nascosti, categorie nascoste e bar di scuole diverse
non entrino nei risultati del menu in frontend. **Non sostituiscono** i test
delle policy RLS eseguiti direttamente sul database, da aggiungere con account
di prova distinti.
