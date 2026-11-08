# Storico delle migrazioni Supabase

Dal 6 novembre 2026 i file in `supabase/migrations/` hanno **la stessa versione** registrata nello storico di Supabase (`supabase_migrations.schema_migrations`) del progetto `breakapp-dev`.

## Come è stato riallineato

- 18 file avevano un timestamp diverso da quello assegnato dal connettore al momento dell'applicazione. Il contenuto era identico (stesso hash MD5 del testo registrato): sono stati solo rinominati con versione e nome remoti.
- 3 file (`20261029191506`, `20261030171145`, `20261103102822`) hanno la stessa versione e lo stesso SQL del remoto; cambiano solo i commenti.
- 6 migrazioni applicate solo sul database ospitato (scheduler push e rimborsi, `revoke_cash_trigger_execute`) sono state aggiunte al repository con il testo registrato su Supabase.
- `20261105180000_school_staff_invitations` era applicata ma non registrata: ora è nello storico (il testo resta nel file del repository).
- La baseline storica `supabase/sql/01`–`31` è precedente allo storico CLI e resta applicata dalla CI nell'ordine di `database.yml`.

## Migrazioni solo per Supabase ospitato

`supabase/hosted-only-migrations.txt` elenca le migrazioni che richiedono `pg_cron`, `pg_net`, l'estensione `http` o Vault. La CI su PostgreSQL le salta; su Supabase sono già applicate.

## Applicare una nuova migrazione

1. Aggiungi il file `supabase/migrations/<versione>_<nome>.sql` e i test in `tests/db/`, poi aggiungi il test a `database.yml`.
2. Dopo il merge, applica il file a Supabase **mantenendo la stessa versione**: con la CLI (`supabase db push`) oppure eseguendo il SQL e registrando la riga in `supabase_migrations.schema_migrations` con la versione del file. Lo strumento `apply_migration` del connettore assegna un timestamp nuovo: se lo usi, rinomina subito il file con la versione registrata.
3. Controlla che `list_migrations` e `ls supabase/migrations` riportino le stesse versioni.
