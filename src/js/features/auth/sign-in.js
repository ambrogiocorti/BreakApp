export const isInternalAdminEmail=email=>typeof email==='string'&&email.trim().length<=254&&/^[^\s@]+@admin\.breakapp\.it$/i.test(email.trim());

export function oauthRequest(provider,redirectTo){
 if(!['google','azure'].includes(provider))throw new Error('Metodo di accesso non supportato.');
 return {provider,options:{redirectTo,scopes:provider==='azure'?'email':'openid email profile',queryParams:{prompt:'select_account'}}};
}

export async function registerWithPassword(client,credentials,redirectTo){
 if(!isInternalAdminEmail(credentials.email))return client.auth.signUp({...credentials,options:{emailRedirectTo:redirectTo}});
 // The service applies the exact-domain exception; the browser cannot confirm
 // an email or set app_metadata, memberships or administrator roles.
 const result=await client.functions.invoke('admin-registration',{body:{email:credentials.email.trim().toLowerCase(),password:credentials.password}});
 if(result.error){
  let message='Registrazione non disponibile. Riprova tra poco.';
  try{const detail=await result.error.context?.clone().json();if(typeof detail?.error==='string')message=detail.error;}catch{/* No internal response details. */}
  return {data:null,error:new Error(message)};
 }
 if(result.data?.ok!==true)return {data:null,error:new Error('Registrazione non disponibile. Riprova tra poco.')};
 return client.auth.signInWithPassword(credentials);
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
