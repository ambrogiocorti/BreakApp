// Metodi di pagamento online ammessi da BreakApp nel Checkout Stripe.
// Il Checkout viene creato sull'account Stripe del bar (Stripe-Account),
// quindi senza un elenco esplicito Stripe mostra tutti i metodi attivi
// su quell'account (Link, Klarna, iDEAL, Multibanco, EPS...).
// Qui scegliamo noi: carta (con Apple Pay e Google Pay) più i soli
// portafogli decisi, e solo se il bar li ha davvero attivi.
// Link non va elencato: senza "link" Stripe non lo propone.
export const ALLOWED_PAYMENT_METHODS=Object.freeze(['card','paypal','satispay','revolut_pay']);

// Sceglie la configurazione dei metodi in uso sull'account del bar:
// quella predefinita attiva, altrimenti la prima attiva.
export function activeConfiguration(list){
 const items=Array.isArray(list?.data)?list.data.filter(item=>item&&item.active!==false):[];
 return items.find(item=>item.is_default)||items[0]||null;
}

// Restituisce i payment_method_types da passare al Checkout.
// La carta c'è sempre; gli altri metodi ammessi solo se disponibili.
export function pickPaymentMethodTypes(configuration){
 const types=['card'];
 for(const type of ALLOWED_PAYMENT_METHODS){
  if(type==='card')continue;
  if(configuration?.[type]?.available===true)types.push(type);
 }
 return types;
}

// Aggiunge payment_method_types[n] al form del Checkout.
export function appendPaymentMethodTypes(form,types){
 types.forEach((type,index)=>form.set('payment_method_types['+index+']',type));
 return form;
}
