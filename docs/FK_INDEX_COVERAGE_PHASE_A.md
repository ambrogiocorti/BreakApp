# BreakApp — Copertura indici delle chiavi esterne

La roadmap del 26/10/2026 riporta circa 50 avvisi sulle chiavi esterne prive
di indice. PostgreSQL crea un indice per le chiavi primarie o univoche
**referenziate**, ma non automaticamente per i campi che **referenziano**.
Gli aggiornamenti o le cancellazioni della riga padre possono pertanto dover
cercare nella tabella figlia senza un indice utile.

## Modifica

- `supabase/sql/23_fk_index_coverage.sql` esamina le FK di `public` e
  `app_private`; riutilizza un indice B-tree valido, non parziale, le cui
  prime colonne coincidono nell'ordine con la FK.
- Crea un indice solo dove manca una copertura equivalente. I nomi sono
  deterministici e la procedura è ripetibile.
- `tests/db/fk-index-coverage.sql` fallisce in CI se resta una FK scoperta.
- L'indicizzazione **non** sostituisce il profiling di query specifiche né
  dimostra il comportamento con 2.000 utenti concorrenti.

## Prima dell'applicazione su Supabase reale

Non eseguire questa migrazione nel mezzo di un intervallo scolastico.
`CREATE INDEX` ordinario può bloccare le scritture mentre costruisce
l'indice. Valutare il numero e la dimensione delle tabelle tramite
`pg_stat_user_tables`, `pg_indexes`, `pg_stat_statements` ed
`EXPLAIN (ANALYZE, BUFFERS)` su query rappresentative.

Su tabelle già popolose preparare una variante revisionata con
`CREATE INDEX CONCURRENTLY`, **fuori da una transazione**, una tabella alla
volta. Verificare disco, tempi e eventuali indici invalidi; attivare in una
finestra di manutenzione. Ogni indice aumenta anche il costo di INSERT/UPDATE.
La migrazione e i test CI non equivalgono a deploy Supabase live.

## Collegamento con le PR esistenti

PR #25 introduce lo script 21; PR #26 introduce lo script 22.
Questo incremento usa il numero 23, e deve essere applicato dopo entrambi
quando saranno integrati.
