# BreakApp — preparazione Cloudflare Pages di test

Il sito attualmente verificato è GitHub Pages, che il titolare ha scelto di
usare per ora. Questa guida resta disponibile per un'eventuale valutazione
futura: non è necessario configurare Cloudflare per il lavoro attuale. Per
qualsiasi futura prova usare un sito di **test** separato e dati fittizi; la
promozione commerciale richiede approvazione manuale e gate superati.

## Build con Git

1. Verificare se esiste già un progetto Pages per BreakApp. Se non esiste,
   predisporre un progetto di test collegato al repository
   `ambrogiocorti/BreakApp`, senza sostituire progetti esistenti.
2. Configurare Node.js 22.12 o superiore, comando `npm run build` e cartella di
   output `dist`. Per un sito alla radice lasciare `GITHUB_PAGES_BASE` non
   impostata: Vite usa `/`. La build deve ricevere le sole variabili pubbliche
   `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` del progetto DEV.
   Nessuna service-role key, chiave privata o secret Stripe va nel frontend.
3. Verificare build e test su GitHub prima di distribuire; un deployment
   automatico del progetto di test non equivale a promozione in produzione.
4. Una volta noto l'URL HTTPS effettivo, configurarlo sul server insieme
   all'indirizzo GitHub Pages esistente secondo `HOSTING_ALLOWED_SITES.md`.
   Configurare separatamente i redirect autorizzati di Supabase Auth e i
   provider OAuth; non assumere che le anteprime con nomi variabili siano già
   autorizzate.

La vecchia istruzione che rimandava alla workflow `Cloudflare Pages emergency
build package` è superata: non è presente tra le workflow attuali. In caso di
Direct Upload, verificare prima le limitazioni Cloudflare: un progetto creato
con quel metodo non si converte successivamente in progetto con integrazione
Git. Non creare un secondo progetto senza aver controllato quelli esistenti.

## Verifica del sito di test

- Aprire il sito dalla sua origine effettiva e verificare caricamento, CSP,
  service worker, installazione e percorsi PWA.
- Provare accessi email, Google e Microsoft con account di prova; verificare
  la 2FA amministrativa, i redirect e l'isolamento tra scuole.
- Configurare una scuola di prova con catalogo, orari, fasce e scorte;
  verificare un ordine completo e il relativo rimborso Stripe TEST con ruoli
  distinti. Provare anche gruppi, offline e notifiche su dispositivi fisici.
- Non usare dati o incassi reali finché backup, privacy, fiscalità, merchant,
  collaudi e accettazione del gestore non siano completati.

Riferimenti: https://developers.cloudflare.com/pages/configuration/build-configuration/ e
https://developers.cloudflare.com/pages/get-started/git-integration/.
