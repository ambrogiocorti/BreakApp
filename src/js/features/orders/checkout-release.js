// Pagamento con carta avviato dal cliente e mai concluso: non deve mai fermare
// il banco. Prima di incassare in contanti o POS il pagamento con carta ancora
// aperto viene chiuso da solo: Stripe fa scadere il Checkout (il cliente non
// puo' piu' pagare online) e solo allora si incassa al banco. Se Stripe dice
// che il cliente ha appena pagato, l'ordine risulta pagato e si consegna e
// basta. Nessuna domanda al barista e nessun doppio incasso.

const pause=ms=>new Promise(done=>setTimeout(done,ms));

// Esito: {state:'free'} si puo' incassare; {state:'paid'} il cliente ha gia'
// pagato con carta; {state:'wait',message} pagamento con carta in corso.
export async function releaseAbandonedCheckout(client,order,{retries=3,delay=900}={}){
  for(let attempt=0;;attempt++){
    const {data,error}=await client.rpc('staff_open_checkout',{p_order:order.id});
    // Se la verifica non risponde il server rifiutera' comunque un doppio incasso.
    if(error||!data?.open)return {state:'free'};
    if(['processing','review'].includes(data.status))
      return {state:'wait',message:`#${order.display_no}: il cliente sta pagando con carta. Appena il pagamento arriva, l’ordine risulta pagato.`};
    const {data:result,error:cancelError}=await client.functions.invoke('stripe-checkout-cancel',{body:{order_id:order.id}});
    const problem=String(cancelError?.message||result?.error||'');
    if(!problem)return {state:'free'};
    if(/già completato/i.test(problem))return {state:'paid'};
    // Pagamento appena aperto o Stripe lento: si riprova da soli.
    if(attempt<retries){await pause(delay);continue;}
    return {state:'wait',message:`#${order.display_no}: il cliente ha appena aperto il pagamento con carta. Riprova tra qualche secondo.`};
  }
}
