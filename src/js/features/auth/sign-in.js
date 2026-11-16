export const isInternalAdminEmail=email=>typeof email==='string'&&email.trim().length<=254&&/^[^\s@]+@admin\.breakapp\.it$/i.test(email.trim());

export function oauthRequest(provider,redirectTo){
 if(!['google','azure'].includes(provider))throw new Error('Metodo di accesso non supportato.');
 return {provider,options:{redirectTo,scopes:provider==='azure'?'email':'openid email profile',queryParams:{prompt:'select_account'}}};
}

export async function registerWithPassword(client,credentials,redirectTo){
 // La registrazione self-service degli account amministratore è stata rimossa
 // (scelta del 16/11/2026): gli account Admin sono creati solo dal Super Admin.
 // Gli indirizzi @admin.breakapp.it non possono più registrarsi da qui.
 if(isInternalAdminEmail(credentials.email))
  return {data:null,error:new Error('Gli account amministratore non si registrano da qui: vengono creati dal Super Admin. Accedi con l’email indicata dal Super Admin e inserisci il codice invito nel Profilo.')};
 return client.auth.signUp({...credentials,options:{emailRedirectTo:redirectTo}});
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
