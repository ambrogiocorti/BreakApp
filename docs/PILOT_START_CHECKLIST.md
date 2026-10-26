# BreakApp — Checklist per avvio pilota reale

**Ambiente di test:** Supabase `ynvswdyirngvdpudcikl`; pubblicazione web tramite GitHub/Vercel. È un *pilota limitato*, non l'intera piattaforma del Prompt Master.

## Prima di aprire il bar agli studenti

1. Accedi come `breakapp.app@gmail.com` e completa la verifica TOTP. Il contesto rimane **solo Super Admin**.
2. Dal pannello **Piattaforma** scegli `ITSOS Marie Curie` e `Bar scolastico`.
3. Fai creare almeno un account Barista e un account Admin scuola da persone reali, con email confermata. In *Personale della scuola* inserisci ciascuna email e assegna il ruolo. L'Admin scuola deve configurare la propria 2FA. **Il Super Admin non deve assumere il ruolo Cliente**.
4. Compila gli **orari settimanali** reali, senza inventare aperture. La scuola ha attualmente un prodotto e una fascia storica; gli orari settimanali mancavano.
5. Per il giorno di ritiro crea una o più **fasce future** comprese negli orari e nel limite di prenotazione configurato. Non è ammessa la creazione di fasce in orari chiusi.
6. Imposta le quantità **fisiche effettivamente disponibili** per ciascun prodotto e giornata. Una capacità vuota significa illimitata e va scelta solo se realmente corretta. Lo stock pre-allocato non può essere ridotto sotto l'allocato.
7. Verifica e inserisci gli **ingredienti e allergeni documentati dal fornitore**, senza supporre che la lista vuota significhi assenza di allergeni. Con l'unico prodotto del catalogo attuale i dati non risultavano ancora compilati.
8. Fai accedere un Cliente di prova registrato, **distinto dal Super Admin**, all'interno del raggio GPS della scuola. Verifica catalogo, carrello, fascia, checkout e conferma.
9. Fai entrare il Barista autorizzato: `Confermato → In preparazione → Pronto`; poi registra esclusivamente un incasso **realmente ricevuto** in contanti oppure su POS esterno. Mai confermare come ricevuto un pagamento non incassato. Infine consegna via QR/numero.
10. Confronta ordine, stato, stock allocato, importo incassato e singola registrazione di pagamento con le tabelle Supabase. Esegui almeno due test a prodotto quasi esaurito, tentativo cross-school, blocco geolocalizzazione, nuovo invio ripetuto e browser senza scanner QR.

## Stato delle funzioni

| Modulo | Livello attuale |
|---|---|
| Auth e 2FA | Implementate, collaudo reale amministratori ancora necessario |
| Super Admin | Solo ruolo globale, provisioning personale e calendario/scorte nel pannello pilota |
| Cliente, catalogo, ordine individuale | Flussi reali disponibili previa configurazione reale delle fasce/scorte |
| Barista, pagamento al ritiro, ritiro QR | Flussi reali, richiedono account Barista e test su dispositivo |
| Supporto | Ticket individuali e allegati, senza notifiche push |
| Chiusure | Blocco sicuro se sono coinvolti incassi già registrati |
| Pagamenti online Stripe | Checkout individuale e rimborso completo implementati in test; merchant, secrets, webhook e collaudo da attivare |
| Gruppi e pagatori separati | Bozze gruppo implementate; pagamenti per riga e finalizzazione non implementati |
| Modalità offline con lease/revoche/sync | Lease e staging con quarantena implementati; esecuzione e riconciliazione di vendite offline non implementate |
| Promozioni, report completi, stampa fiscale | **NON IMPLEMENTATI** |

## Condizioni che impediscono il go-live completo

- Lo stato `READY` di una build Vercel attesta soltanto la pubblicazione, non la conformità al Prompt Master.
- Gli utenti devono testare realmente i dispositivi, l'accesso ai turni e la rete Wi-Fi del bar.
- La posizione GPS browser è falsificabile: non costituisce antifrode assoluta.
- È necessario verificare privacy/GDPR per account scolastici, informativa allergeni, procedure fiscali del POS e rimborsi.
- Non usare denaro o ordini di produzione senza test e supervisione di personale autorizzato.
- Non abilitare Stripe/gruppi/offline con mockup o transazioni simulate.

## Ruoli

- `Super Admin`: account globale esclusivo; può assegnare ruoli ad **altri utenti** confermati.
- `Admin scuola`: gestisce bar, catalogo, personale ove supportato, orari con 2FA.
- `Barista`: prepara e consegna, registra solo incassi effettivi.
- `Magazziniere`: scorte reali della scuola assegnata.
- `Cliente`: ordina; non deve coincidere con il Super Admin.

I test CI su PostgreSQL usano soltanto identificatori e utenti fittizi in un database isolato e non modificano il progetto reale.
