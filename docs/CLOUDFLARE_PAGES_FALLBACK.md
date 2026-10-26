# BreakApp — pacchetto Cloudflare Pages quando Vercel supera la quota

Al 26 ottobre 2026 l'API di Vercel ha restituito `402 api-deployments-free-per-day`; Vercel è soltanto l'ambiente di test. Lo stack confermato per il sito statico è Cloudflare Pages.

## Creazione del pacchetto

La GitHub Action `Cloudflare Pages emergency build package` esegue a ogni push in `main`:

1. `npm ci` e `npm run verify` (test JavaScript e build Vite).
2. Configura l'URL del progetto Supabase BreakApp e la **chiave publishable** (non una service key). Le autorizzazioni sono applicate da RLS/RPC.
3. Crea `breakapp-pages.zip` con **il contenuto della cartella dist alla radice**.
4. Lo pubblica come artifact GitHub scaricabile. Se il job o i test falliscono, non produce un pacchetto approvato.

## Pubblicazione temporanea tramite Cloudflare Dashboard

- Apri la pagina GitHub Actions della repository.
- Seleziona l'ultima esecuzione **verde** di `Cloudflare Pages emergency build package` su `main`.
- Scarica l'artifact `breakapp-pages.zip`.
- Nel tuo account Cloudflare apri **Workers & Pages → Create application → Pages → Direct Upload / Drag and drop**.
- Crea un progetto di test con nome distinto, ad esempio `breakapp-pilot-manual`, e carica il file ZIP.
- Conferma il deployment e verifica l'URL `*.pages.dev`.

**Attenzione:** Cloudflare non consente di trasformare successivamente un progetto Pages creato con **Direct Upload** in uno con integrazione Git. Perciò usare un progetto **temporaneo separato**, non il futuro progetto Pages principale con build automatica.

Se esiste già un progetto Cloudflare Pages con integrazione Git, non ricrearlo con Direct Upload: impostare il repository `ambrogiocorti/BreakApp`, branch `main`, comando `npm run build`, output `dist` e le due variabili pubbliche `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`.

## Verifiche dopo upload

- Login con utente registrato e MFA Super Admin `breakapp.app@gmail.com`.
- Il Super Admin NON deve vedere Cliente come opzione.
- La sezione Piattaforma deve mostrare le operazioni per assegnare personale, calendario, fasce e stock.
- Formati allergeni e scorte devono aggiornare il progetto Supabase corretto.
- Inserire orari, personale, ingredienti e scorte **reali**, non esempi.
- Testare con Cliente e Barista separati prima di utilizzare denaro reale.

**Il pacchetto è una build software:** non rende implementati gruppi, Stripe, modalità offline e le altre funzionalità del Prompt Master ancora aperte.

Documentazione Cloudflare: https://developers.cloudflare.com/pages/get-started/direct-upload/
