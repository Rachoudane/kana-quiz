import '../core/data/dataset.dart';
import '../core/models/models.dart';
import '../core/romaji/romaji_reading.dart';
import 'quiz_mode.dart';

/// Mode production : le sens s'affiche en français, on écrit le mot.
///
/// Le mot se tape en rōmaji, comme partout ailleurs dans l'application : sur
/// un clavier français, écrire en kana demanderait un IME, et c'est la lecture
/// qu'on cherche à produire, pas la frappe japonaise. La fiche de correction
/// montre le mot en kana et son écriture.
///
/// Plusieurs mots partagent souvent le même sens. Ils sont tous acceptés :
/// demander « maison » et refuser うち parce qu'on attendait いえ ne
/// t'apprendrait rien.
class MeaningToKanaMode extends QuizMode {
  const MeaningToKanaMode();

  @override
  String get id => 'meaning_kana';

  @override
  String get title => 'Français → kana';

  @override
  String get subtitle => 'Un sens, tu écris le mot.';

  @override
  String get emoji => '訳';

  @override
  String get instruction => 'Écris le mot en rōmaji.';

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
  ];

  @override
  List<QuizItem> buildItems(ModeContext context) {
    final groups = _groups(context.data.select(fromLevel: context.level));
    final items = groups.values.map(_itemFor).toList();
    return shuffled(items);
  }

  /// Question posée pour un mot, avec ses synonymes du même niveau.
  static QuizItem? itemFor(Dataset data, VocabWord word) {
    final group = _groups(data.select(fromLevel: word.level))[_key(word.fr)];
    if (group == null) return null;
    return _itemFor(group);
  }

  /// Identifiant d'une question de ce mode, à partir du mot qui l'ouvre.
  static String idFor(VocabWord word) => 'm_${word.id}';

  /// Mot d'origine d'un identifiant de ce mode, `null` s'il n'en vient pas.
  static VocabWord? wordOf(Dataset data, String id) =>
      id.startsWith('m_') ? data.wordById(id.substring(2)) : null;

  static String _key(String meaning) => meaning.trim().toLowerCase();

  /// Mots regroupés par sens français, dans l'ordre du jeu de données.
  static Map<String, List<VocabWord>> _groups(List<VocabWord> words) {
    final groups = <String, List<VocabWord>>{};
    for (final word in words) {
      if (word.fr.isEmpty) continue;
      groups.putIfAbsent(_key(word.fr), () => []).add(word);
    }
    return groups;
  }

  static QuizItem _itemFor(List<VocabWord> group) {
    final first = group.first;
    final others = group.skip(1).toList();
    return QuizItem(
      id: idFor(first),
      prompt: first.fr,
      promptScript: 'latin',
      readings: group.map((w) => RomajiReading.of(w.kana)).toList(),
      // Le sens est déjà la question : le répéter sous la réponse n'apprend
      // rien. L'anglais, lui, précise souvent ce que le français élargit.
      fr: '',
      en: first.en,
      secondary: first.hasKanjiForm
          ? '${first.kana}（${first.word}）'
          : first.kana,
      detail: others.isEmpty
          ? null
          : 'aussi : ${others.map((w) => w.kana).join('・')}',
      examples: first.examples,
    );
  }
}
