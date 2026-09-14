self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      await self.registration.unregister();
      if (keys.length > 0) {
        const clients = await self.clients.matchAll({ type: 'window' });
        clients.forEach(function (c) { c.navigate(c.url); });
      }
    } catch (e) {}
  })());
});
self.addEventListener('fetch', function () {});
