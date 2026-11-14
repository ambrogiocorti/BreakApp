// Banco veloce: un tocco per consegnare un ordine.
// Il tocco su «Contanti», «POS» o «Consegna» fa tutto in fila, con le stesse
// chiamate al server di prima: chiude da solo un pagamento con carta lasciato a
// meta', segna l'ordine pronto se serve, registra l'incasso, segna lo scontrino
// come battuto e consegna. Il server continua a rifiutare consegne non pagate,
// fasce non iniziate e doppi incassi.
import { formatEuro } from '../catalog/utils.js';
import { releaseAbandonedCheckout } from './checkout-release.js';
import { markReceiptsIssued } from './receipt-step.js';
import { friendlyError } from '../../core/errors.js';

// Secondi in cui il barista puo' annullare un tocco sbagliato prima dell'invio.
export const UNDO_MS=3000;
export const ACTIVE=Object.freeze(['confirmed','preparing','ready']);

// Importo da incassare al banco, con lo sconto al banco deciso dall'Admin
// (stessa formula del server: app_private.counter_discount_cents).
export function counterAmount(totalCents,bps){
  const due=Math.max(0,Math.trunc(Number(totalCents)||0));
  const rate=Math.trunc(Number(bps)||0);
  if(due<=0||rate<=0)return due;
  return due-Math.min(due-1,Math.floor((due*rate+5000)/10000));
}

// Pulsanti del biglietto, nell'ordine in cui compaiono. Il primo e' quello
// principale. Nessun pulsante per ordini chiusi, salvo il rimborso.
export function ticketActions(order,{bps=0,pendingCashCents=0}={}){
  const actions=[];
  if(ACTIVE.includes(order.status)){
    if(order.payment_status==='due'){
      const cents=counterAmount(order.total_cents,bps);
      actions.push({key:'cash',method:'cash',label:'Contanti '+formatEuro(cents),cents,primary:true});
      actions.push({key:'pos',method:'external_pos',label:'POS',cents});
    }else if(order.payment_status==='paid'){
      actions.push({key:'deliver',method:null,label:'Consegna',primary:true});
    }
    if(order.status==='confirmed')actions.push({key:'ready',label:'Pronto',small:true},{key:'preparing',label:'In preparazione',small:true});
    if(order.status==='preparing')actions.push({key:'ready',label:'Pronto',small:true});
  }
  if(pendingCashCents>0)actions.push({key:'give-back',label:'Dati '+formatEuro(pendingCashCents)+' al cliente',cents:pendingCashCents,primary:true});
  if(order.payment_status==='paid'&&['delivered','no_show'].includes(order.status))actions.push({key:'refund',label:'Rimborsa'});
  return actions;
}

// Testo mostrato durante i secondi per annullare.
export function pendingText(order,action){
  if(action.key==='cash')return `#${order.display_no}: incassati ${formatEuro(action.cents)} in contanti e consegnato`;
  if(action.key==='pos')return `#${order.display_no}: incassati ${formatEuro(action.cents)} con il POS e consegnato`;
  if(action.key==='deliver')return `#${order.display_no}: consegnato`;
  if(action.key==='give-back')return `#${order.display_no}: dati ${formatEuro(action.cents)} in contanti`;
  return `#${order.display_no}: ${action.label.toLowerCase()}`;
}

// Messaggi del server tradotti in cosa fare al banco.
const COUNTER_ERRORS=[
  [/checkout in corso|pagamento con carta/i,'Il cliente sta pagando con carta: riprova tra qualche secondo.'],
  [/già saldato/i,'Era già pagato: ora puoi consegnarlo.'],
  [/transizione di stato non consentita/i,'L’ordine era già stato aggiornato: ecco la lista nuova.'],
  [/saldo non ancora pagato/i,'Prima va incassato.'],
  [/fascia di ritiro non è ancora iniziata/i,'La fascia di ritiro non è ancora iniziata: consegnalo all’orario.'],
  [/turno di cassa/i,'La cassa è chiusa: aprila e riprova.']
];
export function counterError(error){
  const text=String(error?.message||error||'');
  for(const [pattern,message] of COUNTER_ERRORS)if(pattern.test(text))return message;
  return friendlyError(error,'Operazione non riuscita: riprova.');
}

const keys=new Map();
function requestKey(orderId,method){
  const id=orderId+':'+method;
  if(!keys.has(id))keys.set(id,crypto.randomUUID());
  return keys.get(id);
}

// Consegna in un tocco. Restituisce {ok:true,note} oppure {ok:false,message}.
export async function handOver(client,order,method){
  let collect=method;
  if(collect){
    const release=await releaseAbandonedCheckout(client,order);
    if(release.state==='wait')return {ok:false,message:release.message};
    // Il cliente ha appena pagato con carta: niente incasso, solo consegna.
    if(release.state==='paid')collect=null;
  }
  if(order.status!=='ready'){
    const ready=await client.rpc('advance_individual_order',{p_order_id:order.id,p_next:'ready'});
    if(ready.error&&!/transizione/i.test(ready.error.message||''))return {ok:false,message:counterError(ready.error)};
  }
  let note=collect===null&&method?`#${order.display_no} era già pagato con carta: consegnato senza incassare.`:'';
  if(collect){
    const paid=await client.rpc('record_individual_counter_payment',{p_order_id:order.id,p_method:collect,p_request_key:requestKey(order.id,collect)});
    if(paid.error&&!/già saldato/i.test(paid.error.message||''))return {ok:false,message:counterError(paid.error)};
    keys.delete(order.id+':'+collect);
  }
  const receipt=await markReceiptsIssued(client,order.id);
  if(receipt)note=[note,receipt].filter(Boolean).join(' ');
  const delivered=await client.rpc('advance_individual_order',{p_order_id:order.id,p_next:'delivered'});
  if(delivered.error)return {ok:false,message:(collect?'Incasso registrato, consegna no: ':'')+counterError(delivered.error)};
  return {ok:true,note};
}

// Turno di cassa del barista per il bar dell'ordine: id oppure null.
export async function ownCashSession(client,schoolId,barId,actorId){
  const {data,error}=await client.rpc('cash_workspace',{p_school:schoolId});
  if(error)return {error};
  const row=(data?.sessions||[]).find(s=>s.actor_id===actorId&&!s.closed_at&&(!barId||s.bar_id===barId));
  return {id:row?.id||null};
}

// Apre il turno di cassa con il fondo indicato (in centesimi).
export async function openCashSession(client,barId,openingCents){
  const id=crypto.randomUUID();
  const {error}=await client.rpc('record_cash_operation',{p_bar:barId,p_session:id,p_action:'open',
    p_amount:openingCents,p_reason:'',p_key:crypto.randomUUID()});
  if(error)return {error};
  window.dispatchEvent(new CustomEvent('breakapp:cash-refresh'));
  return {id};
}

