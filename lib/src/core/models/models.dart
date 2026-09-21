import '../romaji/romaji_reading.dart';

/// Phrase d'exemple : l'originale, la même en kana, et sa traduction.
class Example {
  const Example(this.jp, this.kana, this.en, [this.fr = '']);

  factory Example.fromJson(Map<String, dynamic> json) => Example(
    json['jp'] as String,
    json['kana'] as String,
    json['en'] as String,
    json['fr'] as String? ?? '',
  );

  /// Phrase telle qu'elle s'écrit, avec ses kanji.
  final String jp;

  /// La même phrase entièrement en kana, pour pouvoir la lire.
  final String kana;

  final String en;

  /// La même phrase en français, quand Tatoeba en a une traduction.
  final String fr;

  /// La traduction à montrer : le français, l'anglais à défaut.
  ///
  /// Neuf phrases sur dix ont une traduction française ; pour les autres
  /// l'anglais vaut mieux que rien.
  String get translation => fr.isNotEmpty ? fr : en;
}

/// Un mot du vocabulaire.
class VocabWord {
  const VocabWord({
    required this.id,
    required this.kana,
    required this.word,
    required this.forms,
    required this.level,
    required this.fr,
    required this.en,
    required this.script,
    required this.examples,
    this.senses = const [],
    this.freq,
  });

  factory VocabWord.fromJson(Map<String, dynamic> json) => VocabWord(
    id: json['id'] as String,
    kana: json['kana'] as String,
    word: json['word'] as String,
    forms: (json['forms'] as List?)?.cast<String>() ?? const [],
    level: json['level'] as int,
    fr: json['fr'] as String,
    en: json['en'] as String,
    script: json['script'] as String,
    examples:
        (json['examples'] as List?)
            ?.map((e) => Example.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    senses: (json['senses'] as List?)?.cast<String>() ?? const [],
    freq: json['freq'] as int?,
  );

  final String id;

  /// Lecture en kana : c'est ce que l'on affiche et ce que l'on lit.
  final String kana;

  /// Écriture usuelle (kanji ou katakana).
  final String word;

  /// Autres écritures rencontrées pour la même lecture.
  final List<String> forms;

  /// Niveau JLPT : 5 pour N5, 4 pour N4, 3 pour N3.
  final int level;

  final String fr;
  final String en;

  /// `hiragana` ou `katakana`, d'après la lecture.
  final String script;
  final List<Example> examples;

  /// Les autres sens du mot, en anglais, quand il en a plusieurs.
  ///
  /// [en] porte le premier, ceux-ci viennent après, dans l'ordre de JMdict qui
  /// met le sens courant en tête. Le français n'y figure pas : sa ligne ne
  /// découpe pas les sens, elle les aplatit tous.
  final List<String> senses;

  /// Bande de fréquence JMdict : 1 pour les 500 mots les plus courants de la
  /// presse, 48 pour les 500 derniers des 24 000 relevés. `null` au-delà.
  ///
  /// Sert à montrer les mots utiles d'abord quand on apprend. Le tirage d'une
  /// partie chronométrée reste au hasard : deux scores ne se comparent que
  /// s'ils sont tirés dans le même sac.
  final int? freq;

  /// Les mots sans bande passent après ceux qui en ont une.
  int get freqRank => freq ?? 99;

  bool get hasKanjiForm => word != kana;
}

/// Un kanji et ses lectures.
class KanjiEntry {
  const KanjiEntry({
    required this.kanji,
    required this.on,
    required this.kun,
    required this.meanings,
    required this.strokes,
    required this.grade,
    required this.jlpt,
    required this.wordIds,
    this.french = const [],
  });

  factory KanjiEntry.fromJson(Map<String, dynamic> json) => KanjiEntry(
    kanji: json['kanji'] as String,
    on: (json['on'] as List).cast<String>(),
    kun: (json['kun'] as List).cast<String>(),
    meanings: (json['meanings'] as List).cast<String>(),
    strokes: json['strokes'] as int?,
    grade: json['grade'] as int?,
    jlpt: json['jlpt'] as int?,
    wordIds: (json['words'] as List?)?.cast<String>() ?? const [],
    french: (json['fr'] as List?)?.cast<String>() ?? const [],
  );

  final String kanji;
  final List<String> on;
  final List<String> kun;
  final List<String> meanings;

  /// Les mêmes sens en français : KANJIDIC2 en donne pour presque tous.
  final List<String> french;

  final int? strokes;
  final int? grade;

  /// Niveau JLPT du kanji, `null` s'il est hors des listes N5 à N3.
  final int? jlpt;
  final List<String> wordIds;

  bool get isN5 => jlpt == 5;
}

/// Une phrase à trou : une particule retirée, et la raison de son choix.
///
/// Les phrases sont entièrement en kana. La position du trou est un index de
/// caractère dans [sentence], calculé à la construction du jeu de données par
/// `tool/build_particles.py` sur la version à kanji de la phrase.
class ParticleSlot {
  const ParticleSlot({
    required this.id,
    required this.sentence,
    required this.translation,
    required this.at,
    required this.answer,
    required this.rule,
    this.accepted = const [],
    this.topic = '',
  });

  final String id;

  /// La phrase complète, particule comprise.
  final String sentence;
  final String translation;

  /// Position du premier caractère de la particule dans [sentence].
  final int at;
  final String answer;

  /// Identifiant du motif grammatical, voir `particle_rules.dart`.
  final String rule;

  /// Particules acceptées quand plusieurs se défendent. Vide = seule [answer].
  final List<String> accepted;

  /// Le mot qui précède le trou, pour écrire l'explication au cas par cas.
  final String topic;

  /// La phrase telle qu'elle est posée, avec son trou.
  String get blanked =>
      '${sentence.substring(0, at)}＿${sentence.substring(at + answer.length)}';

  /// Toutes les réponses justes.
  List<String> get answers => accepted.isEmpty ? [answer] : accepted;

  /// Vrai si plusieurs particules passent : la fiche explique alors l'écart.
  bool get isOpen => accepted.length > 1;
}

/// Une question, indépendante du mode qui l'a produite.
class QuizItem {
  QuizItem({
    required this.id,
    required this.prompt,
    required this.promptScript,
    required this.readings,
    required this.fr,
    required this.en,
    this.answerScript = 'romaji',
    this.secondary,
    this.detail,
    this.note,
    this.examples = const [],
    this.related = const [],
    this.senses = const [],
  });

  final String id;

  /// Ce qui est affiché en grand.
  final String prompt;

  /// `hiragana`, `katakana` ou `kanji` : sert à l'affichage.
  final String promptScript;

  /// Lectures acceptées. La première fournit la graphie de référence.
  final List<RomajiReading> readings;

  /// Comment la réponse s'écrit : `romaji`, ou `kana` quand on la saisit
  /// directement en japonais, à l'IME.
  final String answerScript;

  bool get answeredInKana => answerScript == 'kana';

  /// Sens en anglais, puis en français.
  ///
  /// L'anglais passe devant : JMdict en compte 218 732 entrées contre 15 336
  /// en français, et sa glose tient un seul sens là où la française les
  /// aplatit tous. Le français reste dessous, en retrait.
  final String en;
  final String fr;

  /// Écriture complémentaire montrée après coup (kanji du mot).
  final String? secondary;

  /// Ligne d'information supplémentaire (lectures on/kun d'un kanji…).
  final String? detail;

  /// Ce qu'il y a à comprendre, en français, montré après la réponse.
  ///
  /// Le mode des particules s'en sert pour la raison du choix : trouver la
  /// bonne particule sans savoir pourquoi n'apprend rien.
  final String? note;

  final List<Example> examples;

  /// Les autres sens, en anglais : voir [VocabWord.senses].
  final List<String> senses;

  /// Tous les sens anglais, le principal en tête.
  List<String> get allSenses => [if (en.isNotEmpty) en, ...senses];

  /// Mots du vocabulaire rattachés (utilisé par le mode kanji).
  final List<VocabWord> related;

  String get reference => readings.first.reference;

  /// Ce qu'il faut prononcer : la lecture attendue, en kana.
  String get spoken => readings.isEmpty ? '' : readings.first.kana;

  List<String> get alternates => readings.first.alternates;

  /// Toutes les lectures de référence, pour les kanji à plusieurs lectures.
  List<String> get allReferences =>
      readings.map((r) => r.reference).toSet().toList();

  /// Ce qu'il faut écrire, tel qu'on l'affiche à la correction.
  List<String> get expected => answeredInKana
      ? readings.map((r) => r.kana).toSet().toList()
      : allReferences;

  /// Évalue une saisie contre toutes les lectures acceptées.
  AnswerState evaluate(String input) {
    if (answeredInKana) return _evaluateKana(input);
    var best = AnswerState.invalid;
    for (final reading in readings) {
      final state = reading.evaluate(input);
      if (state == AnswerState.complete) return AnswerState.complete;
      if (state == AnswerState.empty) return AnswerState.empty;
      if (state == AnswerState.partial) best = AnswerState.partial;
    }
    return best;
  }

  /// Compare une saisie en japonais aux lectures attendues.
  ///
  /// L'écriture compte : un mot qui s'écrit en katakana s'écrit en katakana.
  /// Seuls les espaces sont ignorés, l'IME en laisse parfois traîner.
  AnswerState _evaluateKana(String raw) {
    final input = raw.replaceAll(RegExp(r'[\s　]+'), '');
    if (input.isEmpty) return AnswerState.empty;
    var best = AnswerState.invalid;
    for (final reading in readings) {
      if (input == reading.kana) return AnswerState.complete;
      if (reading.kana.startsWith(input)) best = AnswerState.partial;
    }
    return best;
  }
}
