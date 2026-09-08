import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/data/dataset.dart';
import '../core/models/models.dart';

/// Un choix possible pour une option de mode.
class ModeChoice {
  const ModeChoice(this.id, this.label, {this.hint});

  final String id;
  final String label;
  final String? hint;
}

/// Une option configurable avant de lancer une partie.
///
/// Les options font partie de la clé de classement : deux réglages différents
/// ne se comparent pas dans le même tableau des scores.
class ModeOption {
  const ModeOption({
    required this.id,
    required this.label,
    required this.choices,
  });

  final String id;
  final String label;
  final List<ModeChoice> choices;

  String get defaultChoice => choices.first.id;

  String labelFor(String id) =>
      choices.firstWhere((c) => c.id == id, orElse: () => choices.first).label;
}

/// Un mode de jeu.
///
/// Ajouter un mode = créer une classe qui étend [QuizMode] et l'enregistrer
/// dans [quizModes]. Le reste de l'application (chrono, saisie, scores,
/// statistiques) n'a pas besoin d'être modifié.
abstract class QuizMode {
  const QuizMode();

  String get id;
  String get title;
  String get subtitle;
  String get emoji;

  /// Options proposées avant la partie.
  List<ModeOption> get options => const [];

  /// Construit la liste des questions, déjà mélangée.
  List<QuizItem> buildItems(Dataset data, Map<String, String> config);

  Map<String, String> get defaultConfig => {
        for (final option in options) option.id: option.defaultChoice,
      };

  /// Réglages résumés en une ligne, pour les écrans de score.
  String describe(Map<String, String> config) => options
      .map((o) => o.labelFor(config[o.id] ?? o.defaultChoice))
      .join(' · ');

  /// Ce que l'utilisateur doit taper, en une phrase.
  String get instruction;

  @protected
  List<T> shuffled<T>(List<T> items, [int? seed]) {
    final copy = [...items]..shuffle(Random(seed));
    return copy;
  }
}

/// Durées de partie proposées, en secondes.
const List<int> runDurations = [60, 180, 300, 600, 900];
const int defaultDuration = 600;

String formatDuration(int seconds) {
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  return '${seconds}s';
}
