const responseHeaders={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*','access-control-allow-headers':'authorization,apikey,content-type,x-client-info','access-control-allow-methods':'POST,OPTIONS'};
const out=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:responseHeaders});
async function readBody(request){
 const reader=request.body?.getReader();if(!reader)throw new Error('body');
 const chunks=[];let length=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;length+=value.byteLength;if(length>4096){await reader.cancel();throw new Error('size');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 return JSON.parse(new TextDecoder().decode(bytes));
}
// La registrazione self-service di un account @admin.breakapp.it è consentita
// SOLO con un codice di invito valido emesso dal Super Admin: senza invito
// pendente corrispondente (email + codice, scuola attiva) non viene creato
// alcun account. Creato l'account, il ruolo viene assegnato e l'invito consumato
// in un unico passo lato database. La firma accetta (e ignora) un argomento
// mancante per retrocompatibilità con i test che non passano le dipendenze.
export function createAdminRegistrationHandler({createClient,env}={}){
 return async request=>{
  if(request.method==='OPTIONS')return new Response(null,{headers:responseHeaders});
  if(request.method!=='POST')return out({error:'Metodo non consentito.'},405);
  if(Number(request.headers.get('content-length')||0)>4096)return out({error:'Richiesta troppo grande.'},413);
  if(typeof createClient!=='function'||typeof env!=='function')return out({error:'Registrazione temporaneamente non disponibile.'},503);
  const url=env('SUPABASE_URL'),key=env('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!key)return out({error:'Registrazione temporaneamente non disponibile.'},503);
  // Publishable keys are not JWTs: authenticate the project API key here rather
  // than enabling the legacy JWT-only gateway check for this public signup API.
  let publicKeys;
  try{publicKeys=Object.values(JSON.parse(env('SUPABASE_PUBLISHABLE_KEYS')||'{}')).filter(value=>typeof value==='string');}
  catch{return out({error:'Registrazione temporaneamente non disponibile.'},503);}
  const legacyAnon=env('SUPABASE_ANON_KEY');if(legacyAnon)publicKeys.push(legacyAnon);
  if(!publicKeys.length)return out({error:'Registrazione temporaneamente non disponibile.'},503);
  if(!publicKeys.includes(request.headers.get('apikey')||''))return out({error:'Richiesta non autorizzata.'},401);
  let body;
  try{body=await readBody(request);}catch{return out({error:'Richiesta non valida.'},400);}
  const email=typeof body?.email==='string'?body.email.trim().toLowerCase():'',password=body?.password;
  const code=typeof body?.code==='string'?body.code.trim():'';
  if(email.length>254||!/^[^\s@]+@admin\.breakapp\.it$/.test(email)||typeof password!=='string'||password.length<8||password.length>256)return out({error:'Email o password non validi.'},400);
  if(!code||code.length>64)return out({error:'Codice di invito mancante o non valido.'},400);
  try{
   const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
   // Store only a keyed fingerprint; never log credentials or the source address.
   const hmac=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);
   const ip=(request.headers.get('x-forwarded-for')||'unknown').split(',')[0].trim().slice(0,160);
   const bytes=new Uint8Array(await crypto.subtle.sign('HMAC',hmac,new TextEncoder().encode('admin-registration:'+ip)));
   const fingerprint=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
   const limit=await db.rpc('claim_admin_registration',{p_fingerprint:fingerprint});
   if(limit.error)return out({error:'Troppe richieste. Riprova tra qualche minuto.'},429);
   // Nessun account viene creato se il codice di invito non è valido.
   const valid=await db.rpc('admin_registration_invite_valid',{p_email:email,p_code:code});
   if(valid.error||valid.data!==true)return out({error:'Codice di invito non valido o già usato. Contatta il Super Admin.'},403);
   const created=await db.auth.admin.createUser({email,password,email_confirm:true});
   const existed=created.error&&['email_exists','user_already_exists'].includes(created.error.code);
   if(created.error&&!existed)return out({error:'Registrazione non riuscita. Verifica i dati o prova ad accedere.'},400);
   // Assegna il ruolo e consuma l'invito. Se fallisce su un account appena
   // creato, lo rimuove per non lasciare account orfani senza ruolo.
   const consumed=await db.rpc('consume_admin_registration_invite',{p_email:email,p_code:code});
   if(consumed.error){
    if(!existed&&created.data?.user?.id){try{await db.auth.admin.deleteUser(created.data.user.id);}catch{/* best effort */}}
    return out({error:'Codice di invito non valido o già usato. Contatta il Super Admin.'},403);
   }
   return out({ok:true});
  }catch{return out({error:'Registrazione temporaneamente non disponibile.'},503);}
 };
}
