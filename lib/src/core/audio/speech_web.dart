import 'dart:js_interop';

/// Synthèse vocale du navigateur.
///
/// La voix japonaise n'est pas garantie : selon la machine, `ja-JP` peut être
/// absent et le navigateur lit alors avec la voix par défaut. On préfère une
/// voix japonaise quand il y en a une, et on ne dit rien quand l'API manque.
class Speech {
  const Speech._();

  static bool get available => _synthesis != null;

  /// Prononce un texte japonais, en coupant ce qui était en cours.
  ///
  /// Un mot chasse le précédent : pendant une partie chronométrée, une file
  /// d'attente finirait par parler d'un mot répondu dix secondes plus tôt.
  static void say(String text) {
    final synthesis = _synthesis;
    if (synthesis == null || text.isEmpty) return;
    synthesis.cancel();
    final utterance = _Utterance(text)
      ..lang = 'ja-JP'
      ..rate = 0.9;
    final voice = _japaneseVoice(synthesis);
    if (voice != null) utterance.voice = voice;
    synthesis.speak(utterance);
  }

  static void stop() => _synthesis?.cancel();

  static _Voice? _japaneseVoice(_Synthesis synthesis) {
    final voices = synthesis.getVoices().toDart;
    for (final voice in voices) {
      if (voice.lang.replaceAll('_', '-').startsWith('ja')) return voice;
    }
    return null;
  }
}

@JS('speechSynthesis')
external _Synthesis? get _synthesis;

extension type _Synthesis._(JSObject _) implements JSObject {
  external void speak(_Utterance utterance);
  external void cancel();
  external JSArray<_Voice> getVoices();
}

extension type _Voice._(JSObject _) implements JSObject {
  external String get lang;
}

@JS('SpeechSynthesisUtterance')
extension type _Utterance._(JSObject _) implements JSObject {
  external _Utterance(String text);
  external set lang(String value);
  external set rate(num value);
  external set voice(_Voice value);
}
