import '../core/models/models.dart';
import '../core/romaji/romaji_reading.dart';
import 'quiz_mode.dart';

/// Mode principal : un mot en kana s'affiche, on tape sa lecture en rōmaji.
class KanaReadingMode extends QuizMode {
  const KanaReadingMode();

  @override
  String get id => 'kana_reading';

  @override
  String get title => 'Kana → rōmaji';

  @override
  String get subtitle => 'Un mot en kana, tu tapes sa lecture.';

  @override
  String get emoji => 'あ';

  @override
  String get instruction => 'Tape la lecture en rōmaji.';

  @override
  List<ModeOption> get options => const [
    ModeOption(
      id: 'level',
      label: 'Niveau',
      choices: [
        ModeChoice('5', 'N5'),
        ModeChoice('4', 'N5 + N4'),
        ModeChoice('3', 'N5 + N4 + N3'),
      ],
    ),
    ModeOption(
      id: 'script',
      label: 'Écriture',
      choices: [
        ModeChoice('all', 'Hiragana + katakana'),
        ModeChoice('hiragana', 'Hiragana seul'),
        ModeChoice('katakana', 'Katakana seul'),
      ],
    ),
  ];

  @override
  List<QuizItem> buildItems(ModeContext context) {
    final words = context.data.select(
      script: context.option('script', 'all'),
      fromLevel: context.level,
    );
    return shuffled(words).map(itemFor).toList();
  }

  @override
  String summary(ModeContext context) {
    final script = context.option('script', 'all');
    final total = context.data
        .select(script: script, fromLevel: context.level)
        .length;
    if (script == 'katakana') return '$total mots en katakana.';
    final katakana = context.data.katakanaCount(fromLevel: context.level);
    if (script == 'hiragana') return '$total mots en hiragana.';
    return '$total mots dans cette sélection, dont $katakana en katakana.';
  }

  /// Question posée pour un mot. Les autres modes s'en servent aussi : une
  /// question doit être la même partout, sinon les statistiques ne se
  /// rattachent plus au même identifiant.
  static QuizItem itemFor(VocabWord word) => QuizItem(
    id: word.id,
    prompt: word.kana,
    promptScript: word.script,
    readings: [RomajiReading.of(word.kana)],
    fr: word.fr,
    en: word.en,
    secondary: word.hasKanjiForm ? word.word : null,
    detail: word.forms.length > 1 ? word.forms.skip(1).join(' · ') : null,
    examples: word.examples,
  );
}
