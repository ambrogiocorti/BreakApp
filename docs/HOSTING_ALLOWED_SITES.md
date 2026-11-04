# Indirizzi autorizzati per hosting e pagamenti

Aggiornamento 04/11/2026: questa configurazione è distribuita nel progetto
Supabase DEV. I preflight delle cinque funzioni restituiscono 204 per l'origin
GitHub Pages predefinito e 403 per un origin estraneo; le quattro funzioni
Stripe rifiutano con 401 le richieste senza sessione. La chiave push pubblica
risponde nel DEV. Non è ancora una prova da Cloudflare Pages.

Le funzioni Stripe e `push-public-key` leggono dal server la variabile
`BREAKAPP_ALLOWED_SITE_URLS`. Il valore è un elenco separato da virgole di URL
base completi, HTTPS, ciascuno con il percorso pubblico della PWA. Esempio:

```text
https://ambrogiocorti.github.io/BreakApp/,https://example.pages.dev/
```

`example.pages.dev` è soltanto un esempio: sostituirlo con l'indirizzo reale
del progetto Cloudflare Pages prima di configurarlo. Se la variabile è assente
o vuota, l'unico sito autorizzato rimane `https://ambrogiocorti.github.io/BreakApp/`.
Se è presente, elencare esplicitamente **tutti** i siti da mantenere abilitati;
non usare wildcard, credenziali, query o frammenti. Due percorsi diversi sullo
stesso origin non sono ammessi perché l'header Origin non distingue i percorsi.
Una configurazione non valida rifiuta le richieste anziché allargare l'accesso.

La funzione sceglie soltanto l'URL base associato all'origin configurato: i
redirect di Checkout e onboarding non accettano URL forniti dal client. Una
sessione Stripe già creata conserva i propri redirect originali: completare il
pagamento dal sito che l'ha avviata. Le chiavi Stripe restano nel backend e la
configurazione non abilita pagamenti LIVE.

Per attivare Cloudflare Pages occorre comunque creare e verificare il sito,
pubblicare la build con le variabili pubbliche corrette, configurare su
Supabase Auth gli URL di ritorno esatti e verificare anche Google/Microsoft,
service worker, push e checkout nell'ambiente di test. Le anteprime con URL
diversi richiedono un indirizzo esplicito; non abilitare domini arbitrari.
Questa impostazione CORS non sostituisce autenticazione, MFA, controlli di ruolo
o il gate di rilascio. La funzione di onboarding Stripe attuale resta
esclusivamente per il merchant dimostrativo TEST: non è onboarding multitenant
per merchant reali.
