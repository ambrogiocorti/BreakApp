# BreakApp — Attivazione servizi esterni e gate di collaudo (26 ottobre 2026)

## Stato verificato
- Stripe: piattaforma sandbox `acct_1UUniH2RLt7x5EeZ` e **un merchant Connect scolastico di test creato**. Verificato direttamente con `GET /v1/accounts/{id}`: `charges_enabled=false`, `payouts_enabled=false`, `card_payments=inactive`, `details_submitted=false`. Il badge di creazione NON equivale a un esercente abilitato a incassare. Seguire `docs/STRIPE_TEST_MERCHANT_ACTIVATION.md`.
- Supabase `ynvswdyirngvdpudcikl`: scuola ITSOS Marie Curie, nessun merchant nella tabella `school_stripe_merchants`, cinque Edge Functions attive; estensione Vault presente; `pg_cron` e `pg_net` non abilitate.
- GitHub repository `ambrogiocorti/BreakApp`: GitHub Pages abilitato (`has_pages=true`). Il controllo reale della pagina pubblicata, del manifest e del Service Worker è riuscito nella CI; restano da collaudare login e flussi end-to-end con utenti reali.
- Multi-browser: workflow `multibrowser.yml` esegue Playwright Chromium/Firefox/WebKit (desktop e smartphone emulato) in CI. Non sostituisce test su dispositivi fisici.
- Push: workflow `push-dispatch.yml` invoca ogni cinque minuti il dispatcher Supabase **solo se** il segreto `PUSH_DISPATCH_TOKEN` è presente fra i Secrets GitHub; senza segreto salta e avverte.

## Interventi del titolare indispensabili
1. **Pages (abilitato):** la pubblicazione è già raggiungibile su `https://ambrogiocorti.github.io/BreakApp/` e il monitoraggio statico ha superato il test. Rimangono da controllare gli URL di redirect OAuth e l'operatività delle sessioni su dispositivi reali.
2. **Stripe merchant scolastico (creato ma non operativo):** completare l'onboarding Connect dell'esercente giuridicamente responsabile; il merchant scolastico di **test** è già distinto dalla piattaforma, ma `card_payments=inactive` e i pagamenti sono sospesi. Per associarlo a Supabase con interruttori disabilitati usare il runbook `docs/STRIPE_TEST_MERCHANT_ACTIVATION.md`. Abilitare il checkout soltanto dopo verifica Stripe. Non simulare soggetti legali o IBAN.
3. **Stripe Secrets:** creare nei **Supabase Edge Function Secrets** `STRIPE_SECRET_KEY=sk_test_...` e `STRIPE_WEBHOOK_SECRET=whsec_...`. Registrare in Stripe Connect webhook l'URL `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook` per `checkout.session.completed`, `checkout.session.expired`, `refund.updated`. Non usare un live secret per il sandbox.
4. **Web Push:** generare coppia VAPID, salvare nei Supabase Edge Secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT=mailto:breakapp.app@gmail.com`, `PUSH_DISPATCH_TOKEN` robusto (almeno 32 caratteri). Copiare lo **stesso token** in GitHub Actions → Secrets and variables → Actions → `PUSH_DISPATCH_TOKEN`. Non mettere mai i segreti nel codice o in variabili Vite pubbliche.
5. **Accessi Supabase:** aggiungere URL esatto GitHub Pages in Authentication → URL Configuration → Redirect URLs e controllare Google/Microsoft OAuth.
6. **E2E reale:** due Clienti con email confermata, Barista e Admin con 2FA; provare pagamenti test, webhook ripetuti, annullamenti, doppio pagamento bloccato, rimborsi al pagatore originale, lease offline revocato e riconciliazione, notifiche su dispositivo reale e PWA chiusa.

## Policy di rilascio
- Nessun merchant test di piattaforma sostituisce una scuola abilitata.
- Il workflow push è un cron **best effort** GitHub Actions (ritardi possibili, frequenza non garantita). Non sostituisce un dispatcher sempre online.
- Se manca un secret il servizio resta disabilitato: il fallback in-app continua a funzionare.
- Il test multi-browser automatizzato copre i percorsi pubblici e la responsività; i flussi autenticati Stripe/offline necessitano collaudi con account e device reali.
- Implementazione infrastrutturale non equivale alla convalida di tutti i 171 requisiti del Prompt Master.
