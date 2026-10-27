# Roadmap operativa

Aggiornata il 27 ottobre 2026. La specifica privata rimane la fonte dei requisiti.

| Area | Presente e verificata nel codice | Da completare o collaudare |
| --- | --- | --- |
| Account | Ruoli tenant, TOTP, Super Admin esclusivo | OAuth configurato e percorso ospite completo con recupero privato |
| Catalogo/stock | Prodotti, allergeni, immagini, scorte per giorno, conflitti e vincoli atomici | Carico reale durante un intervallo scolastico |
| Ordini | Prenotazione individuale, GPS, QR, preparazione, incasso/consegna | Modifiche con differenze economiche, sostituzioni e nuovi orari |
| Gruppi | Inviti, coordinatore, carrelli, conferma e ritiro unico | Percorso ospite ed eccezioni complete |
| Stripe | Checkout/webhook, allocazioni, rimborso originale e retry controllati | Merchant abilitato, chiave test e webhook secret, pagamento/rimborso sandbox effettivi |
| Grandi ordini | Soglie configurabili, blocco prudente della conferma non gestita | Coda senza riserva, presenza Barista, limite attivazioni, lease 10 minuti e ripianificazione |
| Offline | Vendite itemizzate, ritiri individuali odierni, PIN/cifratura, ordine causale, turni e quarantena | Gruppi offline, cambio operatore offline completo e prove fisiche di revoca/perdita/reinstallazione |
| Cassa | Fondi, movimenti, conteggio, chiusura immutabile e rettifica | Cambio turno reale e recupero di eventi tardivi nel pilota |
| Report | Aggregati per scuola, gruppi, contanti/POS/Stripe, rimborsi, CSV/XLSX/PDF | Verifica contabile con il gestore e analisi aggiuntive |
| Comunicazioni | Annunci tenant, centro notifiche, preferenze per categoria, revoca dispositivo, promemoria ritiro/chiusura idempotenti, VAPID e cron con audit HTTP | Consegna su Android/iPhone fisici e verifica volumi nel pilota |
| Promozioni | Non implementate | Coupon, bundle e prezzi promozionali atomici |
| Scuole | Strumenti Super Admin per personale e pilota | Onboarding autonomo completo di un nuovo istituto |
| Backup | Restore di database temporaneo in CI | Backup giornaliero cifrato esterno e ripristino del servizio reale |
| Rilascio | Build, test e distribuzione automatica | Collaudo di tutti i requisiti, pilota, accessibilità e accordi operativi |

## Ordine di completamento

1. Eseguire il ciclo finanziario Stripe sandbox con credenziali e merchant operativi.
2. Completare grandi ordini, modifiche/eccezioni e promozioni con test finanziari.
3. Completare ospiti, onboarding, offline condiviso e gruppi offline.
4. Attivare backup separati, collaudare dispositivi e seconda scuola, validare il rilascio commerciale.

Una dipendenza esterna non rende completati i moduli di codice ancora mancanti.
