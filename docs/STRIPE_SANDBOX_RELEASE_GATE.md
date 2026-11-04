# BreakApp — rilascio Stripe Connect TEST (verifica senza pagamenti)

## Stato verificato il 4 novembre 2026

L'ambiente Supabase BreakApp `ynvswdyirngvdpudcikl` contiene il merchant scolastico sandbox `acct_1UVx5F2RLtxMJCNo` con flag `charges_enabled=true` e `payouts_enabled=true`, ma presenta **0 tentativi di pagamento**, **0 rimborsi** e **0 eventi** nella inbox Stripe. Questi dati non dimostrano che l'intero flusso di incasso funzioni.

La piattaforma Stripe TEST BreakApp corretta è `acct_1UUniH2RLt7x5EeZ` (distinta da Plateform `acct_1UMbXXCs978fOWHz`). L'API Stripe conferma che il merchant scolastico appartiene a questa piattaforma, è abilitato agli addebiti e ha la capability `card_payments=active`.

**Blocco webhook verificato il 4/11:** la piattaforma BreakApp ha **due destinazioni TEST attive per lo stesso identico URL** `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook`:

- `we_1UUxQW2RLt7x5EeZkEpa55TX` — destinazione precedente, 4 eventi.
- `we_1UXpLo2RLt7x5EeZLsKaYEIj` — destinazione più recente, 8 eventi.

Entrambe hanno `events_from=["@accounts"]` (account connessi) e `event_payload="snapshot"` secondo l'API Event Destinations v2. I segreti `whsec_` delle due destinazioni non sono intercambiabili: prima di disabilitarne una, identificare quella corrispondente a `STRIPE_WEBHOOK_SECRET` nell'ambiente Supabase, utilizzando una consegna TEST firmata e verificata. Non eliminare alcuna destinazione alla cieca. Il gate di verifica ora rifiuta più di una destinazione **attiva** per lo stesso URL.

**Blocco prova applicativa:** su Supabase ITSOS Marie Curie è al momento sospesa (`is_active=false`), e le uniche scorte e fasce sono datate 26/10 e 03/11. Non riaprire la scuola reale o inventare ordini senza preparare una prova isolata e concordata. Il database ha ancora 0 `payment_attempts`, 0 `payment_refunds` e 0 eventi nella inbox; la piattaforma Stripe non ha Checkout Sessions registrate.

### Check automatico di sola lettura

Il workflow `.github/workflows/stripe-readiness.yml` usa `scripts/check-stripe-readiness.mjs` per interrogare **la piattaforma Stripe TEST corretta**, senza creare addebiti, nuovi account o webhook.

1. Aprire Stripe Dashboard **in modalità TEST** e identificare la piattaforma che ha collegato `acct_1UVx5F2RLtxMJCNo`. Non confondere piattaforma e merchant.
2. Generare/recuperare una **restricted key TEST di sola lettura** con permessi sufficienti a leggere account Connect e webhook, se Stripe lo consente; in caso contrario usare una chiave segreta TEST temporanea e revocarla dopo la verifica. Non usare mai una chiave LIVE.
3. Salvare la chiave in GitHub → Settings → Secrets and variables → Actions, nome `BREAKAPP_STRIPE_TEST_KEY`. Nessun secret nei commit, nei log, in screenshot o in chat.
4. Eseguire **Stripe TEST Connect readiness** in GitHub Actions sul branch `main`, con account scolastico `acct_1UVx5F2RLtxMJCNo`.
5. Se il job fallisce, verificare le righe `[NO]` e l'endpoint TEST **esatto** `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook`. **Importante:** nelle prime tre esecuzioni (#41719448617, #41719924264, #41723346645) lo script produceva un falso negativo per la modalità Connect: controllava `webhook.connect === true` anche se Stripe **non restituisce il campo `connect` nella risposta GET /v1/webhook_endpoints**. Il gate corretto convalida solo URL, ambiente TEST, stato e presenza degli eventi sulla medesima destinazione.
5a. **Controllo manuale obbligatorio:** in Stripe Workbench, in modalità TEST e nella piattaforma corretta, aprire la destinazione con l'URL BreakApp e verificare `Events from: Connected accounts` e `Payload style: Snapshot` (NON `Your account` / `Thin`). Se i dati non coincidono, creare la corretta destinazione e configurarne il nuovo `whsec_` in Supabase. Il campo di origine non è verificabile attraverso l'elenco API v1. Confermare la configurazione con un evento TEST realmente consegnato, firmato e contenente `event.account` del merchant scolastico.
6. L'endpoint dev'essere abilitato e ricevere almeno: `checkout.session.completed`, `checkout.session.expired`, `checkout.session.async_payment_succeeded`, `refund.created`, `refund.updated`. La chiave `whsec_...` *di questo endpoint* deve corrispondere a `STRIPE_WEBHOOK_SECRET` nei **Supabase Edge Function Secrets**.
7. Un job **verde** significa soltanto che URL, stato, eventi e merchant risultano corretti secondo l'API REST Stripe. **Non certifica l'ambito Connect, il secret di firma né la contabilizzazione**. Dopo la prova, limitare o rimuovere la chiave temporanea GitHub se superflua. Il workflow non legge il secret webhook e **non può verificare** che il secret Supabase corrisponda realmente a quello Stripe.

## Test finanziario obbligatorio con sandbox e utente di prova

Avere un workflow verde **non** sostituisce questo test:

- Cliente registrato, distinto dal Super Admin, presso la scuola pilota, prodotto con prezzo/stock e fascia futura valida: inviare ordine dal frontend BreakApp ed entrare in Stripe Checkout.
- Pagare con **carta di test ufficiale** nell'account Connect scolastico; controllare importo, PaymentIntent, merchant e stato della Checkout Session.
- Verificare in Supabase che `payment_attempts` e l'ordine siano riconciliati **solo dopo** il webhook Connect valido. Ripetere lo stesso evento e verificare idempotenza e assenza di doppia contabilizzazione.
- Richiedere rimborso con ruolo Barista/Admin abilitato. Controllare che la ricevuta del refund originale sia registrata e che `payment_refunds` diventi completato **solo dopo** `refund.updated` firmato.
- Ripetere almeno un ordine di gruppo con pagatori distinti, una cancellazione e una scadenza di sessione. Controllare il dispatcher e le notifiche di errore.
- Se un webhook risponde 401/400/500, controllare Stripe Event deliveries e Supabase Edge logs. **Mai** intervenire scrivendo manualmente nel ledger per far apparire l'ordine pagato.

## Regole di sicurezza

- Solo chiavi `sk_test_` o `rk_test_`; il codice server rifiuta chiavi LIVE.
- Non generare Checkout di prova direttamente via API fuori dal flusso BreakApp per certificare la contabilità: non genererebbe la corretta registrazione dell'ordine.
- L'endpoint webhook pubblico è `verify_jwt=false`, ma verifica firma HMAC-SHA256 sull'evento raw e usa le procedure SQL per la riconciliazione tenant-safe.
- Verificare separatamente fiscalità, GDPR, consenso informato e configurazione dell'account merchant LIVE prima di qualsiasi incasso reale.
- Il test diagnostico non prova il valore del `STRIPE_WEBHOOK_SECRET`, la consegna webhook, l'idempotenza in runtime, i soldi reali né l'autorizzazione a vendere.
