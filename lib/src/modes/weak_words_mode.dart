import '../core/data/dataset.dart';
import '../core/models/models.dart';
import '../core/storage/progress_store.dart';
import 'kana_reading_mode.dart';
import 'kanji_reading_mode.dart';
import 'quiz_mode.dart';

/// Mode de révision : les questions déjà ratées reviennent en premier.
///
/// Rien de nouveau n'est tiré ici. Le mode rejoue ce que les statistiques
/// signalent comme fragile, du plus raté au moins raté, et la question est
/// exactement celle des autres modes : même identifiant, donc les progrès
/// s'enregistrent au même endroit.
class WeakWordsMode extends QuizMode {
  const WeakWordsMode();

  /// Au-delà, la liste ne tient plus dans une partie et les pires mots
  /// passeraient après ceux qui ne résistent presque plus.
  static const int poolSize = 120;

  @override
  String get id => 'weak_words';

  @override
  String get title => 'Mots qui résistent';

  @override
  String get subtitle => 'Ce que tu as déjà raté, du pire au moins pire.';

  @override
  String get emoji => '難';

  @override
  String get instruction => 'Tape la lecture en rōmaji.';

  @override
  List<QuizItem> buildItems(ModeContext context) {
    final items = <QuizItem>[];
    for (final id in rankedIds(context.stats)) {
      final item = _rebuild(context.data, id);
      if (item != null) items.add(item);
    }
    return items;
  }

  @override
  String? emptyReason(ModeContext context) =>
      buildItems(context).isEmpty
          ? 'Rien à revoir : aucune faute enregistrée pour le moment. '
              'Joue une partie dans un autre mode et reviens ici.'
          : null;

  @override
  String summary(ModeContext context) {
    final count = buildItems(context).length;
    if (count == 0) return 'Rien à revoir pour le moment.';
    return '$count question${count > 1 ? 's' : ''} à revoir.';
  }

  /// Questions ratées, de la plus résistante à la moins résistante.
  ///
  /// À taux d'échec égal, celle qui a été ratée le plus souvent passe devant :
  /// un mot raté une fois sur une rencontre n'est pas encore un problème.
  static List<String> rankedIds(Map<String, ItemStat> stats) {
    final failed = stats.entries.where((e) => e.value.missed > 0).toList();
    failed.sort((a, b) {
      final byRate = b.value.failureRate.compareTo(a.value.failureRate);
      if (byRate != 0) return byRate;
      return b.value.missed.compareTo(a.value.missed);
    });
    return failed.take(poolSize).map((e) => e.key).toList();
  }

  /// Reconstruit une question à partir de son identifiant.
  ///
  /// Le vocabulaire garde l'identifiant du mot, les kanji celui que leur donne
  /// le mode kanji (`k_漢_any`), réglage de lecture compris.
  static QuizItem? _rebuild(Dataset data, String id) {
    final word = data.wordById(id);
    if (word != null) return KanaReadingMode.itemFor(word);

    final parts = id.split('_');
    if (parts.length != 3 || parts.first != 'k') return null;
    for (final entry in data.kanji) {
      if (entry.kanji == parts[1]) {
        return KanjiReadingMode.itemFor(data, entry, parts[2]);
      }
    }
    return null;
  }
}
