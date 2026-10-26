# BreakApp — Incremento 07: calendario, pause e chiusure del bar

**Specifica:** Prompt Master v1, sezioni 3, 4, 7 e criteri di test 390. **Ambiente:** Supabase progetto `ynvswdyirngvdpudcikl` e Vercel di test.

## Implementato nell'incremento

- Orari settimanali per bar, con uno o più intervalli al giorno (Admin scuola AAL2), validati con impedimento di sovrapposizioni e di modifica retroattiva delle fasce future già pubblicate.
- Pausa/ripresa delle **nuove prenotazioni**, effettuabile da Admin scuola AAL2 o Barista autorizzato dello stesso tenant. Gli ordini confermati non vengono modificati.
- Chiusure programmate solo Admin AAL2; se una chiusura programmata intercetta ordini già attivi viene rifiutata.
- Chiusure straordinarie da Admin AAL2 o Barista, con anteprima degli ordini interessati. Annullamento atomico dei soli ordini non consegnati/non riscossi nello specifico intervallo, ripristino delle scorte soltanto se i prodotti non erano ancora in preparazione, tracciamento in audit e notifica **in-app** al proprietario ordine.
- Se una chiusura interessa incassi realmente registrati, viene **bloccata** in sicurezza, non simulata: i rimborsi automatici reali via Stripe/contabilità sono un requisito ancora da implementare.
- Riapertura anticipata, con storico e senza resurrezione degli ordini cancellati. I prodotti di ordini già in preparazione/pronti non tornano automaticamente vendibili: rimangono conteggiati per evitare sovravendita e richiedono riconciliazione inventariale.
- Trigger DB blocca nuove prenotazioni in pausa/chiusura/fuori apertura e la pubblicazione di nuove fasce in orari chiusi. La migrazione 08 impedisce di disattivare direttamente fasce con ordini attivi.
- Catalogo consultabile anche durante la pausa. Carrello e scelta ritiro leggono lo stato reale e disabilitano checkout non disponibile. Verifica server ripetuta all'invio.
- Area personale e Admin responsive; storico azioni consultabile da personale autorizzato.

## Limitazioni da non nascondere

1. **Push non implementate**: l'evento di annullamento compare nel centro avvisi in-app dello studente quando ricarica gli ordini. Notifiche push e automatiche arriveranno con l'infrastruttura notifiche.
2. **Rimborsi Stripe non ancora implementati**: non attivare chiusure automatiche su ordini già riscossi. Il backend rifiuta senza mutazioni. Il flusso completo del Prompt Master resta aperto.
3. Aperture e chiusure si esprimono per singolo giorno locale; turni che attraversano mezzanotte richiederanno modello dedicato, se necessario.
4. Le fasce concrete devono essere configurate dall'Admin nel pannello del magazzino; un calendario settimanale non crea prenotazioni fittizie.
5. Nessun dato di test deve essere inserito nel progetto reale. Le prove di concorrenza e RLS vengono eseguite nella pipeline PostgreSQL temporanea.
6. UI corrente non è ancora il planner grafico finale in stile approvato: il dato e i controlli sono reali; estensione calendario mese/settimana e pianificazione bulk rimangono da completare.

## Piano di collaudo

- CI `tests/db/service-calendar.sql`: blocco Admin senza 2FA, autorizzazioni per scuola, pause, blocco checkout, ordinazione dopo ripresa, preview, chiusura straordinaria, restituzione scorte e avvisi, riapertura senza ripristino.
- CI: rifiuto chiusura già pagata, saldo e storico immutati, nessuna chiusura parziale.
- Test browser da fare con account Barista e Admin AAL2: form, responsive, permessi, scelta scuola/bar, posizioni, browser senza GPS, segnalazione al cliente.
- Prima di passare da Vercel test a scuola pilota servono Stripe, rimborsi, push, sicurezza E2E e revisione GDPR/fiscale.

## Regola di deployment

Il merge avviene **solo dopo** CI JavaScript/Vite + PostgreSQL verde, migrazione applicata a `ynvswdyirngvdpudcikl` verificata e Vercel preview pronta. Il database non viene riempito di orari o chiusure inventati.
