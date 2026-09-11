import 'kana_reading_mode.dart';
import 'kanji_reading_mode.dart';
import 'quiz_mode.dart';
import 'weak_words_mode.dart';

export 'kana_reading_mode.dart';
export 'kanji_reading_mode.dart';
export 'quiz_mode.dart';
export 'weak_words_mode.dart';

/// Modes disponibles, dans l'ordre d'affichage sur l'accueil.
const List<QuizMode> quizModes = [
  KanaReadingMode(),
  KanjiReadingMode(),
  WeakWordsMode(),
];

QuizMode modeById(String id) =>
    quizModes.firstWhere((m) => m.id == id, orElse: () => quizModes.first);
