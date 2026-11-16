export const isInternalAdminEmail=email=>typeof email==='string'&&email.trim().length<=254&&/^[^\s@]+@admin\.breakapp\.it$/i.test(email.trim());

export function oauthRequest(provider,redirectTo){
 if(!['google','azure'].includes(provider))throw new Error('Metodo di accesso non supportato.');
 return {provider,options:{redirectTo,scopes:provider==='azure'?'email':'openid email profile',queryParams:{prompt:'select_account'}}};
}

export async function registerWithPassword(client,credentials,redirectTo){
 const {email,password,code}=credentials;
 // Gli account @admin.breakapp.it si registrano solo con un codice di invito
 // valido emesso dal Super Admin: l'edge function crea l'account e assegna il
 // ruolo solo se il codice corrisponde a un invito pendente. Gli altri indirizzi
 // seguono la normale registrazione con conferma via email.
 if(isInternalAdminEmail(email)){
  const invite=(code||'').trim();
  if(!invite)
   return {data:null,error:new Error('Inserisci il codice di invito ricevuto dal Super Admin per creare l’account amministratore.')};
  const registration=await client.functions.invoke('admin-registration',{body:{email,password,code:invite}});
  if(registration.error)
   return {data:null,error:new Error('Registrazione non riuscita: codice di invito non valido o già usato. Contatta il Super Admin.')};
  return client.auth.signInWithPassword({email,password});
 }
 return client.auth.signUp({email,password,options:{emailRedirectTo:redirectTo}});
}

export async function readOAuthProviders(config,fetcher=fetch){
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),8000);
 try{
  const response=await fetcher(new URL('/auth/v1/settings',config.url),{headers:{apikey:config.publishableKey},credentials:'omit',cache:'no-store',signal:controller.signal});
  if(!response.ok)throw new Error('Stato degli accessi non disponibile.');
  const data=await response.json();
  if(typeof data.external?.google!=='boolean'||typeof data.external?.azure!=='boolean')throw new Error('Stato degli accessi non disponibile.');
  return {google:data.external.google,azure:data.external.azure};
 }finally{clearTimeout(timeout);}
}

export function oauthReturnError(location){
 const query=new URLSearchParams(location.search),fragment=new URLSearchParams(location.hash.slice(1));
 const code=query.get('error_code')||query.get('error')||fragment.get('error_code')||fragment.get('error');
 if(!code)return null;
 return ['access_denied','provider_access_denied'].includes(code)?'Accesso annullato. Puoi riprovare o usare email e password.':'Non è stato possibile completare l’accesso. Riprova o usa email e password.';
}
