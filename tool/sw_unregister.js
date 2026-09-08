// Remplace le service worker de Flutter au moment du déploiement.
//
// Les navigateurs qui ont visité le site avant sa suppression gardent l'ancien
// service worker, et celui-ci continue de servir sa propre copie du site : une
// nouvelle version peut rester invisible indéfiniment. Ce script prend sa
// place, se désinscrit, vide ses caches et recharge les pages ouvertes.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    self.registration
      .unregister()
      .then(() => caches.keys())
      .then((names) => Promise.all(names.map((name) => caches.delete(name))))
      .then(() => self.clients.matchAll({ type: 'window' }))
      .then((clients) => clients.forEach((client) => client.navigate(client.url)))
  );
});
