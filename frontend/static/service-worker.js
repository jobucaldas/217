const CACHE_NAME = '217-shell-v1';
const SHELL = ['/', '/manifest.webmanifest', '/pwa.js', '/icon-192.png', '/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  event.respondWith(fetch(event.request).then((response) => {
    if (response.ok && ['document', 'script', 'style', 'wasm', 'manifest', 'image'].includes(event.request.destination)) {
      const copy = response.clone();
      event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)));
    }
    return response;
  }).catch(() => caches.match(event.request).then((cached) => cached || (event.request.mode === 'navigate' ? caches.match('/') : Response.error()))));
});

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) {}
  const date = typeof data.date === 'string' ? data.date : new Date().toISOString().slice(0, 10);
  const options = {
    body: typeof data.body === 'string' ? data.body : 'Time to record your medication',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: typeof data.tag === 'string' ? data.tag : `217-reminder-${date}`,
    renotify: false,
    data: { url: typeof data.url === 'string' ? data.url : '/' }
  };
  event.waitUntil(self.registration.showNotification(typeof data.title === 'string' ? data.title : '217', options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  let target = new URL('/', self.location.origin);
  try {
    const requested = new URL(event.notification.data?.url || '/', self.location.origin);
    if (requested.origin === self.location.origin) target = requested;
  } catch (_) {}
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async (windows) => {
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin) {
        await client.focus();
        if ('navigate' in client) await client.navigate(target.href);
        return;
      }
    }
    return self.clients.openWindow(target.href);
  }));
});
