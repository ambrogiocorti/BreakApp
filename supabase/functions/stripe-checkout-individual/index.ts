// Supabase Edge Function: stripe-checkout-individual
// Requires STRIPE_SECRET_KEY, SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY (Edge Function secrets; never frontend).
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{
 status,headers:{'content-type':'application/json; charset=utf-8',
 'cache-control':'no-store','access-control-allow-origin':'https://ambrogiocorti.github.io',
 'vary':'Origin','access-control-allow-headers':'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
 'access-control-allow-methods':'POST, OPTIONS'}
});
const origin='https://ambrogiocorti.github.io';
const site=origin+'/BreakApp/';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function required(name:string){
 const value=Deno.env.get(name);if(!value)throw new Error('Configurazione server incompleta: '+name);
 return value;
}
function stripeError(obj:Record<string,unknown>):string{
 const item=obj.error as Record<string,unknown>|undefined;
 return String(item?.message||'Stripe non disponibile');
}
async function stripe(endpoint:string,account:string,key:string,init?:RequestInit){
 const response=await fetch('https://api.stripe.com/v1/'+endpoint,{
  ...init,headers:{authorization:'Bearer '+key,'Stripe-Account':account,
   ...(init?.headers||{})}});
 const data=await response.json() as Record<string,unknown>;
 if(!response.ok)throw new Error('Stripe: '+stripeError(data));
 return data;
}
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{'access-control-allow-origin':origin,'access-control-allow-methods':'POST, OPTIONS','access-control-allow-headers':'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage','vary':'Origin'}});
 if(req.method!=='POST')return json({error:'Metodo non consentito'},405);
 if(req.headers.get('Origin')!==origin)return json({error:'Origine non autorizzata'},403);
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'').trim();
  if(!token)return json({error:'Sessione richiesta'},401);
  const url=required('SUPABASE_URL');
  const anon=required('SUPABASE_ANON_KEY');
  const stripeKey=required('STRIPE_SECRET_KEY');
  if(!/^[sr]k_test_[A-Za-z0-9]+$/.test(stripeKey))return json({error:'Checkout non attivo in ambiente di test'},503);
  const db=createClient(url,anon,{global:{headers:{Authorization:'Bearer '+token}},
    auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await db.auth.getUser(token);
  if(authError||!identity.user)return json({error:'Sessione non valida'},401);
  const payload=await req.json() as Record<string,unknown>;
  if(typeof payload.order_id!=='string'||!uuid.test(payload.order_id)||
    typeof payload.request_key!=='string'||!uuid.test(payload.request_key))
   return json({error:'Identificatori non validi'},400);
  const {data:attempt,error:dbError}=await db.rpc('begin_individual_stripe_checkout',{
   p_order_id:payload.order_id,p_request_key:payload.request_key
  });
  if(dbError)return json({error:dbError.message},409);
  if(!attempt||!uuid.test(attempt.attempt_id)||!/^acct_[A-Za-z0-9]+$/.test(attempt.stripe_account_id)
   ||!Number.isSafeInteger(Number(attempt.amount_cents))||Number(attempt.amount_cents)<=0)
   return json({error:'Tentativo di pagamento incoerente'},500);
  const account=attempt.stripe_account_id as string;
  let checkout:Record<string,unknown>;
  if(attempt.existing_session){
   checkout=await stripe('checkout/sessions/'+encodeURIComponent(attempt.existing_session),
     account,stripeKey);
  }else{
   const body=new URLSearchParams({
    mode:'payment',
    'client_reference_id':attempt.attempt_id,
    'metadata[attempt_id]':attempt.attempt_id,
    'payment_intent_data[metadata][attempt_id]':attempt.attempt_id,
    'line_items[0][quantity]':'1',
    'line_items[0][price_data][currency]':'eur',
    'line_items[0][price_data][unit_amount]':String(attempt.amount_cents),
    'line_items[0][price_data][product_data][name]':'BreakApp · Ordine scolastico',
    // Stripe requires a window of at least 30 minutes. No local timeout
    // may be used to release the cash-desk payment lock.
    expires_at:String(Math.floor(Date.now()/1000)+35*60),
    success_url:site+'#orders',
    cancel_url:site+'#orders'
   });
   checkout=await stripe('checkout/sessions',account,stripeKey,{
    method:'POST',headers:{'content-type':'application/x-www-form-urlencoded',
      'Idempotency-Key':'breakapp-checkout-'+attempt.attempt_id},body
   });
   const admin=createClient(url,required('SUPABASE_SERVICE_ROLE_KEY'),{
    auth:{persistSession:false,autoRefreshToken:false}
   });
   const {error:attachError}=await admin.rpc('attach_stripe_checkout_session',{
    p_attempt:attempt.attempt_id,p_session:checkout.id
   });
   if(attachError)throw new Error('Sessione creata ma registrazione fallita: '+attachError.message);
  }
  if(typeof checkout.url!=='string'||!checkout.url.startsWith('https://checkout.stripe.com/'))
   throw new Error('Checkout non ha restituito un URL Stripe valido');
  return json({checkout_url:checkout.url,attempt_id:attempt.attempt_id});
 }catch(error){
  // Never print keys, tokens, or payment payloads in responses/logs.
  return json({error:error instanceof Error?error.message:'Checkout temporaneamente non disponibile'},503);
 }
});
