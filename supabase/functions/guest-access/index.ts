import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*',
 'access-control-allow-headers':'authorization,apikey,content-type,x-client-info','access-control-allow-methods':'POST,OPTIONS'};
const out=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))).map(n=>n.toString(16).padStart(2,'0')).join('');
const randomToken=()=>Array.from(crypto.getRandomValues(new Uint8Array(32))).map(n=>n.toString(16).padStart(2,'0')).join('');
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return out({error:'Metodo non consentito'},405);
 if(Number(req.headers.get('content-length')||0)>4096)return out({error:'Richiesta non valida'},400);
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!key)return out({error:'Servizio non configurato'},503);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const raw=await req.text();if(raw.length>4096)return out({error:'Richiesta troppo grande'},400);
  const body=JSON.parse(raw);let token=body.token as string;let userId:string|undefined;let returnPrivate=false;
  const {data:config}=await db.rpc('push_runtime_configuration');
  const fingerprint=await hash((config?.breakapp_dispatch_token||'guest')+':'+(req.headers.get('x-forwarded-for')||'unknown').slice(0,160));
  const {error:rateError}=await db.rpc('claim_guest_creation',{p_fingerprint:fingerprint});
  if(rateError)return out({error:'Troppe richieste. Riprova tra qualche minuto.'},429);
  if(['prepare_recovery','list_recovery','confirm_recovery','recover_verified'].includes(body.action)){
   const jwt=req.headers.get('authorization')?.replace(/^Bearer\s+/i,'').trim();if(!jwt)return out({error:'Accesso richiesto'},401);
   const {data:identity,error:identityError}=await db.auth.getUser(jwt);const actor=identity.user;
   if(identityError||!actor)return out({error:'Sessione non valida'},401);
   if(body.action==='prepare_recovery'){
    const email=typeof body.email==='string'?body.email.trim().toLowerCase():'';
    if(email.length>255||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.endsWith('@guest.breakapp.invalid'))return out({error:'Email non valida'},400);
    const {data,error}=await db.rpc('prepare_guest_email_recovery',{p_guest:actor.id,p_email_hash:await hash(email)});
    if(error)return out({error:'Richiesta non disponibile: accedi come ospite o attendi prima di riprovare.'},409);
    return out({request_id:data});
   }
   if(!actor.email_confirmed_at||!actor.email||actor.email.endsWith('@guest.breakapp.invalid'))return out({error:'Accedi tramite il link ricevuto sulla tua email verificata'},403);
   const emailHash=await hash(actor.email.trim().toLowerCase());
   if(body.action==='list_recovery'){
    const {data,error}=await db.rpc('list_verified_guest_recovery',{p_identity:actor.id,p_email_hash:emailHash});
    return error?out({error:'Recupero non disponibile'},409):out(data);
   }
   const {data,error}=body.action==='confirm_recovery'
    ?await db.rpc('confirm_guest_email_recovery',{p_request:body.request_id,p_identity:actor.id,p_email_hash:emailHash})
    :await db.rpc('resolve_verified_guest_recovery',{p_identity:actor.id});
   if(error||!data)return out({error:'Profilo non disponibile per questa email. Verifica la richiesta e la sua scadenza.'},403);
   userId=data;token=randomToken();
   const rotated=await db.rpc('rotate_guest_private_link',{p_guest:userId,p_hash:await hash(token)});
   if(rotated.error)return out({error:'Profilo non disponibile'},409);returnPrivate=true;
  }else if(body.action==='create'){
   if(typeof body.name!=='string'||body.name.trim().length<2||body.name.length>100||typeof body.school_id!=='string'||
    (body.class_name&&String(body.class_name).length>80))return out({error:'Nome, scuola e classe non validi'},400);
   token=randomToken();returnPrivate=true;
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
   ...(returnPrivate?{private_token:token}:{})});
 }catch{return out({error:'Richiesta non valida'},400);}
});
