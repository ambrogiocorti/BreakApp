# BreakApp

**BreakApp** è una piattaforma multitenant per la gestione dei bar scolastici.

> Stato: **Fase 1/2 — catalogo Admin in attivazione**. Scuole e ruoli sono letti
> da Supabase. Il codice del catalogo (categorie/prodotti) e la verifica 2FA
> TOTP Admin sono implementati; le scritture richiedono le policy della migration 03
> da eseguire nel nuovo Supabase. Non esistono ancora vendite, ordini o pagamenti.

## Stack

- HTML semantico, CSS personalizzato e JavaScript vanilla (moduli ES).
- Vite esclusivamente come strumento di build.
- Supabase Auth/Postgres/RLS con 2FA TOTP obbligatoria per scritture Admin sul catalogo; tutte le scritture sono autorizzate server-side.
- Vercel per l'ambiente di test temporaneo; hosting definitivo da stabilire.
- GitHub Actions per sintassi, test e build a ogni push.

## Verifiche automatiche

Il workflow `.github/workflows/checks.yml` esegue `npm run verify`, che include
controlli sintattici, test unitari e generazione della build.

## Anteprima online su Vercel

Il progetto usa `npm run build` e pubblica la directory `dist`. L'integrazione
GitHub/Vercel aggiorna l'ambiente di test a ogni push.

La schermata di autenticazione sarà abilitata soltanto dopo la configurazione di
un **nuovo progetto Supabase dedicato** a BreakApp, con URL e chiave
`sb_publishable_…` impostati come variabili `VITE_SUPABASE_URL` e
`VITE_SUPABASE_PUBLISHABLE_KEY` su Vercel. Mai esporre `service_role`, chiavi
segrete, token privati o credenziali in questa repository o nel frontend.

La configurazione da un **secondo account Supabase**, interamente da browser,
è descritta in [`docs/SUPABASE_SETUP_ONLINE.md`](docs/SUPABASE_SETUP_ONLINE.md).
Gli script SQL da eseguire nel nuovo progetto sono in `supabase/sql/`.
Per attivare il primo catalogo reale, segui [le istruzioni SQL 03 e test online](docs/FASE1_CATALOGO_ADMIN.md).

## Sicurezza e roadmap

Il codice pubblicato è solo il bootstrap pubblico. La specifica funzionale
completa e i documenti di progetto riservati non vengono inclusi nella
repository pubblica. Le funzioni multi-scuola saranno rilasciate solo dopo
verifica di RLS, RBAC e isolamento tra tenant con controlli server-side.

La shell PWA di questo incremento **non** consente operazioni offline su ordini,
cassa o scorte.

