/* CALI.LAAD · service worker: abre la app aunque no haya conexión.
   La página se pide primero a la red (así siempre llega la última versión) y, sin red, sale de la copia guardada.
   Las sesiones se guardan en la cuenta (Supabase): sin conexión no se pueden guardar. Cambia V al publicar una versión nueva. */
const V = 'calilaad-v2';
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png', 'favicon-32.png',
  'privacidad.html', 'condiciones.html', 'aviso-legal.html'];
self.addEventListener('install', e => { e.waitUntil(caches.open(V).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin) return; // cuentas, pagos y fuentes van siempre a la red
  if (req.mode === 'navigate') {
    e.respondWith(fetch(req).then(r => { const c = r.clone(); caches.open(V).then(x => x.put(req, c)); return r; })
      .catch(() => caches.match(req).then(r => r || caches.match('index.html'))));
    return;
  }
  e.respondWith(caches.match(req).then(r => r || fetch(req).then(n => { const c = n.clone(); caches.open(V).then(x => x.put(req, c)); return n; })));
});
