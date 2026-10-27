// Supabase Edge Function: stripe-full-refund
// Authenticated Admin (AAL2) calls a protected database RPC, not Stripe directly.
// Stripe Connect secret stays in Supabase Edge Function secrets.
import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const origin='https://ambrogiocorti.github.io';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function json(value:unknown,status=200){
 return new Response(JSON.stringify(value),{
 status,headers:{'content-type':'application/json','cache-control':'no-store',
 'access-control-allow-origin':origin,
 'access-control-allow-headers':'authorization,apikey,content-type',
 'access-control-allow-methods':'POST,OPTIONS','vary':'Origin'}});
}
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{
  'access-control-allow-origin':origin,'access-control-allow-methods':'POST,OPTIONS',
  'access-control-allow-headers':'authorization,apikey,content-type','vary':'Origin'}});
 if(req.method!=='POST')return json({error:'Metodo non consentito'},405);
 if(req.headers.get('Origin')!==origin)return json({error:'Origine non autorizzata'},403);
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'').trim();
  if(!token)return json({error:'Accesso richiesto'},401);
  const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),
   secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),stripeKey=Deno.env.get('STRIPE_SECRET_KEY');
  if(!url||!anon||!secret||!stripeKey||!stripeKey.startsWith('sk_test_'))
   return json({error:'Rimborsi Stripe test non configurati'},503);
  const userClient=createClient(url,anon,{
   global:{headers:{Authorization:'Bearer '+token}},
   auth:{persistSession:false,autoRefreshToken:false}
  });
  const {data:identity,error:authError}=await userClient.auth.getUser(token);
  if(authError||!identity.user)return json({error:'Sessione non valida'},401);
  const body=await req.json() as Record<string,unknown>;
  if(typeof body.order_id!=='string'||!uuid.test(body.order_id)||
    typeof body.request_key!=='string'||!uuid.test(body.request_key)||
    typeof body.reason!=='string'||body.reason.trim().length<8||body.reason.length>300)
   return json({error:'Richiesta rimborso non valida'},400);
  const {data:refund,error:dbError}=await userClient.rpc('request_full_individual_stripe_refund',{
   p_order_id:body.order_id,p_request_key:body.request_key,p_reason:body.reason.trim()
  });
  if(dbError)return json({error:dbError.message},409);
  if(refund?.status==='succeeded')return json({refund_id:refund.refund_id,status:'succeeded'});
  if(!uuid.test(refund?.refund_id||'')||
     !/^acct_[A-Za-z0-9]+$/.test(refund?.account||'')||
     !/^pi_[A-Za-z0-9]+$/.test(refund?.payment_intent||'')||
     !Number.isSafeInteger(refund?.amount_cents)||refund.amount_cents<=0)
   throw new Error('Ledger rimborso incoerente');
  const params=new URLSearchParams({
   payment_intent:refund.payment_intent,
   amount:String(refund.amount_cents),
   reason:'requested_by_customer',
   'metadata[breakapp_refund_id]':refund.refund_id,
   'metadata[breakapp_kind]':'ledger'
  });
  const response=await fetch('https://api.stripe.com/v1/refunds',{
    method:'POST',
    headers:{Authorization:'Bearer '+stripeKey,
      'Stripe-Account':refund.account,
      'Idempotency-Key':'breakapp-group-refund-'+refund.refund_id,
      'content-type':'application/x-www-form-urlencoded'},body:params
  });
  const stripe=await response.json() as Record<string,unknown>;
  if(!response.ok||typeof stripe.id!=='string'||
    !/^re_[A-Za-z0-9]+$/.test(stripe.id))
   throw new Error('Stripe non ha accettato il rimborso; riprova con la stessa richiesta.');
  const admin=createClient(url,secret,{
   auth:{persistSession:false,autoRefreshToken:false}
  });
  const {error:attachError}=await admin.rpc('attach_verified_stripe_refund',{
   p_refund_id:refund.refund_id,p_stripe_refund:stripe.id
  });
  if(attachError)throw new Error('Rimborso Stripe creato ma non associato: necessaria riconciliazione.');
  return json({refund_id:refund.refund_id,status:'processing'});
 }catch(e){
  return json({error:e instanceof Error?e.message:'Rimborso non disponibile'},503);
 }
});
