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
- Ordini individuali, preparazione, QR, contanti/POS esterno, modifiche atomiche, sostituzioni e nuovi orari con consenso.
- Gruppi, inviti, conferma atomica, ritiro unico, ledger multipagatore e supplementi di sostituzione.
- Grandi ordini: coda senza stock, presenza, priorità, riserva di dieci minuti e ripianificazione.
- Ospiti con link privato, onboarding scuole, import classi, coupon/bundle e ticket condivisi o personali.
- Checkout/webhook verificati e rimborsi al pagatore originale. **Merchant di test ancora disabilitato e credenziali Stripe mancanti: incassi online non attivi.**
- Terminale Barista cifrato e condiviso, vendite e ritiri individuali/gruppi offline, riconciliazione del saldo e revisione Admin.
- Turni di cassa online/offline, movimenti, conteggi, chiusure immutabili e rettifiche Admin.
- Report per scuola con CSV, XLSX e PDF; annunci e notifiche personali.
- Runtime VAPID e cron con audit HTTP; preferenze push, revoca del dispositivo e promemoria ritiro/chiusura. Consegna su telefoni fisici da collaudare.

Flussi applicativi implementati e coperti da test. [ROADMAP.md](ROADMAP.md) distingue le funzioni disponibili dalle attivazioni e dai collaudi esterni necessari alla vendita. Uso e invarianti: [COMPLETE_WORKFLOWS.md](docs/COMPLETE_WORKFLOWS.md).

## Database e verifiche

La baseline storica è in `supabase/sql/`, nell'ordine specificato dal workflow `database.yml`. Le nuove migrazioni CLI timestampate, in `supabase/migrations/`, vengono applicate dopo la baseline. Non usare `db push` su un database vuoto prima di aver ricostruito e riconciliato la cronologia storica.

La CI verifica sintassi, unit test, build, PostgreSQL 17, autorizzazioni, concorrenza stock e restore di un database temporaneo. Un workflow separato usa Chromium/Firefox/WebKit su desktop e mobile emulato. Non sostituisce il pilota fisico.

Procedure e rollback: [docs/OPERATIONS_20261027.md](docs/OPERATIONS_20261027.md).
