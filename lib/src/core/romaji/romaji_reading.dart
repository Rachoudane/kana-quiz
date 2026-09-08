import 'kana_table.dart';

/// État d'une saisie par rapport à la lecture attendue.
enum AnswerState {
  /// Rien de saisi.
  empty,

  /// Début valide, la réponse n'est pas encore complète.
  partial,

  /// Lecture complète et correcte.
  complete,

  /// La saisie ne peut plus mener à la bonne réponse.
  invalid,
}

/// Un mora (ou groupe sokuon + mora) et les graphies qui le transcrivent.
class RomajiUnit {
  RomajiUnit(
    this.kana,
    this.strict, {
    List<String> extra = const [],
    this.ambiguous = false,
  }) : _extra = extra;

  /// Portion de kana couverte, par ex. « っち ».
  final String kana;

  /// Graphies acceptées en mode strict. La première fait référence.
  ///
  /// Il n'y en a qu'une, sauf pour les cas où deux graphies transcrivent
  /// exactement la même prononciation (ん avec ou sans apostrophe).
  final List<String> strict;

  final List<String> _extra;

  /// Vrai pour les mora dont la transcription hésite en pratique : ん devant
  /// voyelle, sokuon, allongement.
  final bool ambiguous;

  String get reference => strict.first;

  /// Graphies acceptées en mode tolérant : la référence, les équivalents
  /// stricts, puis les autres systèmes de transcription.
  late final List<String> loose = [...strict, ..._extra];

  List<String> spellings(bool strictMode) => strictMode ? strict : loose;
}

/// Découpe une lecture en kana et sait dire si une saisie en rōmaji correspond.
///
/// Par défaut le moteur est strict : une seule graphie est correcte, celle de
/// la transcription Hepburn (`shi`, `chi`, `tsu`, `fu`, `ja`, `tchi`), les
/// voyelles longues étant écrites comme elles sont écrites en kana
/// (`toukyou`, `koohii`). Seule tolérance : l'apostrophe de ん reste
/// facultative, `sanin` et `san'in` valent tous les deux.
class RomajiReading {
  RomajiReading._(this.kana, this.units);

  factory RomajiReading(String kana) => RomajiReading._(kana, _segment(kana));

  /// Réglage global. `false` accepte aussi kunrei et les graphies de saisie IME.
  static bool strictMode = true;

  /// Change le mode et vide le cache : les graphies alternatives affichées
  /// dépendent du réglage.
  static void setStrict(bool value) {
    if (value == strictMode) return;
    strictMode = value;
    _cache.clear();
  }

  final String kana;
  final List<RomajiUnit> units;

  static final Map<String, RomajiReading> _cache = {};

  /// Instance mémoïsée : la même lecture revient souvent dans une partie.
  static RomajiReading of(String kana) =>
      _cache.putIfAbsent(kana, () => RomajiReading(kana));

  /// Graphie de référence, celle qu'on affiche après validation.
  late final String reference = units.map((u) => u.reference).join();

  /// Autres graphies acceptées, à titre indicatif.
  late final List<String> alternates = _buildAlternates();

  /// Vrai si la lecture comporte un point qui prête à confusion à la saisie.
  late final bool hasTrickySpot = units.any((u) => u.ambiguous);

  /// Normalise une saisie utilisateur : minuscules, apostrophes typographiques,
  /// espaces retirés.
  static String normalize(String input) {
    var out = input.toLowerCase().trim();
    out = out.replaceAll('’', "'").replaceAll('ʼ', "'");
    out = out.replaceAll(RegExp(r'\s+'), '');
    return out;
  }

  /// Compare une saisie à la lecture attendue.
  AnswerState evaluate(String rawInput) {
    final input = normalize(rawInput);
    if (input.isEmpty) return AnswerState.empty;

    final n = units.length;
    final m = input.length;
    final seen = List.generate(n + 1, (_) => List.filled(m + 1, false));
    final queue = <int>[0];
    seen[0][0] = true;

    var complete = false;
    var prefix = false;

    while (queue.isNotEmpty) {
      final state = queue.removeLast();
      final u = state ~/ (m + 1);
      final j = state % (m + 1);

      if (j == m) {
        prefix = true;
        if (u == n) complete = true;
      }
      if (u == n) continue;

      for (final spelling in units[u].spellings(strictMode)) {
        if (spelling.isEmpty) {
          if (!seen[u + 1][j]) {
            seen[u + 1][j] = true;
            queue.add((u + 1) * (m + 1) + j);
          }
          continue;
        }
        final end = j + spelling.length;
        if (end <= m) {
          if (input.startsWith(spelling, j) && !seen[u + 1][end]) {
            seen[u + 1][end] = true;
            queue.add((u + 1) * (m + 1) + end);
          }
        } else if (spelling.startsWith(input.substring(j))) {
          // La saisie s'arrête au milieu de ce mora : elle reste valide.
          prefix = true;
        }
      }
    }

    if (complete) return AnswerState.complete;
    if (prefix) return AnswerState.partial;
    return AnswerState.invalid;
  }

  bool accepts(String input) => evaluate(input) == AnswerState.complete;

  List<String> _buildAlternates() {
    final out = <String>[];
    void add(String Function(RomajiUnit) pick) {
      final candidate = units.map(pick).join();
      if (candidate.isNotEmpty &&
          candidate != reference &&
          !out.contains(candidate)) {
        out.add(candidate);
      }
    }

    // Équivalents stricts : uniquement l'apostrophe de ん.
    add((u) => u.strict.length > 1 ? u.strict[1] : u.reference);
    if (!strictMode) {
      add((u) => u.loose.length > 1 ? u.loose[1] : u.reference);
      add((u) => u.loose.last);
    }
    return out.take(3).toList();
  }
}

// ---------------------------------------------------------------------------
// Découpage
// ---------------------------------------------------------------------------

const _vowelKana = 'あいうえおゃゅょやゆよ';
const _labialKana = 'ばびぶべぼぱぴぷぺぽまみむめも';

/// Longueur du prochain mora à partir de [i] : 2 pour un digramme, sinon 1.
int _unitLength(String s, int i) {
  if (i + 1 < s.length && kanaHepburn.containsKey(s.substring(i, i + 2))) {
    return 2;
  }
  return 1;
}

String _lastVowel(List<RomajiUnit> units) {
  for (var i = units.length - 1; i >= 0; i--) {
    final ref = units[i].reference;
    if (ref.isEmpty) continue;
    final last = ref[ref.length - 1];
    if (vowels.contains(last)) return last;
  }
  return '';
}

/// Redouble une graphie derrière un sokuon.
///
/// Hepburn écrit っち « tchi » ; « cchi » et « tti » restent acceptés en mode
/// tolérant.
String _geminate(String spelling) {
  if (spelling.isEmpty) return spelling;
  if (spelling.startsWith('ch')) return 't$spelling';
  return '${spelling[0]}$spelling';
}

List<RomajiUnit> _segment(String rawKana) {
  final s = toHiragana(rawKana);
  final particleWa = particleWaReadings.contains(s);
  final units = <RomajiUnit>[];
  var i = 0;

  while (i < s.length) {
    final ch = s[i];

    if (ch == sokuon) {
      if (i + 1 >= s.length) {
        units.add(RomajiUnit('っ', const ['tsu'], ambiguous: true));
        i++;
        continue;
      }
      final len = _unitLength(s, i + 1);
      final key = s.substring(i + 1, i + 1 + len);
      final base = kanaHepburn[key];
      if (base == null) {
        i++;
        continue;
      }
      final extra = <String>[
        if (base.startsWith('ch')) 'c$base',
        for (final variant in kanaVariants[key] ?? const <String>[])
          _geminate(variant),
      ];
      units.add(
        RomajiUnit(
          ch + key,
          [_geminate(base)],
          extra: extra,
          ambiguous: true,
        ),
      );
      i += 1 + len;
      continue;
    }

    if (ch == prolongedMark) {
      final v = _lastVowel(units);
      units.add(
        RomajiUnit(
          ch,
          [if (v.isNotEmpty) v else ''],
          extra: const ['', '-'],
          ambiguous: true,
        ),
      );
      i++;
      continue;
    }

    if (ch == 'ん') {
      final next = i + 1 < s.length ? s[i + 1] : '';
      final needsApostrophe = next.isNotEmpty && _vowelKana.contains(next);
      units.add(
        RomajiUnit(
          ch,
          // L'apostrophe reste facultative : « sanin » comme « san'in ».
          needsApostrophe ? ['n', "n'"] : ['n'],
          extra: [
            'nn',
            if (next.isNotEmpty && _labialKana.contains(next)) 'm',
          ],
          ambiguous: needsApostrophe,
        ),
      );
      i++;
      continue;
    }

    final len = _unitLength(s, i);
    final key = s.substring(i, i + len);
    final base = kanaHepburn[key];
    if (base == null) {
      // Caractère hors table (ponctuation, kanji) : ignoré.
      i += len;
      continue;
    }

    final isFinal = i + len == s.length;
    if (key == 'は' && isFinal && particleWa) {
      units.add(RomajiUnit('は', const ['wa'], extra: const ['ha']));
      i += len;
      continue;
    }

    final previous = _lastVowel(units);
    final extra = <String>[...?kanaVariants[key]];
    var ambiguous = false;
    if ((key == 'う' && (previous == 'o' || previous == 'u')) ||
        (key == 'お' && previous == 'o')) {
      // Voyelle longue : on écrit ce qui est écrit en kana (toukyou, ookii).
      extra.addAll(const ['']);
      if (key == 'う' && previous == 'o') extra.add('o');
      ambiguous = true;
    } else if (key == 'い' && previous == 'e') {
      extra.add('e');
      ambiguous = true;
    }

    units.add(RomajiUnit(key, [base], extra: extra, ambiguous: ambiguous));
    i += len;
  }

  return units;
}
