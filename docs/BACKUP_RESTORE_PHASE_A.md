# Backup cifrati e ripristino

Il workflow `encrypted-backup.yml` è predisposto ogni giorno alle 02:17 UTC. Richiede due GitHub Actions Secrets: `SUPABASE_BACKUP_DB_URL` (connessione server/pooler di sessione compatibile con pg_dump) e `BACKUP_PASSPHRASE` (almeno 32 caratteri, custodita separatamente dagli archivi). In assenza di configurazione il job fallisce esplicitamente; non viene dichiarato un backup riuscito.

Gli strumenti PostgreSQL 17 esportano schemi `public`, `app_private`, `auth`, `storage`, dati, RLS e privilegi. L'archivio viene cifrato con GnuPG AES-256 e integrità autenticata prima dell'upload; sul runner il file in chiaro è temporaneo, con permessi riservati e rimozione tramite trap. Solo `.dump.gpg` e checksum entrano negli artifact GitHub, conservati 30 giorni. Non pubblicare passphrase, connection string o contenuti decifrati.

Il workflow `database.yml` prova gli stessi script su dati sintetici: esportazione, cifratura, verifica della decifratura, restore in un database separato e controlli di dati, RLS, privilegi e indici FK. Il normale dump/restore viene provato anche separatamente. I ruoli globali esistono nello stesso cluster di test: questo non dimostra il ripristino dell'intero servizio Supabase su infrastruttura vergine.

## Verifica e restore separato

Eseguire `bash scripts/verify-backup.sh /percorso/archivio.dump.gpg` con la passphrase caricata dal secret manager. Senza `RESTORE_TEST_DB_URL` autentica l'archivio e ne verifica l'indice, senza applicare dati.

Per la prova di ripristino, creare un database usa e getta con ruoli Supabase ed estensioni compatibili e impostare `RESTORE_TEST_DB_URL`. Lo script rifiuta un target che contenga già oggetti applicativi: non usarlo contro produzione. L'operazione è transazionale e fallisce sul primo errore. Dopo il restore eseguire verifiche di isolamento tenant, login, ordini, ledger, cash, cron e rimborsi in un ambiente isolato, con invii e provider reali inizialmente disabilitati.

## Elementi esterni all'archivio

I metadati Storage sono nel dump, i byte dei file nei bucket no: predisporre una copia separata cifrata. Conservare versione del repository, Edge Functions, configurazione Auth/OAuth, DNS, webhook, dipendenze e procedura di riattivazione del cron. Vault e segreti di provider non sono inclusi; rifornirli dal secret manager e ruotarli prima della riapertura. Non copiare chiavi in Git.

Prima della vendita: configurare i segreti, eseguire il primo backup reale, misurarne dimensioni/quote e tempi, completare un restore in un progetto separato e registrare responsabile, RPO/RTO e conservazione dei dati autorizzati. Gli artifact GitHub e i piani gratuiti hanno quote: verificarle sul volume reale del pilota.
