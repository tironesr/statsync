const CACHE_NAME = 'statsync-cache-v11';
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
    // Strategy: Cache-First for everything once fetched successfully.
    // This catches dynamic assets inside office.js which were not in ASSETS_TO_CACHE.
    event.respondWith(
        caches.match(event.request).then((cachedResponse) => {
            if (cachedResponse) return cachedResponse;

            return fetch(event.request).then((networkResponse) => {
                // Cache the newly fetched asset (especially from Microsoft CDN)
                if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic' || networkResponse.type === 'cors') {
                    const responseToCache = networkResponse.clone();
                    caches.open(CACHE_NAME).then((cache) => {
                        cache.put(event.request, responseToCache);
                    });
                }
                return networkResponse;
            });
        }).catch(() => {
            // Offline fallback
            return caches.match('./taskpane.html');
        })
    );
});
