// Service worker de Kana Quiz.
//
// Celui de Flutter avait été retiré parce qu'il servait indéfiniment sa propre
// copie du site : après un déploiement, on continuait de voir l'ancienne
// version, et vider le cache du navigateur n'y changeait rien. Celui-ci est
// écrit pour que ça n'arrive pas.
//
// Deux règles. Ce qui définit la version du site — la page et son script de
// démarrage — part toujours sur le réseau, le cache ne sert que si le réseau
// ne répond pas. Le reste, immuable à l'intérieur d'une version, se sert
// depuis le cache, et chaque déploiement ouvre un cache neuf : les anciens
// sont supprimés à l'activation, rien ne survit à une mise à jour.

// Remplacé au déploiement par l'identifiant du commit. En local la valeur
// reste telle quelle, et le cache s'appelle « dev ».
const BUILD = '__BUILD_ID__';
const VERSION = BUILD.startsWith('__') ? 'dev' : BUILD;
const CACHE = 'kana-quiz-' + VERSION;

// Le strict nécessaire pour ouvrir l'application hors ligne. Le reste — le
// moteur, les polices, les données — entre en cache à la première visite.
const SHELL = ['./', 'index.html', 'flutter_bootstrap.js', 'manifest.json'];

// Ces fichiers disent quelle version du site est en cours : les servir depuis
// le cache, c'est figer le site sur une version passée.
const ALWAYS_FRESH = /(?:^|\/)(?:index\.html|flutter_bootstrap\.js|flutter_service_worker\.js)$/;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) => Promise.all(names.filter((name) => name !== CACHE).map((name) => caches.delete(name))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate' || ALWAYS_FRESH.test(url.pathname)) {
    event.respondWith(freshFirst(request));
    return;
  }
  event.respondWith(cacheFirst(request));
});

// Réseau d'abord : la version en ligne gagne toujours, le cache ne sert que
// hors ligne. Une navigation qui échoue retombe sur la page d'accueil, la
// seule qui existe.
function freshFirst(request) {
  return fetch(request)
    .then((response) => {
      if (response && response.ok) {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
      }
      return response;
    })
    .catch(() =>
      caches
        .match(request)
        .then((cached) => cached || caches.match('index.html'))
    );
}

// Cache d'abord : à version fixée, ces fichiers ne changent plus. Ce qui
// manque est téléchargé une fois, puis gardé.
function cacheFirst(request) {
  return caches.match(request).then((cached) => {
    if (cached) return cached;
    return fetch(request).then((response) => {
      if (response && response.ok && response.type === 'basic') {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
      }
      return response;
    });
  });
}
