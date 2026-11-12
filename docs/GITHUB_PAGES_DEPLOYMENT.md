# BreakApp — GitHub Pages (hosting attivo scelto dal committente)

**Decisione aggiornata il 26 ottobre 2026:** utilizzare **GitHub Pages** per il frontend, al posto della scelta precedente Cloudflare Pages. Lo stack applicativo e le autorizzazioni backend restano invariati.

## Deploy automatico

Il workflow `.github/workflows/github-pages.yml` esegue `npm ci`, test e build, prepara il service worker e il manifesto PWA per un URL del tipo:

`https://ambrogiocorti.github.io/BreakApp/`

e distribuisce il contenuto di `dist` con `actions/deploy-pages` tramite OIDC. Non richiede chiavi Stripe, service-role o altre credenziali segrete nel browser.

**Configurazione verificata:** per la repository `ambrogiocorti/BreakApp`, GitHub Pages usa **Settings → Pages → Build and deployment → Source → GitHub Actions**. Il sito di test è attivo; su una nuova repository la sorgente Pages va comunque configurata dall'account proprietario.

**Sito senza dominio personalizzato:** lasciare il valore predefinito `GITHUB_PAGES_BASE=/BreakApp/`. Se in futuro si sceglie un dominio personalizzato su GitHub Pages, impostare la repository Actions variable `GITHUB_PAGES_BASE` a `/`, quindi eseguire il workflow di nuovo.

## Supabase Auth

Una volta attivo l'URL, impostare in Supabase `Authentication → URL Configuration → Redirect URLs` un URL consentito `https://ambrogiocorti.github.io/BreakApp/` (o il dominio personalizzato effettivo).

I provider OAuth Google e Microsoft potrebbero richiedere anche le rispettive impostazioni di redirect secondo il provider. BreakApp usa la propria origine nel redirect di accesso; pertanto questa configurazione è fondamentale per il funzionamento con Pages.

## GitHub Pages e backend

GitHub Pages ospita **soltanto file statici**. Non può eseguire in modo sicuro webhook Stripe, rimborsi, dispatcher Web Push o API amministrative con segreti.

Tutte queste funzioni devono risiedere in Supabase Edge Functions e Postgres con RLS/RPC. Non inserire mai `STRIPE_SECRET_KEY`, chiavi di firma webhook, `SUPABASE_SERVICE_ROLE_KEY`, chiave VAPID privata o PIN offline nel frontend, workflow Vite o file pubblici.

## Cache / PWA

- Manifest PWA `start_url`, `scope` e icone vengono riscritti rispetto al base path.
- Il service worker viene registrato alla directory propria dell'app e non tenta di controllare altri siti o cartelle.
- La cache offline del service worker contiene **solo la shell e asset statici**, non autorizza ancora incassi o consegne offline.
- Un `404.html` permette fallback statico delle route (il router attuale utilizza hash URL).

## Condizioni prima dell'utilizzo reale

Testare accesso, 2FA, recupero email e permessi dopo l'attivazione del sito, poi ordine Cliente, preparazione Barista e contabilità. Il fatto che una build GitHub Actions sia verde non costituisce un test E2E in produzione.

**Nota di sicurezza:** GitHub Pages ignora `public/_headers`. Per questo la build inserisce la Content Security Policy in un tag `<meta http-equiv="Content-Security-Policy">` subito dopo il charset (`scripts/content-security-policy.mjs`): script, stili, font e worker solo dallo stesso sito; immagini e connessioni anche verso l'origine Supabase indicata da `VITE_SUPABASE_URL`; nessun `object`, `base-uri` e `form-action` limitati al sito. Un tag `<meta>` non può applicare `frame-ancestors`, `X-Frame-Options`, `X-Content-Type-Options` né `Referrer-Policy`: queste protezioni restano in `public/_headers` per un hosting che le supporti. Le policy RLS e RPC restano obbligatorie.
