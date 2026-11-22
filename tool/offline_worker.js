// The staging step embeds byte digests for this exact Web build.
const assets = __SABLEEN_ASSETS__;
const base = self.registration.scope;
const prefix = `sableen-shell:${base}:`;
const cacheName = `${prefix}__SABLEEN_VERSION__`;
const files = new Map(assets.map(([file, integrity]) => [new URL(file, base).href, integrity]));

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(cacheName);
    try {
      const requests = [...files].map(([url, integrity]) => new Request(url, {integrity, cache: 'reload'}));
      await cache.addAll(requests);
      if (self.registration.active?.scriptURL !== self.location.href) await self.skipWaiting();
    } catch (error) {
      await caches.delete(cacheName);
      throw error;
    }
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(prefix) && name !== cacheName) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  url.search = '';
  const key = url.href === base ? new URL('index.html', base).href : url.href;
  if (!files.has(key)) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    return (await cache.match(key)) ?? fetch(event.request);
  })());
});
