# Accessi Google/Microsoft e politica Auth — 28 ottobre 2026

Il frontend usa Supabase Auth con PKCE, scelta esplicita dell’account e ritorno al percorso pubblicato. Microsoft richiede lo scope `email`; Google richiede `openid email profile`. Nessun segreto dei provider entra nel bundle Vite.

## Parametri del progetto attuale

| Campo | Valore |
| --- | --- |
| Progetto Supabase | `ynvswdyirngvdpudcikl` — BreakApp / breakapp-dev |
| Sito e ritorno dopo l’accesso | `https://ambrogiocorti.github.io/BreakApp/` |
| Callback da registrare presso entrambi i provider | `https://ynvswdyirngvdpudcikl.supabase.co/auth/v1/callback` |
| Origine JavaScript Google | `https://ambrogiocorti.github.io` |
| Provider Microsoft in Supabase | Azure |
| Tenant Microsoft per account personali e scolastici | `https://login.microsoftonline.com/common` |

Il callback dei provider è l’endpoint Supabase, mentre l’URL di ritorno dell’app è il sito BreakApp. Sono due impostazioni distinte. Eventuali domini futuri richiedono URL di ritorno esplicitamente autorizzati.

## Attivazione dei provider

1. In Google Cloud configurare l’app OAuth e il client di tipo **Applicazione web**. Inserire origine e callback della tabella. Rendere l’app utilizzabile dal pubblico previsto; in modalità test, ammettere esplicitamente gli utenti che devono provarla.
2. In Supabase, Authentication → Sign In / Providers → Google, inserire **Client ID** e **Client secret**, quindi abilitare Google.
3. In Microsoft Entra registrare l’app con account in qualsiasi directory organizzativa e account Microsoft personali. Registrare il callback come **Web**, non come SPA: lo scambio con Microsoft avviene sul server Supabase.
4. Generare il segreto nell’app Entra e inserire **Application (client) ID**, **valore del segreto** e tenant `common` nel provider Azure di Supabase. La data di scadenza del segreto richiede rinnovo operativo.
5. Configurare i claim opzionali Microsoft `email` e `xms_edov` secondo la documentazione Supabase, per consentire al server di riconoscere email verificate.
6. In Supabase, Authentication → URL Configuration, impostare Site URL e Redirect URLs al valore esatto del sito riportato nella tabella.
7. Provare entrambi gli accessi con account reali autorizzati, annullamento del consenso e ritorno al sito. Verificare che gli Admin debbano ancora completare la 2FA.

Client secret, codici di autorizzazione e token vanno inseriti esclusivamente nei pannelli sicuri dei servizi, mai in chat, Git o variabili `VITE_*`. I pulsanti leggono lo stato pubblico dei provider: un provider disabilitato rimane indicato come non disponibile, senza simulare un accesso funzionante.

Riferimenti ufficiali: [Google](https://supabase.com/docs/guides/auth/social-sign-in/auth-google), [Microsoft Azure](https://supabase.com/docs/guides/auth/social-sign-in/auth-azure), [URL di ritorno](https://supabase.com/docs/guides/auth/redirect-urls).

## Eccezione per il dominio interno

La funzione Edge `admin-registration` gestisce esclusivamente email con dominio esatto `admin.breakapp.it`, indipendentemente dalle maiuscole. Crea l’identità con `email_confirm: true` e non invia un link di conferma. Il browser esegue poi il normale accesso con password. Altri domini conservano la registrazione Supabase standard e la verifica email prevista dal progetto.

Il servizio non accetta `app_metadata`, ruoli o iscrizioni a scuole e non modifica account già esistenti. La conferma dell’email non costituisce assegnazione del ruolo Admin. Il nome del dominio non è una regola di autorizzazione. Per gli account esistenti valgono password, assegnazioni e 2FA già configurate.

La funzione autentica la chiave pubblica del progetto usando le variabili native `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_ANON_KEY`. Usa `verify_jwt: false` perché la chiave pubblicabile non è un JWT; questo non conferisce privilegi di utente. I limiti sono 5 richieste al minuto per sorgente, 30 al minuto complessive e 200 al giorno complessive. La sorgente è rappresentata da un’impronta HMAC: nessun indirizzo IP o password è scritto nelle tabelle di controllo.

## Un solo nuovo Authenticator

Il comando per aggiungere un Authenticator di riserva è rimosso. La UI rifiuta un nuovo TOTP se esiste già un fattore verificato e può riavviare solo una configurazione non completata. Il trigger `breakapp_single_totp_factor` sul confine di persistenza Auth impedisce anche inserimenti diretti aggiuntivi e l’attivazione di un vecchio fattore di riserva ancora pendente. Il lock per utente serializza gli enroll concorrenti.

I fattori verificati preesistenti non vengono cancellati automaticamente: non è possibile stabilire quale dispositivo sia il principale dal solo record Auth. La verifica TOTP e i controlli AAL2 delle operazioni amministrative rimangono obbligatori. Il trigger dipende dalle colonne standard di `auth.mfa_factors`; gli aggiornamenti di Supabase Auth vanno accompagnati dai test d’integrazione inclusi nel repository.
