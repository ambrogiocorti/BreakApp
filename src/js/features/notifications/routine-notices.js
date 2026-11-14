// Avvisi di routine: confermano solo ciò che la persona ha appena fatto o
// vede già nella pagina Ordini (stato, QR, saldo). Dal 14/11/2026 il database
// non li crea più; qui nascondiamo quelli già salvati prima di allora.
// Restano visibili gli avvisi utili: ordine annullato o spostato di fascia,
// modifiche e articoli mancanti, gruppi, assistenza, avvisi della scuola.
const ROUTINE_PREFIXES=[
 'Ordine confermato. Controlla in app',
 'Richiesta inviata: attende approvazione',
 'Rimborso richiesto:',
 'Pagamento con carta annullato al banco',
 'Cambio registrato al banco'
];
const STATUS_UPDATE=/^Ordine #\d+: stato aggiornato a /;

export function isRoutineNotice(row){
 if(!row||row.event_type&&row.event_type!=='order_status')return false;
 const message=String(row.message||'');
 return STATUS_UPDATE.test(message)||ROUTINE_PREFIXES.some(prefix=>message.startsWith(prefix));
}

export const usefulNotices=rows=>(rows||[]).filter(row=>!isRoutineNotice(row));
