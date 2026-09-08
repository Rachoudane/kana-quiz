import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kana_quiz/src/app/app.dart';
import 'package:kana_quiz/src/core/data/dataset.dart';
import 'package:kana_quiz/src/core/models/models.dart';
import 'package:kana_quiz/src/features/common/widgets.dart';
import 'package:kana_quiz/src/core/romaji/romaji_reading.dart';
import 'package:kana_quiz/src/core/storage/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dataset dataset;

  // Le chargement des assets fait de vraies entrées-sorties : il doit avoir
  // lieu hors du temps simulé de `testWidgets`.
  setUpAll(() async => dataset = await Dataset.load());

  Future<void> pumpApp(WidgetTester tester) async {
    // Une fenêtre haute : les listes ne construisent que ce qui est visible.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await ProgressStore.open();
    await tester.pumpWidget(KanaQuizApp(store: store, dataset: dataset));
    await tester.pumpAndSettle();
  }

  /// Le chrono tourne pendant la partie : `pumpAndSettle` ne rendrait jamais
  /// la main, on avance donc image par image.
  Future<void> advance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('l\'accueil propose les modes et les durées', (tester) async {
    await pumpApp(tester);

    expect(find.text('Kana Quiz'), findsOneWidget);
    expect(find.text('Kana → rōmaji'), findsOneWidget);
    expect(find.text('Kanji → lecture'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.textContaining('Commencer'), findsOneWidget);
  });

  testWidgets('une partie se lance, se joue et s\'arrête', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.textContaining('Commencer'));
    await advance(tester);

    expect(find.text('Tape la lecture en rōmaji.'), findsOneWidget);
    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    // Une saisie impossible ne fait pas avancer.
    await tester.enterText(field, 'qqq');
    await tester.pump();
    expect(find.textContaining('Entrée'), findsOneWidget);

    // Entrée : la correction s'affiche et il faut la recopier.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await advance(tester);
    expect(find.text('recopie la lecture'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await advance(tester);
    await tester.tap(find.text('Arrêter'));
    await tester.pumpAndSettle();

    expect(find.text('Kana Quiz'), findsOneWidget);
  });

  testWidgets('une bonne réponse affiche la fiche du mot', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.textContaining('Commencer'));
    await advance(tester);

    final prompt = tester.widget<Text>(find.byKey(const Key('prompt'))).data!;
    final word = dataset.words.firstWhere((w) => w.kana == prompt);

    await tester.enterText(
      find.byType(TextField),
      RomajiReading(prompt).reference,
    );
    await advance(tester);

    // La fiche montre le sens français, le sens anglais, et l'exemple :
    // écriture normale, puis lecture en kana quand elle en diffère.
    expect(find.text(word.fr), findsOneWidget);
    expect(find.text(word.en), findsOneWidget);
    if (word.examples.isNotEmpty) {
      expect(find.text(word.examples.first.jp), findsOneWidget);
      expect(find.text(word.examples.first.kana), findsOneWidget);
    }

    await tester.tap(find.byIcon(Icons.close).first);
    await advance(tester);
    await tester.tap(find.text('Arrêter'));
    await tester.pumpAndSettle();
  });

  testWidgets('une phrase sans kanji ne se répète pas', (tester) async {
    const phrase = 'シャワーにするわ。';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ExampleBlock(
          example: Example(phrase, phrase, 'I will take a shower.'),
        ),
      ),
    ));

    expect(find.text(phrase), findsOneWidget);
  });

  testWidgets('le champ récupère le focus si on clique ailleurs',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.textContaining('Commencer'));
    await advance(tester);

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    tester.widget<TextField>(field).focusNode!.unfocus();
    await tester.pump();
    await tester.tapAt(const Offset(40, 500));
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.close).first);
    await advance(tester);
    await tester.tap(find.text('Arrêter'));
    await tester.pumpAndSettle();
  });

  testWidgets('rien ne signale la direction pendant la frappe',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.textContaining('Commencer'));
    await advance(tester);

    Color border() {
      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!.enabledBorder as OutlineInputBorder;
      return decoration.borderSide.color;
    }

    final neutral = border();
    final prompt = tester.widget<Text>(find.byKey(const Key('prompt'))).data!;

    // Un début juste ne doit pas encourager…
    await tester.enterText(
      find.byType(TextField),
      RomajiReading(prompt).reference.substring(0, 1),
    );
    await tester.pump();
    expect(border(), neutral);

    // …et une lettre impossible ne doit pas prévenir.
    await tester.enterText(find.byType(TextField), 'qqq');
    await tester.pump();
    expect(border(), neutral);

    await tester.tap(find.byIcon(Icons.close).first);
    await advance(tester);
    await tester.tap(find.text('Arrêter'));
    await tester.pumpAndSettle();
  });

  testWidgets('les réglages expliquent les graphies acceptées',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Réglages'), findsOneWidget);
    expect(find.text('Hepburn strict'), findsOneWidget);
    expect(find.textContaining("san'in"), findsOneWidget);
    expect(find.text('koohii'), findsOneWidget);
  });
}
