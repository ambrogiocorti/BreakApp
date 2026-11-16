# Sicurezza dei backup

## Problema

Il repository è pubblico. I workflow `encrypted-backup.yml` ed `encrypted-storage-backup.yml`
producono ogni notte un dump cifrato dell'intero database (e dello Storage) e lo caricano
come **artifact di GitHub Actions**. Su un repository pubblico quegli artifact sono
scaricabili da qualunque utente GitHub con accesso in lettura: l'unica barriera tra il
pubblico e tutti i dati è la robustezza della `BACKUP_PASSPHRASE`.

## Cosa è stato cambiato in questo PR

Entrambi i workflow ora **si rifiutano di girare se il repository è pubblico**: controllano
la visibilità via `gh api` e falliscono con un messaggio chiaro. Questo impedisce nuovi
backup scaricabili pubblicamente, ma **non rimuove** quelli già caricati né mette i backup
al sicuro altrove: servono i passi manuali qui sotto.

## Passi manuali richiesti (da fare su GitHub)

1. **Eliminare gli artifact già pubblicati.** In GitHub: `Actions` → esecuzioni di
   «Encrypted daily database backup» e «Encrypted daily Supabase Storage backup» →
   aprire ogni esecuzione e cancellare gli artifact (o eliminare le esecuzioni). Gli
   artifact hanno 30 giorni di conservazione, ma vanno rimossi subito.
2. **Ruotare i segreti**, perché i dump cifrati sono stati pubblici e la passphrase è
   l'unica protezione:
   - `BACKUP_PASSPHRASE`
   - `SUPABASE_BACKUP_DB_URL` (credenziali del DB usate per il backup)
   - `BREAKAPP_STORAGE_S3_ACCESS_KEY_ID` e `BREAKAPP_STORAGE_S3_SECRET_ACCESS_KEY`
3. **Ripristinare i backup in un luogo privato.** Due opzioni:
   - creare un **repository privato** dedicato e spostarci questi due workflow più gli
     script in `scripts/` che usano, **oppure**
   - rendere **privato** questo repository (Impostazioni → General → Danger Zone →
     Change visibility). Nota: la versione online su GitHub Pages resta pubblica anche
     con repository privato.

Finché uno di questi due passi non è fatto, i backup automatici restano disattivati (è
voluto): meglio nessun backup pubblico che un dump del database scaricabile da chiunque.
