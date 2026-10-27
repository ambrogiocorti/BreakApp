// Supabase Edge Function: push-dispatch
// Requires PUSH_DISPATCH_TOKEN (random >=32 chars), VAPID_PUBLIC_KEY,
// VAPID_PRIVATE_KEY, VAPID_SUBJECT, SUPABASE_SERVICE_ROLE_KEY.
// Deploy with verify_jwt=false; validate dispatch token before DB access.
import webpush from 'npm:web-push@3.6.7';
import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
function out(data:unknown,status=200){
 return new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json',
   'cache-control':'no-store'}});
}
function constantTime(a:string,b:string){
 if(a.length!==b.length)return false;
 let n=0;for(let i=0;i<a.length;i++)n|=a.charCodeAt(i)^b.charCodeAt(i);
 return n===0;
}
Deno.serve(async request=>{
 if(request.method!=='POST')return out({error:'Metodo non consentito'},405);
 const url=Deno.env.get('SUPABASE_URL');
 const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!service)return out({error:'Dispatcher non configurato'},503);
 const db=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:config,error:configError}=await db.rpc('push_runtime_configuration');
 const key=Deno.env.get('PUSH_DISPATCH_TOKEN')||config?.breakapp_dispatch_token||'';
 const supplied=request.headers.get('x-breakapp-dispatch-token')||'';
 if(key.length<32||!constantTime(key,supplied))return out({error:'Non autorizzato'},401);
 const vapidPublic=Deno.env.get('VAPID_PUBLIC_KEY')||config?.breakapp_vapid_public;
 const vapidPrivate=Deno.env.get('VAPID_PRIVATE_KEY')||config?.breakapp_vapid_private;
 const subject=Deno.env.get('VAPID_SUBJECT')||config?.breakapp_vapid_subject;
 if(!url||!service||!vapidPublic||!vapidPrivate||!subject)
  return out({error:'Dispatcher non configurato'},503);
 try{
  webpush.setVapidDetails(subject,vapidPublic,vapidPrivate);
  const {error:warningError}=await db.rpc('warn_group_drafts_before_expiry',{p_limit:50});
  const {error:expiryError}=await db.rpc('expire_group_drafts',{p_limit:50});
  if(warningError||expiryError)return out({error:'Manutenzione gruppi non disponibile'},503);
  const {data:jobs,error:claimError}=await db.rpc('claim_push_jobs',{p_limit:15});
  if(claimError)return out({error:'Coda indisponibile'},503);
  let succeeded=0,failed=0;
  for(const job of jobs||[]){
    let ok=false,status=0,err='';
    try{
      const data=JSON.stringify({title:'BreakApp',body:'Hai un nuovo avviso in BreakApp.',
       url:'/BreakApp/#accesso'});
      const result=await webpush.sendNotification({
        endpoint:job.endpoint,
        keys:{p256dh:job.p256dh,auth:job.auth}
      },data,{TTL:1800,urgency:'normal'});
      status=result.statusCode||201;ok=status>=200&&status<300;
    }catch(e){
      status=typeof e==='object'&&e!==null&&'statusCode' in e?
        Number((e as {statusCode?:number}).statusCode||0):0;
      err='Web Push delivery failed';
    }
    const {error:finishError}=await db.rpc('finish_push_job',{
      p_job_id:job.job_id,p_success:ok,p_status_code:status,p_error:err
    });
    if(finishError)return out({error:'Riconciliazione consegne non riuscita'},503);
    if(ok)succeeded++;else failed++;
  }
  return out({processed:(jobs||[]).length,succeeded,failed});
 }catch{
  return out({error:'Dispatcher temporaneamente non disponibile'},503);
 }
});
