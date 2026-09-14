import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Accès aux jeux de données embarqués (`assets/data`).
///
/// Un seul chargement par session ; les modes piochent ensuite dedans.
class Dataset {
  Dataset._(this.words, this.kanji, this.particles, this.attributions)
      : _wordsById = {for (final w in words) w.id: w};

  final List<VocabWord> words;
  final List<KanjiEntry> kanji;

  /// Phrases à trou du mode des particules.
  final List<ParticleSlot> particles;
  final List<String> attributions;
  final Map<String, VocabWord> _wordsById;
  Map<String, ParticleSlot>? _particlesById;

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
    final particlesRaw =
        await rootBundle.loadString('assets/data/particles.json');
    final vocabJson = jsonDecode(vocabRaw) as Map<String, dynamic>;
    final kanjiJson = jsonDecode(kanjiRaw) as Map<String, dynamic>;
    final particlesJson = jsonDecode(particlesRaw) as Map<String, dynamic>;

    final dataset = Dataset._(
      (vocabJson['words'] as List)
          .map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
          .toList(),
      (kanjiJson['kanji'] as List)
          .map((e) => KanjiEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      _particles(particlesJson),
      // particles.json ne s'ajoute pas ici : ses phrases sont celles du
      // Tanaka Corpus, déjà créditées par la ligne du vocabulaire.
      [
        vocabJson['attribution'] as String,
        kanjiJson['attribution'] as String,
      ],
    );
    _instance = dataset;
    return dataset;
  }

  /// Les phrases sont stockées à part des trous : une même phrase sert
  /// souvent plusieurs fois, une fois par particule qu'elle contient.
  static List<ParticleSlot> _particles(Map<String, dynamic> json) {
    final sentences = (json['sentences'] as List).cast<Map<String, dynamic>>();
    final items = (json['items'] as List).cast<Map<String, dynamic>>();
    return [
      for (var i = 0; i < items.length; i++)
        ParticleSlot(
          id: items[i]['id'] as String,
          sentence: sentences[items[i]['s'] as int]['k'] as String,
          translation: sentences[items[i]['s'] as int]['en'] as String,
          at: items[i]['at'] as int,
          answer: items[i]['a'] as String,
          rule: items[i]['r'] as String,
          accepted: (items[i]['alt'] as List?)?.cast<String>() ?? const [],
          topic: items[i]['t'] as String? ?? '',
        ),
    ];
  }

  VocabWord? wordById(String id) => _wordsById[id];

  ParticleSlot? particleById(String id) {
    final index = _particlesById ??= {for (final s in particles) s.id: s};
    return index[id];
  }

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
