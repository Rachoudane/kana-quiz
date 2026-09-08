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
    final vocabRaw = await rootBundle.loadString('assets/data/vocab_n5.json');
    final kanjiRaw = await rootBundle.loadString('assets/data/kanji_n5.json');
    final vocabJson = jsonDecode(vocabRaw) as Map<String, dynamic>;
    final kanjiJson = jsonDecode(kanjiRaw) as Map<String, dynamic>;

    final dataset = Dataset._(
      (vocabJson['words'] as List)
          .map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
          .toList(),
      (kanjiJson['kanji'] as List)
          .map((e) => KanjiEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      [
        vocabJson['attribution'] as String,
        kanjiJson['attribution'] as String,
      ],
    );
    _instance = dataset;
    return dataset;
  }

  VocabWord? wordById(String id) => _wordsById[id];

  List<VocabWord> wordsByScript(String script) => script == 'all'
      ? words
      : words.where((w) => w.script == script).toList();

  int get katakanaCount => words.where((w) => w.script == 'katakana').length;

  int get coreKanjiCount => kanji.where((k) => k.core).length;
}
