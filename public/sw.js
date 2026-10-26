// Fase 1: SOLO cache di asset e shell. Nessuna operazione di business offline.
const CACHE_NAME = 'breakapp-shell-v4';
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
