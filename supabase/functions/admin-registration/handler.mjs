const responseHeaders={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*','access-control-allow-headers':'authorization,apikey,content-type,x-client-info','access-control-allow-methods':'POST,OPTIONS'};
const out=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:responseHeaders});

// La registrazione self-service degli account amministratore è stata RIMOSSA
// (scelta del 16/11/2026, punto 4 del report di sicurezza): gli account Admin
// sono creati solo dal Super Admin. Questo endpoint è disattivato e non crea
// più alcun account né tocca il database: risponde 410 a qualsiasi richiesta.
// La firma accetta (e ignora) le dipendenze per retrocompatibilità con i test.
export function createAdminRegistrationHandler(){
 return async request=>{
  if(request.method==='OPTIONS')return new Response(null,{headers:responseHeaders});
  return out({error:'Registrazione amministratore disattivata: gli account Admin sono creati dal Super Admin.'},410);
 };
}
