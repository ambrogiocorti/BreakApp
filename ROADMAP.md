# BreakApp — Roadmap esecutiva

**Versione:** 2026-10-25. **Ambiente di prova:** Vercel. **Hosting finale previsto:** Cloudflare Pages. **Nessun cambio di stack.**

## Stato iniziale verificato
- Repository pubblico `ambrogiocorti/BreakApp`, branch `main`, commit `67339932904d219463aef2f1e9aab6ae7266b4be`.
- Vercel: ultimo deployment su quel commit `READY`; GitHub Actions `BreakApp checks` riuscito.
- Vite come SOLO strumento di build, HTML/CSS/JS vanilla; Supabase client; shell PWA.
- Funzioni codice: autenticazione, MFA Admin, scuola/ruolo, catalogo Admin base, consultazione menu pubblico.
- **Non completati:** flussi ordine, checkout, inventario giornaliero, cassa, Stripe, gruppi, QR, offline operativo.
- **Non verificabile con connessione Supabase di questa chat:** database BreakApp nuovo account. Evitare di agire su altri progetti Supabase.
- Il codice non corrisponde alla UX approvata: `index.html` presenta ancora landing/hero e login secondario.

## Regole di esecuzione
1. Nuove funzioni solo con RBAC/RLS tenant-scoped, controlli server, audit, gestione errori e test negativi.
2. Branch per ogni incremento, PR e controllo CI; non fare push diretto a `main` senza review.
3. Preview Vercel, test da browser remoto; nessuna richiesta di test locale all'utente.
4. Ogni consegna deve specificare `completato / parziale / da verificare`, commit, migrazioni, test e limiti.
5. Mai usare segreti in frontend o commit; mai agire sui Supabase di altri progetti.
6. Pagamenti, stock e ordini hanno fonte di verita' server-side; operazioni concorrenti e retry idempotenti.
7. Database e report reali, nessun mock dato per funzionalita' commerciali.

## Roadmap prioritaria

### M0 — Riallineamento UX / app shell (immediata)
- Eliminare landing promozionale dall'esperienza iniziale: login split desktop/mobile secondo decisione 1.
- Definire routing e shell per contesti scuola/ruolo: cliente, barista, magazziniere, Admin scuola, Super Admin.
- Bottom nav `Menu / Ordini / Gruppi / Profilo` su mobile; sidebar desktop.
- Componenti CSS riutilizzabili (buttons, forms, cards, bottom sheets, alert, skeleton, focus states).
- Conservare flussi Auth/MFA e catalogo esistenti evitando regressioni.
- Stati reali: disconnessione, errore, caricamento e vista non autorizzata; nessuna navigazione fittizia.
- **Accettazione:** login diretto `/`; niente homepage promozionale; logout; MFA Admin; menu pubblico raggiungibile; accessibility smoke test; CI verde; preview Vercel separata.
- **Vincolo:** componenti che non hanno ancora un backend vanno marcati chiaramente come non disponibili, non fingere operativita'.

### M1 — Fondazioni prodotto e catalogo reale
- Consolidare deploy/test/env, RLS e policy tra due account/scuole, audit delle migrazioni applicate.
- Catalogo completo: immagini Storage, ingredienti e allergeni strutturati, ordine categorie e scheda prodotto.
- Scuole/bar, calendario, orari e fasce di ritiro; disponibilita' giornaliera con intervalli.
- **Accettazione:** test RBAC/RLS con due scuole; prodotti pubblicati/nascosti coerenti; media protetti; nessuna disponibilita' inventata.

### M2 — Ordine individuale reale
- Carrello persistente, disponibilita' per data, prenotazione geolocalizzata e cutoff.
- DB `orders`, `order_items`, `daily_stock`, riserve con lock/transaction, idempotency keys e macchine a stati.
- Dashboard/ordine barista, modalita' preparazione attiva/già pronta, QR verificabile, ricerca numero e conferma consegna.
- Vendita diretta al banco e incasso in presenza come operazioni contabilizzate (non integrare falsa emissione fiscale).
- **Accettazione:** race sull'ultimo prodotto; doppi click; RLS cross-tenant; QR invalido; saldo dovuto impedisce consegna; stock/ordini persistenti.

### M3 — Pagamenti e ledger
- Stripe **test mode**; isolamento conti per scuola, verifica fattibilita' Stripe Connect.
- Ledger delle allocazioni, callback/webhook con firma, inbox idempotente e state machine rimborsi.
- Pagamento aggiuntivo/rimborso parziale dopo modifica; anomalie e amministrazione finanziaria.
- **Accettazione:** doppio webhook, timeout, pagamento tardivo e rimborsi idempotenti, dati economici segregati tra scuole.

### M4 — Gruppi
- Inviti, registrati/ospiti, approvazioni, riepilogo partecipanti, bozza con scadenza per inattivita'.
- Pagamenti Stripe di righe intere anche altrui e rimborso al **pagatore effettivo**; allocazioni atomiche.
- Conferma solo coordinatore, geolocalizzazione d'ingresso/di conferma, QR esclusivo, lock ritiro di 10 minuti.
- **Accettazione:** scenari Anna/Luca; ingressi sospesi; ultimo prodotto; doppio pagatore; rimborsi corretti; impossibile ritirare gruppo come semplice partecipante.

### M5 — Operazioni avanzate e amministrazione
- Approvazione manuale grandi ordini (coda senza riserva; lease attivi 10 minuti).
- Ritardi, sostituzioni, annullamenti, chiusure, pause e calendario eccezioni.
- Promozioni, notifiche push+in-app, ticket con privacy, cassa/turni, statistiche/export e pannello Super Admin.
- **Accettazione:** ordine impact preview; transazioni corrette; statuti veritieri; audit; controlli negativi tenant/ruolo.

### M6 — Offline barista robusto
- Dispositivo offline singolo per barista, trasferimento/revoca, finestra massima di 8 ore.
- IndexedDB protetto, PIN, cache minima per gli ordini odierni, coda eventi idempotente.
- Gestione conflitti, quarantena eventi post-revoca/dubbi e riconciliazioni autorizzate.
- Cassa offline e sync; pagamenti cash duplicati con Stripe e rimborso appropriato.
- **Accettazione:** disconnessione reale, expiry, conflitti, dispositivi revocati, nessuna perdita silenziosa di eventi.

### M7 — Sicurezza, produzione pilota, Cloudflare Pages
- Audit indipendente RLS/RBAC/Storage, CSP, accessibilita', performance, GDPR, fiscalita' e backup/restore.
- Supporto multi-scuola; report reali; osservabilita', alert, prova carico e procedure rollback.
- Passaggio dell'hosting statico a Cloudflare Pages con cutover controllato; Vercel resta ambiente test finche' richiesto.
- **Accettazione:** test end-to-end su scuola pilota, prove di ripristino, approvazione umana per promozione in produzione.

## Dipendenze e verifiche preliminari
- Nuovo account Supabase di BreakApp deve essere collegato in modo sicuro: connessione MCP attuale elenca altri progetti; **nessuna modifica remota** finche' il corretto target non e' identificato.
- Deployment Vercel READY non equivale a test end-to-end dell'app. Mancano test browser con credenziali di prova e permessi reali.
- `vercel.json` usa `Permissions-Policy: camera=()`: **lo scanner QR non puo' chiedere accesso alla camera** finche' non si modifica consapevolmente la policy; verificare anche CSP per immagini Storage/media.
- Allineare `README.md` in un PR successivo: contiene indicazioni obsolete di setup rispetto allo stato corrente.
- Logo approvato solo come concetto, non come arte finale.
