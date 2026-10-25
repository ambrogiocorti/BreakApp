# BreakApp — Audit iniziale codice e infrastruttura (2026-10-25)

## Verifiche effettuate (sola lettura)
- Repository `ambrogiocorti/BreakApp`, accessibile, default `main`, ultimo commit `6733993` (2026-10-23).
- Ultimo workflow GitHub Actions sul commit: **success**.
- Progetto Vercel `breakapp`, ultimo deployment sul medesimo commit: **READY**, URL di test `https://breakapp-smoky.vercel.app/`.
- Inventario dei file mediante API GitHub: `index.html`, `src/css/base.css`, moduli `src/js`, `supabase/sql/01..03`, `tests/unit`, `public/sw.js`, `manifest.webmanifest`.
- Codice esaminato: `index.html`, `src/js/main.js`, Auth/MFA, accesso/ruoli, catalogo e menu pubblico, SQL principali, CI, Vercel config, tests e README.
- Il deployment `READY` e' un risultato di piattaforma, non un test manuale della pagina. La richiesta web automatizzata del dominio non e' riuscita: **accessibilita' da browser da verificare**.

## Implementazione attuale (analisi statica, NON QA live)
| Area | Evidenza | Giudizio |
|---|---|---|
| Build/CI | `npm run verify` esegue sintassi, unit test, Vite build | Esistente; esito CI verde |
| Accesso | login/signup email/password, provider Google/Microsoft, logout | Codice presente; test provider end-to-end mancanti |
| Scuole/ruoli | query `school_memberships`, `role_assignments`, `bars` con RLS | Codice e SQL presenti; RLS multiutenza non verificata live |
| MFA Admin | TOTP Supabase, check `aal2` nelle policy CRUD | Codice e SQL presenti; verifica negativa DB da fare |
| Catalogo | CRUD `categories/products`; soft visibility; menu pubblico | Parziale: mancano media, ingredienti, allergeni e ordinamento UX |
| PWA | manifest+service worker cache shell/static | Shell presente, nessun offline business |
| Ordini/cassa/pagamenti/gruppi | Tabelle, API e UI operative assenti | Da implementare |

## Gap e rischi confermati nel codice
1. `index.html` apre **landing/hero**, accesso via anchor `#accesso`, contrario alla decisione UX di app login-first.
2. `products` non contiene media/ingredienti/allergeni strutturati; mancano disponibilita' giornaliere.
3. `vercel.json` imposta `Permissions-Policy: camera=()`: blocca l'accesso alla camera per un futuro scanner QR.
4. CSP `img-src 'self' data: blob:` non copre in generale immagini ospitate su Supabase Storage con host esterno: progettare allowlist mirata se si usa quel CDN.
5. CI testa utility JavaScript ma non flussi completi, transazioni e policy RLS con due utenti/tenant distinti.
6. Mancano `DECISIONS.md`, `ROADMAP.md`, registro ADR e politiche di release; questo PR documentale ne crea una base.
7. `README.md` include indicazioni di setup non aggiornate e afferma che l'hosting definitivo e' da stabilire; il Prompt Master sceglie Cloudflare Pages.

## Ambito non verificato
- Lo schema effettivamente migrato nel **nuovo account** Supabase dedicato a BreakApp; nessuna query SQL su quel DB in questa sessione.
- Disponibilita' e configurazione funzionante dei provider OAuth nel progetto dedicato.
- Esecuzione browser e corretto rendering sui dispositivi finali.
- Risultati reali dei test di permessi con accounts clienti/admin di due scuole.
- Quota e sostenibilita' piani free, Stripe Connect e compliance da accertare con informazioni correnti prima di implementare.

## Nessuna alterazione dei servizi
Questo audit non modifica dati, schemi, ambienti, deployment, autorizzazioni, pagamenti o ordini. La successiva implementazione avverra' in PR separati, con review e test.
