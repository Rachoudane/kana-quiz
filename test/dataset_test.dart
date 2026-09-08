import 'package:flutter_test/flutter_test.dart';
import 'package:kana_quiz/src/core/data/dataset.dart';
import 'package:kana_quiz/src/core/romaji/romaji_reading.dart';
import 'package:kana_quiz/src/modes/modes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dataset data;

  setUpAll(() async {
    data = await Dataset.load();
  });

  test('le vocabulaire N5 est complet et bien formé', () {
    expect(data.words.length, greaterThan(600));
    expect(data.katakanaCount, greaterThan(40));
    expect(
      data.words.where((w) => w.examples.isNotEmpty).length,
      greaterThan(data.words.length ~/ 2),
    );
    for (final word in data.words) {
      expect(word.kana, isNotEmpty, reason: word.id);
      expect(word.meaning, isNotEmpty, reason: word.id);
      expect(word.script, anyOf('hiragana', 'katakana'));
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
        expect(reading.accepts(alternate), isTrue,
            reason: '${word.kana} -> $alternate');
      }
    }
  });

  test('les kanji ont au moins une lecture exploitable', () {
    expect(data.coreKanjiCount, greaterThanOrEqualTo(79));
    for (final entry in data.kanji) {
      expect(
        entry.on.isNotEmpty || entry.kun.isNotEmpty,
        isTrue,
        reason: entry.kanji,
      );
      for (final reading in [...entry.on, ...entry.kun]) {
        final parsed = RomajiReading(reading);
        expect(parsed.accepts(parsed.reference), isTrue,
            reason: '${entry.kanji} -> $reading');
      }
    }
  });

  test('chaque mode produit des questions jouables', () {
    for (final mode in quizModes) {
      final items = mode.buildItems(data, mode.defaultConfig);
      expect(items.length, greaterThan(50), reason: mode.id);
      for (final item in items.take(200)) {
        expect(item.prompt, isNotEmpty);
        expect(item.readings, isNotEmpty);
        expect(item.evaluate(item.reference), AnswerState.complete,
            reason: '${mode.id} / ${item.prompt}');
      }
    }
  });
}
