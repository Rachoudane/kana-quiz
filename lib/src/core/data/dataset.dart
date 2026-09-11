import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Accès aux jeux de données embarqués (`assets/data`).
///
/// Un seul chargement par session ; les modes piochent ensuite dedans.
class Dataset {
  Dataset._(this.words, this.kanji, this.attributions)
    : _wordsById = {for (final w in words) w.id: w};

  final List<VocabWord> words;
  final List<KanjiEntry> kanji;
  final List<String> attributions;
  final Map<String, VocabWord> _wordsById;

  static Dataset? _instance;
  static Future<Dataset>? _pending;

  static Dataset? get instanceOrNull => _instance;

  static Future<Dataset> load() {
    if (_instance != null) return Future.value(_instance);
    return _pending ??= _load();
  }

  static Future<Dataset> _load() async {
    final vocabRaw = await rootBundle.loadString('assets/data/vocab.json');
    final kanjiRaw = await rootBundle.loadString('assets/data/kanji.json');
    final vocabJson = jsonDecode(vocabRaw) as Map<String, dynamic>;
    final kanjiJson = jsonDecode(kanjiRaw) as Map<String, dynamic>;

    final dataset = Dataset._(
      (vocabJson['words'] as List)
          .map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
          .toList(),
      (kanjiJson['kanji'] as List)
          .map((e) => KanjiEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      [vocabJson['attribution'] as String, kanjiJson['attribution'] as String],
    );
    _instance = dataset;
    return dataset;
  }

  VocabWord? wordById(String id) => _wordsById[id];

  /// Mots filtrés par écriture et par niveau minimum (5 = N5 seul).
  List<VocabWord> select({String script = 'all', int fromLevel = 5}) => words
      .where((w) => w.level >= fromLevel)
      .where((w) => script == 'all' || w.script == script)
      .toList();

  int katakanaCount({int fromLevel = 5}) =>
      select(script: 'katakana', fromLevel: fromLevel).length;

  int wordCount({int fromLevel = 5}) => select(fromLevel: fromLevel).length;

  int get n5KanjiCount => kanji.where((k) => k.isN5).length;
}
