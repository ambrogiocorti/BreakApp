// Pagamento con carta avviato dal cliente e mai concluso: blocca l'incasso al
// banco finche' Stripe non lo chiude. Prima di incassare, il barista puo'
// annullarlo: Stripe fa scadere il Checkout (il cliente non puo' piu' pagare
// online) e solo allora si incassa in contanti o POS. Nessun doppio incasso.
import { formatEuro } from '../catalog/utils.js';

export function abandonedCheckoutQuestion(displayNo,cents){
  return `Ordine #${displayNo}: il cliente ha aperto il pagamento con carta`+
    (cents>0?` (${formatEuro(cents)})`:'')+' ma non l’ha concluso. Lo annullo per incassare al banco? Dopo non potrà più pagare online.';
}

// Restituisce '' se si puo' incassare, altrimenti il motivo per cui no.
// ask(message) => Promise<boolean> mostra la domanda al barista.
export async function releaseAbandonedCheckout(client,order,ask){
  const {data,error}=await client.rpc('staff_open_checkout',{p_order:order.id});
  if(error)return '';// Il server rifiutera' comunque l'incasso se serve.
  if(!data?.open)return '';
  if(['processing','review'].includes(data.status))
    return 'Il pagamento con carta di questo ordine è in elaborazione: aspetta l’esito prima di incassare al banco.';
  if(!await ask(abandonedCheckoutQuestion(order.display_no,Number(data.amount_cents||0))))
    return 'Incasso non fatto: il pagamento con carta del cliente è ancora aperto.';
  const {data:result,error:cancelError}=await client.functions.invoke('stripe-checkout-cancel',{body:{order_id:order.id}});
  const problem=cancelError?.message||result?.error;
  if(problem)return 'Pagamento con carta non annullato: '+problem;
  return '';
}
