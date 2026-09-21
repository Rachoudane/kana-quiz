import 'package:flutter_test/flutter_test.dart';
import 'package:kana_quiz/src/core/romaji/romaji_reading.dart';

void main() {
  setUp(() => RomajiReading.strictMode = true);

  void accepts(String kana, List<String> inputs) {
    final reading = RomajiReading(kana);
    for (final input in inputs) {
      expect(
        reading.evaluate(input),
        AnswerState.complete,
        reason:
            '$kana devrait accepter « $input » '
            '(référence ${reading.reference})',
      );
    }
  }

  void rejects(String kana, List<String> inputs) {
    final reading = RomajiReading(kana);
    for (final input in inputs) {
      expect(
        reading.evaluate(input),
        isNot(AnswerState.complete),
        reason: '$kana ne devrait pas accepter « $input »',
      );
    }
  }

  void reference(String kana, String expected) {
    expect(RomajiReading(kana).reference, expected);
  }

  group('une seule graphie correcte', () {
    test('hepburn, pas kunrei', () {
      reference('しゃしん', 'shashin');
      accepts('しゃしん', ['shashin', 'SHASHIN', ' shashin ']);
      rejects('しゃしん', ['syasin', 'syashin', 'shasin']);

      reference('ちゅうい', 'chuui');
      rejects('ちゅうい', ['tyuui', 'cyuui']);

      reference('ふじ', 'fuji');
      rejects('ふじ', ['huzi', 'fuzi', 'huji']);

      reference('つくえ', 'tsukue');
      rejects('つくえ', ['tukue']);

      reference('ちいさい', 'chiisai');
      rejects('ちいさい', ['tiisai']);
    });

    test('voyelles longues écrites comme en kana', () {
      reference('とうきょう', 'toukyou');
      rejects('とうきょう', ['tokyo', 'tookyoo', 'tōkyō']);

      reference('コーヒー', 'koohii');
      rejects('コーヒー', ['kohi', 'ko-hi-', 'koohi']);

      reference('せんせい', 'sensei');
      rejects('せんせい', ['sensee']);

      reference('おおきい', 'ookii');
      rejects('おおきい', ['okii']);
    });

    test('sokuon : consonne doublée, tch pour ち', () {
      reference('がっこう', 'gakkou');
      rejects('がっこう', ['gakko', 'gakkoo', 'gakou']);

      reference('こっち', 'kotchi');
      rejects('こっち', ['kocchi', 'kotti', 'kochi']);

      reference('みっつ', 'mittsu');
      reference('きっさてん', 'kissaten');
    });
  });

  group('ん', () {
    test('l\'apostrophe reste facultative', () {
      reference('さんいん', 'sanin');
      accepts('さんいん', ['sanin', "san'in", 'SANIN']);
      rejects('さんいん', ['sannin', 'sain']);
      expect(RomajiReading('さんいん').alternates, ["san'in"]);
    });

    test('devant une consonne, une seule graphie', () {
      reference('にほん', 'nihon');
      rejects('にほん', ['nihonn']);
      reference('しんぶん', 'shinbun');
      rejects('しんぶん', ['shimbun', 'shinnbunn']);
    });
  });

  group('は final', () {
    test('les particules se lisent wa', () {
      reference('では', 'dewa');
      reference('それでは', 'soredewa');
      rejects('では', ['deha']);
    });

    test('ailleurs は se lit ha', () {
      reference('はは', 'haha');
      rejects('はは', ['hawa', 'wawa']);
    });
  });

  group('saisies invalides', () {
    test('une lettre en trop ou en moins est refusée', () {
      rejects('さんいん', ['sanina', 'sani']);
      rejects('ねこ', ['neko!', 'nek', 'nekko']);
    });

    test('un début valide reste partiel', () {
      final reading = RomajiReading('がっこう');
      expect(reading.evaluate('gak'), AnswerState.partial);
      expect(reading.evaluate('g'), AnswerState.partial);
      expect(reading.evaluate(''), AnswerState.empty);
      expect(reading.evaluate('z'), AnswerState.invalid);
    });
  });

  group('mode tolérant', () {
    setUp(() => RomajiReading.strictMode = false);
    tearDown(() => RomajiReading.strictMode = true);

    test('les autres systèmes passent', () {
      accepts('しゃしん', ['shashin', 'syasin']);
      accepts('ふじ', ['fuji', 'huzi']);
      accepts('こっち', ['kotchi', 'kocchi', 'kotti']);
      accepts('さんいん', ['sanin', "san'in", 'sannin']);
      accepts('コーヒー', ['koohii', 'kohi', 'ko-hi-']);
      accepts('とうきょう', ['toukyou', 'tokyo', 'tookyoo']);
    });

    test('la référence ne change pas', () {
      reference('しゃしん', 'shashin');
      reference('さんいん', 'sanin');
    });
  });

  group('robustesse', () {
    test('la référence de chaque lecture est acceptée par elle-même', () {
      const samples = [
        'あたらしい',
        'いっしょ',
        'おちゃ',
        'かいしゃ',
        'きって',
        'ぎゅうにゅう',
        'けっこん',
        'こんばん',
        'しゅくだい',
        'じてんしゃ',
        'せんげつ',
        'たいへん',
        'ちょうど',
        'でんわ',
        'にちようび',
        'ひゃく',
        'べんきょう',
        'まいにち',
        'りょこう',
        'エレベーター',
        'カレンダー',
        'ワイシャツ',
        'ニュース',
      ];
      for (final kana in samples) {
        final reading = RomajiReading(kana);
        expect(reading.reference, isNotEmpty, reason: kana);
        expect(
          reading.accepts(reading.reference),
          isTrue,
          reason: '$kana -> ${reading.reference}',
        );
        for (final alt in reading.alternates) {
          expect(reading.accepts(alt), isTrue, reason: '$kana -> $alt');
        }
      }
    });
  });
}
