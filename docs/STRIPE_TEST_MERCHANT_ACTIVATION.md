# Attivazione del merchant scolastico Stripe — solo sandbox

Questo runbook **non abilita alcun pagamento**. Associa in modo controllato una scuola a un account Connect di test e conserva gli interruttori di pagamento spenti finché Stripe non verifica l'esercente. La specifica resta `BreakApp_PROMPT_MASTER_v1.md`; il test automatizzato verifica che i checkout con merchant inattivo siano rifiutati.

## Stato osservato il 26 ottobre 2026

- Piattaforma sandbox Stripe BreakApp: `acct_1UUniH2RLt7x5EeZ`.
- Account Connect scolastico di **prova** creato in Italia, distinto dalla piattaforma. L'ID esatto viene comunicato al responsabile tramite canale operativo; non includere qui link di onboarding né token.
- Lettura Stripe API `GET /v1/accounts/{id}`: `charges_enabled=false`, `payouts_enabled=false`, `capabilities.card_payments=inactive`, `details_submitted=false`.
- Il gestore deve completare i requisiti di Stripe. Nessun documento legale, conto bancario o rappresentante può essere inventato per sbloccare l'ambiente reale.
- Accesso diretto a Supabase non disponibile dall'integrazione corrente: i passaggi SQL seguenti vanno eseguiti **manualmente** da un amministratore nel progetto corretto.

## 1. Prerequisiti

1. Aprire il progetto Supabase di BreakApp `ynvswdyirngvdpudcikl`, **non** quello di 5AHub.
2. Accertare che tutte le migrazioni richieste siano state applicate in ordine, in particolare `16_payments_offline_push_foundations.sql`, `17_stripe_checkout_individual.sql`, `19_full_stripe_refunds.sql` e `20_checkout_expiry_reconciliation.sql`.
3. Il gestore del bar è il soggetto che vende e incassa; la piattaforma gestisce soltanto l'ordine e invoca Stripe con header `Stripe-Account` di quella scuola. Questa è l'architettura a **pagamenti diretti** adottata dal codice esistente.
4. Non distribuire la riconciliazione asincrona di PR #30 finché il suo collaudo finanziario in sandbox non sarà concluso.

## 2. Verifica di sola lettura nel SQL Editor

```sql
select id, slug, name
from public.schools
order by name;

select school_id, stripe_account_id,
       charges_enabled, payouts_enabled, verified_at
from public.school_stripe_merchants
order by school_id;
```

Se `school_stripe_merchants` non esiste, fermarsi: manca almeno la migrazione 16. Identificare l'UUID esatto della scuola prima di qualsiasi inserimento. Se la scuola ha già un merchant, **fermarsi**: non sostituirlo senza una riconciliazione amministrativa.

## 3. Associare il solo merchant di test, ancora disabilitato

Sostituire **entrambi** i valori segnaposto usando l'UUID ricavato dalla query precedente e l'ID Connect scolastico visualizzato nella dashboard Stripe (non l'ID della piattaforma).

```sql
do $link_test_merchant$
declare
  v_school_id uuid := '00000000-0000-4000-8000-000000000000';
  v_stripe_account text := 'acct_SOSTITUISCIID';
begin
  if v_school_id = '00000000-0000-4000-8000-000000000000'::uuid
     or v_stripe_account = 'acct_SOSTITUISCIID'
  then raise exception 'Sostituire prima i segnaposto'; end if;

  if not exists (select 1 from public.schools where id = v_school_id)
  then raise exception 'Scuola inesistente: %', v_school_id; end if;

  if exists (select 1 from public.school_stripe_merchants
             where school_id = v_school_id or stripe_account_id = v_stripe_account)
  then raise exception 'Scuola o merchant gia associati; verificare prima di procedere'; end if;

  insert into public.school_stripe_merchants
    (school_id, stripe_account_id, charges_enabled, payouts_enabled, verified_at)
  values (v_school_id, v_stripe_account, false, false, null);
end;
$link_test_merchant$;
```

Rileggere la tabella: deve esserci **una sola** riga per la scuola, con entrambi i flag `false` e `verified_at=null`. Non disabilitare o sovrascrivere un merchant preesistente con uno script di setup.

## 4. Secret e deploy delle funzioni Supabase

I segreti vanno salvati tramite **Supabase Dashboard → Edge Functions → Secrets**, mai nel repository o nel frontend:

- `STRIPE_SECRET_KEY`: chiave `sk_test_...` della **piattaforma sandbox BreakApp**, non chiave `sk_live_`.
- `STRIPE_WEBHOOK_SECRET`: chiave di firma `whsec_...` dell'endpoint **Connect events**.
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY`: verificare le variabili iniettate dal runtime; la service role key è solo lato server.

Distribuire `stripe-checkout-individual` con controllo JWT e `stripe-webhook` con verifica JWT disattivata **solo perché** il codice verifica autonomamente la firma HMAC Stripe del corpo raw. Non cambiare questa regola per altre funzioni.

Endpoint dei webhook Connect:
`https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/stripe-webhook`

Eventi base: `checkout.session.completed`, `checkout.session.expired`, `refund.updated`. Gli eventi `checkout.session.async_payment_succeeded` e `checkout.session.async_payment_failed` devono essere attivati **solo dopo** aver distribuito e verificato la funzione di riconciliazione della PR #30.

Non incollare mai segreti, link di onboarding personalizzati o dati bancari nei ticket, nella chat o nei commit.

## 5. Criteri di sblocco

- Stripe riporta per il **merchant scolastico** `capabilities.card_payments=active` e `charges_enabled=true`; verificare nuovamente dal server.
- L'associazione `school_id ↔ acct_...` è univoca e il merchant è quello giuridicamente responsabile.
- Esistono funzioni Edge deployate, secret corretti e webhook Connect firmati correttamente.
- Solo a quel punto un amministratore può valutare l'attivazione del flag `school_stripe_merchants.charges_enabled` e registrare `verified_at` dopo una nuova verifica Stripe. Non farlo basandosi sulla sola esistenza dell'account.
- Registrare un ordine test, pagarlo su Checkout con carta di test, verificare importo e account destinatario, webhook ricevuto una sola volta e stato DB aggiornato **soltanto** dal webhook.
- Provare annullamento, sessione scaduta, pagamento al banco concorrente, errore Stripe, webhook duplicato e rimborso; non dichiarare completato prima dei riscontri.

## Note di sicurezza

- La sandbox non è un'autorizzazione a usare dati fittizi per l'onboarding reale.
- Il badge «Account abilitato» nel Dashboard può coesistere con **pagamenti sospesi**; contano le capability di pagamento effettive.
- Non attivare `sk_live_`, `charges_enabled` o incassi reali senza un merchant legalmente verificato e collaudo finanziario concluso.
