const CACHE_NAME = 'statsync-cache-v12';
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

    // Strategy: Cache-First for everything from our origin or the Microsoft Office CDN
    event.respondWith(
        caches.match(event.request).then((cachedResponse) => {
            if (cachedResponse) return cachedResponse;

            return fetch(event.request).then((networkResponse) => {
                // If it's a successful regular response OR an opaque response from Microsoft CDN
                const isOfficeScript = url.hostname.includes('appsforoffice.microsoft.com');
                const isSuccessful = networkResponse && (networkResponse.status === 200 || networkResponse.status === 0);

                if (isSuccessful && (networkResponse.type === 'basic' || isOfficeScript)) {
                    const responseToCache = networkResponse.clone();
                    caches.open(CACHE_NAME).then((cache) => {
                        cache.put(event.request, responseToCache);
                    });
                }
                return networkResponse;
            });
        }).catch(() => {
            // Offline fallback
            if (event.request.mode === 'navigate') {
                return caches.match('./taskpane.html');
            }
        })
    );
});
