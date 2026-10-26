# BreakApp — Prima barriera di sicurezza automatizzata (Fase A / P0)

**Stato:** controlli automatici aggiunti su database CI isolato; non sostituiscono
un penetration test o un audit delle 171 decisioni.

## Cosa controlla `tests/db/security-gates.sql`

1. Nessuna funzione `SECURITY DEFINER` negli schemi applicativi `public` e
   `app_private` deve essere eseguibile dal ruolo anonimo.
2. Tutte le funzioni privilegiate devono avere `search_path` esplicitamente
   vuoto, per evitare risoluzioni di oggetti alterabili dal chiamante.
3. Ogni tabella ordinaria pubblica deve avere RLS abilitata.
4. Checkout, rimborso e dispatcher push riservati al ruolo di servizio non
   devono essere eseguibili da `anon` o `authenticated`.
5. I ledger di pagamento, i merchant, i lease e gli eventi offline non devono
   essere accessibili direttamente con `SELECT` ai ruoli di frontend.
6. Un Admin della scuola A, con 2FA, non deve poter configurare la scuola B.

## Correzione concreta individuata

La prima esecuzione del gate ha rilevato che
`app_private.prevent_cash_stripe_overlap()` era ancora eseguibile dal ruolo
anonimo. Si tratta di una funzione trigger `SECURITY DEFINER`, che non ha
bisogno di essere invocata direttamente dagli utenti. Lo script incrementale
`supabase/sql/22_revoke_cash_trigger_execute.sql` elimina la concessione
superflua. La CI riesegue il gate dopo aver applicato tale script.

## Come interpretare le segnalazioni dei Supabase Advisors

- Le segnalazioni *authenticated SECURITY DEFINER function executable* non
  dimostrano automaticamente una vulnerabilità: molti RPC sono intenzionalmente
  accessibili a un utente autenticato per eseguire una transazione atomica,
  con controlli di identità, ruolo e tenant **all'interno** della funzione.
- I test automatizzati proteggono un minimo di invarianti, ma ciascuna funzione
  accessibile agli utenti deve essere revisionata nel merito e provata con
  ruoli diversi, sessioni anonime, utenti di altre scuole e 2FA non verificata.
- Gli indici mancanti sulle chiavi esterne sono un *rilievo prestazionale*, non
  di per sé una violazione di isolamento. La scelta degli indici va collegata a
  query reali, piano d'esecuzione e volumi di traffico, evitando aggiunte
  massicce e ridondanti senza misurazione.

## Per chiudere il gate commerciale di sicurezza

- Eseguire `get_advisors` su Supabase dev/test e confrontare i risultati con
  l'inventario degli RPC, registrando le eccezioni deliberate.
- Verificare tutte le tabelle esposte, le policy RLS, i permessi Storage e
  l'isolamento tra due scuole con account **reali** e dati di prova separati.
- Eseguire un test di carico concorrente su prenotazioni, scorte e pagamenti;
  raccogliere `EXPLAIN (ANALYZE, BUFFERS)` per identificare gli indici necessari.
- Nessun dato di minori o credenziale deve essere inserito nei fixture CI.
