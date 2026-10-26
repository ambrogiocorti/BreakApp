# BreakApp — Stripe Connect: rimborso completo al pagatore originale

## Funzioni implementate
- `request_full_individual_stripe_refund` controlla lato server: ruolo Super Admin o Admin scuola, MFA AAL2, ordine **consegnato o non ritirato**, pagamento Stripe originario `succeeded`, nessun rimborso già in corso. Non è possibile specificare un altro beneficiario.
- `stripe-full-refund` invoca l'API Stripe Refund esclusivamente in **test mode**, sul merchant Connect del pagamento originale. La chiave di idempotenza è fissata a `breakapp-full-refund-<uuid>`.
- `attach_verified_stripe_refund`: accessibile solo al service role, registra l'ID provider dopo la creazione.
- Il webhook firmato `refund.updated` concilia solo importi e payment intent uguali al ledger originale, marcando il pagamento rimborsato soltanto dopo esito `succeeded`. Il cliente vede «Rimborsato» quando il webhook aggiorna l'ordine.
- Un errore contabile non equivale mai a un rimborso registrato. È necessario il controllo del webhook e del ledger.

## Attivazione
1. Utilizzare account Stripe BreakApp collegato in modalità test.
2. Configurare `STRIPE_SECRET_KEY=sk_test_...` e `STRIPE_WEBHOOK_SECRET=whsec_...` nei Supabase Edge Function Secrets, non su GitHub Pages.
3. Attivare Stripe Connect per la scuola e verificare `charges_enabled`. Nessun merchant viene abilitato automaticamente.
4. Pubblicare `stripe-full-refund` con verifica JWT attiva e aggiornare `stripe-webhook` con firma HMAC valida (`verify_jwt=false`).
5. Nel webhook Connect includere `checkout.session.completed` e `refund.updated`.
6. Eseguire un Checkout di test su ordine individuale, consegnarlo, richiedere rimborso dal pannello Admin, verificare nel dashboard Stripe e attendere webhook firmato.

## Limitazioni
- Soltanto **rimborso totale** per ordini individuali consegnati/non ritirati. Sono ancora da implementare: rimborsi parziali per riga, rimborsi massivi fine giornata, chiusure straordinarie, ordini gruppo, pagatori terzi e gestione di chargeback/dispute.
- Non inserire la chiave live finché non sono completati onboarding fiscale/merchant, privacy, documentazione e simulazione di webhook ritardati.
- La gestione di Stripe rimane disabilitata se mancano segreti e merchant scolastici verificati.
