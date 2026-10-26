# BreakApp — Web Push VAPID: deployment sicuro

## Stato verificato
- Migrazione `18_web_push_dispatch.sql` installata nel progetto Supabase BreakApp.
- Edge Functions `push-public-key` e `push-dispatch` distribuite sul progetto BreakApp, con `verify_jwt=false`: il primo endpoint fornisce solo dati pubblici, il secondo verifica un token di dispatch segreto in confronto a tempo costante, prima di richiedere job.
- La PWA può richiedere consenso, creare una sottoscrizione nativa `PushManager` e registrarla nella tabella RLS `push_subscriptions`. Il service worker mostra una notifica quando riceve un payload firmato dal push service.
- Trigger PostgreSQL su `customer_notifications`: un job per ciascun dispositivo attivo, ID di evento idempotente, retry esponenziale, disabilitazione su 404/410, massimo sei tentativi.

## Abilitazione necessaria (non installare segreti in GitHub Pages)
Per le notifiche **ad app chiusa** servono ancora chiavi VAPID e un invocatore schedulato:
1. Generare chiavi VAPID per l'origine del sito, ad esempio con libreria `web-push` su ambiente sicuro. Non riutilizzare chiavi di progetti diversi.
2. Inserire nei **Supabase Edge Function Secrets**: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT=mailto:breakapp.app@gmail.com` e `PUSH_DISPATCH_TOKEN` casuale di almeno 32 caratteri.
3. Impostare un cron server (pg_cron + pg_net oppure un scheduler affidabile) che invochi via HTTPS **POST** `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/push-dispatch` con header `x-breakapp-dispatch-token`. Inserire il token soltanto in secret storage server, mai SQL in chiaro nel repository.
4. Usare l'URL GitHub Pages effettivamente abilitato; confermare l'installabilità PWA e la disponibilità del Service Worker in HTTPS.
5. Testare un avviso ordinario con due dispositivi diversi, browser chiuso, notifica cliccata, device disabilitato, retry e limitazioni iOS/browser.

## Controlli / limiti
- Le push usano il service worker e **non elaborano incassi, ordini o rimborsi**.
- Non inviare numeri di telefono, dettagli di minori o contenuti sensibili nel payload. Il titolo è generico e il messaggio notificato può essere disabilitato da preferenze utente.
- La UI può registrare la sottoscrizione; senza secrets o cron gli utenti ricevono soltanto avvisi in-app/foreground.
- Le risposte 404/410 disabilitano un endpoint scaduto. Gli errori transitori ritentano con ritardo e vengono registrati senza esporre la chiave privata.
- Non configurare due cron concorrenti senza verificare claim atomico e semantica at-least-once.
- Le browser push dipendono da permessi e politiche del sistema operativo; non sono garantite come consegna «istantanea» su qualsiasi telefono.
