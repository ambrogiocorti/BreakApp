# BreakApp — Backup cifrati dei file Supabase Storage

Stato al 3 novembre 2026: **due bucket presenti, zero oggetti in `storage.objects`**. È stato provato il restore PostgreSQL del 3/11; quel dump contiene **solo metadati** Storage, non i byte delle immagini/allegati. Il sistema di backup S3 qui descritto è implementato nel repository ma richiede credenziali e una prima esecuzione reale per essere considerato attivo.

## Architettura

- Cron GitHub Actions `Encrypted daily Supabase Storage backup` alle 02:37 UTC; anche avvio manuale.
- Con **credenziali S3 generate in Supabase Storage**, legge tutti i bucket, elenca tutti gli oggetti, scarica i byte e verifica che ogni file corrisponda all'elenco e alle dimensioni attese.
- Un manifest JSON, dentro l'archivio cifrato, include bucket, nomi logici degli oggetti, dimensioni e SHA-256. Il job **fallisce** se manca un oggetto, se il nome non è sicuro o se i byte superano il limite di 1 GiB previsto per GitHub Artifacts.
- L'intero snapshot viene cifrato con GnuPG AES-256 mediante `BACKUP_PASSPHRASE`. Il file tar in chiaro non viene mai scritto su disco; i file scaricati temporaneamente sono cancellati tramite trap nel runner effimero. La verifica decifra verso `tar -tf -` senza conservare un archivio in chiaro.
- GitHub conserva solo `.tar.gpg` e relativo `.sha256` per 30 giorni. **Nessun dato deve essere trattato come ripristinabile finché non si prova realmente il recupero.**

## Attivazione — dati da copiare solo nei secret manager

1. Aprire Supabase BreakApp `ynvswdyirngvdpudcikl` → **Storage → S3 Configuration**. Verificare che il protocollo S3 sia abilitato; creare una coppia di chiavi per l'ambiente di backup.
2. Annotare i valori **Endpoint** e **Region** visualizzati da Supabase (nessuna supposizione di regione). In GitHub → Settings → Secrets and variables → Actions → **Variables** impostare:
   - `BREAKAPP_STORAGE_S3_ENDPOINT` = endpoint HTTPS Supabase che termina in `/storage/v1/s3`
   - `BREAKAPP_STORAGE_S3_REGION` = region visualizzata da Supabase, esempio `eu-west-1`
3. In GitHub → Actions → **Secrets** impostare:
   - `BREAKAPP_STORAGE_S3_ACCESS_KEY_ID` = Access Key ID S3
   - `BREAKAPP_STORAGE_S3_SECRET_ACCESS_KEY` = Secret Access Key S3
   - `BACKUP_PASSPHRASE` = **passphrase già esistente per backup database**, conservata anche in Bitwarden
4. Eseguire manualmente `Encrypted daily Supabase Storage backup` su `main`; attendere stato verde e artifact `encrypted-breakapp-storage-<run_id>`.
5. Scaricare e archiviare una seconda copia del file cifrato e del checksum in uno storage indipendente da GitHub e dal progetto Supabase. Custodire la passphrase separatamente.
6. Verificare la prossima esecuzione **schedulata** (non basta l'esecuzione manuale). Configurare notifiche GitHub per eventuali failure.

**Attenzione:** le credenziali S3 Supabase danno accesso completo ai bucket e bypassano RLS. Non inserirle nel frontend, nel repository, in chat o in log; limitarne la custodia ai secret GitHub; ruotarle se esposte. Non usare la `SUPABASE_SERVICE_ROLE_KEY` per questo backup: sono richieste solo credenziali S3.

## Verifica e ripristino

- Verifica iniziale: il job ha scaricato l'elenco e tutti gli oggetti, costruito il manifest, cifrato e caricato l'artifact. GitHub CI prova anche cifratura, lettura e rifiuto della password errata su dati **sintetici**.
- Per un test di restore, creare **un progetto Supabase di prova separato**, ricreare i bucket e caricare i file dall'archivio decifrato tramite Storage API/S3. Non scrivere direttamente in `storage.objects` e non copiare file manualmente nei dischi interni del server.
- Controllare che ciascun file di prova sia effettivamente leggibile, abbia SHA-256 corretto e sia soggetto alle policy di accesso desiderate. Un backup locale e un restore di database da soli non certificano questo passaggio.
- **Se il numero attuale di oggetti è zero**, un backup vuoto può avere esito positivo; ripetere la prova di recupero dopo aver caricato un file di test autorizzato, per evitare falsi positivi.
- Supabase Storage non offre versioning S3; per garantire recuperabilità da cancellazioni accidentali servono snapshot periodici e conservazione di più versioni indipendenti.
- I backup S3 e PostgreSQL sono acquisiti in momenti diversi: non costituiscono uno snapshot transazionale coordinato tra database e Storage. Per recupero dopo guasti importanti servono procedure di riconciliazione e prova con il cliente.

## Incidente S3 GetObject del 3 novembre 2026

La prima esecuzione del backup con un file di prova denominato `Screenshot 2026-10-27 155847.png` è fallita nella fase di download, mentre `ListBuckets` e `ListObjectsV2` restavano autorizzati. I log del server Supabase confermano **HTTP 403 `SignatureDoesNotMatch`** sulla richiesta GET firmata dal client AWS CLI 2.39.3 con runtime CRT. L'archivio non è stato creato né caricato, per evitare backup incompleti.

La correzione imposta in modo isolato per quel singolo runner AWS CLI `preferred_transfer_client = classic` e `addressing_style = path`. La modalità classic è documentata ufficialmente da AWS per trasferimenti S3 compatibili. I test CI verificano che la configurazione sia presente e che il manifest includa anche un nome oggetto con spazi. **Il successo con il servizio Supabase reale richiede una nuova esecuzione manuale con l'oggetto ancora presente**: non interpretare la CI verde come prova del download reale.

Se anche la seconda prova presenta un errore GET, consultare i `storage_logs` su Supabase, verificare il codice server ed evitare rotazioni inutili dei secret, visto che l'elenco dei bucket aveva già funzionato.

## Limitazioni operative

Il workflow rifiuta un inventario incompleto, oggetti con path non sicuri, file mancanti o snapshot oltre 1 GiB. Per dimensioni superiori o maggiore retention usare storage cifrato esterno con piano e quote adeguati, non disabilitare silenziosamente i controlli. Un backup completo di studenti deve rispettare nomine GDPR, requisiti di conservazione e accessi del gestore.

Documentazione ufficiale: [Supabase S3 Authentication](https://supabase.com/docs/guides/storage/s3/authentication), [Supabase S3 Compatibility](https://supabase.com/docs/guides/storage/s3/compatibility), [Copy Storage Objects](https://supabase.com/docs/guides/self-hosting/copy-from-platform-s3).
