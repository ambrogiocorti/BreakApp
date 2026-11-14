// Supabase Edge Function: stripe-checkout-cancel
// Il barista annulla un pagamento con carta avviato dal cliente e non concluso,
// per incassare al banco. Stripe fa scadere il Checkout: da quel momento il
// cliente non puo' piu' pagare online, quindi non c'e' doppio incasso.
// Requires STRIPE_SECRET_KEY, SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY (Edge Function secrets; never frontend).
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import {resolveAllowedSite,corsHeaders} from '../_shared/allowed-sites.mjs';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function required(name:string){
 const value=Deno.env.get(name);if(!value)throw new Error('Configurazione server incompleta: '+name);
 return value;
}
async function stripe(endpoint:string,account:string,key:string,init?:RequestInit){
 const response=await fetch('https://api.stripe.com/v1/'+endpoint,{
  ...init,headers:{authorization:'Bearer '+key,'Stripe-Account':account,...(init?.headers||{})}});
 const data=await response.json() as Record<string,unknown>;
 return {ok:response.ok,data};
}
Deno.serve(async(req)=>{
 const site=resolveAllowedSite(req.headers.get('Origin'),Deno.env.get('BREAKAPP_ALLOWED_SITE_URLS'));
 const headers=corsHeaders(site,'POST, OPTIONS');
 const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{
  status,headers:{...headers,'content-type':'application/json; charset=utf-8'}});
 if(!site)return json({error:'Origine non autorizzata'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return json({error:'Metodo non consentito'},405);
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'').trim();
  if(!token)return json({error:'Sessione richiesta'},401);
  const url=required('SUPABASE_URL');
  const stripeKey=required('STRIPE_SECRET_KEY');
  if(!/^[sr]k_test_[A-Za-z0-9]+$/.test(stripeKey))return json({error:'Pagamenti attivi solo in ambiente di test'},503);
  const db=createClient(url,required('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:'Bearer '+token}},
   auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await db.auth.getUser(token);
  if(authError||!identity.user)return json({error:'Sessione non valida'},401);
  const payload=await req.json() as Record<string,unknown>;
  if(typeof payload.order_id!=='string'||!uuid.test(payload.order_id))return json({error:'Ordine non valido'},400);
  // Controllo del personale e dati del Checkout con i permessi dell'utente.
  const {data:open,error:openError}=await db.rpc('staff_checkout_to_cancel',{p_order:payload.order_id});
  if(openError)return json({error:openError.message},409);
  if(!open?.open)return json({status:'none'});
  if(!uuid.test(open.attempt_id))return json({error:'Tentativo di pagamento incoerente'},500);
  const session=open.session as string|null;
  if(session){
   if(!/^cs_(test|live)_[A-Za-z0-9]+$/.test(session)||!/^acct_[A-Za-z0-9]+$/.test(open.account||''))
    return json({error:'Dati Stripe incoerenti'},500);
   const path='checkout/sessions/'+encodeURIComponent(session);
   let result=await stripe(path+'/expire',open.account,stripeKey,{method:'POST'});
   // Gia' scaduta o conclusa: si legge lo stato reale da Stripe.
   if(!result.ok)result=await stripe(path,open.account,stripeKey);
   if(!result.ok)return json({error:'Stripe non raggiungibile: riprova tra poco'},503);
   const s=result.data;
   if(s.status!=='expired'||s.payment_status!=='unpaid')
    return json({error:'Il cliente ha già completato il pagamento con carta: aggiorna la lista prima di incassare.'},409);
  }
  const admin=createClient(url,required('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:outcome,error}=await admin.rpc('cancel_abandoned_checkout',{p_attempt:open.attempt_id,p_session:session});
  if(error)return json({error:error.message},409);
  if(outcome==='not_cancelled')return json({error:'Il pagamento con carta è in elaborazione: aspetta l’esito.'},409);
  return json({status:'cancelled'});
 }catch(error){
  // Never print keys, tokens, or payment payloads in responses/logs.
  return json({error:error instanceof Error?error.message:'Annullamento non disponibile'},503);
 }
});
