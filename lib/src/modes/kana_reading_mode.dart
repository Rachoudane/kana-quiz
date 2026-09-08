import '../core/data/dataset.dart';
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
  List<QuizItem> buildItems(Dataset data, Map<String, String> config) {
    final script = config['script'] ?? 'all';
    final words = data.wordsByScript(script);
    return shuffled(words).map(_toItem).toList();
  }

  QuizItem _toItem(VocabWord word) => QuizItem(
        id: word.id,
        prompt: word.kana,
        promptScript: word.script,
        readings: [RomajiReading.of(word.kana)],
        meaning: word.meaning,
        secondary: word.hasKanjiForm ? word.word : null,
        detail: word.forms.length > 1 ? word.forms.skip(1).join(' · ') : null,
        examples: word.examples,
      );
}
