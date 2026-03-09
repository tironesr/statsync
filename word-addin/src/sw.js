const CACHE_NAME = 'statsync-cache-v1';
const ASSETS_TO_CACHE = [
    './taskpane.html',
    './taskpane.js',
    './dialog.html',
    './dialog.js',
    'https://appsforoffice.microsoft.com/lib/1.1/hosted/office.js'
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            return cache.addAll(ASSETS_TO_CACHE);
        })
    );
});

self.addEventListener('fetch', (event) => {
    event.respondWith(
        caches.match(event.request).then((response) => {
            // Return cached asset or fetch from network
            return response || fetch(event.request).catch(() => {
                // If both fail (offline and not in cache), return blank or error
                return new Response('Network error occurred', { status: 408 });
            });
        })
    );
});
