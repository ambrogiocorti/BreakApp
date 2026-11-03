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
  // Stripe GET /v1/webhook_endpoints returns id, url, status, livemode,
  // enabled_events, etc., but NOT the connect flag supplied on creation.
  // A test requiring w.connect === true is therefore always a false negative.
  // Check only observable fields and require a real signed Connect delivery
  // (event.account present) for confirmation of the event scope.
  const matching=endpoints.filter(w=>w.url===endpoint&&w.livemode!==true);
  assertion(matching.length>0,'Webhook TEST BreakApp presente sulla piattaforma',checks);
  const readyWebhook=matching.find(w=>w.status==='enabled'&&
    (w.enabled_events?.includes('*')||
      requiredEvents.every(event=>w.enabled_events?.includes(event))));
  assertion(matching.some(w=>w.status==='enabled'),'Webhook TEST BreakApp attivo',checks);
  for(const event of requiredEvents)
    assertion(matching.some(w=>w.status==='enabled'&&
      (w.enabled_events?.includes('*')||w.enabled_events?.includes(event))),
      'Evento webhook '+event+' abilitato (ambito Connect non leggibile)',checks);
  assertion(Boolean(readyWebhook),'Un solo webhook TEST attivo copre tutti gli eventi richiesti',checks);
  return {
    // "ready" means observable REST configuration only, not Connect scope
    // or a completed payment. It must never be presented as go-live approval.
    ready:checks.every(c=>c.ok),
    connectScopeVerified:false,
    endpoint,
    checks,
    matchingEndpoints:matching.length,
    limitations:[
      'DA VERIFICARE: Stripe /v1/webhook_endpoints non restituisce il campo connect. Il test non puo stabilire se la destinazione ascolta Connected accounts. Verificarlo in Workbench e con un evento firmato che contenga event.account.',
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
    if(typeof result.matchingEndpoints==='number')
      console.log('Endpoint TEST con questo URL trovati:',result.matchingEndpoints);
    if(result.connectScopeVerified===false)
      console.log('[DA VERIFICARE] Ambito Connected accounts: impossibile determinarlo tramite GET /v1/webhook_endpoints.');
    for(const caveat of result.limitations)console.log('NOTA:',caveat);
    console.log(result.ready?'[OK] Verifiche di configurazione REST superate (NON e un test Connect E2E).':'[NO] Alcune verifiche osservabili della configurazione Stripe sono fallite.');
    if(!result.ready)process.exitCode=1;
  }catch(err){
    console.error('BLOCCO STRIPE:',err.message);
    process.exitCode=1;
  }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await main();
