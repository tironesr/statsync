const CACHE_NAME = 'statsync-assets-v16';
const ASSETS_TO_CACHE = [
    './taskpane.html',
    './taskpane.js',
    './dialog.html',
    './dialog.js',
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
    const url = new URL(event.request.url);

    // Speed Logic:
    // 1. If match in cache, return it INSTANTLY.
    // 2. Fetch fresh copy in background and update cache (Stale-While-Revalidate).
    event.respondWith(
        caches.match(event.request).then((cachedResponse) => {
            const fetchPromise = fetch(event.request).then((networkResponse) => {
                if (networkResponse && (networkResponse.status === 200 || networkResponse.status === 0)) {
                    const responseToCache = networkResponse.clone();
                    caches.open(CACHE_NAME).then((cache) => {
                        cache.put(event.request, responseToCache);
                    });
                }
                return networkResponse;
            }).catch(() => {
                // Network failed (offline), if we have a cache, it was already returned by match()
                // If not, return nothing.
            });

            // Return cached response immediately if it exists, otherwise wait for network
            return cachedResponse || fetchPromise;
        })
    );
});
