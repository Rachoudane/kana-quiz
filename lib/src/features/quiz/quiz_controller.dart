import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../app/app.dart';
import '../../core/audio/speech.dart';
import '../../core/models/models.dart';
import '../../core/romaji/romaji_reading.dart';
import '../../core/storage/progress_store.dart';
import '../../modes/modes.dart';

enum QuizPhase { running, finished }

/// Une réponse donnée pendant la partie.
class AnsweredEntry {
  const AnsweredEntry(this.item, {required this.correct});

  final QuizItem item;
  final bool correct;
}

/// Déroulé d'une partie chronométrée.
///
/// Règle de saisie : la réponse est validée dès qu'elle est complète, sans
/// appuyer sur Entrée. Entrée sert à déclarer forfait sur le mot en cours ;
/// il faut alors recopier la bonne lecture pour repartir. Échap le passe, et
/// le compte faux lui aussi, mais sans s'arrêter.
class QuizController extends ChangeNotifier {
  QuizController({
    required this.mode,
    required this.config,
    required this.durationSeconds,
    required List<QuizItem> items,
    required this.store,
  })  : _items = items,
        remainingSeconds = durationSeconds {
    _current = _nextItem();
    teaching = _teaches(_current);
    if (teaching) _say(_current);
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  final QuizMode mode;
  final Map<String, String> config;
  final int durationSeconds;
  final ProgressStore store;

  List<QuizItem> _items;
  int _cursor = 0;
  late QuizItem _current;
  late final Timer _ticker;

  QuizPhase phase = QuizPhase.running;
  int remainingSeconds;
  int correct = 0;
  int mistakes = 0;
  int streak = 0;
  int bestStreak = 0;

  /// Saisie en cours.
  String input = '';
  AnswerState state = AnswerState.empty;

  /// Vrai après une erreur : la correction est affichée et il faut la recopier.
  bool correcting = false;

  /// Vrai quand le mot est présenté et non demandé : sa lecture est affichée,
  /// il n'y a qu'à la recopier, et rien n'est compté.
  bool teaching = false;

  /// Rappels d'un mot appris, en nombre de questions.
  ///
  /// Trois passages réussis suffisent à le considérer comme su : il sort
  /// alors du tour et laisse la place aux mots suivants.
  static const List<int> _reviewGaps = [3, 8, 21];

  /// Palier de rappel atteint par chaque question déjà présentée.
  final Map<String, int> _steps = {};

  final List<AnsweredEntry> history = [];
  final Map<String, bool> _outcomes = {};

  QuizItem get current => _current;

  RunResult? result;
  bool isRecord = false;

  int get answered => correct + mistakes;

  double get accuracy => answered == 0 ? 1 : correct / answered;

  double get progress =>
      durationSeconds == 0 ? 0 : 1 - remainingSeconds / durationSeconds;

  QuizItem _nextItem() {
    if (_cursor >= _items.length) {
      _items = [..._items]..shuffle();
      _cursor = 0;
    }
    return _items[_cursor++];
  }

  void _tick(Timer timer) {
    if (phase == QuizPhase.finished) return;
    remainingSeconds--;
    if (remainingSeconds <= 0) {
      remainingSeconds = 0;
      finish();
      return;
    }
    notifyListeners();
  }

  /// Prononce la lecture, si l'audio est activé dans les réglages.
  ///
  /// On parle quand la lecture devient visible : réponse validée, correction
  /// affichée, mot présenté. Entendre le mot pendant qu'on le cherche
  /// donnerait la réponse.
  void _say(QuizItem item) {
    if (store.setting(KanaQuizApp.audioSetting) == 'on') {
      Speech.say(item.spoken);
    }
  }

  /// Vrai si la question doit d'abord être montrée.
  bool _teaches(QuizItem item) =>
      mode.teachesFirst && !_steps.containsKey(item.id);

  /// Saisie modifiée. Valide automatiquement dès que la lecture est complète.
  ///
  /// `composing` est vrai tant que l'IME n'a pas confirmé sa conversion : le
  /// texte affiché n'est encore qu'une proposition, valider à sa place
  /// couperait la saisie en cours.
  void onInputChanged(String value, {bool composing = false}) {
    input = value;
    state = _current.evaluate(value);
    if (composing) {
      notifyListeners();
      return;
    }
    if (state == AnswerState.complete) {
      // Recopier un mot qu'on vient de montrer n'est pas une bonne réponse.
      _advance(correct: !correcting && !teaching);
      return;
    }
    notifyListeners();
  }

  /// Nombre de questions avant qu'un mot passé ne revienne.
  static const int _requeueGap = 12;

  /// Échap : passe le mot en cours, compté comme une faute.
  ///
  /// Un mot qu'on ne sait pas est un mot raté : il compte faux, il entre dans
  /// les statistiques comme tel, et il revient plus loin dans la partie. La
  /// différence avec Entrée est qu'on ne s'arrête pas pour recopier.
  void skip() {
    if (phase == QuizPhase.finished) return;
    final passed = _current;
    // Un mot présenté n'a pas encore été demandé : le passer ne rate rien.
    if (!teaching && !correcting) {
      mistakes++;
      streak = 0;
      _outcomes[passed.id] = false;
      history.insert(0, AnsweredEntry(passed, correct: false));
    }
    if (mode.teachesFirst) {
      _schedule(passed, remembered: false);
    } else {
      _requeue(passed);
    }
    correcting = false;
    input = '';
    state = AnswerState.empty;
    _current = _nextItem();
    teaching = _teaches(_current);
    notifyListeners();
  }

  void _requeue(QuizItem item, {int gap = _requeueGap}) {
    final at = min(_items.length, _cursor + gap);
    _items = [..._items]..insert(at, item);
  }

  /// Entrée : déclare forfait sur le mot en cours et affiche la correction.
  void giveUp() {
    if (phase == QuizPhase.finished || correcting) return;
    // Rien à abandonner sur un mot dont la lecture est déjà affichée.
    if (teaching) return;
    mistakes++;
    streak = 0;
    _outcomes[_current.id] = false;
    correcting = true;
    input = '';
    state = AnswerState.empty;
    _say(_current);
    notifyListeners();
  }

  void _advance({required bool correct}) {
    final answered = _current;
    final shown = teaching;
    if (correct) {
      this.correct++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
      _outcomes.putIfAbsent(answered.id, () => true);
    }
    // Un mot présenté ne rejoint pas l'historique : sa fiche est déjà à
    // l'écran, et il n'a été ni réussi ni raté.
    if (!shown) history.insert(0, AnsweredEntry(answered, correct: correct));
    if (mode.teachesFirst) _schedule(answered, remembered: correct);
    correcting = false;
    input = '';
    state = AnswerState.empty;
    _current = _nextItem();
    teaching = _teaches(_current);
    _say(teaching ? _current : answered);
    notifyListeners();
  }

  /// Replace un mot appris à son prochain rappel.
  ///
  /// Retrouvé de mémoire, il passe au palier suivant et revient plus tard ;
  /// manqué, il repart du premier rappel.
  void _schedule(QuizItem item, {required bool remembered}) {
    final step = remembered ? (_steps[item.id] ?? 0) + 1 : 0;
    _steps[item.id] = step;
    if (step >= _reviewGaps.length) return;
    _requeue(item, gap: _reviewGaps[step]);
  }

  /// Termine la partie. Une partie abandonnée n'entre pas au classement.
  Future<void> finish({bool aborted = false}) async {
    if (phase == QuizPhase.finished) return;
    phase = QuizPhase.finished;
    _ticker.cancel();
    if (aborted) {
      notifyListeners();
      return;
    }

    final missed = history
        .where((e) => !e.correct)
        .map((e) => '${e.item.prompt} · ${e.item.reference}')
        .toSet()
        .toList();

    final run = RunResult(
      modeId: mode.id,
      config: config,
      durationSeconds: durationSeconds,
      finishedAt: DateTime.now(),
      correct: correct,
      mistakes: mistakes,
      bestStreak: bestStreak,
      missedLabels: missed,
    );
    result = run;
    isRecord = store.isRecord(run);
    await store.saveRun(run, _outcomes);
    notifyListeners();
  }

  @override
  void dispose() {
    Speech.stop();
    _ticker.cancel();
    super.dispose();
  }
}
