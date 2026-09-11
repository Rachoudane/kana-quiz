/// Prononciation des mots.
///
/// La synthèse du navigateur est la seule source disponible sans serveur ni
/// fichiers audio : rien à télécharger, rien à héberger, mais une voix qui
/// dépend de la machine. Hors du web, l'implémentation ne fait rien.
library;
export 'speech_stub.dart' if (dart.library.js_interop) 'speech_web.dart';
