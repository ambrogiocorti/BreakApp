# BreakApp — rilascio Stripe Connect TEST (collaudo Sandbox)

## Stato verificato il 3 novembre 2026

L'ambiente Supabase BreakApp `ynvswdyirngvdpudcikl` contiene il merchant scolastico sandbox `acct_1UVx5F2RLtxMJCNo` con flag `charges_enabled=true` e `payouts_enabled=true`, ma presenta **0 tentativi di pagamento**, **0 rimborsi** e **0 eventi** nella inbox Stripe. Questi dati non dimostrano che l'intero flusso di incasso funzioni.

Il connettore Stripe disponibile nell'ambiente di sviluppo corrente espone la piattaforma test `acct_1UMbXXCs978fOWHz` (nome Plateform), che restituisce **zero account Connect** e due webhook relativi a **progetti Supabase differenti**. Non usare questo account per creare pagamenti o un webhook di BreakApp. L'account piattaforma BreakApp documentato storicamente nel repository e distinto da quello associato alla chat: occorre verificare nel Dashboard Stripe quale piattaforma sia proprietaria del merchant scolastico.

## Aggiornamento verificato il 4 novembre 2026

- Identificata tramite Stripe Workbench la piattaforma corretta **BreakApp TEST** `acct_1UUniH2RLt7x5EeZ`; il merchant collegato resta `acct_1UVx5F2RLtxMJCNo`. Non applicare queste impostazioni all'account LIVE o a Plateform.
- Creati temporaneamente una finestra di ritiro, scorte e un ordine ospite TEST da **2,50 EUR** nel progetto Supabase DEV. La Edge Function ha prodotto una vera sessione Stripe Checkout Sandbox; la sessione e scaduta **senza addebito**. L'evento `checkout.session.expired` firmato e stato accettato (`HTTP 200`), registrato nella inbox e ha portato il tentativo di pagamento allo stato `cancelled`.
- L'ordine e stato annullato mediante il workflow applicativo, la scuola e stata riportata allo stato `is_active=false`, la finestra TEST disattivata e la prenotazione della scorta rilasciata. Restano record TEST inattivi per audit, non prenotazioni attive.
- Stripe aveva **due endpoint TEST attivi con URL identico** e segreti di firma diversi: `we_1UXpLo2RLt7x5EeZLsKaYEIj` (nome *BreakApp Connect TEST*: 1 consegna riuscita, 0 fallite; copre 8 eventi) e `we_1UUxQW2RLt7x5EeZkEpa55TX` (endpoint pilota storico: 3 consegne fallite su 3; copre 4 eventi). L'endpoint pilota e stato **disabilitato**, non eliminato, e lo stato di entrambi e stato riletto via API. Questo evita duplicati invalidi e tentativi ripetuti, ma richiede una nuova prova di consegna dopo il cambio.
- **Collaudo reale completato, individuale:** un secondo ordine ospite TEST da **250 centesimi**, ID `fb77abd9-ce00-444b-8b50-8736b3dc2a58`, e stato creato tramite la stessa Edge Function ospite e RPC ordini usate dal client. Il Checkout Stripe collegato al merchant scolastico ha accettato una carta fittizia ufficiale Stripe in **EUR**, reindirizzando alla pagina di successo; l'evento firmato `checkout.session.completed` e stato registrato in inbox alle 17:16:59 UTC. Il tentativo `22468fea-162b-4a72-ae94-8ee1be8db850` e passato a `succeeded` e l'ordine a `payment_status='paid'`.
- **Rimborso reale Sandbox completato:** il workflow applicativo interno di annullamento ha accodato il refund da **250 centesimi**, ID `83a88559-d58a-40e7-83d0-4df674e20c44`. Il job pg_cron `breakapp-push-and-refunds` ha invocato `group-refund-dispatch` con **HTTP 200** e il primo tentativo ha creato il refund Stripe `re_3UY7nw2RLtxMJCNo1kwQvZFa`. Il webhook firmato `refund.updated` e stato registrato alle 17:18:04 UTC; `payment_refunds.status='succeeded'`, `orders.payment_status='refunded'`, ordine `cancelled`, stock allocato **0**. La scuola resta `is_active=false` e la finestra QA e stata disattivata nuovamente. Totale in inbox: **3 eventi firmati** (`expired`, `completed`, `refund.updated`). Nessun denaro reale e stato movimentato.
- **Limite della prova:** l'ordine e stato creato via RPC con coordinate GPS sintetiche da QA e l'annullamento e stato invocato tramite workflow interno per il test; manca ancora la prova UI completa con ruolo Barista/Admin, oltre a gruppo, pagatori distinti, dispositivi reali e merchant LIVE.

### Check automatico di sola lettura

Il workflow `.github/workflows/stripe-readiness.yml` usa `scripts/check-stripe-readiness.mjs` per interrogare **la piattaforma Stripe TEST corretta**, senza creare addebiti, nuovi account o webhook.

1. Aprire Stripe Dashboard **in modalità TEST** e identificare la piattaforma che ha collegato `acct_1UVx5F2RLtxMJCNo`. Non confondere piattaforma e merchant.
2. Generare/recuperare una **restricted key TEST di sola lettura** con permessi sufficienti a leggere account Connect e webhook, se Stripe lo consente; in caso contrario usare una chiave segreta TEST temporanea e revocarla dopo la verifica. Non usare mai una chiave LIVE.
3. Salvare la chiave in GitHub → Settings → Secrets and variables → Actions, nome `BREAKAPP_STRIPE_TEST_KEY`. Nessun secret nei commit, nei log, in screenshot o in chat.
4. Eseguire **Stripe TEST Connect readiness** in GitHub Actions sul branch `main`, con account scolastico `acct_1UVx5F2RLtxMJCNo`.
5. Se il job fallisce, verificare le righe `[NO]` e l'endpoint TEST **esatto** `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook`. **Importante:** nelle prime tre esecuzioni (#41719448617, #41719924264, #41723346645) lo script produceva un falso negativo per la modalità Connect: controllava `webhook.connect === true` anche se Stripe **non restituisce il campo `connect` nella risposta GET /v1/webhook_endpoints**. Il gate corretto convalida URL, ambiente TEST, stato e presenza degli eventi sulla medesima destinazione. Inoltre ora **rifiuta piu endpoint attivi con lo stesso URL**: ciascuno ha un `whsec_` diverso e con un solo secret configurato in Supabase i duplicati generano `HTTP 400` e nuovi tentativi. E consentito conservare un endpoint storico **disattivato**.
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
