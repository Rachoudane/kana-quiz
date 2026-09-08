import '../core/data/dataset.dart';
import '../core/models/models.dart';
import '../core/romaji/romaji_reading.dart';
import 'quiz_mode.dart';

/// Mode kanji : un kanji s'affiche, on tape une de ses lectures en rōmaji.
///
/// N'importe quelle lecture on ou kun est acceptée : à ce niveau, l'objectif
/// est de reconnaître le caractère, pas de deviner la lecture attendue.
class KanjiReadingMode extends QuizMode {
  const KanjiReadingMode();

  @override
  String get id => 'kanji_reading';

  @override
  String get title => 'Kanji → lecture';

  @override
  String get subtitle => 'Un kanji, tu tapes une de ses lectures.';

  @override
  String get emoji => '漢';

  @override
  String get instruction => 'Tape une lecture (on ou kun) en rōmaji.';

  @override
  List<ModeOption> get options => const [
        ModeOption(
          id: 'level',
          label: 'Niveau',
          choices: [
            ModeChoice('5', 'N5', hint: 'Les 79 kanji du programme N5'),
            ModeChoice('4', 'N5 + N4'),
            ModeChoice('3', 'N5 + N4 + N3'),
          ],
        ),
        ModeOption(
          id: 'readings',
          label: 'Lectures',
          choices: [
            ModeChoice('any', 'On ou kun'),
            ModeChoice('on', 'Lecture on seule'),
            ModeChoice('kun', 'Lecture kun seule'),
          ],
        ),
      ];

  @override
  List<QuizItem> buildItems(Dataset data, Map<String, String> config) {
    final fromLevel = int.tryParse(config['level'] ?? '5') ?? 5;
    final readingType = config['readings'] ?? 'any';

    final items = <QuizItem>[];
    for (final entry in data.kanji) {
      if ((entry.jlpt ?? 0) < fromLevel) continue;
      final readings = switch (readingType) {
        'on' => entry.on,
        'kun' => entry.kun,
        _ => [...entry.on, ...entry.kun],
      };
      if (readings.isEmpty) continue;

      final related =
          entry.wordIds.map(data.wordById).whereType<VocabWord>().toList();

      items.add(
        QuizItem(
          id: 'k_${entry.kanji}_$readingType',
          prompt: entry.kanji,
          promptScript: 'kanji',
          readings: readings.map(RomajiReading.of).toList(),
          fr: related.isNotEmpty ? related.first.fr : '',
          en: entry.meanings.join(', '),
          detail: _detail(entry),
          examples: related.isNotEmpty ? related.first.examples : const [],
          related: related,
        ),
      );
    }
    return shuffled(items);
  }

  String _detail(KanjiEntry entry) {
    final parts = <String>[];
    if (entry.on.isNotEmpty) parts.add('on ${entry.on.join('・')}');
    if (entry.kun.isNotEmpty) parts.add('kun ${entry.kun.join('・')}');
    if (entry.strokes != null) parts.add('${entry.strokes} traits');
    return parts.join('   ');
  }
}
