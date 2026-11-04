// Supabase Edge Function: push-public-key (public information only).
import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {resolveAllowedSite,corsHeaders} from '../_shared/allowed-sites.mjs';
Deno.serve(async request=>{
 const site=resolveAllowedSite(request.headers.get('Origin'),Deno.env.get('BREAKAPP_ALLOWED_SITE_URLS'));
 const headers={
  ...corsHeaders(site,'GET, OPTIONS'),'content-type':'application/json'
 };
 if(request.method==='OPTIONS')return site?new Response(null,{status:204,headers}):
  new Response(JSON.stringify({error:'Origine non autorizzata'}),{status:403,headers});
 if(request.method!=='GET')return new Response(JSON.stringify({error:'Method not allowed'}),{status:405,headers});
 let publicKey=Deno.env.get('VAPID_PUBLIC_KEY');
 if(!publicKey){
  const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(url&&key){
   const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data,error}=await db.rpc('push_runtime_configuration');
   if(!error)publicKey=data?.breakapp_vapid_public;
  }
 }
 if(!publicKey)return new Response(JSON.stringify({error:'Push non configurate'}),{status:503,headers});
 if(!/^[A-Za-z0-9_-]{80,120}$/.test(publicKey))
  return new Response(JSON.stringify({error:'Chiave push non valida'}),{status:503,headers});
 return new Response(JSON.stringify({public_key:publicKey}),{status:200,headers});
});
