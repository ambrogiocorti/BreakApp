# BreakApp

**BreakApp** è una piattaforma multitenant per la gestione dei bar scolastici.

> Stato: **pilota tecnico in sviluppo — non pronto per la vendita né per l'incasso reale**.
> Sono presenti catalogo, ruoli/MFA, ordini individuali, incassi al banco e QR;
> Stripe Checkout e rimborsi completi sono implementati in test ma richiedono
> merchant scolastico verificato, secret server e collaudo. Sono presenti bozze
> gruppo e fondazioni offline, non ancora tutti i relativi flussi operativi.
> Vedi [`ROADMAP.md`](ROADMAP.md) per lo stato puntuale delle fasi 0–7.

## Stack

- HTML semantico, CSS personalizzato e JavaScript vanilla (moduli ES).
- Vite esclusivamente come strumento di build.
- Supabase Auth/Postgres/RLS con 2FA TOTP obbligatoria per scritture Admin sul catalogo; tutte le scritture sono autorizzate server-side.
- GitHub Pages come hosting frontend scelto il 26 ottobre 2026; Vercel è stato
  l'ambiente di prova temporaneo. GitHub Pages è già attivo; il monitoraggio esterno statico è abilitato.
- GitHub Actions per sintassi, test e build a ogni push.

## Verifiche automatiche

Il workflow `.github/workflows/checks.yml` esegue `npm run verify`, che include
controlli sintattici, test unitari e generazione della build.

## Anteprima online su Vercel

Il progetto usa `npm run build` e pubblica la directory `dist`. L'integrazione
GitHub/Vercel aggiorna l'ambiente di test a ogni push.

Il progetto Supabase dedicato è `ynvswdyirngvdpudcikl`. Il frontend richiede
`VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` in build; non esporre
`service_role`, chiavi Stripe/VAPID private o token nel browser o nella repository.

La configurazione da un **secondo account Supabase**, interamente da browser,
è descritta in [`docs/SUPABASE_SETUP_ONLINE.md`](docs/SUPABASE_SETUP_ONLINE.md).
Gli script SQL da eseguire nel nuovo progetto sono in `supabase/sql/`.
Per attivare il primo catalogo reale, segui [le istruzioni SQL 03 e test online](docs/FASE1_CATALOGO_ADMIN.md).

## Sicurezza e roadmap

Il codice pubblicato è un pilota tecnico pubblico; la specifica completa resta
riservata. Nessuna promessa di isolamento multitenant, affidabilità offline
o incasso reale è valida senza test end-to-end e convalida dei controlli server.

La shell PWA non consente ancora incassi offline definitivamente contabilizzati:
gli eventi offline sono messi in quarantena in attesa di una riconciliazione sicura.


## Menu pubblico (senza accesso)

La sezione [Menu di BreakApp](https://breakapp-smoky.vercel.app/#menu) consente di scegliere scuola e bar,
filtrare per categoria e cercare prodotti. Legge in tempo reale le righe pubblicate
su Supabase tramite chiave pubblica e policy RLS. Mostra uno stato vuoto corretto
quando l'Admin non ha ancora creato categorie e prodotti. Non permette ordini
perché la gestione delle disponibilità giornaliere non è ancora attiva.

I controlli e i criteri di prova sono in
[docs/FASE2_MENU_PUBBLICO.md](docs/FASE2_MENU_PUBBLICO.md).
