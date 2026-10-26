# BreakApp — Attivazione servizi esterni e gate di collaudo (26 ottobre 2026)

## Stato verificato
- Stripe context collegato: `acct_1UUniH2RLt7x5EeZ`, **test mode**, account piattaforma BreakApp Standard IT, `charges_enabled=true`, `payouts_enabled=true`. Connect abilitato nella sandbox. `GET /v1/accounts`: nessun account collegato.
- Supabase `ynvswdyirngvdpudcikl`: scuola ITSOS Marie Curie, nessun merchant nella tabella `school_stripe_merchants`, cinque Edge Functions attive; estensione Vault presente; `pg_cron` e `pg_net` non abilitate.
- GitHub repository `ambrogiocorti/BreakApp`: GitHub Pages abilitato (`has_pages=true`). Il controllo reale della pagina pubblicata, del manifest e del Service Worker è riuscito nella CI; restano da collaudare login e flussi end-to-end con utenti reali.
- Multi-browser: workflow `multibrowser.yml` esegue Playwright Chromium/Firefox/WebKit (desktop e smartphone emulato) in CI. Non sostituisce test su dispositivi fisici.
- Push: workflow `push-dispatch.yml` invoca ogni cinque minuti il dispatcher Supabase **solo se** il segreto `PUSH_DISPATCH_TOKEN` è presente fra i Secrets GitHub; senza segreto salta e avverte.

## Interventi del titolare indispensabili
1. **Pages (abilitato):** la pubblicazione è già raggiungibile su `https://ambrogiocorti.github.io/BreakApp/` e il monitoraggio statico ha superato il test. Rimangono da controllare gli URL di redirect OAuth e l'operatività delle sessioni su dispositivi reali.
2. **Stripe merchant scolastico:** nell'account Stripe **test** della piattaforma, avviare onboarding Connect per l'esercente giuridicamente responsabile del bar; non associare automaticamente l'account globale BreakApp alla scuola. Ottenere `acct_...` distinto, con `card_payments=active` e `charges_enabled`. Verificare contratto, soggetto responsabile e proprietà dell'account prima di salvare l'associazione server `school_stripe_merchants`. Non simulare soggetti legali o IBAN.
3. **Stripe Secrets:** creare nei **Supabase Edge Function Secrets** `STRIPE_SECRET_KEY=sk_test_...` e `STRIPE_WEBHOOK_SECRET=whsec_...`. Registrare in Stripe Connect webhook l'URL `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook` per `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `refund.updated`. Applicare prima lo script 21 e distribuire il webhook aggiornato. Non usare un live secret per il sandbox.
4. **Web Push:** generare coppia VAPID, salvare nei Supabase Edge Secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT=mailto:breakapp.app@gmail.com`, `PUSH_DISPATCH_TOKEN` robusto (almeno 32 caratteri). Copiare lo **stesso token** in GitHub Actions → Secrets and variables → Actions → `PUSH_DISPATCH_TOKEN`. Non mettere mai i segreti nel codice o in variabili Vite pubbliche.
5. **Accessi Supabase:** aggiungere URL esatto GitHub Pages in Authentication → URL Configuration → Redirect URLs e controllare Google/Microsoft OAuth.
6. **E2E reale:** due Clienti con email confermata, Barista e Admin con 2FA; provare pagamenti test, webhook ripetuti, annullamenti, doppio pagamento bloccato, rimborsi al pagatore originale, lease offline revocato e riconciliazione, notifiche su dispositivo reale e PWA chiusa.

## Policy di rilascio
- Nessun merchant test di piattaforma sostituisce una scuola abilitata.
- Il workflow push è un cron **best effort** GitHub Actions (ritardi possibili, frequenza non garantita). Non sostituisce un dispatcher sempre online.
- Se manca un secret il servizio resta disabilitato: il fallback in-app continua a funzionare.
- Il test multi-browser automatizzato copre i percorsi pubblici e la responsività; i flussi autenticati Stripe/offline necessitano collaudi con account e device reali.
- Implementazione infrastrutturale non equivale alla convalida di tutti i 171 requisiti del Prompt Master.
