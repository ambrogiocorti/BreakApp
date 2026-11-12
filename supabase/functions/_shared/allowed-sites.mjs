// Only server-configured site URLs may receive CORS access or Stripe returns.
// A single origin maps to a single base path, so redirects cannot be supplied
// by a client or silently changed by the browser's Referer header.
export const DEFAULT_SITE_URL='https://ambrogiocorti.github.io/BreakApp/';

export function resolveAllowedSite(requestOrigin,configuredSites){
 if(typeof requestOrigin!=='string'||!requestOrigin)return null;
 const input=typeof configuredSites==='string'&&configuredSites.trim()
  ?configuredSites.split(','):[DEFAULT_SITE_URL];
 const sites=new Map();
 for(const raw of input){
  let url;
  try{url=new URL(raw.trim());}catch{return null;}
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||
     !url.hostname||url.hostname.includes('*')||sites.has(url.origin))return null;
  if(!url.pathname.endsWith('/'))url.pathname+='/';
  sites.set(url.origin,{origin:url.origin,baseUrl:url.href});
 }
 return sites.get(requestOrigin)||null;
}

export function corsHeaders(site,methods){
 return {
  ...(site?{'access-control-allow-origin':site.origin}:{}),
  'access-control-allow-methods':methods,
  'access-control-allow-headers':'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
  'cache-control':'no-store',vary:'Origin'
 };
}
