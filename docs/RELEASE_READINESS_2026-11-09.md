# BreakApp — verifica prima della vendita (9 novembre 2026)

Questo documento distingue **codice implementato**, **configurazione ospitata** e
**collaudo sul campo**. Una build locale riuscita non certifica un servizio pronto
per una scuola reale. I dati della scuola DEMO e le carte di test non devono mai
produrre addebiti reali.

## Modifiche in questa proposta

- **Posizione configurabile:** Admin scuola con 2FA può richiedere o disattivare
  il GPS alla conferma della prenotazione, con default `true`, controllo nella
  RPC server e audit della modifica. Accesso ai gruppi sempre libero da GPS.
- **Rimborsi fisici:** controllo anticipato del turno di cassa del personale;
  guida alla sezione cassa se manca. La restituzione va registrata soltanto dopo
  aver davvero dato i soldi; il POS esterno si storna separatamente. Il vincolo
  server su un turno di cassa aperto non viene rimosso.
- **Notifiche:** centro avvisi compatto e accessibile; contrassegno di lettura,
  stato del dispositivo, istruzioni di installazione iOS, tap dalla push verso
  la sezione corretta. Test automatici di logica e build disponibili.
- **Banco:** accesso rapido alla cassa, ricerca `Ctrl/Cmd+K`, controlli e testi
  più chiari. Su telefono si costruiscono solo le schede della colonna selezionata,
  evitando di disegnare centinaia di ordini nascosti. È un'ottimizzazione concreta
  del rendering, non un collaudo prestazionale o una revisione totale dell'offline.

## Blocchi da chiudere

| Area | Stato | Prova richiesta per il via libera |
|---|---|---|
| Migrazioni Supabase | Applicate in `breakapp-dev` il 9/11, controlli SQL in CI verdi | Prova manuale Admin scuola A/B e politica GPS con telefono reale |
| Deploy frontend e Edge | `push-dispatch` v13 distribuito sul DEV; frontend da unire/pubblicare | Nuova versione visibile su URL ufficiale, RPC e dispatcher coerenti |
| Stripe DEMO | Merchant distinto da ITSOS associato; `charges_enabled` e `payouts_enabled` attivi nel DB DEV | Checkout e rimborso con carte TEST e webhook firmati, nessun addebito live per DEMO |
| Stripe scuole reali | Configurazione merchant e legittimazione da verificare | Account connesso abilitato, pagamenti/rimborsi reali riconciliati |
| Push desktop/Android/iOS | Cron Supabase e chiamate HTTP 200 osservati; **0 sottoscrizioni attive** al controllo del 9/11 | Attivare una sottoscrizione TEST, verificare recapito con app aperta/chiusa, permessi revocati e account alternati |
| Offline banco | Automatismi e coda esistono; prove fisiche da completare | Tablet disconnesso, cambio dispositivo, incassi, doppio pagamento, replay e conflitti |
| Cassa e rimborsi | Vincolo turno implementato; flusso fisico da provare | Barista apre/chiude cassa, restituzione tracciata, POS manuale, riconciliazione Admin |
| Multi-scuola e sicurezza | Test già presenti; accettazione da aggiornare | Audit RLS/ruoli/2FA, accessi incrociati negativi e dati sensibili |
| Backup e ripristino | Script/test CI presenti; prova produzione da firmare | Backup cifrato, ripristino reale su ambiente isolato, tempi e retention |
| Dispositivi, accessibilità, stabilità | Da completare | Matrice mobile/desktop, accessibilità tastiera/screen reader, carico a intervallo |
| Documentazione commerciale e dati | Da completare con titolare/consulenti | Contratti, privacy/GDPR, ruoli del trattamento, assistenza, SLA, prezzi e fatturazione |

**Regola di pubblicazione:** finché rimane un blocco su addebiti, isolamento
delle scuole, rimborsi, disponibilità offline o dati personali, BreakApp deve
essere presentata come **pilota controllato**, non come piattaforma pronta
per la vendita senza limitazioni.

Per la matrice fisica di prova si veda `docs/PUSH_AND_DEVICE_RELEASE_GATE.md`.
