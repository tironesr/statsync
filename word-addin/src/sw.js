const CACHE_NAME = 'statsync-assets-v13';
const ASSETS_TO_CACHE = [
    'taskpane.html',
    'taskpane.js',
    'dialog.html',
    'dialog.js',
    'https://appsforoffice.microsoft.com/lib/1.1/hosted/office.js'
];

self.addEventListener('install', (event) => {
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            return cache.addAll(ASSETS_TO_CACHE);
        })
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        Promise.all([
            self.clients.claim(),
            caches.keys().then((keys) => {
                return Promise.all(
                    keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
                );
            }),
        ])
    );
});

self.addEventListener('fetch', (event) => {
    // Strategy: Cache-First, then Network + Cache update
    event.respondWith(
        caches.match(event.request).then((cachedResponse) => {
            if (cachedResponse) {
                // Return cached version immediately for speed
                return cachedResponse;
            }

            return fetch(event.request).then((networkResponse) => {
                // If successful or opaque (for CDN), cache for next time
                if (networkResponse && (networkResponse.status === 200 || networkResponse.status === 0)) {
                    const responseToCache = networkResponse.clone();
                    caches.open(CACHE_NAME).then((cache) => {
                        cache.put(event.request, responseToCache);
                    });
                }
                return networkResponse;
            });
        }).catch(() => {
            // No network, no cache — return nothing or handle gracefully.
            // Do NOT return taskpane.html here as it breaks the dialog window!
            return new Response("Offline resource not found", { status: 404, statusText: "Offline" });
        })
    );
});
