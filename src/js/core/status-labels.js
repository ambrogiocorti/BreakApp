const label=(dictionary,value)=>dictionary[value]||'Stato da verificare';
export const approvalLabel=value=>label({queued:'In coda',active:'In valutazione',awaiting_reschedule:'In attesa di una nuova fascia',approved:'Approvata',rejected:'Rifiutata',expired:'Scaduta',cancelled:'Annullata'},value);
export const ticketLabel=value=>label({open:'Aperta',in_progress:'In lavorazione',awaiting_customer:'In attesa di risposta',resolved:'Risolta',closed:'Chiusa'},value);
export const reopenLabel=value=>label({pending:'In attesa',approved:'Approvata',denied:'Rifiutata'},value);
export const membershipLabel=value=>label({active:'Attivo',pending:'In attesa',suspended:'Sospeso'},value);
export const paymentLabel=value=>label({due:'Da pagare',initiated:'Avviato',requires_action:'Azione richiesta',processing:'In elaborazione',succeeded:'Completato',failed:'Non riuscito',cancelled:'Annullato',pending:'In attesa',review:'Da verificare',paid:'Pagato',refunded:'Rimborsato',refund_pending:'Rimborso in elaborazione',returned:'Restituito'},value);
export const changeKindLabel=value=>label({amendment:'Modifica ordine',substitution:'Sostituzione',delay:'Cambio orario'},value);
export const changeStateLabel=value=>label({staff_pending:'In attesa del bar',customer_pending:'In attesa del cliente',applied:'Applicata',rejected:'Rifiutata',expired:'Scaduta'},value);
