# BreakApp — Monitoraggio pubblico dell'hosting

La pipeline `.github/workflows/availability.yml` interroga la PWA realmente
pubblicata su GitHub Pages alle minute 17 e 47 di ogni ora, e può essere
avviata anche manualmente. Verifica:

- Risposta HTTP 200 e presenza dell'interfaccia login;
- manifest PWA installabile, con percorso e scope corretti;
- service worker raggiungibile e con codice JavaScript plausibile.

In caso di guasto il workflow **fallisce**: l'operatore deve abilitare le
notifiche GitHub Actions e predisporre un canale di reperibilità. I cron
GitHub Actions sono *best effort*, possono ritardare o non eseguire una
specifica istanza. Il controllo non è una garanzia SLA.

## Verifiche che mancano prima del pilota

Questa sonda esterna non controlla le sessioni Supabase reali, il checkout
Stripe, il saldo del bar, il dispatcher push, le query cross-school, i backup,
né il ripristino. È uno strato di osservabilità **statico**, non il monitoraggio
end-to-end della piattaforma. Non raccoglie o memorizza dati degli studenti.

Per controlli interni aggiungere in una fase successiva metriche server-side
di errori applicativi, fallimenti webhook e rimborsi, code push e conflitti
offline, evitando credenziali di servizio in Pages e log di GitHub.
