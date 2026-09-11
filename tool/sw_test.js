// Vérifie web/sw.js hors navigateur.
//
// Le service worker précédent servait indéfiniment sa copie du site : une
// version pouvait rester invisible après un déploiement. Ces vérifications
// tiennent la règle qui l'empêche — la page part toujours sur le réseau, et un
// déploiement laisse un seul cache derrière lui.
//
// Usage : node tool/sw_test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.dirname(__dirname);
const source = fs
  .readFileSync(path.join(ROOT, 'web', 'sw.js'), 'utf8')
  .replace('__BUILD_ID__', 'essai');

const ORIGIN = 'https://rachoudane.github.io';
const listeners = {};
const stores = new Map();
const network = [];
let offline = false;

function store(name) {
  if (!stores.has(name)) stores.set(name, new Map());
  return stores.get(name);
}

const caches = {
  open: (name) => {
    const entries = store(name);
    return Promise.resolve({
      addAll: (urls) => {
        urls.forEach((url) => entries.set(url, 'précache'));
        return Promise.resolve();
      },
      put: (request, response) => {
        entries.set(request.url || request, response);
        return Promise.resolve();
      },
      match: (request) => Promise.resolve(entries.get(request.url || request)),
    });
  },
  keys: () => Promise.resolve([...stores.keys()]),
  delete: (name) => Promise.resolve(stores.delete(name)),
  match: (request) => {
    for (const entries of stores.values()) {
      const hit = entries.get(request.url || request);
      if (hit) return Promise.resolve(hit);
    }
    return Promise.resolve(undefined);
  },
};

function fetchStub(request) {
  network.push(request.url || request);
  if (offline) return Promise.reject(new Error('hors ligne'));
  return Promise.resolve({
    ok: true,
    type: 'basic',
    body: 'réseau',
    clone: () => 'copie réseau',
  });
}

const self = {
  location: { origin: ORIGIN },
  addEventListener: (type, handler) => {
    listeners[type] = handler;
  },
  skipWaiting: () => Promise.resolve(),
  clients: { claim: () => Promise.resolve() },
};

vm.runInNewContext(source, { self, caches, fetch: fetchStub, URL, Promise, console });

async function lifecycle(name) {
  const pending = [];
  listeners[name]({ waitUntil: (promise) => pending.push(promise) });
  await Promise.all(pending);
}

async function ask(url, { mode = 'no-cors', method = 'GET' } = {}) {
  let answer = null;
  listeners.fetch({
    request: { url, mode, method },
    respondWith: (promise) => {
      answer = promise;
    },
  });
  return answer ? answer : null;
}

(async () => {
  await lifecycle('install');
  assert.deepStrictEqual(
    [...store('kana-quiz-essai').keys()],
    ['./', 'index.html', 'flutter_bootstrap.js', 'manifest.json'],
    'le nécessaire pour ouvrir le site hors ligne doit être en cache',
  );

  store('kana-quiz-version-precedente').set('/index.html', 'vieille page');
  store('flutter-app-cache').set('/main.dart.js', 'vieux moteur');
  await lifecycle('activate');
  assert.deepStrictEqual(
    [...stores.keys()],
    ['kana-quiz-essai'],
    'un déploiement doit effacer les caches des versions précédentes',
  );

  network.length = 0;
  await ask(ORIGIN + '/index.html', { mode: 'navigate' });
  await ask(ORIGIN + '/flutter_bootstrap.js');
  assert.strictEqual(
    network.length,
    2,
    'la page et son script de démarrage partent toujours sur le réseau',
  );

  network.length = 0;
  await ask(ORIGIN + '/main.dart.js');
  await ask(ORIGIN + '/main.dart.js');
  await ask(ORIGIN + '/assets/data/vocab.json');
  assert.strictEqual(
    network.length,
    2,
    'le moteur et les données ne se téléchargent qu\'une fois par version',
  );

  offline = true;
  assert.ok(
    await ask(ORIGIN + '/', { mode: 'navigate' }),
    'hors ligne, la page doit être servie depuis le cache',
  );
  offline = false;

  assert.strictEqual(
    await ask('https://fonts.googleapis.com/css'),
    null,
    'ce qui vient d\'ailleurs ne nous regarde pas',
  );
  assert.strictEqual(
    await ask(ORIGIN + '/api', { method: 'POST' }),
    null,
    'seules les lectures passent par le cache',
  );

  console.log('service worker : 7 vérifications passées');
})();
