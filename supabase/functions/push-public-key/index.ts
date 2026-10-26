// Supabase Edge Function: push-public-key (public information only).
Deno.serve(request=>{
 const headers={
  'content-type':'application/json','cache-control':'no-store',
  'access-control-allow-origin':'https://ambrogiocorti.github.io',
  'access-control-allow-methods':'GET, OPTIONS','vary':'Origin'
 };
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='GET')return new Response(JSON.stringify({error:'Method not allowed'}),{status:405,headers});
 const publicKey=Deno.env.get('VAPID_PUBLIC_KEY');
 if(!publicKey)return new Response(JSON.stringify({error:'Push non configurate'}),{status:503,headers});
 if(!/^[A-Za-z0-9_-]{80,120}$/.test(publicKey))
  return new Response(JSON.stringify({error:'Chiave push non valida'}),{status:503,headers});
 return new Response(JSON.stringify({public_key:publicKey}),{status:200,headers});
});
