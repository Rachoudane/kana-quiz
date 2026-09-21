import 'package:flutter_test/flutter_test.dart';
import 'package:kana_quiz/src/core/data/dataset.dart';
import 'package:kana_quiz/src/core/data/particle_rules.dart';
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

  test('les autres sens ne répètent pas le premier', () {
    final several = data.words.where((w) => w.senses.isNotEmpty).toList();
    // JMdict découpe les sens des mots courants : plus d'un mot sur trois en
    // a au moins deux. Si ce compte s'effondre, la construction a décroché.
    expect(several.length, greaterThan(data.words.length ~/ 3));
    for (final word in several) {
      expect(word.senses.length, lessThanOrEqualTo(2), reason: word.kana);
      expect(word.senses, isNot(contains(word.en)), reason: word.kana);
      expect(word.senses.toSet().length, word.senses.length, reason: word.kana);
      for (final sense in word.senses) {
        expect(sense.trim(), isNotEmpty, reason: word.kana);
      }
    }
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
        // Une phrase de Tatoeba peut n'avoir que le français ou que
        // l'anglais : c'est la traduction affichée qui doit exister.
        expect(example.translation, isNotEmpty, reason: example.jp);
      }
    }
  });

  test('les exemples sont traduits en français dans leur grande majorité', () {
    final examples = [for (final w in data.words) ...w.examples];
    final french = examples.where((e) => e.fr.isNotEmpty).length;
    // 90 % à la construction. Seuls 20 % du corpus japonais de Tatoeba ont une
    // traduction française : c'est le tri qui va les chercher, et s'il casse
    // ce compte retombe à 20 %.
    expect(french, greaterThan(examples.length * 17 ~/ 20));
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

    // Une phrase d'exemple parle du mot, pas de son homophone. Ce qui le
    // garantit est le lemme annoté par le corpus, pas l'écriture de surface :
    // 何してるの est bien する, sous sa forme contractée. On vérifie donc que
    // les homophones sont absents, pas que する apparaît tel quel.
    for (final example in word('する').examples) {
      expect(
        example.jp,
        isNot(anyOf(contains('刷'), contains('擦'), contains('摺'))),
      );
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

  test('chaque sens supplémentaire a son français', () {
    final multiple = data.words.where((w) => w.senses.isNotEmpty).toList();
    for (final word in multiple) {
      // Même longueur et même ordre : c'est ce qui apparie un sens anglais
      // avec sa traduction. Un décalage ferait mentir la fiche.
      expect(word.sensesFr.length, word.senses.length, reason: word.kana);
      for (final sense in word.sensesFr) {
        expect(sense.trim(), isNotEmpty, reason: word.kana);
      }
    }
    // Le français d'un sens ne répète pas la ligne de JMdict du mot.
    final echoes = multiple
        .where((w) => w.sensesFr.any((s) => s == w.fr))
        .length;
    expect(echoes, lessThan(multiple.length ~/ 20));
  });

  test('tous les sens affichés portent les deux langues', () {
    for (final word in data.words.where((w) => w.senses.isNotEmpty).take(200)) {
      final item = KanaReadingMode.itemFor(word);
      expect(item.allSenses.length, word.senses.length + 1, reason: word.kana);
      for (final sense in item.allSenses) {
        expect(sense.en.trim(), isNotEmpty, reason: word.kana);
        expect(sense.fr.trim(), isNotEmpty, reason: word.kana);
      }
    }
  });

  test('les kanji portent des sens en français', () {
    final french = data.kanji.where((k) => k.french.isNotEmpty).length;
    // Tous, sans exception : les 51 que KANJIDIC2 ne traduit pas sont écrits
    // à la main dans tool/kanji_fr_overrides.json.
    expect(french, data.kanji.length);
    for (final entry in data.kanji.where((k) => k.french.isNotEmpty)) {
      expect(entry.french.length, lessThanOrEqualTo(4), reason: entry.kanji);
      for (final sense in entry.french) {
        expect(sense.trim(), isNotEmpty, reason: entry.kanji);
      }
    }
  });

  test('les bandes de fréquence couvrent les mots courants', () {
    final ranked = data.words.where((w) => w.freq != null).toList();
    expect(ranked.length, greaterThan(data.words.length ~/ 2));
    for (final word in ranked) {
      expect(word.freq, inInclusiveRange(1, 48), reason: word.kana);
    }
    // Un mot sans bande n'est pas rare, il est hors des 24 000 relevés : il
    // passe après, jamais avant.
    final unranked = data.words.firstWhere((w) => w.freq == null);
    expect(unranked.freqRank, greaterThan(48));
  });

  test('apprendre commence par les mots les plus courants', () {
    final items = const LearningMode().buildItems(
      ModeContext(data: data, config: const {'level': '5', 'script': 'all'}),
    );
    final ranks = [
      for (final item in items.take(40)) data.wordById(item.id)?.freqRank ?? 99,
    ];
    // Les quarante premiers mots enseignés sont des mots courants, pas le
    // début de l'ordre des kana.
    final median = ([...ranks]..sort())[ranks.length ~/ 2];
    expect(median, lessThan(15));
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

  test('chaque phrase à trou est bien percée', () {
    final kanji = RegExp('[一-龯々]');
    expect(data.particles.length, greaterThan(3000));

    for (final slot in data.particles) {
      // Le trou doit tomber exactement sur la particule annoncée : c'est la
      // seule chose que l'analyse morphologique pouvait rater.
      expect(
        slot.sentence.substring(slot.at, slot.at + slot.answer.length),
        slot.answer,
        reason: slot.sentence,
      );
      expect(slot.blanked.contains('＿'), isTrue, reason: slot.sentence);
      expect(slot.blanked.length, lessThan(slot.sentence.length + 2));

      // Aucun kanji : à ce niveau la phrase ne serait pas lisible.
      expect(kanji.hasMatch(slot.sentence), isFalse, reason: slot.sentence);
      expect(slot.translation, isNotEmpty, reason: slot.sentence);
    }
  });

  test('chaque trou porte une raison', () {
    for (final slot in data.particles) {
      expect(
        particleRules.containsKey(slot.rule),
        isTrue,
        reason: 'motif sans explication : ${slot.rule}',
      );
      expect(particleNote(slot), isNotEmpty, reason: slot.rule);
      expect(particleLabel(slot), isNotEmpty, reason: slot.rule);
    }
  });

  test('aucune particule ne dépasse le tiers du jeu', () {
    final counts = <String, int>{};
    for (final slot in data.particles) {
      counts[slot.answer] = (counts[slot.answer] ?? 0) + 1;
    }
    // Sans plafond, は vaut 40 % des trous et le mode apprend à répondre は.
    for (final entry in counts.entries) {
      expect(
        entry.value / data.particles.length,
        lessThan(0.34),
        reason: '${entry.key} écrase le reste',
      );
    }
  });

  test('un trou où les deux se défendent accepte les deux', () {
    const mode = ParticlesMode();
    final items = mode.buildItems(
      ModeContext(data: data, config: mode.defaultConfig),
    );

    expect(items.length, data.particles.length);
    expect(items.every((i) => i.promptScript == 'sentence'), isTrue);
    expect(items.every((i) => i.answeredInKana), isTrue);
    expect(items.every((i) => i.note != null && i.note!.isNotEmpty), isTrue);

    final ouvert = data.particles.firstWhere((s) => s.isOpen);
    final item = ParticlesMode.itemFor(ouvert);
    for (final particule in ['は', 'が']) {
      expect(
        item.evaluate(particule),
        AnswerState.complete,
        reason: '${ouvert.blanked} refuse $particule',
      );
    }
    // L'explication dit laquelle la phrase a choisie, sans compter faux.
    expect(item.note, contains(ouvert.answer));

    final ferme = data.particles.firstWhere((s) => !s.isOpen);
    final autre = ferme.answer == 'を' ? 'に' : 'を';
    expect(
      ParticlesMode.itemFor(ferme).evaluate(autre),
      isNot(AnswerState.complete),
    );
  });

  test('la sélection par particule ne garde que ce qu\'elle annonce', () {
    const mode = ParticlesMode();
    final waga = mode.buildItems(
      ModeContext(data: data, config: const {'focus': 'waga'}),
    );
    final tout = mode.buildItems(
      ModeContext(data: data, config: const {'focus': 'all'}),
    );

    expect(waga, isNotEmpty);
    expect(waga.length, lessThan(tout.length));
    for (final item in waga) {
      expect(
        item.expected.any((p) => p == 'は' || p == 'が'),
        isTrue,
        reason: item.prompt,
      );
    }
  });

  test('une particule ratée revient dans les mots qui résistent', () {
    final slot = data.particles.first;

    // Identifiant dérivé du contenu : il survit à une régénération du jeu de
    // données, contrairement à un numéro de ligne.
    expect(slot.id, startsWith('p'));
    expect(data.particleById(slot.id)?.sentence, slot.sentence);
    expect(
      data.particles.map((s) => s.id).toSet().length,
      data.particles.length,
    );

    const mode = WeakWordsMode();
    final items = mode.buildItems(
      ModeContext(
        data: data,
        config: mode.defaultConfig,
        stats: {slot.id: const ItemStat(3, 2)},
      ),
    );

    expect(items.map((i) => i.id), contains(slot.id));
    expect(items.first.prompt, slot.blanked);
  });
}
