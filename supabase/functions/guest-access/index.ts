import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*',
 'access-control-allow-headers':'authorization,apikey,content-type,x-client-info','access-control-allow-methods':'POST,OPTIONS'};
const out=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))).map(n=>n.toString(16).padStart(2,'0')).join('');
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return out({error:'Metodo non consentito'},405);
 if(Number(req.headers.get('content-length')||0)>4096)return out({error:'Richiesta non valida'},400);
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!key)return out({error:'Servizio non configurato'},503);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const raw=await req.text();if(raw.length>4096)return out({error:'Richiesta troppo grande'},400);
  const body=JSON.parse(raw);let token=body.token as string;let userId:string|undefined;
  const {data:config}=await db.rpc('push_runtime_configuration');
  const fingerprint=await hash((config?.breakapp_dispatch_token||'guest')+':'+(req.headers.get('x-forwarded-for')||'unknown').slice(0,160));
  const {error:rateError}=await db.rpc('claim_guest_creation',{p_fingerprint:fingerprint});
  if(rateError)return out({error:'Troppe richieste. Riprova tra qualche minuto.'},429);
  if(body.action==='create'){
   if(typeof body.name!=='string'||body.name.trim().length<2||body.name.length>100||typeof body.school_id!=='string'||
    (body.class_name&&String(body.class_name).length>80))return out({error:'Nome, scuola e classe non validi'},400);
   token=Array.from(crypto.getRandomValues(new Uint8Array(32))).map(n=>n.toString(16).padStart(2,'0')).join('');
   const {data,error}=await db.auth.admin.createUser({email:crypto.randomUUID()+'@guest.breakapp.invalid',email_confirm:true,
    password:crypto.randomUUID()+crypto.randomUUID(),app_metadata:{guest:true},user_metadata:{display_name:body.name.trim()}});
   if(error||!data.user)return out({error:'Accesso ospite non disponibile'},503);userId=data.user.id;
   const {error:saveError}=await db.rpc('create_guest_access',{p_user:userId,p_school:body.school_id,p_name:body.name.trim(),p_class:body.class_name||'',p_hash:await hash(token)});
   if(saveError){await db.auth.admin.deleteUser(userId);return out({error:'Scuola o dati ospite non validi'},400);}
  }else{
   if(typeof token!=='string'||!/^[a-f0-9]{64}$/.test(token))return out({error:'Link non valido o scaduto'},403);
   const {data}=await db.rpc('resolve_guest_access',{p_hash:await hash(token)});userId=data||undefined;
  }
  if(!userId)return out({error:'Link non valido o scaduto'},403);
  const {data:userData,error:userError}=await db.auth.admin.getUserById(userId);
  if(userError||!userData.user?.email)return out({error:'Link non valido o scaduto'},403);
  const {data:link,error:linkError}=await db.auth.admin.generateLink({type:'magiclink',email:userData.user.email});
  if(linkError||!link.properties?.hashed_token)return out({error:'Accesso non disponibile'},503);
  const publicClient=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:session,error:sessionError}=await publicClient.auth.verifyOtp({token_hash:link.properties.hashed_token,type:'magiclink'});
  if(sessionError||!session.session)return out({error:'Accesso non disponibile'},503);
  return out({access_token:session.session.access_token,refresh_token:session.session.refresh_token,
   ...(body.action==='create'?{private_token:token}:{})});
 }catch{return out({error:'Richiesta non valida'},400);}
});
