# BreakApp — Terminale Barista offline: coda cifrata e quarantena

## Implementato
- Area Barista dedicata «Operazioni offline», non accessibile da Cliente/Admin scuola/Super Admin.
- Ogni Barista chiede online al server il lease esclusivo: **un solo dispositivo autorizzato**, durata 8 ore. Il trasferimento revoca la generazione precedente sul server.
- PIN numerico 6–12 cifre; PBKDF2-SHA256 310.000 iterazioni con salt unico per derivare chiave AES-256-GCM. PIN e chiave **non vengono persistiti**. Il verificatore cifrato conferma il PIN prima della lettura del vault.
- IndexedDB memorizza soltanto eventi cifrati e metadati minimi (identificatore, contesto). Blocco dopo 5 minuti di inattività; blocco temporaneo dopo tentativi PIN errati.
- È possibile creare **bozze di operazioni di banco** senza nominativi o informazioni su studenti, con importo dichiarato (non incassato a sistema), poi inviarle alla RPC `stage_my_offline_event` con `request_key` idempotente.
- L'invio passa sempre a **quarantena sul backend**: server registra device/generazione e motivi di revisione; nessuna vendita, consegna, contabilità o scorta cambia automaticamente. Eventi successivi alla revoca non diventano mai definitivi senza controllo.

## Non implementato
- **Vendite offline definitive e consegna di ordini già pagati offline** non sono abilitate finché non esistono snapshot firmati, conflitti stock, offline QR, cassa e workflow Admin riconciliazione/verifica.
- Non è ancora possibile lavorare senza connettività **dopo la riapertura completa della PWA**: l'autenticazione e la selezione del contesto richiedono attualmente il server. La coda opera nell'app già aperta e autorizzata.
- I dati salvati come bozza **non sono scontrini o ricevute** e non generano impegni di incasso. Il Barista deve seguire la procedura di cassa effettiva del bar.
- Recupero PIN: non esiste backdoor, la perdita del PIN rende la coda locale non decifrabile. Non sovrascrivere dati locali pendenti finché non sono stati recuperati/verificati.
- Il browser/device clock non è attendibile: il server quarantina e un Admin dovrà validare. Il GPS non basta a provare identità.

## Verifiche
`tests/unit/offline-vault.test.mjs`: crittografia AES-GCM, PIN errato, cifrato alterato, ruoli autorizzati. `tests/db/offline-security.sql`: un solo lease corrente e quarantena al trasferimento, zero accessi a Cliente/Super Admin.

Il backend `staff_offline_leases` e `offline_events_inbox` sono stati installati e testati nella migrazione 16. Nel workflow attuale gli eventi offline non vengono mai applicati automaticamente al conto.
