# BreakApp — Checklist per avvio pilota reale

**Ambiente di test:** Supabase `ynvswdyirngvdpudcikl`; pubblicazione web tramite GitHub/Vercel. I flussi sono sottoposti a collaudo operativo prima dell'apertura commerciale.

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

I flussi applicativi di account/ospiti, scorte, ordini e gruppi, variazioni economiche, grandi ordini, ticket, promozioni, offline, cassa e report sono implementati. Lo stato verificabile e le dipendenze esterne sono in `ROADMAP.md`; le istruzioni sono in `COMPLETE_WORKFLOWS.md`.

Il pilota deve ancora certificare gli incassi/rimborsi presso Stripe con merchant e segreti operativi, OAuth dei provider scelti, backup reali con restore separato, push e revoche su dispositivi fisici, fiscalità e procedure privacy. Non confondere i pagamenti sintetici del database CI con transazioni presso Stripe.

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
