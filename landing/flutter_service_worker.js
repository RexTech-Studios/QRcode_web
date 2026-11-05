// FULL-STAR-QR-KILL-SWITCH (deploy.ps1 checks for this marker, keep it)
//
// The Flutter app used to live at the site root, so a root-scope service
// worker may exist in visitors' browsers at this exact URL. A browser re-checks
// a registered worker by re-fetching its script, so this file is how such a
// worker gets replaced. If it ever disappears, the check fails and the old
// worker keeps running, which is why it must stay here forever.
//
// Only the root-scope worker is affected. The app under /app/ has its own
// scope, and Flutter's worker there removes itself.
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(names.map((name) => caches.delete(name)));
      await self.registration.unregister();

      // Without includeUncontrolled this is only the pages this worker
      // controls: navigate() rejects for any others, such as tabs under /app/.
      const windows = await self.clients.matchAll({ type: 'window' });
      await Promise.all(
        windows.map((client) => client.navigate(client.url).catch(() => {}))
      );
    })()
  );
});

// There is deliberately no fetch handler: every request goes to the network.
