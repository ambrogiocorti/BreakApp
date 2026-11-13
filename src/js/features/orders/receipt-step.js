// Scontrino nello stesso passaggio dell'incasso o della consegna: prima il
// barista batte lo scontrino sul registratore del bar, poi conferma l'incasso.
// Dopo l'incasso la riga del registro scontrini dell'ordine viene segnata come
// emessa, senza passare dalla pagina "Scontrini da emettere".
import { formatEuro } from '../catalog/utils.js';

export function receiptQuestion(displayNo,cents,{online=false}={}){
  return `Ordine #${displayNo}: batti lo scontrino di ${formatEuro(cents)} sul registratore del bar`+
    (online?' (pagato online con carta)':'')+'. Fatto?';
}

// Importo ancora da scontrinare per un ordine gia' pagato (es. online).
export async function pendingReceiptCents(client,orderId){
  const {data,error}=await client.rpc('pending_order_receipts',{p_order:orderId});
  if(error||!data)return 0;
  return Math.max(0,Number(data.sale_cents||0)-Number(data.return_cents||0));
}

// Segna come emessi gli scontrini dell'ordine. Non blocca mai la consegna:
// se non riesce, la riga resta nella pagina "Scontrini da emettere".
export async function markReceiptsIssued(client,orderId){
  const {error}=await client.rpc('mark_order_receipts_issued',{p_order:orderId});
  return error?'Scontrino non segnato come emesso: segnalo dalla pagina «Scontrini da emettere».':'';
}
