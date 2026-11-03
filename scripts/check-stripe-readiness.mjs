// Read-only Stripe Connect TEST release gate. Never creates payments, merchants or webhooks.
import { pathToFileURL } from 'node:url';

const accountPattern=/^acct_[A-Za-z0-9]+$/;
const projectPattern=/^[a-z0-9]{12,32}$/;
const requiredEvents=[
  'checkout.session.completed',
  'checkout.session.expired',
  'checkout.session.async_payment_succeeded',
  'refund.created',
  'refund.updated'
];

function assertion(ok,message,checks){
  checks.push({name:message,ok:Boolean(ok)});
}

export async function checkStripeReadiness({
  apiKey,connectedAccountId,projectRef,fetchImpl=fetch
}){
  if(typeof apiKey!=='string'||!/^((sk|rk)_test_)[A-Za-z0-9]+$/.test(apiKey))
    throw Error('Richiesta una chiave Stripe di TEST valida: nessun pagamento LIVE ammesso.');
  if(!accountPattern.test(connectedAccountId||''))
    throw Error('ID account Connect non valido.');
  if(!projectPattern.test(projectRef||''))
    throw Error('Identificativo progetto Supabase non valido.');
  const checks=[];
  const endpoint='https://'+projectRef+'.supabase.co/functions/v1/stripe-webhook';
  async function get(route){
    // Never log Stripe credentials or raw provider error bodies.
    let response;
    try{
      response=await fetchImpl('https://api.stripe.com/v1/'+route,{
        method:'GET',
        headers:{Authorization:'Bearer '+apiKey},
        signal:AbortSignal.timeout(12000)
      });
    }catch{
      throw Error('Stripe API non raggiungibile: controllare connessione e DNS.');
    }
    if(!response.ok)
      throw Error('Stripe API ha rifiutato la verifica (HTTP '+response.status+'). Controllare che la chiave appartenga alla piattaforma Connect corretta e possa leggere account e webhook.');
    return response.json();
  }
  let account;
  try{account=await get('accounts/'+encodeURIComponent(connectedAccountId));}
  catch(err){
    return {ready:false,endpoint,checks:[{
      name:'Account Connect leggibile dalla piattaforma Stripe configurata',
      ok:false,
      reason:err instanceof Error?err.message:'Account Stripe non verificabile'
    }],limitations:['Non verifica la consegna webhook, il relativo signing secret o un pagamento di test.']};
  }
  assertion(account?.id===connectedAccountId,'Merchant Connect associato alla piattaforma Stripe',checks);
  assertion(account?.charges_enabled===true,'Merchant abilitato a ricevere addebiti',checks);
  assertion(account?.capabilities?.card_payments==='active','Capability pagamenti con carta attiva',checks);
  // An enabled TEST merchant alone does not authorize live operation.
  let next='';
  const endpoints=[];
  for(let page=0;page<10;page++){
    const route='webhook_endpoints?limit=100'+(next?'&starting_after='+encodeURIComponent(next):'');
    let list;
    try{list=await get(route);}catch(err){
      assertion(false,'Elenco webhook leggibile dalla piattaforma',checks);
      return {ready:false,endpoint,checks,limitations:[err.message]};
    }
    if(!Array.isArray(list?.data))
      throw Error('Stripe ha restituito un elenco webhook non valido.');
    endpoints.push(...list.data);
    if(!list.has_more)break;
    if(page===9||!list.data.length)
      throw Error('Elenco webhook incompleto: impossibile verificare la configurazione.');
    next=list.data.at(-1).id;
  }
  const matching=endpoints.filter(w=>w.url===endpoint);
  assertion(matching.length>0,'Webhook BreakApp presente sulla piattaforma',checks);
  const readyWebhook=matching.find(w=>w.status==='enabled'&&w.connect===true&&
    (w.enabled_events?.includes('*')||
      requiredEvents.every(event=>w.enabled_events?.includes(event))));
  assertion(matching.some(w=>w.status==='enabled'),'Webhook BreakApp attivo',checks);
  assertion(matching.some(w=>w.connect===true),'Webhook impostato per eventi Connect',checks);
  for(const event of requiredEvents)
    assertion(matching.some(w=>w.status==='enabled'&&w.connect===true&&
      (w.enabled_events?.includes('*')||w.enabled_events?.includes(event))),
      'Evento Connect '+event+' abilitato',checks);
  assertion(Boolean(readyWebhook),'Un singolo endpoint Connect copre tutti gli eventi richiesti',checks);
  return {
    ready:checks.every(c=>c.ok),
    endpoint,
    checks,
    limitations:[
      'Non verifica che STRIPE_WEBHOOK_SECRET in Supabase corrisponda al signing secret dell’endpoint.',
      'Non verifica Checkout → firma webhook → ledger → rimborso; servono transazioni Stripe TEST reali.',
      'Non abilita pagamenti LIVE o autorizza la vendita commerciale.'
    ]
  };
}

async function main(){
  const apiKey=process.env.BREAKAPP_STRIPE_TEST_KEY||'';
  const connectedAccountId=process.env.BREAKAPP_STRIPE_CONNECTED_ACCOUNT||'';
  const projectRef=process.env.BREAKAPP_SUPABASE_REF||'';
  try{
    const result=await checkStripeReadiness({apiKey,connectedAccountId,projectRef});
    for(const check of result.checks)
      console.log((check.ok?'[OK] ':'[NO] ')+check.name+(check.reason?' — '+check.reason:''));
    console.log('Webhook atteso:',result.endpoint);
    for(const caveat of result.limitations)console.log('NOTA:',caveat);
    if(!result.ready)process.exitCode=1;
  }catch(err){
    console.error('BLOCCO STRIPE:',err.message);
    process.exitCode=1;
  }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await main();
