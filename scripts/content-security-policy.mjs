// Content Security Policy per GitHub Pages. GitHub Pages ignora public/_headers,
// quindi la policy viene scritta in un tag <meta> durante la build. Un <meta>
// non può esprimere frame-ancestors: quella protezione resta affidata
// all'hosting quando sarà disponibile.
export function supabaseOrigins(url){
 try{
  const parsed=new URL(String(url||'').trim());
  if(parsed.protocol!=='https:'&&parsed.protocol!=='http:')return [];
  const ws=(parsed.protocol==='https:'?'wss://':'ws://')+parsed.host;
  return [parsed.origin,ws];
 }catch{return [];}
}

export function contentSecurityPolicy(supabaseUrl){
 const [http,ws]=supabaseOrigins(supabaseUrl);
 return [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self' data: blob:"+(http?' '+http:''),
  "font-src 'self'",
  "connect-src 'self'"+(http?' '+http+' '+ws:''),
  "worker-src 'self'",
  "manifest-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'"
 ].join('; ');
}

export function contentSecurityPolicyPlugin(env){
 return {
  name:'breakapp-content-security-policy',
  apply:'build',
  // Subito dopo il charset, prima di qualunque script o foglio di stile.
  transformIndexHtml(html){
   const meta='<meta http-equiv="Content-Security-Policy" content="'+contentSecurityPolicy(env.VITE_SUPABASE_URL)+'" />';
   const charset=/<meta charset="UTF-8" \/>/i;
   if(!charset.test(html))throw new Error('index.html: meta charset non trovato, impossibile inserire la CSP');
   return html.replace(charset,match=>match+'\n    '+meta);
  }
 };
}
