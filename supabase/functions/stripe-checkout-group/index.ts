// Group Stripe Checkout: every selected line is charged as a whole.
// Requires STRIPE_SECRET_KEY, SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY in the Supabase Edge secrets manager.
import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const origin='https://ambrogiocorti.github.io';
const site=origin+'/BreakApp/';
const uid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const response=(data:unknown,status=200)=>new Response(JSON.stringify(data),{
 status,headers:{'content-type':'application/json','cache-control':'no-store',
  'access-control-allow-origin':origin,'vary':'Origin',
  'access-control-allow-methods':'POST, OPTIONS',
  'access-control-allow-headers':'authorization, apikey, content-type'}
});
const required=(name:string)=>{const s=Deno.env.get(name);if(!s)throw Error('Config server incompleta: '+name);return s;};
async function stripe(endpoint:string,account:string,key:string,init?:RequestInit){
 const res=await fetch('https://api.stripe.com/v1/'+endpoint,{
  ...init,headers:{authorization:'Bearer '+key,'Stripe-Account':account,...(init?.headers||{})}});
 const out=await res.json() as Record<string,any>;
 if(!res.ok)throw Error('Stripe: '+String(out.error?.message||'Checkout non disponibile'));
 return out;
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return response({},204);
 if(req.method!=='POST')return response({error:'Metodo non consentito'},405);
 if(req.headers.get('Origin')!==origin)return response({error:'Origine non autorizzata'},403);
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'').trim();
  if(!token)return response({error:'Autenticazione richiesta'},401);
  const url=required('SUPABASE_URL'),anon=required('SUPABASE_ANON_KEY');
  const key=required('STRIPE_SECRET_KEY');
  if(!/^[sr]k_test_[A-Za-z0-9]+$/.test(key))return response({error:'Solo sandbox Stripe abilitata'},503);
  const client=createClient(url,anon,{global:{headers:{Authorization:'Bearer '+token}},
   auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:identityError}=await client.auth.getUser(token);
  if(identityError||!identity.user)return response({error:'Sessione non valida'},401);
  const body=await req.json() as Record<string,unknown>;
  if(typeof body.group_id!=='string'||!uid.test(body.group_id)||
   typeof body.request_key!=='string'||!uid.test(body.request_key)||
   !Array.isArray(body.line_ids)||body.line_ids.length<1||body.line_ids.length>50||
   !body.line_ids.every(x=>typeof x==='string'&&uid.test(x)))
    return response({error:'Righe pagamento non valide'},400);
  const {data:attempt,error}=await client.rpc('begin_group_stripe_checkout',{
   p_group_id:body.group_id,p_line_ids:body.line_ids,p_request_key:body.request_key
  });
  if(error)return response({error:error.message},409);
  if(!attempt||!uid.test(attempt.attempt_id)||
   !/^acct_[A-Za-z0-9]+$/.test(attempt.stripe_account_id)||
   !Number.isSafeInteger(Number(attempt.amount_cents))||Number(attempt.amount_cents)<=0)
   throw Error('Ledger non coerente con richiesta gruppo');
  let checkout:Record<string,any>;
  if(attempt.existing_session){
   checkout=await stripe('checkout/sessions/'+encodeURIComponent(attempt.existing_session),
     attempt.stripe_account_id,key);
  }else{
   const form=new URLSearchParams({
    mode:'payment',client_reference_id:attempt.attempt_id,
    'metadata[attempt_id]':attempt.attempt_id,
    'metadata[group_id]':body.group_id,
    'payment_intent_data[metadata][attempt_id]':attempt.attempt_id,
    'line_items[0][quantity]':'1',
    'line_items[0][price_data][currency]':'eur',
    'line_items[0][price_data][unit_amount]':String(attempt.amount_cents),
    'line_items[0][price_data][product_data][name]':'BreakApp · Righe intere del gruppo',
    expires_at:String(Math.floor(Date.now()/1000)+35*60),
    success_url:site+'#groups',cancel_url:site+'#groups'
   });
   checkout=await stripe('checkout/sessions',attempt.stripe_account_id,key,{
    method:'POST',
    headers:{'content-type':'application/x-www-form-urlencoded',
     'Idempotency-Key':'breakapp-group-'+attempt.attempt_id},
    body:form
   });
   const admin=createClient(url,required('SUPABASE_SERVICE_ROLE_KEY'),{
    auth:{persistSession:false,autoRefreshToken:false}});
   const {error:attachError}=await admin.rpc('attach_stripe_checkout_session',{
    p_attempt:attempt.attempt_id,p_session:checkout.id
   });
   if(attachError)throw Error('Sessione Stripe creata ma non collegata: '+attachError.message);
  }
  if(typeof checkout.url!=='string'||!checkout.url.startsWith('https://checkout.stripe.com/'))
   throw Error('URL Stripe non valido');
  return response({checkout_url:checkout.url,attempt_id:attempt.attempt_id});
 }catch(e){
  return response({error:e instanceof Error?e.message:'Checkout non disponibile'},503);
 }
});
