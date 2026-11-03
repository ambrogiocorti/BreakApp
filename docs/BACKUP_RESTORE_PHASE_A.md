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

## Prima prova di ripristino reale — 3 novembre 2026

Il titolare ha scaricato l'artifact della run GitHub Actions #41654538860 e verificato sul proprio PC Windows il checksum SHA-256 del file `breakapp-20261103T143157Z.dump.gpg`.

Nel test finale (script PowerShell `BreakApp-Test-Ripristino-v8.ps1`, esterno al repository), il dump e stato decifrato correttamente nel volume temporaneo Docker con GPG, riconosciuto da `pg_restore` di PostgreSQL 17 e ripristinato con transazione su `supabase/postgres:17.6.1.136`, container senza porte esposte e senza rete. `pg_restore` ha terminato senza errori; PostgreSQL rispondeva ai comandi successivi. Risultati delle interrogazioni aggregate: 4 righe in `auth.users`, 1 in `schools`, 1 in `bars`, 1 in `orders`, 2 in `storage.buckets`, e 0 tabelle pubbliche prive di RLS. Il controllo SQL aggiuntivo e terminato con `DO`. Container e volume dati temporanei eliminati.

**Ambito della prova:** restore PostgreSQL effettivamente riuscito e struttura base verificata. **Fuori ambito:** file binari Storage, autenticazione completa Auth/OAuth, servizio Edge Functions, webhooks Stripe, cron/secret manager, transazioni dal frontend contro il database ripristinato, ripristino su infrastruttura completamente vergine e accessi cross-tenant con utenti reali. La presenza di RLS non dimostra da sola la correttezza di tutte le policy. Non dichiarare il servizio interamente ripristinabile o pronto alla vendita sulla sola base di questo test.

Conservare l'archivio cifrato al di fuori di GitHub con copia separata della passphrase, e ripetere la verifica su backup periodici. Gli script di test v1-v8 non fanno parte del codice distribuito e la prova manuale non costituisce una suite automatica di restore per l'infrastruttura reale.
