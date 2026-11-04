'use strict';
// Keep this response at the legacy URL, including after subsequent releases.
self.addEventListener('install', (event) => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', (event) => event.waitUntil((async () => {
  await Promise.all(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']
    .map((name) => caches.delete(name)));
  await self.clients.claim();
  await self.registration.unregister();
})()));
// No fetch handler and no automatic navigation. User storage/drafts stay intact.
