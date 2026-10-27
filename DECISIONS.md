# Decisioni tecniche

## Requisiti conservati

Frontend vanilla, tenant isolation, autorizzazioni server, TOTP Admin, denaro in centesimi, rimborso al pagatore originale, un dispositivo offline per Barista, autonomia massima otto ore, blocco dopo cinque minuti di inattività e cinque minuti dopo cinque PIN errati. Nessuna attivazione fittizia di Stripe.

## 27 ottobre 2026

- Scelta implementativa: un turno aperto per bar; il passaggio richiede il conteggio del precedente. Incassi senza turno restano espliciti. Più casse fisiche nello stesso bar richiederanno una risorsa cassa dedicata.
- Conteggio confermato immutabile; rettifiche come nuovi movimenti Admin con 2FA e motivazione.
- Eventi offline cifrati con sequenza IndexedDB atomica. Una revisione non contabilizzata conserva i dati anche sul dispositivo.
- Cronologia delle generazioni dei dispositivi per attribuire la scuola originale ai dati pendenti; revoca senza cancellazione dell'attività fisica.
- VAPID e token del cron in Supabase Vault. Recupero segreti solo backend; cron ospitato ogni minuto, nessun segreto nel repository/frontend.
- Rimborso confermato dal webhook firmato. Retry limitati e distanziati; errori definitivi/esauriti segnalati ad Admin e pagatore.
- CSV neutralizza formule; XLSX conserva testo letterale e importi numerici. Report senza identità pagatori o token QR.
- Vercel resta anteprima; GitHub Pages sito di test già esistente; compatibilità Cloudflare mantenuta.
