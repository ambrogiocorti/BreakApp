// Public, credential-free availability probe for the deployed BreakApp PWA.
// It checks a real hosted HTML page, PWA manifest, and service worker.
// Deliberately does NOT claim to test Stripe, Supabase Auth, RLS, or a live order.
import {pathToFileURL} from 'node:url';

export async function checkPages({
  siteUrl=process.env.BREAKAPP_HEALTH_URL||'https://ambrogiocorti.github.io/BreakApp/',
  fetchImpl=globalThis.fetch,
  timeoutMs=15000
}={}){
  const site=new URL(siteUrl);
  if(site.protocol!=='https:'||!site.pathname.endsWith('/'))
    throw new Error('Health URL must be an HTTPS directory URL ending in /');
  const start=Date.now();
  async function get(path,label){
    const url=path?new URL(path,site):site;
    const response=await fetchImpl(url,{redirect:'follow',signal:AbortSignal.timeout(timeoutMs)});
    if(response.status!==200)throw new Error(`${label} returned HTTP ${response.status}`);
    return response;
  }
  const page=await (await get('', 'Landing page')).text();
  if(!/<title>\s*BreakApp\b/i.test(page)||!page.includes('id="auth-form"'))
    throw new Error('Hosted page does not contain the BreakApp login');
  const manifest=await (await get('manifest.webmanifest','PWA manifest')).json();
  if(manifest.name!=='BreakApp'||manifest.display!=='standalone'||
     manifest.start_url!==site.pathname||manifest.scope!==site.pathname)
    throw new Error('PWA manifest is missing or is scoped to the wrong location');
  const serviceWorker=await (await get('sw.js','Service worker')).text();
  if(!serviceWorker.includes("addEventListener"))
    throw new Error('Service worker response is not a JavaScript worker');
  return {ok:true,origin:site.origin,path:site.pathname,
    verified:['HTML login','PWA manifest','Service Worker'],
    elapsed_ms:Date.now()-start};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  checkPages().then(data=>console.log(JSON.stringify(data)))
    .catch(error=>{console.error('BreakApp availability probe failed:',error.message);
      process.exitCode=1;});
}
