import 'package:flutter_test/flutter_test.dart';
import 'package:kana_quiz/src/core/data/dataset.dart';
import 'package:kana_quiz/src/core/romaji/romaji_reading.dart';
import 'package:kana_quiz/src/core/storage/progress_store.dart';
import 'package:kana_quiz/src/features/quiz/quiz_controller.dart';
import 'package:kana_quiz/src/modes/modes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dataset data;
  late ProgressStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    data = await Dataset.load();
    store = await ProgressStore.open();
  });

  const kanaConfig = {'level': '5', 'script': 'all'};

  QuizController build({int duration = 600}) => QuizController(
        mode: const KanaReadingMode(),
        config: kanaConfig,
        durationSeconds: duration,
        items: const KanaReadingMode().buildItems(
          ModeContext(data: data, config: kanaConfig),
        ),
        store: store,
      );

  test('le mode apprentissage montre le mot avant de le demander', () {
    const mode = LearningMode();
    const config = {'level': '5', 'script': 'all'};
    final quiz = QuizController(
      mode: mode,
      config: config,
      durationSeconds: 600,
      items: mode.buildItems(ModeContext(data: data, config: config)),
      store: store,
    );

    // Premier passage : la lecture est affichée, on la recopie, rien n'est
    // compté ni porté à l'historique.
    final premier = quiz.current;
    expect(quiz.teaching, isTrue);
    quiz.onInputChanged(premier.reference);
    expect(quiz.correct, 0);
    expect(quiz.mistakes, 0);
    expect(quiz.history, isEmpty);

    // Trois mots plus loin, il revient, et cette fois il faut le retrouver.
    for (var i = 0; i < 3; i++) {
      expect(quiz.teaching, isTrue, reason: 'mot ${i + 2} encore inconnu');
      quiz.onInputChanged(quiz.current.reference);
    }
    expect(quiz.current.id, premier.id);
    expect(quiz.teaching, isFalse);

    quiz.onInputChanged(premier.reference);
    expect(quiz.correct, 1);
    expect(quiz.history.first.item.id, premier.id);
    quiz.dispose();
  });

  test('Entrée ne compte pas de faute sur un mot présenté', () {
    const mode = LearningMode();
    const config = {'level': '5', 'script': 'all'};
    final quiz = QuizController(
      mode: mode,
      config: config,
      durationSeconds: 600,
      items: mode.buildItems(ModeContext(data: data, config: config)),
      store: store,
    );
    quiz.giveUp();
    expect(quiz.mistakes, 0);
    expect(quiz.correcting, isFalse);
    quiz.dispose();
  });

  test('Échap passe le mot, le compte faux, et il revient', () {
    final quiz = build();
    final passe = quiz.current.id;
    quiz.skip();

    expect(quiz.correct, 0);
    expect(quiz.mistakes, 1, reason: 'un mot passé est un mot raté');
    expect(quiz.streak, 0);
    expect(quiz.history.first.correct, isFalse);
    expect(quiz.current.id, isNot(passe));

    final vus = <String>[];
    for (var i = 0; i < 20; i++) {
      vus.add(quiz.current.id);
      quiz.onInputChanged(quiz.current.reference);
    }
    expect(vus, contains(passe), reason: 'le mot passé revient dans la partie');
    quiz.dispose();
  });

  test('passer pendant une correction ne compte pas deux fois', () {
    final quiz = build();
    quiz.giveUp();
    expect(quiz.mistakes, 1);
    quiz.skip();
    expect(quiz.mistakes, 1, reason: 'la faute était déjà comptée');
    expect(quiz.correcting, isFalse);
    quiz.dispose();
  });

  test('une réponse complète valide sans appuyer sur Entrée', () {
    final quiz = build();
    final expected = quiz.current.reference;
    quiz.onInputChanged(expected);
    expect(quiz.correct, 1);
    expect(quiz.mistakes, 0);
    expect(quiz.streak, 1);
    expect(quiz.input, isEmpty);
    expect(quiz.history.first.correct, isTrue);
    quiz.dispose();
  });

  test('une saisie partielle n\'avance pas', () {
    final quiz = build();
    final item = quiz.current;
    quiz.onInputChanged(item.reference.substring(0, 1));
    expect(quiz.correct, 0);
    expect(identical(quiz.current, item), isTrue);
    quiz.dispose();
  });

  test('Entrée révèle la réponse et impose de la recopier', () {
    final quiz = build();
    final item = quiz.current;

    quiz.giveUp();
    expect(quiz.mistakes, 1);
    expect(quiz.correcting, isTrue);
    expect(identical(quiz.current, item), isTrue,
        reason: 'on reste sur le mot raté');

    quiz.onInputChanged('zzz');
    expect(identical(quiz.current, item), isTrue);

    quiz.onInputChanged(item.reference);
    expect(quiz.correcting, isFalse);
    expect(quiz.correct, 0, reason: 'la recopie ne rapporte pas de point');
    expect(quiz.history.first.correct, isFalse);
    expect(identical(quiz.current, item), isFalse);
    quiz.dispose();
  });

  test('la série repart de zéro après une faute', () {
    final quiz = build();
    quiz.onInputChanged(quiz.current.reference);
    quiz.onInputChanged(quiz.current.reference);
    expect(quiz.streak, 2);
    quiz.giveUp();
    expect(quiz.streak, 0);
    expect(quiz.bestStreak, 2);
    quiz.dispose();
  });

  test('la partie terminée est enregistrée et devient un record', () async {
    final quiz = build();
    quiz.onInputChanged(quiz.current.reference);
    await quiz.finish();

    expect(store.runs, hasLength(1));
    expect(store.runs.first.correct, 1);
    expect(quiz.isRecord, isTrue);
    expect(store.best(store.runs.first.boardKey)?.correct, 1);
    quiz.dispose();
  });

  test('une partie abandonnée n\'est pas enregistrée', () async {
    final quiz = build();
    quiz.onInputChanged(quiz.current.reference);
    await quiz.finish(aborted: true);
    expect(store.runs, isEmpty);
    quiz.dispose();
  });

  test('les statistiques par mot retiennent les échecs', () async {
    final quiz = build();
    final missed = quiz.current;
    quiz.giveUp();
    quiz.onInputChanged(missed.reference);
    await quiz.finish();

    expect(store.itemStats[missed.id]?.missed, 1);
    expect(store.weakest().first.key, missed.id);
  });

  test('les classements séparent les durées et les réglages', () async {
    final a = build(duration: 60);
    a.onInputChanged(a.current.reference);
    await a.finish();
    final b = build(duration: 600);
    await b.finish();

    expect(store.board(a.result!.boardKey), hasLength(1));
    expect(store.board(b.result!.boardKey), hasLength(1));
    expect(a.result!.boardKey, isNot(b.result!.boardKey));
    a.dispose();
    b.dispose();
  });

  test('l\'export puis l\'import restituent la progression', () async {
    final quiz = build();
    quiz.onInputChanged(quiz.current.reference);
    await quiz.finish();
    final json = store.exportJson();

    await store.clear();
    expect(store.runs, isEmpty);

    expect(await store.importJson(json), isTrue);
    expect(store.runs, hasLength(1));
    quiz.dispose();
  });

  test('le mode kanji accepte n\'importe quelle lecture', () {
    final items = const KanjiReadingMode().buildItems(
      ModeContext(data: data, config: const {'level': '5', 'readings': 'any'}),
    );
    final item = items.firstWhere((i) => i.readings.length > 1);
    for (final reading in item.readings) {
      expect(item.evaluate(reading.reference), AnswerState.complete,
          reason: '${item.prompt} -> ${reading.reference}');
    }
  });

  // Écrire à l'IME produit deux événements pour un seul geste : la fin de
  // conversion, et la touche Entrée qui l'a déclenchée. Flutter efface la zone
  // de conversion avant d'appeler onSubmitted — le contrôleur ne peut donc pas
  // savoir qu'une touche vient de l'IME, et doit rester juste dans les deux
  // ordres d'arrivée possibles.

  QuizController particles() {
    const mode = ParticlesMode();
    const config = {'focus': 'all'};
    return QuizController(
      mode: mode,
      config: config,
      durationSeconds: openEnded,
      items: mode.buildItems(ModeContext(data: data, config: config)),
      store: store,
    );
  }

  test('en correction, la réponse écrite à l\'IME débloque la question', () {
    final quiz = particles();
    final question = quiz.current;
    final bonne = question.expected.first;
    final fausse = bonne == 'に' ? 'を' : 'に';

    // On se trompe : la correction s'affiche, il faut recopier la réponse.
    quiz.onInputChanged(fausse, composing: true);
    quiz.submit(fausse);
    expect(quiz.correcting, isTrue);
    expect(quiz.mistakes, 1);

    // On recopie à l'IME. Tant que la conversion n'est pas confirmée, rien.
    quiz.onInputChanged(bonne, composing: true);
    expect(quiz.correcting, isTrue);
    expect(quiz.current.id, question.id);

    // Entrée confirme la conversion. Le texte n'a pas changé, seulement son
    // état : c'est la relecture du champ qui débloque, pas `onChanged`.
    quiz.submit(bonne);
    expect(quiz.correcting, isFalse, reason: 'resté bloqué en correction');
    expect(quiz.current.id, isNot(question.id));
    // Recopier une correction ne vaut pas une bonne réponse.
    expect(quiz.correct, 0);
    expect(quiz.mistakes, 1);
  });

  test('Entrée sur un champ vide affiche toujours la réponse', () {
    final quiz = particles();
    final question = quiz.current;

    quiz.submit('');
    expect(quiz.mistakes, 1);
    expect(quiz.correcting, isTrue);
    expect(quiz.current.id, question.id);
  });

  test('Entrée arrivée avant la fin de conversion valide la réponse', () {
    final quiz = particles();
    final question = quiz.current;
    final bonne = question.expected.first;

    // L'IME propose sa conversion, le texte n'est pas confirmé.
    quiz.onInputChanged(bonne, composing: true);
    expect(quiz.correct, 0, reason: 'une proposition ne vaut pas validation');

    // Entrée : Flutter a déjà effacé la zone de conversion, le contrôleur ne
    // voit qu'une touche nue sur une réponse juste. Il la valide.
    quiz.giveUp();
    expect(quiz.correct, 1);
    expect(quiz.mistakes, 0);
    expect(quiz.correcting, isFalse);
    expect(quiz.current.id, isNot(question.id));

    // La fin de conversion arrive ensuite : déjà comptée, elle ne doit pas
    // remplir le champ de la question suivante.
    final suivante = quiz.current;
    quiz.onInputChanged(bonne);
    expect(quiz.input, isEmpty, reason: 'le reliquat a rempli le champ');
    expect(quiz.current.id, suivante.id);
    expect(quiz.correct, 1);
    expect(quiz.mistakes, 0);
  });

  test('Entrée arrivée après la fin de conversion n\'abandonne pas', () {
    final quiz = particles();
    final bonne = quiz.current.expected.first;

    // Dans l'autre ordre, la fin de conversion valide toute seule.
    quiz.onInputChanged(bonne, composing: true);
    quiz.onInputChanged(bonne);
    expect(quiz.correct, 1);
    final suivante = quiz.current;

    // La touche Entrée arrive après, sur une question qu'on n'a pas lue.
    quiz.giveUp();
    expect(quiz.mistakes, 0, reason: 'la question suivante a été abandonnée');
    expect(quiz.correcting, isFalse);
    expect(quiz.current.id, suivante.id);
  });

  test('passé le délai de grâce, Entrée révèle bien la réponse', () {
    final quiz = particles();
    var horloge = DateTime(2026, 9, 14, 20);
    quiz.now = () => horloge;

    quiz.onInputChanged(quiz.current.expected.first);
    expect(quiz.correct, 1);

    // On prend le temps de lire la question suivante, on ne la sait pas.
    horloge = horloge.add(const Duration(seconds: 3));
    quiz.giveUp();
    expect(quiz.mistakes, 1);
    expect(quiz.correcting, isTrue, reason: 'la réponse doit s\'afficher');
  });

  test('une vraie frappe qui suit une validation n\'est pas avalée', () {
    final quiz = particles();
    final bonne = quiz.current.expected.first;
    quiz.onInputChanged(bonne, composing: true);
    quiz.giveUp();

    // Rien n'est arrivé en retard : la frappe suivante passe normalement.
    quiz.onInputChanged('z');
    expect(quiz.input, 'z');
  });

  test('deux questions de suite avec la même réponse restent jouables', () {
    final quiz = particles();
    var horloge = DateTime(2026, 9, 14, 20);
    quiz.now = () => horloge;

    final bonne = quiz.current.expected.first;
    quiz.onInputChanged(bonne, composing: true);
    quiz.onInputChanged(bonne);
    expect(quiz.correct, 1);

    // Le reliquat n'est ignoré que dans l'instant qui suit. La même particule
    // écrite un peu plus tard est une vraie réponse, pas un écho.
    horloge = horloge.add(const Duration(seconds: 1));
    quiz.onInputChanged(bonne, composing: true);
    expect(quiz.input, bonne, reason: 'la frappe a été prise pour un reliquat');
  });


  test('Entrée sur une réponse déjà juste la valide au lieu d\'abandonner', () {
    final quiz = build();
    final question = quiz.current;

    quiz.onInputChanged(question.reference, composing: true);
    quiz.giveUp();

    expect(quiz.correct, 1);
    expect(quiz.mistakes, 0);
    expect(quiz.correcting, isFalse);
    expect(quiz.current.id, isNot(question.id));
  });

  test('Entrée sur une saisie incomplète abandonne toujours', () {
    final quiz = build();
    final question = quiz.current;

    quiz.onInputChanged('zzz');
    quiz.giveUp();

    expect(quiz.mistakes, 1);
    expect(quiz.correcting, isTrue);
    expect(quiz.current.id, question.id, reason: 'il faut recopier');
  });

  test('une partie sans limite compte à l\'endroit et ne s\'arrête pas seule',
      () {
    const mode = ParticlesMode();
    const config = {'focus': 'all'};
    final quiz = QuizController(
      mode: mode,
      config: config,
      durationSeconds: openEnded,
      items: mode.buildItems(ModeContext(data: data, config: config)),
      store: store,
    );

    expect(quiz.untimed, isTrue);
    expect(quiz.clockSeconds, 0);
    expect(quiz.progress, 0, reason: 'rien à jauger sans fin annoncée');

    for (var i = 0; i < 3; i++) {
      quiz.onInputChanged(quiz.current.expected.first);
    }
    expect(quiz.phase, QuizPhase.running);
    expect(quiz.correct, 3);
  });

  test('arrêter une partie sans limite l\'enregistre', () async {
    const mode = ParticlesMode();
    const config = {'focus': 'all'};
    final quiz = QuizController(
      mode: mode,
      config: config,
      durationSeconds: openEnded,
      items: mode.buildItems(ModeContext(data: data, config: config)),
      store: store,
    );

    quiz.onInputChanged(quiz.current.expected.first);
    await quiz.finish();

    expect(quiz.result, isNotNull);
    expect(quiz.result!.isOpenEnded, isTrue);
    expect(store.runs, hasLength(1));
    // Une réponse ne fait pas un classement.
    expect(quiz.isRecord, isFalse);
    expect(store.best(quiz.result!.boardKey), isNull);
  });

  test('sans chrono, les mots qui résistent s\'arrêtent avec la liste',
      () async {
    const mode = WeakWordsMode();
    final rate = data.words.first;
    final quiz = QuizController(
      mode: mode,
      config: mode.defaultConfig,
      durationSeconds: openEnded,
      items: mode.buildItems(ModeContext(
        data: data,
        config: mode.defaultConfig,
        stats: {rate.id: const ItemStat(4, 3)},
      )),
      store: store,
    );

    expect(quiz.phase, QuizPhase.running);
    quiz.onInputChanged(quiz.current.expected.first);

    // La liste ne se remélange pas : elle est finie, la partie aussi.
    expect(quiz.phase, QuizPhase.finished);
    expect(quiz.correct, 1);
  });

  test('un classement sans limite se range à la précision', () async {
    const key = 'particles|0|focus=all';
    RunResult run(int correct, int mistakes, DateTime at) => RunResult(
          modeId: 'particles',
          config: const {'focus': 'all'},
          durationSeconds: openEnded,
          finishedAt: at,
          correct: correct,
          mistakes: mistakes,
          bestStreak: correct,
          missedLabels: const [],
          elapsedSeconds: 600,
        );

    // Beaucoup de réponses, précision moyenne.
    final laborieuse = run(60, 40, DateTime(2026, 9, 14, 10));
    // Moins de réponses, presque sans faute.
    final propre = run(28, 2, DateTime(2026, 9, 14, 11));
    // Trop courte pour être classée.
    final courte = run(5, 0, DateTime(2026, 9, 14, 12));

    await store.saveRun(laborieuse, const {});
    await store.saveRun(propre, const {});
    await store.saveRun(courte, const {});

    expect(store.board(key).first.finishedAt, propre.finishedAt,
        reason: 'la précision classe, pas le volume');
    expect(store.best(key)!.finishedAt, propre.finishedAt);
    expect(courte.isRanked, isFalse);
    expect(store.isRecord(courte), isFalse);
    expect(store.isRecord(propre), isTrue);
  });
}
