// Self-destroying service worker (kill switch).
//
// The app is online-first (it needs the backend), and a caching service worker
// was causing browsers to keep serving a STALE build even after a hard refresh
// — because a hard refresh does not bypass an installed service worker. This
// worker deletes every cache and unregisters itself, so the app is always
// loaded fresh from the network. Any browser that still has an old worker will
// fetch this script on its next update check and un-stick itself.

self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      await self.registration.unregister();
      // Only reload open tabs when we actually cleared a stale cache, so we
      // never loop on subsequent (already-clean) loads.
      if (keys.length > 0) {
        const clients = await self.clients.matchAll({ type: 'window' });
        clients.forEach(function (c) { c.navigate(c.url); });
      }
    } catch (e) {
      /* best-effort */
    }
  })());
});

// Pass all requests straight through to the network (no caching).
self.addEventListener('fetch', function () {});
