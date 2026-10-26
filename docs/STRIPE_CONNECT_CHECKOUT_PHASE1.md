# BreakApp — Stripe Connect Checkout / webhook (solo ordini individuali)

## Sicurezza attuale

- Funzione `stripe-checkout-individual`: riceve JWT Supabase, verifica `auth.getUser()`, interroga `begin_individual_stripe_checkout` con JWT utente, lascia al **database** validare proprietà dell'ordine, stato, merchant, ammontare, idempotenza e conflitti.
- Checkout Session viene creata **solo lato server** tramite `STRIPE_SECRET_KEY`, in test mode, usando `Stripe-Account` del merchant scolastico selezionato dal database. Nessuna chiave segreta in HTML/JS/Pages.
- Funzione `stripe-webhook`: `verify_jwt=false` perché Stripe non invia un JWT Supabase. Verifica HMAC-SHA256 di `Stripe-Signature` sul body **raw** e rifiuta timestamp oltre 5 minuti.
- Elaborazione solo di `checkout.session.completed` con `payment_status=paid`, evento Connect con account coerente, importo/currency/session/attempt/payment intent verificati da RPC `finalize_verified_checkout`; ack 2xx solo dopo commit. Ripetizione dello stesso evento è idempotente.
- Se l'ordine è stato pagato al banco, cancellato o consegnato quando arriva il webhook, pagamento Stripe rimane **review**, non viene fittiziamente riconciliato né duplicato. Serve orchestrazione automatica dei rimborsi e una segnalazione Admin.
- Il blocco contanti impedisce nuove registrazioni finché un checkout non è scaduto o riconciliato.

## Attivazione (non eseguita automaticamente senza credenziali e merchant verificati)

1. Stripe in modalità test: configurare **Stripe Connect** per ciascun merchant/scuola; verificare che `charges_enabled` appartenga al merchant reale. Non usare l'account piattaforma come conto di una scuola senza accordi e verifica.
2. Supabase → Project `ynvswdyirngvdpudcikl` → Edge Functions → Secrets: creare `STRIPE_SECRET_KEY=sk_test_...` e `STRIPE_WEBHOOK_SECRET=whsec_...`. Sono segreti distinti e **non** devono essere incollati in GitHub, URL pubblici o browser.
3. Deploy da repository delle funzioni `stripe-checkout-individual` con verifica JWT attiva e `stripe-webhook` con verifica JWT disattivata, esattamente perché la funzione webhook verifica **la firma Stripe**.
4. In Stripe, configurare endpoint **Connect events** `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook`, evento `checkout.session.completed`. La chiave `whsec_` deve essere quella dell'endpoint configurato.
5. Associare la scuola al proprio `acct_...` in `public.school_stripe_merchants` attraverso un'operazione amministrativa protetta; attivare `charges_enabled` soltanto dopo verifica Stripe/merchant.
6. In GitHub Pages, accedere come Cliente registrato, creare un ordine individuale, scegliere il bottone **Stripe (test)** e pagare con una carta di test. Verificare evento, webhook inbox, payment_attempts e ordine `paid` **dopo** webhook (mai dalla return page).
7. Simulare timeout, doppio webhook, cambio importo, annullamento durante Checkout e incasso al banco concorrente, senza usare denaro reale.

## Limiti vincolanti

- Questo incremento implementa Checkout test per **ordini individuali già confermati**, non checkout pagato prima della prenotazione, gruppi o split payer.
- Non ci sono ancora rimborsi online eseguibili, allocazioni per item effettivamente contabilizzate, trasferimenti merchant, Stripe Connect onboarding self-service, POS Stripe, documenti fiscali o rimborsi automatici da offline.
- La conferma gruppo e pagamenti pre-conferma del Prompt Master **non sono disponibili**. Sono necessari una macchina stati con riserve 10 minuti, pagatore effettivo, event inbox/retry, refund workflow e copertura di doppio cash/online.
- Per i dati dei minori usare minimizzazione dei metadati Checkout e informativa appropriata; non inviare classe, dati personali o dettagli alimentari ai metadati Stripe.
- Mai considerare un `status=paid` senza controllo server Stripe firmato e ledger corrispondente.

## Hosting

Frontend GitHub Pages; Edge Functions e segreti su Supabase. Il workflow `github-pages.yml` richiede GitHub Pages attivato nelle impostazioni della repository.
