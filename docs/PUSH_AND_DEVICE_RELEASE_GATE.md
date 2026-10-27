# BreakApp — Attivazione push e collaudo su dispositivi reali

Stato: **procedura preparata, NON eseguita su dispositivi fisici**.
Non dichiarare il prodotto pronto alla vendita finché tutti i gate essenziali non sono verdi.

## 1. Configurazione segreti (una tantum)

La funzione Supabase `push-public-key` restituisce HTTP 503 se manca
`VAPID_PUBLIC_KEY`. La GitHub Action `push-dispatch.yml` omette
volutamente la chiamata se manca `PUSH_DISPATCH_TOKEN`. Il codice non può
creare automaticamente segreti negli account senza accesso autenticato ai
rispettivi secret manager.

1. Generare una coppia VAPID con una versione attendibile di `web-push`
   (ad esempio, su un computer sicuro: `npx web-push generate-vapid-keys`).
   Proteggere la chiave privata; non committarla e non inserirla nei log.
2. Generare un token casuale separato di almeno 32 caratteri, ad esempio
   `openssl rand -hex 32`, e conservarlo in un gestore di password.
3. Nel progetto Supabase **ynvswdyirngvdpudcikl**, configurare i secret
   delle Edge Functions:
   - `VAPID_PUBLIC_KEY` — chiave pubblica generata
   - `VAPID_PRIVATE_KEY` — chiave privata corrispondente
   - `VAPID_SUBJECT` — indirizzo `mailto:` reale gestito dal titolare
   - `PUSH_DISPATCH_TOKEN` — token casuale del punto 2
   - `SUPABASE_SERVICE_ROLE_KEY` — gestito come secret server; non esporre al client
4. Nella repository `ambrogiocorti/BreakApp` → Settings →
   Secrets and variables → Actions, creare il repository secret
   `PUSH_DISPATCH_TOKEN` con **lo stesso valore** del progetto Supabase.
5. Verificare che `https://ynvswdyirngvdpudcikl.supabase.co/functions/v1/push-public-key`
   restituisca HTTP 200 e un `public_key` valido; non aspettarsi 200 prima
   di aver impostato i secret.
6. Eseguire manualmente la workflow `Push dispatcher schedule` dalla scheda
   Actions. Controllare che il job non sia "skipped", non segnali 401/503
   e che nessun valore segreto sia stampato nei log.

**Mai** committare le credenziali, incollarle in chat o rendere pubblica
la service-role key. La chiave VAPID pubblica può invece essere esposta.

## 2. Matrice di verifica fisica

Usare account di prova, ordini fittizi e, per Stripe, soltanto la sandbox.
Ripetere ogni scenario su dispositivi distinti, conservando screenshot,
data, browser/OS, log CI e identificativo build.

| ID | Dispositivo | Prova | Esito atteso | Esito osservato |
|----|-------------|-------|--------------|-----------------|
| PUSH-01 | Android Chrome, PWA installata | Consenso e sottoscrizione push | Subscription privata del proprietario | DA ESEGUIRE |
| PUSH-02 | Android Chrome, app completamente chiusa | Inviare notifica test dalla coda | Avviso OS con click che riapre BreakApp | DA ESEGUIRE |
| PUSH-03 | iPhone Safari, PWA aggiunta alla Home | Consenso e sottoscrizione push | Se il sistema supporta Web Push, subscription persistita | DA ESEGUIRE |
| PUSH-04 | iPhone, app chiusa | Notifica test su PWA installata | Avviso OS, nessuna richiesta di aprire prima la pagina | DA ESEGUIRE |
| PUSH-05 | Due account sullo stesso browser | Cambiare utente/subscription | Nessuna notifica privata dell'account precedente | DA ESEGUIRE |
| PUSH-06 | Browser con notifiche negate | Tentativo iscrizione | Messaggio chiaro, app resta utilizzabile | DA ESEGUIRE |
| GROUP-01 | Due telefoni, due utenti | Invitare, approvare, aggiornare carrelli | Isolamento righe per utente e soli totali aggregati per membro | DA ESEGUIRE |
| GROUP-02 | Due telefoni | Rigenerare invito e trasferire coordinamento | Vecchio invito invalido, nuovi permessi immediati | DA ESEGUIRE |
| OFF-01 | Tablet Barista | Attivare lease e passare offline | Operazioni cifrate, scadenza entro 8 ore | DA ESEGUIRE |
| OFF-02 | Tablet Barista | Cinque PIN errati | Blocco UI di 5 minuti | DA ESEGUIRE |
| OFF-03 | Tablet Barista | Salvare evento e riconnettere | Una sola acquisizione server, in quarantena | DA ESEGUIRE |
| OFF-04 | Due dispositivi Barista | Trasferire lease mentre il primo è disconnesso | Vecchia generazione revocata; evento dubbio in quarantena | DA ESEGUIRE |
| OFF-05 | Admin scuola, MFA attivo | Approva/rifiuta con motivazione | Audit immodificabile e nessun incasso automatico | DA ESEGUIRE |
| OFF-06 | Cliente, altro tenant o Admin senza MFA | Tentare review offline | RPC rifiutata | DA ESEGUIRE |
| PAY-01 | Stripe sandbox e POS di test | Riconciliare checkout/cash/rimborso | Nessun doppio incasso, webhook firmato e rimborso idempotente | DA ESEGUIRE |

## 3. Gate di rilascio

- [ ] Segreti Supabase e GitHub configurati nel loro secret manager
- [ ] GET `push-public-key` = 200 e dispatcher eseguito realmente
- [ ] PUSH-01–PUSH-06 con prove su dispositivi fisici
- [ ] GROUP-01–GROUP-02 con prove su dispositivi fisici
- [ ] OFF-01–OFF-06 con prove su dispositivi fisici
- [ ] PAY-01 e verifica merchant Stripe abilitato
- [ ] Flussi ancora mancanti (pagamenti di gruppo e contabilità offline) implementati
- [ ] Test di sicurezza, accessibilità, privacy, backup/ripristino approvati

**Importante:** i test Playwright emulati, i test SQL e la CI sono utili,
ma **non sostituiscono** il collaudo con app chiusa su smartphone/tablet
reali. Approvare un evento offline non equivale a registrare un pagamento.
