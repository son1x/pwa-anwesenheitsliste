// sw.js - Service Worker der Anwesenheitsliste.
// App-Shell wird zwischengespeichert (Start auch bei schlechtem Netz);
// /api/* geht immer ans Netz und wird nie gecacht (personenbezogene Daten).
const CACHE = 'anwesenheitsliste-v1';
const SHELL = ['/', '/index.html', '/manifest.json', '/img/icon-192.png', '/img/icon-512.png'];

self.addEventListener('install', event => {
    event.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', event => {
    const url = new URL(event.request.url);
    if (event.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) {
        return; // normal ans Netz
    }
    // Network first, damit neue Versionen sofort ankommen; Cache nur als Rückfall
    event.respondWith(
        fetch(event.request)
            .then(res => {
                if (res.ok && SHELL.includes(url.pathname)) {
                    const kopie = res.clone();
                    caches.open(CACHE).then(c => c.put(event.request, kopie));
                }
                return res;
            })
            .catch(() => caches.match(event.request).then(r => r || caches.match('/index.html')))
    );
});
