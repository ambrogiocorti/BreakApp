// Static shell only. Financial events and same-day manifests use the encrypted IndexedDB vault.
const CACHE_NAME = 'breakapp-shell-v7';
const BASE_PATH = new URL('./', self.location.href).pathname;
const SHELL_URL = BASE_PATH;
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.add(SHELL_URL)));
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  event.waitUntil(Promise.all([
    caches.keys().then((names) => Promise.all(names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name)))),
    self.clients.claim()
  ]));
});
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.put(SHELL_URL, copy)));
      }
      return response;
    }).catch(() => caches.match(SHELL_URL)));
    return;
  }
  if (url.pathname.startsWith(BASE_PATH+'assets/') || url.pathname === BASE_PATH+'icon-placeholder.svg') {
    event.respondWith(caches.match(request).then((cached) => cached || fetch(request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)));
      }
      return response;
    })));
  }
});

// Foreground-initiated notifications: clicking opens an app-controlled URL.
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  const raw=event.notification.data?.url||BASE_PATH;
  let target;
  try{target=new URL(raw,self.location.origin);}
  catch{target=new URL(BASE_PATH,self.location.origin);}
  if(target.origin!==self.location.origin)target=new URL(BASE_PATH,self.location.origin);
  event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async clients=>{
    const open=clients.find(c=>c.url.startsWith(self.location.origin+BASE_PATH));
    if(open){await open.focus();return;}
    await self.clients.openWindow(target.href);
  }));
});

// True background push: service worker can run while app tabs are closed.
// No order/payment mutations are performed from the notification payload.
self.addEventListener('push',event=>{
 let data={title:'BreakApp',body:'Hai un nuovo avviso',url:BASE_PATH};
 try{
   if(event.data){
     const value=event.data.json();
     if(typeof value.title==='string')data.title=value.title.slice(0,70);
     if(typeof value.body==='string')data.body=value.body.slice(0,200);
     if(typeof value.url==='string')data.url=value.url;
   }
 }catch{/* retain safe generic message */}
 let url=new URL(BASE_PATH,self.location.origin);
 try{
   const candidate=new URL(data.url,self.location.origin);
   if(candidate.origin===self.location.origin&&candidate.pathname.startsWith(BASE_PATH))
     url=candidate;
 }catch{/* retain internal URL */}
 event.waitUntil(self.registration.showNotification(data.title,{
  body:data.body,icon:BASE_PATH+'icon-placeholder.svg',
  tag:'breakapp-push-'+Date.now(),data:{url:url.href}
 }));
});
