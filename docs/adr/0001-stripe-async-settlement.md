# ADR 0001 — Gestione degli esiti Stripe Checkout asincroni

**Stato:** Proposta tecnica implementata su branch; attivazione soggetta a test CI e sandbox.
**Data:** 26 ottobre 2026.

## Contesto

Un metodo di pagamento differito può emettere `checkout.session.completed`
quando lo stato è ancora `unpaid`. Il precedente webhook rifiutava questo evento
e ignorava `checkout.session.async_payment_succeeded` e
`checkout.session.async_payment_failed`. Il lock anti-doppio incasso resta attivo
fino a una conferma del provider, non fino a un timer locale.

## Scelta

1. `completed` + `paid`: contabilizzazione atomica tramite RPC esistente.
2. `completed` + `unpaid`: ack dell'evento firmato, nessuna contabilizzazione;
   mantenere il tentativo bloccante fino all'esito definitivo.
3. `async_payment_succeeded` + `paid`: stessa RPC di contabilizzazione
   idempotente, conservando nell'inbox il vero tipo di evento.
4. `async_payment_failed` + `unpaid`: nuova RPC service-role che confronta account
   Connect, sessione, PaymentIntent, tentativo, importo, valuta, scuola e pagatore.
   Solo dopo il commit del fallimento libera la cassa per un eventuale incasso reale.
5. Un pagamento giunto dopo cassa/annullamento passa in `review` per la gestione
   esplicita dell'eccedenza, non diventa una seconda conferma automatica.

## Conseguenze

- Migrazione incrementale `supabase/sql/21_stripe_async_reconciliation.sql`, dopo 20.
- Aggiornare il webhook Edge Function e i tipi di evento nell'endpoint Stripe Connect.
- Aggiungere unit test e test PostgreSQL a ogni PR.
- Non attivare con denaro reale finché non sono verificati merchant, webhook,
  idempotenza, rimborsi e anomalie su una sandbox Stripe reale.
