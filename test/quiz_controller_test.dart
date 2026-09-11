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

  test('Échap passe le mot sans le compter, et il revient', () {
    final quiz = build();
    final passe = quiz.current.id;
    quiz.skip();

    expect(quiz.correct, 0);
    expect(quiz.mistakes, 0);
    expect(quiz.history, isEmpty, reason: "un mot passé n'est pas une réponse");
    expect(quiz.current.id, isNot(passe));

    final vus = <String>[];
    for (var i = 0; i < 20; i++) {
      vus.add(quiz.current.id);
      quiz.onInputChanged(quiz.current.reference);
    }
    expect(vus, contains(passe), reason: 'le mot passé revient dans la partie');
    quiz.dispose();
  });

  test("passer après une faute ne l'efface pas", () {
    final quiz = build();
    quiz.giveUp();
    expect(quiz.mistakes, 1);
    quiz.skip();
    expect(quiz.mistakes, 1);
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
}
