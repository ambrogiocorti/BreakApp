// BreakApp refund-dispatch: Stripe Connect refunds from the immutable individual and group ledger.
// Deploy verify_jwt=false. Shared trusted scheduler secret PUSH_DISPATCH_TOKEN (>=32 bytes).
// STRIPE_SECRET_KEY must remain only in Supabase Edge Function secrets.
// Responses are only attached; payment status is finalized by signed Stripe webhook.
import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const response=(data:unknown,status=200)=>new Response(JSON.stringify(data),
 {status,headers:{'content-type':'application/json','cache-control':'no-store'}});
function equal(a:string,b:string){if(a.length!==b.length)return false;
 let n=0;for(let i=0;i<a.length;i++)n|=a.charCodeAt(i)^b.charCodeAt(i);return n===0;}
Deno.serve(async request=>{
 if(request.method!=='POST')return response({error:'Metodo non consentito'},405);
 const token=Deno.env.get('PUSH_DISPATCH_TOKEN')||'';
 if(token.length<32||!equal(token,request.headers.get('x-breakapp-dispatch-token')||''))
  return response({error:'Non autorizzato'},401);
 const url=Deno.env.get('SUPABASE_URL');
 const role=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const secret=Deno.env.get('STRIPE_SECRET_KEY')||'';
 if(!url||!role||!/^sk_test_[a-zA-Z0-9]+$/.test(secret))
  return response({error:'Rimborsi Stripe in test non configurati'},503);
 const db=createClient(url,role,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:jobs,error}=await db.rpc('list_group_refunds_for_dispatch',{p_limit:10});
 if(error)return response({error:'Coda rimborsi non disponibile'},503);
 let dispatched=0,pending=0,errors=0;
 for(const job of jobs||[]){
  try{
   const payload=new URLSearchParams();
   payload.set('payment_intent',job.payment_intent);
   payload.set('amount',String(job.amount_cents));
   payload.set('metadata[breakapp_refund_id]',job.refund_id);
   payload.set('metadata[breakapp_kind]','ledger');
   payload.set('reason','requested_by_customer');
   const result=await fetch('https://api.stripe.com/v1/refunds',{
    method:'POST',headers:{
      'Authorization':'Bearer '+secret,
      'Stripe-Account':job.account,
      'Idempotency-Key':'breakapp-group-refund-'+job.refund_id,
      'Content-Type':'application/x-www-form-urlencoded'
    },body:payload
   });
   if(!result.ok){errors++;continue;}
   const refund=await result.json();
   if(!/^re_[A-Za-z0-9]+$/.test(refund.id||'')||
      refund.amount!==job.amount_cents||refund.payment_intent!==job.payment_intent||
      refund.currency!=='eur'){errors++;continue;}
   const {error:attached}=await db.rpc('attach_verified_stripe_refund',{
     p_refund_id:job.refund_id,p_stripe_refund:refund.id
   });
   if(attached){errors++;continue;}
   dispatched++;
   if(refund.status!=='succeeded')pending++;
  }catch{errors++;}
 }
 return response({seen:(jobs||[]).length,dispatched,pending,errors});
});
