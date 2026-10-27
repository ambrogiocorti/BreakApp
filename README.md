# BreakApp

PWA multitenant per bar scolastici, con HTML/CSS/JavaScript ES, Supabase e Stripe. Vite è usato per build e sviluppo.

[Sito di test GitHub Pages](https://ambrogiocorti.github.io/BreakApp/). Vercel genera anteprime dei branch; il pacchetto statico rimane compatibile con Cloudflare Pages.

## Avvio

```bash
npm ci
npm run dev
npm run verify
```

Il frontend richiede soltanto `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` (vedi `.env.example`). Nessuna credenziale privilegiata deve entrare nel bundle.

## Funzioni presenti

- Ruoli per scuola, Super Admin esclusivo e TOTP Admin.
- Catalogo, ingredienti/allergeni, immagini, scorte giornaliere, orari, fasce e chiusure.
- Ordini individuali, preparazione, QR, contanti/POS esterno.
- Gruppi, inviti, conferma atomica, ritiro unico e ledger multipagatore.
- Checkout/webhook verificati e rimborsi al pagatore originale. **Merchant di test ancora disabilitato e credenziali Stripe mancanti: incassi online non attivi.**
- Terminale Barista cifrato, vendite/ritiri individuali offline, riconciliazione e revisione Admin.
- Turni di cassa online/offline, movimenti, conteggi, chiusure immutabili e rettifiche Admin.
- Report per scuola con CSV, XLSX e PDF; annunci e notifiche personali.
- Runtime VAPID e cron con audit HTTP; preferenze push, revoca del dispositivo e promemoria ritiro/chiusura. Consegna su telefoni fisici da collaudare.

**Stato: sviluppo avanzato, non certificato per la vendita come piattaforma completa.** [ROADMAP.md](ROADMAP.md) documenta i limiti effettivi.

## Database e verifiche

La baseline storica è in `supabase/sql/`, nell'ordine specificato dal workflow `database.yml`. Le nuove migrazioni CLI timestampate, in `supabase/migrations/`, vengono applicate dopo la baseline. Non usare `db push` su un database vuoto prima di aver ricostruito e riconciliato la cronologia storica.

La CI verifica sintassi, unit test, build, PostgreSQL 17, autorizzazioni, concorrenza stock e restore di un database temporaneo. Un workflow separato usa Chromium/Firefox/WebKit su desktop e mobile emulato. Non sostituisce il pilota fisico.

Procedure e rollback: [docs/OPERATIONS_20261027.md](docs/OPERATIONS_20261027.md).
