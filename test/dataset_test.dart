import 'package:flutter_test/flutter_test.dart';
import 'package:kana_quiz/src/core/data/dataset.dart';
import 'package:kana_quiz/src/core/models/models.dart';
import 'package:kana_quiz/src/core/storage/progress_store.dart';
import 'package:kana_quiz/src/core/romaji/romaji_reading.dart';
import 'package:kana_quiz/src/modes/modes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dataset data;

  setUpAll(() async {
    data = await Dataset.load();
  });

  test('le vocabulaire couvre les trois niveaux', () {
    expect(data.wordCount(fromLevel: 5), greaterThan(650));
    expect(data.wordCount(fromLevel: 3), greaterThan(2500));
    expect(data.katakanaCount(fromLevel: 5), greaterThan(55));
    expect(data.katakanaCount(fromLevel: 3), greaterThan(200));
    expect(
      data.words.where((w) => w.examples.isNotEmpty).length,
      greaterThan(data.words.length * 3 ~/ 4),
    );
  });

  test('chaque mot a un sens français et un sens anglais', () {
    for (final word in data.words) {
      expect(word.kana, isNotEmpty, reason: word.id);
      expect(word.fr, isNotEmpty, reason: '${word.kana} sans français');
      expect(word.en, isNotEmpty, reason: '${word.kana} sans anglais');
      expect(word.script, anyOf('hiragana', 'katakana'));
      expect(word.level, anyOf(3, 4, 5));
    }
  });

  test('chaque phrase d\'exemple a sa version en kana', () {
    final kanji = RegExp('[一-龯々]');
    for (final word in data.words) {
      for (final example in word.examples) {
        expect(example.kana, isNotEmpty, reason: word.kana);
        expect(
          kanji.hasMatch(example.kana),
          isFalse,
          reason: 'reste des kanji dans « ${example.kana} »',
        );
        expect(example.en, isNotEmpty, reason: example.jp);
      }
    }
  });

  test('l\'écriture d\'un verbe en する garde son する', () {
    // する seul est un mot à part, pas un verbe composé.
    final suru = data.words
        .where((w) => w.kana.length > 2 && w.kana.endsWith('する'))
        .toList();
    expect(suru.length, greaterThan(30));
    for (final word in suru) {
      expect(
        word.word.endsWith('する'),
        isTrue,
        reason: '${word.kana} écrit « ${word.word} »',
      );
    }
  });

  test('une lecture ne prend pas le sens de son homonyme', () {
    // Les listes source rangent 刷る, 為る et 擦る sous la lecture する : c'est
    // la ligne du niveau le plus accessible qui donne le mot, et l'entrée
    // choisie fixe l'écriture affichée comme les exemples.
    VocabWord word(String kana) => data.words.firstWhere((w) => w.kana == kana);

    expect(word('する').word, 'する');
    expect(word('する').en, contains('to do'));
    expect(word('なる').en, contains('to become'));
    expect(word('はい').en, contains('yes'));

    // Une phrase d'exemple parle du mot, pas de son homophone.
    for (final example in word('する').examples) {
      expect(example.jp, contains('する'));
    }
    for (final example in word('かみ').examples) {
      expect(example.jp, contains('紙'));
    }
  });

  test('chaque lecture se transcrit et se relit', () {
    for (final word in data.words) {
      final reading = RomajiReading(word.kana);
      expect(reading.units, isNotEmpty, reason: word.kana);
      expect(reading.reference, isNotEmpty, reason: word.kana);
      expect(
        reading.accepts(reading.reference),
        isTrue,
        reason: '${word.kana} -> ${reading.reference}',
      );
      for (final alternate in reading.alternates) {
        expect(
          reading.accepts(alternate),
          isTrue,
          reason: '${word.kana} -> $alternate',
        );
      }
    }
  });

  test('les kanji ont au moins une lecture exploitable', () {
    expect(data.n5KanjiCount, greaterThanOrEqualTo(79));
    for (final entry in data.kanji) {
      expect(
        entry.on.isNotEmpty || entry.kun.isNotEmpty,
        isTrue,
        reason: entry.kanji,
      );
      for (final reading in [...entry.on, ...entry.kun]) {
        final parsed = RomajiReading(reading);
        expect(
          parsed.accepts(parsed.reference),
          isTrue,
          reason: '${entry.kanji} -> $reading',
        );
      }
    }
  });

  test('chaque mode produit des questions jouables', () {
    for (final mode in quizModes) {
      final context = ModeContext(data: data, config: mode.defaultConfig);
      final items = mode.buildItems(context);
      // Un mode de révision n'a rien à proposer tant que rien n'a été raté :
      // il le dit, et c'est l'accueil qui refuse de lancer la partie.
      if (mode.emptyReason(context) != null) {
        expect(items, isEmpty, reason: mode.id);
        continue;
      }
      expect(items.length, greaterThan(50), reason: mode.id);
      for (final item in items.take(200)) {
        expect(item.prompt, isNotEmpty);
        expect(item.readings, isNotEmpty);
        expect(
          item.evaluate(item.expected.first),
          AnswerState.complete,
          reason: '${mode.id} / ${item.prompt}',
        );
      }
    }
  });

  test('le mode français vers kana accepte tous les synonymes', () {
    const mode = MeaningToKanaMode();
    final items = mode.buildItems(
      ModeContext(data: data, config: mode.defaultConfig),
    );

    expect(items.length, greaterThan(400));
    expect(items.every((i) => i.promptScript == 'latin'), isTrue);
    expect(items.every((i) => i.prompt.trim().isNotEmpty), isTrue);
    // Le sens posé en question n'est pas répété sous la réponse.
    expect(items.every((i) => i.fr.isEmpty), isTrue);

    final synonymes = items.firstWhere((i) => i.readings.length > 1);
    for (final reading in synonymes.readings) {
      expect(
        synonymes.evaluate(reading.kana),
        AnswerState.complete,
        reason: '${synonymes.prompt} refuse ${reading.kana}',
      );
    }

    // La réponse s'écrit en japonais : les rōmaji ne passent pas, et
    // l'écriture compte.
    final mot = items.firstWhere(
      (i) => i.readings.length == 1 && i.readings.first.kana.length > 2,
    );
    final kana = mot.readings.first.kana;
    expect(mot.evaluate(mot.readings.first.reference), AnswerState.invalid);
    expect(mot.evaluate(kana), AnswerState.complete);
    expect(mot.evaluate(kana.substring(0, 2)), AnswerState.partial);
    expect(mot.evaluate(' $kana '), AnswerState.complete);
    expect(mot.evaluate(''), AnswerState.empty);

    // Une question de ce mode se reconstruit pour la révision.
    final rejoue = const WeakWordsMode().buildItems(
      ModeContext(
        data: data,
        config: const {},
        stats: {items.first.id: const ItemStat(3, 2)},
      ),
    );
    expect(rejoue.map((i) => i.id), [items.first.id]);
  });

  test('les mots qui résistent rejouent ce qui a été raté', () {
    const mode = WeakWordsMode();
    final faible = data.words[0];
    final solide = data.words[1];
    final kanji = data.kanji.first.kanji;
    final stats = {
      faible.id: const ItemStat(6, 4),
      solide.id: const ItemStat(6, 0),
      'k_${kanji}_any': const ItemStat(3, 1),
    };

    final vide = ModeContext(data: data, config: const {});
    expect(mode.buildItems(vide), isEmpty);
    expect(mode.emptyReason(vide), isNotNull);

    final context = ModeContext(data: data, config: const {}, stats: stats);
    final items = mode.buildItems(context);
    final ids = items.map((i) => i.id).toList();
    expect(mode.emptyReason(context), isNull);
    expect(ids, contains(faible.id));
    expect(ids, contains('k_${kanji}_any'));
    expect(
      ids,
      isNot(contains(solide.id)),
      reason: 'jamais raté, rien à revoir',
    );
    // Le plus raté passe devant.
    expect(ids.first, faible.id);
    for (final item in items) {
      expect(item.evaluate(item.expected.first), AnswerState.complete);
    }
  });

  test('les options de niveau élargissent bien le tirage', () {
    const mode = KanaReadingMode();
    List<QuizItem> items(QuizMode mode, Map<String, String> config) =>
        mode.buildItems(ModeContext(data: data, config: config));

    final n5 = items(mode, {'level': '5', 'script': 'all'});
    final n3 = items(mode, {'level': '3', 'script': 'all'});
    final katakana = items(mode, {'level': '3', 'script': 'katakana'});
    expect(n3.length, greaterThan(n5.length));
    expect(katakana.length, greaterThan(200));
    expect(katakana.every((i) => i.promptScript == 'katakana'), isTrue);

    const kanji = KanjiReadingMode();
    final coreKanji = items(kanji, {'level': '5', 'readings': 'any'});
    final wideKanji = items(kanji, {'level': '3', 'readings': 'any'});
    expect(coreKanji.length, 79);
    expect(wideKanji.length, greaterThan(coreKanji.length));
  });

  test('le tirage est aléatoire et sans répétition avant la fin', () {
    const mode = KanaReadingMode();
    final config = {'level': '5', 'script': 'all'};
    final first = mode.buildItems(ModeContext(data: data, config: config));
    final second = mode.buildItems(ModeContext(data: data, config: config));

    expect(first.length, second.length);
    expect(
      first.map((i) => i.id).toSet(),
      second.map((i) => i.id).toSet(),
      reason: 'les deux tirages contiennent les mêmes mots',
    );
    expect(
      first.take(30).map((i) => i.id).toList(),
      isNot(second.take(30).map((i) => i.id).toList()),
      reason: 'deux parties ne doivent pas commencer pareil',
    );
    expect(
      first.map((i) => i.id).toSet().length,
      first.length,
      reason: 'aucun mot ne revient avant que la liste soit épuisée',
    );
  });
}
