# BreakApp — Prova di ripristino PostgreSQL in CI

Il workflow `database.yml` applica tutte le migration disponibili nel
database **effimero** della CI, esegue gli integration test, crea un archivio
`pg_dump -Fc`, lo ripristina in un secondo database chiamato
`breakapp_restore` e verifica i dati di prova, le RLS, i privilegi di una
RPC service-only e la copertura degli indici FK.

- La prova fallisce se `pg_dump`, `pg_restore` o le asserzioni falliscono.
- Il dump contiene **solo dati sintetici** ed è conservato soltanto sul
  runner temporaneo. Non viene caricato come artifact GitHub.
- Il ripristino avviene nello stesso cluster PostgreSQL: perciò i ruoli
  globali sono già presenti. Questa prova non dimostra il ripristino su
  un server vergine, con ruoli, estensioni, segreti, storage ed Edge Functions.

## Backup del Supabase reale — ancora da abilitare

Prima di un pilota:
1. Definire RPO e RTO accettabili, retention, accesso ai dump cifrati e
   collocazione fuori dal progetto principale; non inviare dati di minori
   in artifact pubblici o log CI.
2. Abilitare un backup automatico verificabile tramite provider o job
   server sicuro, con monitoraggio degli errori e controllo delle dimensioni.
3. Salvare separatamente le configurazioni e gli strumenti di ripristino:
   ruoli e grant, SQL e migrazioni, Edge Functions, Storage, webhook Stripe,
   DNS e rotazione dei segreti. I segreti non vanno mai nei dump Git.
4. Eseguire un ripristino in **un progetto separato** con dati autorizzati,
   verificare login, isolamento scuole, ledger e integrità degli ordini.
5. Provare un incidente e registrare tempi effettivi e responsabili prima di
   dichiarare il servizio vendibile.

Nessun backup di produzione è stato eseguito o configurato da questa PR.
