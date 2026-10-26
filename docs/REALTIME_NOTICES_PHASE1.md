# BreakApp — Avvisi in-app in tempo reale (incremento 15)

Questo incremento **non equivale a Web Push ad app chiusa**. Aggiunge avvisi reali, persistiti su Supabase, letti attraverso RLS e consegnati alla schermata con Realtime.

## Eventi backend reali

- Stato di ordine individuale modificato: nuovo avviso al cliente proprietario.
- Nuova richiesta di ingresso in gruppo: avviso al coordinatore.
- Richiesta gruppo approvata/rifiutata: avviso al partecipante interessato.
- Nuova risposta dell'Admin a un ticket: avviso al titolare del ticket.
- Chiusura straordinaria: conserva l'avviso già previsto dalla migrazione 07.

Gli avvisi vengono emessi dalla stessa transazione del cambio di stato tramite trigger PostgreSQL. I clienti possono leggere e segnare come letti **soltanto i propri avvisi**.

## Frontend

- Pulsante Notifiche nell'intestazione, contatore non letti e centro storico.
- Abbonamento Supabase Realtime `postgres_changes`, filtrato per utente autenticato.
- Recupero periodico ogni 60 secondi e quando la scheda torna visibile come fallback.
- L'utente può dare **consenso esplicito** alle notifiche di sistema mentre BreakApp è aperta.
- Il service worker apre/focalizza l'app quando un avviso foreground viene cliccato.

## Non ancora implementato

- Push VAPID recapitata quando browser/PWA sono **completamente chiusi**; serve chiave VAPID privata in Supabase Secrets, tabella subscription, dispatcher Edge Functions, retries e ricevute reali.
- Reminder programmati 5 minuti prima del ritiro, scadenza bozza gruppo -1h, strategie silenziose per browser che limitano le push.
- Notifiche personalizzate di staff/Barista e digest, con rate-limit per singola scuola.
- Qualsiasi promessa di recapito istantaneo quando il dispositivo è offline o il browser blocca notifiche.

## QA

`tests/db/realtime-notices.sql` prova i trigger richieste/approvazione, la visibilità per utente e la pubblicazione Realtime. Il collaudo della notifica di sistema richiede browser reale, permessi e test su GitHub Pages.
