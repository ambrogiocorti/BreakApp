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
export function createAdminRegistrationHandler({createClient,env}){
 return async request=>{
  if(request.method==='OPTIONS')return new Response(null,{headers:responseHeaders});
  if(request.method!=='POST')return out({error:'Metodo non consentito.'},405);
  if(Number(request.headers.get('content-length')||0)>4096)return out({error:'Richiesta troppo grande.'},413);
  const url=env('SUPABASE_URL'),key=env('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!key)return out({error:'Registrazione temporaneamente non disponibile.'},503);
  let body;
  try{body=await readBody(request);}catch{return out({error:'Richiesta non valida.'},400);}
  const email=typeof body?.email==='string'?body.email.trim().toLowerCase():'',password=body?.password;
  if(email.length>254||!/^[^\s@]+@admin\.breakapp\.it$/.test(email)||typeof password!=='string'||password.length<8||password.length>256)return out({error:'Email o password non validi.'},400);
  try{
   const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
   // Store only a keyed fingerprint; never log credentials or the source address.
   const hmac=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);
   const ip=(request.headers.get('x-forwarded-for')||'unknown').split(',')[0].trim().slice(0,160);
   const bytes=new Uint8Array(await crypto.subtle.sign('HMAC',hmac,new TextEncoder().encode('admin-registration:'+ip)));
   const fingerprint=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
   const limit=await db.rpc('claim_admin_registration',{p_fingerprint:fingerprint});
   if(limit.error)return out({error:'Troppe richieste. Riprova tra qualche minuto.'},429);
   const created=await db.auth.admin.createUser({email,password,email_confirm:true});
   // A repeated registration never changes an existing identity or its password.
   // Return the same result; the normal password sign-in proves account ownership.
   if(created.error&&!['email_exists','user_already_exists'].includes(created.error.code))return out({error:'Registrazione non riuscita. Verifica i dati o prova ad accedere.'},400);
   return out({ok:true});
  }catch{return out({error:'Registrazione temporaneamente non disponibile.'},503);}
 };
}
