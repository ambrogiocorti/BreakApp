// Rimborso dall'ordine concluso, in un solo passaggio al banco.
// Il cliente sceglie: i soldi indietro oppure un altro prodotto.
// I soldi tornano come sono stati pagati: la parte online con un rimborso
// Stripe sulla carta, la parte in contanti o POS in contanti al banco, che il
// barista registra subito nel turno di cassa (niente pagina a parte).
import { formatEuro } from '../catalog/utils.js';

export const REFUND_REASONS=Object.freeze([
  'Prodotto non buono o rovinato',
  'Prodotto sbagliato',
  'Prodotto finito o non disponibile',
  'Il cliente ha cambiato idea'
]);
export const OTHER_REASON='__other__';

// Motivo da inviare al server: una voce pronta oppure il testo scritto.
export function refundReason(preset,written){
  const text=preset===OTHER_REASON?String(written||'').trim():String(preset||'').trim();
  return text.length>=8&&text.length<=300?text:'';
}

// Righe dell'ordine che si possono rendere (solo quelle con prodotto e prezzo).
export function exchangeableLines(order){
  return (order?.order_items||[]).filter(line=>line.product_id&&Number(line.quantity)>0&&Number.isFinite(Number(line.unit_cents)));
}

// Differenza del cambio: positiva = il cliente paga, negativa = gli si restituisce.
export function exchangeDifference(outUnitCents,inPriceCents,quantity){
  const q=Math.max(0,Math.trunc(Number(quantity)||0));
  return (Number(inPriceCents)||0)*q-(Number(outUnitCents)||0)*q;
}

export function exchangeDifferenceText(diff){
  if(diff>0)return 'Il cliente paga la differenza: '+formatEuro(diff)+'.';
  if(diff<0)return 'Al cliente tornano '+formatEuro(-diff)+', come ha pagato.';
  return 'Stesso prezzo: niente da pagare né da restituire.';
}

export function cashReturnQuestion(displayNo,cents){
  return `Ordine #${displayNo}: dai ${formatEuro(cents)} in contanti al cliente e batti il reso sul registratore del bar. Fatto?`;
}

export function exchangePaymentQuestion(displayNo,cents,method){
  return `Ordine #${displayNo}: incassa ${formatEuro(cents)} `+(method==='cash'?'in contanti':'con il POS')+'. Fatto?';
}

// Registra subito nel turno di cassa le restituzioni in contanti dell'ordine.
// Restituisce i centesimi registrati e quelli rimasti da registrare.
export async function returnCashNow(client,orderId,reason){
  const {data,error}=await client.rpc('order_cash_refunds_to_return',{p_order:orderId});
  if(error)return {returned:0,pending:null,problem:error.message};
  let returned=0,pending=0,problem='';
  for(const item of Array.isArray(data)?data:[]){
    const cents=Number(item.amount_cents||0);
    if(problem){pending+=cents;continue;}
    const result=await client.rpc('confirm_cash_refund_return',{p_refund:item.id,p_reason:('Restituiti al banco: '+reason).slice(0,300)});
    if(result.error){problem=result.error.message;pending+=cents;}else returned+=cents;
  }
  return {returned,pending,problem};
}

export function cashOutcomeText({returned,pending,problem}){
  const parts=[];
  if(returned>0)parts.push('Restituzione di '+formatEuro(returned)+' registrata in cassa.');
  if(pending>0||pending===null){
    parts.push(/turno di cassa/i.test(problem||'')
      ?'Contanti non registrati: apri il turno di cassa, poi registrali da «Restituzioni da registrare».'
      :'Contanti da registrare ancora in «Restituzioni da registrare»'+(problem?' ('+problem+')':'')+'.');
  }
  return parts.join(' ');
}
