// Supabase Edge Function: stripe-webhook
// Must be deployed verify_jwt=false: Stripe cannot send a Supabase JWT.
// Authentication is Stripe-Signature verification over RAW body bytes;
// STRIPE_WEBHOOK_SECRET is stored in Supabase Edge Function secrets only.
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const respond=(value:unknown,status:number)=>new Response(JSON.stringify(value),{
 status,headers:{'content-type':'application/json','cache-control':'no-store'}
});
const hex=(bytes:Uint8Array)=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
const equal=(a:string,b:string)=>{
 if(a.length!==b.length)return false;
 let diff=0;
 for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
 return diff===0;
};
async function verify(raw:string,signature:string,secret:string):Promise<boolean>{
 const values:Record<string,string[]>={};
 for(const part of signature.split(',')){
  const i=part.indexOf('=');if(i<1)continue;
  const k=part.slice(0,i),v=part.slice(i+1);
  (values[k]||=[]).push(v);
 }
 const timestamp=Number(values.t?.[0]);
 const candidates=values.v1||[];
 if(!Number.isSafeInteger(timestamp)||candidates.length===0||
  Math.abs(Date.now()/1000-timestamp)>300)return false;
 const encoder=new TextEncoder();
 const key=await crypto.subtle.importKey('raw',encoder.encode(secret),
  {name:'HMAC',hash:'SHA-256'},false,['sign']);
 const digest=hex(new Uint8Array(await crypto.subtle.sign('HMAC',key,
  encoder.encode(timestamp+'.'+raw))));
 return candidates.some(value=>equal(digest,value));
}
Deno.serve(async request=>{
 if(request.method!=='POST')return respond({error:'Metodo non consentito'},405);
 try{
  const secret=Deno.env.get('STRIPE_WEBHOOK_SECRET');
  if(!secret)return respond({error:'Webhook non configurato'},503);
  const signature=request.headers.get('stripe-signature')||'';
  const raw=await request.text();
  if(raw.length>262144)return respond({error:'Evento troppo grande'},413);
  if(!await verify(raw,signature,secret))
   return respond({error:'Firma Stripe non valida'},400);
  const evt=JSON.parse(raw) as Record<string,any>;
  if(!/^evt_[A-Za-z0-9]+$/.test(evt.id||'')||evt.livemode!==false)
   return respond({error:'Evento Stripe non valido per il test'},400);
  if(evt.type==='checkout.session.expired'){
    const expired=evt.data?.object;
    if(!expired||expired.object!=='checkout.session'||
      expired.status!=='expired'||expired.payment_status!=='unpaid'||
      expired.metadata?.attempt_id!==expired.client_reference_id||
      !/^[0-9a-f-]{36}$/i.test(expired.client_reference_id||'')||
      !/^cs_(test|live)_[A-Za-z0-9]+$/.test(expired.id||'')||
      !/^acct_[A-Za-z0-9]+$/.test(evt.account||''))
      return respond({error:'Evento scadenza Checkout non valido'},400);
    const url=Deno.env.get('SUPABASE_URL'),
      key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if(!url||!key)return respond({error:'Backend non configurato'},503);
    const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error}=await admin.rpc('reconcile_signed_checkout_expiry',{
      p_event_id:evt.id,p_stripe_account:evt.account,
      p_session:expired.id,p_attempt:expired.client_reference_id
    });
    if(error)return respond({error:'Scadenza non riconciliata'},500);
    return respond({received:true,result:data},200);
  }
  if(evt.type==='refund.updated'){
    const refund=evt.data?.object;
    if(!refund||refund.object!=='refund'||
      !['succeeded','failed'].includes(refund.status)||
      !/^re_[A-Za-z0-9]+$/.test(refund.id||'')||
      !/^pi_[A-Za-z0-9]+$/.test(refund.payment_intent||'')||
      !/^acct_[A-Za-z0-9]+$/.test(evt.account||'')||
      !/^[0-9a-f-]{36}$/i.test(refund.metadata?.breakapp_refund_id||'')||
      !Number.isSafeInteger(refund.amount)||refund.amount<=0||refund.currency!=='eur')
      return respond({error:'Evento rimborso incompleto o incongruente'},400);
    const url=Deno.env.get('SUPABASE_URL'),
      key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if(!url||!key)return respond({error:'Backend non configurato'},503);
    const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error}=await admin.rpc('finalize_verified_stripe_refund',{
      p_event_id:evt.id,p_stripe_account:evt.account,
      p_refund_id:refund.metadata.breakapp_refund_id,
      p_stripe_refund:refund.id,p_payment_intent:refund.payment_intent,
      p_amount:refund.amount,p_currency:refund.currency,p_status:refund.status
    });
    if(error)return respond({error:'Rimborso non riconciliato'},500);
    return respond({received:true,result:data},200);
  }
  if(evt.type!=='checkout.session.completed')
   return respond({received:true,handled:false},200);
  const session=evt.data?.object;
  if(!session||session.object!=='checkout.session'||
   session.mode!=='payment'||session.payment_status!=='paid'||
   session.currency!=='eur'||session.amount_total<=0||
   typeof session.payment_intent!=='string'||session.metadata?.attempt_id!==session.client_reference_id||
   !/^acct_[A-Za-z0-9]+$/.test(evt.account||''))
   return respond({error:'Evento pagamento incompleto o incongruente'},400);
  const url=Deno.env.get('SUPABASE_URL'),
   key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!key)return respond({error:'Backend non configurato'},503);
  const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await admin.rpc('finalize_verified_checkout',{
   p_event_id:evt.id,p_event_account:evt.account,
   p_session:session.id,p_intent:session.payment_intent,
   p_attempt:session.metadata.attempt_id,
   p_amount:session.amount_total,p_currency:session.currency,
   p_paid:true,p_payload:{
     event_id:evt.id,event_type:evt.type,session_id:session.id,
     account:evt.account,amount_total:session.amount_total,currency:session.currency
   }
  });
  if(error){
   // Stripe retries non-2xx responses. Never acknowledge uncommitted ledger.
   return respond({error:'Registrazione transazione non riuscita'},500);
  }
  return respond({received:true,result:data},200);
 }catch{
  return respond({error:'Evento non elaborabile'},500);
 }
});
