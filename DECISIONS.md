# BreakApp — Decisioni tracciate

La fonte primaria è il Prompt Master v1 del progetto ChatGPT (non pubblicato qui).
Questo file registra modifiche e chiarimenti, senza sostituire i 171 requisiti confermati.

| Data | Decisione | Motivazione / riferimento |
|---|---|---|
| 2026-10-22 | HTML/CSS/JavaScript vanilla, Supabase e Stripe, multitenant per scuola | Specifica confermata nel Prompt Master. |
| 2026-10-26 | GitHub Pages per il frontend, in luogo di Cloudflare Pages; Vercel solo per prove precedenti | Richiesta aggiornata dal committente; `docs/GITHUB_PAGES_DEPLOYMENT.md`. |
| 2026-10-26 | Conti Stripe scolastici distinti e verificati; mai usare implicitamente il merchant piattaforma | Separazione delle responsabilità economiche; `docs/EXTERNAL_ACTIVATION_GATES.md`. |
| 2026-10-26 | Esiti Checkout asincroni riconciliati solo da eventi firmati; nessun incasso riconosciuto su `completed` non pagato | Invariante anti-doppio incasso; `docs/adr/0001-stripe-async-settlement.md`. |

Restano **da confermare con il gestore effettivo** il modello di responsabilità
Stripe Connect, gli accordi commerciali e i flussi fiscali. Nessuna voce in questa
tabella rappresenta l'approvazione di tali aspetti.
