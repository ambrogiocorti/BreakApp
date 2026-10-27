# BreakApp — Roadmap esecutiva

Fonte dei requisiti: `BreakApp_PROMPT_MASTER_v1.md` (documento di progetto non pubblico).
Il codice in repository è una base tecnica: **nessuna fase è certificata per la vendita o il go-live** senza i relativi collaudi.

## Stato al 26 ottobre 2026

| Fase | Stato | Risultato verificabile e lavoro residuo |
|---|---|---|
| 0 — Analisi | Parziale | Specifica funzionale definita; completare matrice tracciabilità requisiti e analisi GDPR/fiscalità. |
| 1 — Fondazioni | Parziale | Auth, MFA, ruoli, RLS, CI e webapp presenti; completare controlli tenant reali, deploy definitivo e ADR. |
| 2 — Bar base | Parziale | Catalogo, ordini individuali, disponibilità, QR e incasso al banco implementati; collaudo con utenti/stock reali assente. |
| 3 — Pagamenti Stripe | Parziale, disabilitata operativamente | Checkout individuale e rimborso totale in codice; merchant scolastico, secrets e webhook di test da attivare; completare pagamenti asincroni, rimborsi parziali e riconciliazione. |
| 4 — Gruppi | Parziale | Bozze e inviti presenti; mancanti ripartizione per riga, checkout singoli pagatori, conferma e rimborsi coordinati. |
| 5 — Operatività avanzata | Parziale | Calendario del servizio, avvisi e ticket presenti; ancora mancanti diversi casi limite, report, promozioni e procedure fiscali. |
| 6 — Offline affidabile | Fondazioni | Lease univoco, vault e coda di quarantena presenti; sincronizzazione di incassi e stock reali non abilitata. |
| 7 — Hardening e rilascio | Parziale | CI ed emulazioni multibrowser presenti; assenti collaudo fisico, prova ripristino, verifica privacy e pilota autorizzato. |

## Priorità attive

1. **P0 — Integrità economica:** completare riconciliazione dei pagamenti Stripe asincroni (successo/fallimento), prevenire doppi incassi e aggiungere test di evento tardivo/idempotenza.
2. **P0 — Attivazioni esterne:** merchant Stripe intestato al gestore reale; chiavi test Stripe/Web Push in secret storage; dispatcher schedulato; GitHub Pages; callback Auth. Vedi `docs/EXTERNAL_ACTIVATION_GATES.md`.
3. **P0 — Collaudo in sandbox:** due clienti, un barista, un admin MFA e due dispositivi fisici; prove di checkout, cassa, stock, QR, rimborsi, isolamento scuole, offline e push.
4. **P1 — Gruppi:** finalizzazione bozza con finestra di stock atomica, pagatori per singola riga, idempotenza e riconciliazione rimborsi.
5. **P1 — Offline:** riconciliazione server effettiva, revoche, risoluzione conflitti ed eccedenze Stripe/contanti.
6. **P1 — Uscita commerciale:** accordi merchant e responsabilità, privacy/GDPR (anche minori), fiscalità, accessibilità, osservabilità, backup e supporto.

## Criterio «completato»

Una funzione passa a **Completata** solo dopo codice funzionante, controllo server/RLS, test automatizzati, verifica manuale del caso reale, documentazione e deploy sul corretto ambiente. La build verde non dimostra un pagamento riuscito o l'idoneità alla vendita.

## Decisioni e limiti

- Stack applicativo invariato: HTML/CSS/JS vanilla, Supabase, GitHub e Stripe. La decisione di hosting del **26 ottobre 2026** è GitHub Pages (vedi `docs/GITHUB_PAGES_DEPLOYMENT.md`); Vercel resta ambiente di prova precedente.
- Le scuole incassano tramite merchant verificati distinti; non associare il conto della piattaforma alla scuola per convenienza.
- Nessuna chiave privata in repository o frontend. Nessun go-live con denaro reale prima del collaudo Stripe e delle verifiche legali/fiscali.
