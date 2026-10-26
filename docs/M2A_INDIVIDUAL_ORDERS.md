# BreakApp — Fase M2a: ordini individuali reali (scorte, prenotazione e incasso al ritiro)

**Stato: INTEGRATO NEL CODICE, NON ATTIVATO.** Il deploy non deve essere presentato come commercio attivo prima di eseguire e verificare SQL 04 sul progetto Supabase **BreakApp**. Nessun intervento sul progetto Supabase diverso da BreakApp.

## Cosa introduce
- `supabase/sql/04_individual_orders_core.sql`: posizione scuola, fasce di ritiro, scorte giornaliere, ordini, righe prodotti, pagamenti al banco append-only, audit, RLS.
- `submit_individual_order`: RPC con price snapshot dal server, controllo GPS, limite ordini non pagati, blocchi PostgreSQL sulle scorte e idempotenza richiesta.
- `cancel_individual_order`: cancellazione consentita prima del cutoff, ripristino scorte in transazione.
- `advance_individual_order`: transizioni autorizzate per il personale, verifica saldo zero prima di consegnare.
- `record_individual_counter_payment`: incasso contanti o POS esterno segnato dal personale solo per pagamento effettivo; una sola registrazione per ordine.
- UI reale catalogo → dettaglio → carrello → ritiro → pagamento al ritiro → riepilogo → geolocalizzazione → RPC; storico cliente e vista operatore.

## Attivazione corretta
1. Confermare che l'URL del progetto Supabase corrente sia quello di BreakApp: `https://ynvswdyirngvdpudcikl.supabase.co`.
2. Eseguire **solo dopo backup e audit** SQL 04 dal SQL Editor del progetto corretto (gli script 01 e 03 devono già esistere).
3. Configurare posizione reale della scuola: `latitude`, `longitude`; **non inventare coordinate**. Senza coordinate il backend rifiuta la prenotazione.
4. Configurare la data e le fasce di ritiro reali in `pickup_windows`, per il bar selezionato.
5. Configurare per ogni prodotto vendibile e giornata la tabella `daily_stock`: `capacity=null` significa illimitato, un numero intero positivo indica scorte limitate. Senza riga la vendita viene bloccata.
6. Verificare con 2 utenti di scuole diverse: utente cliente, barista e Admin 2FA; poi provare ordine di pochi pezzi con geolocalizzazione consentita.
7. Testare doppio click con stessa UUID, ultime scorte richieste contemporaneamente da due clienti, checkout fuori raggio, ordine di altra scuola, consegna non pagata, cancellazione dopo cutoff, conferma POS esterno non riuscita.
8. Solo dopo test reali, approvare merge e attivazione sulla build di test.

## Esempi SQL per amministratore del progetto (SOLO per dati reali)

```sql
-- Sostituisci LATITUDINE_REALE/LONGITUDINE_REALE con coordinate verificate,
-- mai con valori arbitrari. Il simbolo fra parentesi è segnaposto, non SQL eseguibile.
update public.schools
set latitude = <LATITUDINE_REALE>, longitude = <LONGITUDINE_REALE>
where slug = 'itsos-marie-curie';

-- Scegli una data futura reale per la fascia di ritiro:
insert into public.pickup_windows(school_id,bar_id,service_date,starts_at,ends_at)
select b.school_id,b.id, date '2026-11-02', time '10:50', time '11:10'
from public.bars b join public.schools s on s.id=b.school_id
where s.slug='itsos-marie-curie' and b.name='Bar scolastico'
on conflict (bar_id,service_date,starts_at) do nothing;

-- Configura stock solo dopo aver verificato data/bar/prodotti;
-- nessuna quantità fittizia deve essere caricata in produzione.
```

## Limitazioni esplicite
- Solo **clienti registrati**, non ancora ospiti con link privato.
- **Solo pagamento al ritiro**; Stripe e riconciliazione automatica fiscale non ancora implementati.
- La cassa digitale non sostituisce documenti fiscali e registratore esterno.
- Grandi ordini oltre soglie configurate sono rifiutati in sicurezza finché la coda di approvazione non è disponibile: **mai autoapprovati**.
- Questo modulo non include gruppi, coupon, notifiche push, chiusure straordinarie né offline operativo.
- La geolocalizzazione browser non è una prova antifrode inattaccabile.
- Senza tabella SQL non mostra prenotazioni attive, e il checkout è disabilitato.

## QA da completare prima di dichiarare il modulo pronto
- Applicazione migrazione e schema diff sul progetto corretto.
- Prove SQL/RLS cross-tenant con JWT distinti e assenza di bypass dalla Data API.
- Prove transazionali di concorrenza con due utenti e stock=1.
- Prove su Firefox/Chrome/Android/iOS, permesso GPS, timeout, sessione scaduta e prezzi aggiornati.
- Auditoria della registrazione incassi al banco e dei controlli fiscali.
