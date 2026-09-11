import '../romaji/romaji_reading.dart';

/// Phrase d'exemple : l'originale, la même en kana, et sa traduction.
class Example {
  const Example(this.jp, this.kana, this.en);

  factory Example.fromJson(Map<String, dynamic> json) => Example(
        json['jp'] as String,
        json['kana'] as String,
        json['en'] as String,
      );

  /// Phrase telle qu'elle s'écrit, avec ses kanji.
  final String jp;

  /// La même phrase entièrement en kana, pour pouvoir la lire.
  final String kana;

  final String en;
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
        examples: (json['examples'] as List?)
                ?.map((e) => Example.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
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
      );

  final String kanji;
  final List<String> on;
  final List<String> kun;
  final List<String> meanings;
  final int? strokes;
  final int? grade;

  /// Niveau JLPT du kanji, `null` s'il est hors des listes N5 à N3.
  final int? jlpt;
  final List<String> wordIds;

  bool get isN5 => jlpt == 5;
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
    this.examples = const [],
    this.related = const [],
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

  /// Sens en français, puis en anglais.
  final String fr;
  final String en;

  /// Écriture complémentaire montrée après coup (kanji du mot).
  final String? secondary;

  /// Ligne d'information supplémentaire (lectures on/kun d'un kanji…).
  final String? detail;

  final List<Example> examples;

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
