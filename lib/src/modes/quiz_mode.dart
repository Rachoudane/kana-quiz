import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/data/dataset.dart';
import '../core/models/models.dart';
import '../core/storage/progress_store.dart';

/// Ce dont un mode dispose pour composer une partie.
///
/// Les statistiques par question sont fournies à tous les modes : c'est ce
/// qui permet à un mode de rejouer en priorité ce qui a déjà été raté.
class ModeContext {
  const ModeContext({
    required this.data,
    required this.config,
    this.stats = const {},
  });

  final Dataset data;
  final Map<String, String> config;
  final Map<String, ItemStat> stats;

  String option(String id, String fallback) => config[id] ?? fallback;

  int get level => int.tryParse(option('level', '5')) ?? 5;
}

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
  List<QuizItem> buildItems(ModeContext context);

  /// Vrai si le mode montre chaque mot avant de le demander.
  ///
  /// La partie devient un apprentissage : un mot encore inconnu est présenté
  /// avec sa lecture et son sens, il suffit de le recopier, et il revient
  /// ensuite à intervalles croissants jusqu'à être su.
  bool get teachesFirst => false;

  /// Ce que le mode répond quand il n'a rien à proposer, `null` sinon.
  String? emptyReason(ModeContext context) => null;

  /// Ce que contient la sélection courante, en une ligne, pour l'accueil.
  String summary(ModeContext context) =>
      '${buildItems(context).length} questions dans cette sélection.';

  Map<String, String> get defaultConfig => {
    for (final option in options) option.id: option.defaultChoice,
  };

  /// Réglages résumés en une ligne, pour les écrans de score.
  String describe(Map<String, String> config) => options
      .map((o) => o.labelFor(config[o.id] ?? o.defaultChoice))
      .join(' · ');

  /// Ce que l'utilisateur doit taper, en une phrase.
  String get instruction;

  /// Durée proposée par défaut quand on choisit ce mode.
  ///
  /// Le chrono mesure une vitesse de lecture : il a du sens là où lire vite
  /// est la compétence. Un mode qui explique, montre ou fait réviser pousse
  /// au contraire à prendre le temps — le compte à rebours y travaillerait
  /// contre le mode.
  int get preferredDuration => defaultDuration;

  /// Vrai si la liste ne se rejoue pas une fois épuisée.
  ///
  /// Sans chrono, une liste finie doit pouvoir s'arrêter d'elle-même.
  bool get singlePass => false;

  @protected
  List<T> shuffled<T>(List<T> items, [int? seed]) {
    final copy = [...items]..shuffle(Random(seed));
    return copy;
  }
}

/// Durées de partie proposées, en secondes. `0` = sans limite.
const List<int> runDurations = [60, 180, 300, 600, 900, openEnded];
const int defaultDuration = 600;

/// Durée d'une partie qui s'arrête quand on l'arrête.
const int openEnded = 0;

/// Durée réellement jouée, en clair : « 4 min 32 ».
String formatElapsed(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes == 0) return '$rest s';
  if (rest == 0) return '$minutes min';
  return '$minutes min $rest';
}

String formatDuration(int seconds) {
  if (seconds == openEnded) return 'Sans limite';
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  return '${seconds}s';
}
