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
  List<QuizItem> buildItems(ModeContext context) {
    final readingType = context.option('readings', 'any');
    final items = <QuizItem>[];
    for (final entry in context.data.kanji) {
      if ((entry.jlpt ?? 0) < context.level) continue;
      final item = itemFor(context.data, entry, readingType);
      if (item != null) items.add(item);
    }
    return shuffled(items);
  }

  @override
  String summary(ModeContext context) =>
      '${buildItems(context).length} kanji dans cette sélection.';

  /// Question posée pour un kanji, `null` s'il n'a aucune lecture du type
  /// demandé. Partagée avec les autres modes, comme pour le vocabulaire.
  static QuizItem? itemFor(Dataset data, KanjiEntry entry, String readingType) {
    final readings = switch (readingType) {
      'on' => entry.on,
      'kun' => entry.kun,
      _ => [...entry.on, ...entry.kun],
    };
    if (readings.isEmpty) return null;

    final related = entry.wordIds
        .map(data.wordById)
        .whereType<VocabWord>()
        .toList();

    return QuizItem(
      id: 'k_${entry.kanji}_$readingType',
      prompt: entry.kanji,
      promptScript: 'kanji',
      readings: readings.map(RomajiReading.of).toList(),
      fr: related.isNotEmpty ? related.first.fr : '',
      en: entry.meanings.join(', '),
      detail: _detail(entry),
      examples: related.isNotEmpty ? related.first.examples : const [],
      related: related,
    );
  }

  static String _detail(KanjiEntry entry) {
    final parts = <String>[];
    if (entry.on.isNotEmpty) parts.add('on ${entry.on.join('・')}');
    if (entry.kun.isNotEmpty) parts.add('kun ${entry.kun.join('・')}');
    if (entry.strokes != null) parts.add('${entry.strokes} traits');
    return parts.join('   ');
  }
}
