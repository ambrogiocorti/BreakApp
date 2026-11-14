# Banco veloce

Obiettivo (Ambrogio, 14/11/2026): durante la fascia una consegna non deve
richiedere più di 3 secondi di interazione, 7 secondi con il rimborso. Il
barista non deve mai vedere messaggi tecnici né restare bloccato da un
pagamento con carta lasciato a metà dal cliente.

## Come funziona

- **Un tocco per ordine.** Sul biglietto ci sono «Contanti X €», «POS» oppure
  «Consegna». Il tocco fa tutto in fila: chiude da solo un pagamento con carta
  rimasto aperto, segna l'ordine pronto se serve, registra l'incasso, segna lo
  scontrino come battuto e consegna. Vale anche per ordini ancora «Da preparare».
- **3 secondi per annullare.** Dopo il tocco il biglietto mostra cosa sta per
  essere registrato e il pulsante «Annulla». Il barista può già passare
  all'ordine successivo. Se l'app va in secondo piano, il tocco parte subito.
- **Pagamento con carta abbandonato.** Nessuna domanda: Stripe fa scadere il
  Checkout e poi si incassa al banco. Se Stripe dice che il cliente ha appena
  pagato, l'ordine si consegna senza incassare di nuovo.
- **Una coda sola su telefono e tablet** («Tutti»), le schede restano come filtro.
- **Ricerca.** Numero + Invio porta sul pulsante giusto, anche per ordini già
  conclusi negli ultimi due giorni (per rimborsarli).
- **Scanner QR.** La fotocamera si accende subito; l'ordine compare nello
  scanner con gli stessi pulsanti e dopo il tocco la lettura riprende da sola.
- **Rimborso in due tocchi.** «Rimborsa», poi il motivo: il rimborso parte.
  I soldi tornano come sono stati pagati (opzione A). I contanti vengono
  registrati subito nel turno di cassa del barista. Se la cassa è chiusa, la
  finestra lo mostra con il fondo da usare e la apre nello stesso tocco, prima
  del rimborso: nessun rimborso resta «in elaborazione».
- **Soldi da dare.** Un ordine con contanti ancora da restituire compare in
  cima al banco con il pulsante «Dati X € al cliente».

## Tocchi per flusso (misurati sul banco di prova)

| Flusso | Prima | Dopo |
|---|---|---|
| Ordine pronto da incassare (telefono) | 5 (scheda Pronti, Contanti, scontrino, conferma; + checkout abbandonato) | 1 |
| Ordine da preparare, incasso e consegna | 6 (Pronto, scheda, Contanti, scontrino, conferma) | 1 |
| Ordine pagato online | 4-5 (scheda, Consegna, scontrino, conferma) | 1 |
| Cliente con QR | 5 (Scansiona, Apri fotocamera, Contanti e consegna, scontrino, conferma) | 2 (Scansiona una volta, poi 1 per cliente) |
| Rimborso in contanti | 6 (filtro Conclusi, Rimborsa, Rimborsa, conferma contanti) | 2 |
| Rimborso con cassa chiusa | 12+ e cambio pagina (Cassa, fondo, apri, torna, restituzione, motivo, conferma) | 2 (+ fondo, se diverso da 0) |

## Regole invariate

Il server continua a controllare ruoli, scuola, consegne non pagate, fasce non
iniziate, doppi incassi e turno di cassa. Nessuna modifica al database.
