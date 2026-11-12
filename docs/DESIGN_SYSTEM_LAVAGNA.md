# Design system «Lavagna e tuorlo»

## Principi
- Una sola azione primaria per schermata o per ticket. Le azioni rare stanno in «Altre azioni».
- Niente decorazioni: niente gradienti vistosi, vetro, ombre pesanti, card annidate, badge senza significato, numeri inventati.
- Mobile-first: tab bar in basso e menu «Altro» sui telefoni, barra laterale fissa da 1024px.
- Lo stato si legge da testo, non solo dal colore (badge con etichetta, passi d'ordine con nome).

## Colori (`src/css/tokens.css`)
| Token | Chiaro | Uso |
|---|---|---|
| `--lavagna` | `#1d4b40` | azioni primarie, navigazione attiva |
| `--tuorlo` | `#f2b92b` | marchio, indicatore attivo, carrello (con parsimonia) |
| `--canvas` / `--surface` | `#f6f4ef` / `#ffffff` | sfondo / superfici |
| `--ink`, `--ink-2`, `--ink-3` | `#1c1917`, `#4a4540`, `#6b645c` | testo principale, secondario, terziario |
| `--success`, `--warning`, `--danger`, `--info` | | stati, sempre con la variante `-soft` per lo sfondo |

Il tema scuro ridefinisce gli stessi token su `:root[data-theme="dark"]`. L'app parte in chiaro; scuro e «come il dispositivo» si scelgono dal Profilo o dal pulsante in alto.

## Tipografia
- Titoli e numeri: Bricolage Grotesque (variabile).
- Interfaccia e testo: Atkinson Hyperlegible Next (variabile), scelto per la leggibilità.
- Font self-hosted tramite `@fontsource-variable/*` (versioni fissate), compatibili con la CSP `style-src 'self'`.

## File CSS
`app.css` importa nell'ordine: `tokens`, `base`, `components`, `shell`, `access`, `customer`, `groups`, `staff`, `admin`.

## Componenti JS condivisi
- `core/dialog.js`: `confirmDialog`, `promptDialog`, `toast` (sostituiscono `confirm()`/`prompt()` del browser).
- `core/location-ui.js`: messaggi distinti per permesso negato, posizione non disponibile, precisione insufficiente, distanza e controlli lato server.
- `core/errors.js`: `friendlyError` per messaggi d'errore leggibili.

## Verifica
`TOUR_VIEWPORTS=320x568,390x844,1440x900 TOUR_THEMES=light,dark node tests/e2e/visual-tour.mjs` scatta tutte le schermate per ruolo e segnala overflow orizzontali ed errori in console.
