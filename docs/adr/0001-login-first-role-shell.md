# ADR 0001 — Applicazione login-first con shell per ruolo

- **Data:** 2026-10-25
- **Stato:** proposto per implementazione; UX confermata
- **Contesto:** il frontend attuale contiene una landing page, mentre il committente ha scelto una webapp che si apre direttamente nel login.

## Decisione architetturale proposta
- Conservare stack HTML/CSS custom/JS ES modules e Vite solo come build tool.
- Route radice `/` → session gate: utente non autenticato = login; utente autenticato = contesto scuola/ruolo valido.
- Login desktop a due pannelli, mobile singolo; nessuna landing introduttiva.
- Shell cliente e personale differenziate per routing/permessi, con componenti grafici riusabili.
- Il client non stabilisce privilegi: riconfermare Auth, `school_memberships`, RLS e MFA per operazioni privilegiate.
- Gestire deep link (inviti, ticket, QR) senza perdere il percorso dopo autenticazione.
- Se un flusso backend non esiste, renderlo esplicitamente non disponibile e non falsificare interazioni/persistenza.
- Aggiungere route-state e test E2E in preview prima di proporre merge.

## Conseguenze
- Migrazione dei moduli `features/auth`, `catalog` e `menu` senza perdere gli accessi reali.
- Rimozione del `#accesso` come modalita' primaria di ingresso.
- Nessuna modifica alla privacy/accessibilita', a OAuth/MFA o alle regole di business confermate.
- Il merge verso `main` va autorizzato solo dopo QA su preview Vercel.
