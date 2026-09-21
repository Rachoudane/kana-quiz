import '../core/data/particle_rules.dart';
import '../core/models/models.dart';
import '../core/romaji/romaji_reading.dart';
import 'quiz_mode.dart';

/// Mode grammaire : une phrase en kana, une particule retirée, à retrouver.
///
/// Le but n'est pas de deviner mais de savoir pourquoi. Chaque trou est
/// rattaché à un motif grammatical, et la fiche donne la raison du choix en
/// même temps que la réponse. Les trous dont le motif n'a pas été reconnu ne
/// sont pas dans le jeu de données : voir `tool/build_particles.py`.
///
/// Sur les trous où は et が se défendent tous les deux — un sujet nu en tête
/// de phrase — les deux sont acceptés et la fiche explique ce qui change.
/// Compter faux une réponse juste n'apprendrait rien, et c'est justement là
/// que se joue la différence entre les deux.
class ParticlesMode extends QuizMode {
  const ParticlesMode();

  @override
  String get id => 'particles';

  @override
  String get title => 'Particules';

  @override
  String get subtitle => 'Une phrase à trou, et la raison du choix.';

  @override
  String get emoji => 'を';

  @override
  int get preferredDuration => openEnded;

  @override
  String get instruction => 'Écris la particule qui manque.';

  @override
  List<ModeOption> get options => const [
    ModeOption(
      id: 'focus',
      label: 'Particules',
      choices: [
        ModeChoice('all', 'Toutes'),
        ModeChoice('waga', 'は et が'),
        ModeChoice('place', 'に · で · へ'),
        ModeChoice('other', 'を · の · と · から'),
      ],
    ),
  ];

  /// Particules retenues pour chaque sélection.
  static const Map<String, Set<String>> _focus = {
    'waga': {'は', 'が'},
    'place': {'に', 'で', 'へ'},
    'other': {'を', 'の', 'と', 'から', 'まで', 'も'},
  };

  static List<ParticleSlot> _select(ModeContext context) {
    final focus = context.option('focus', 'all');
    final keep = _focus[focus];
    if (keep == null) return context.data.particles;
    return context.data.particles
        .where((s) => s.answers.any(keep.contains))
        .toList();
  }

  @override
  List<QuizItem> buildItems(ModeContext context) =>
      shuffled(_select(context).map(itemFor).toList());

  @override
  String summary(ModeContext context) {
    final slots = _select(context);
    final rules = slots.map((s) => s.rule).toSet().length;
    return '${slots.length} phrases à trou, $rules motifs de grammaire.';
  }

  /// Question posée pour une phrase à trou.
  ///
  /// La phrase complète est montrée après coup : lire la phrase juste en
  /// entier vaut mieux que de ne relire que la particule.
  static QuizItem itemFor(ParticleSlot slot) => QuizItem(
    id: slot.id,
    prompt: slot.blanked,
    promptScript: 'sentence',
    answerScript: 'kana',
    readings: slot.answers.map(RomajiReading.of).toList(),
    fr: '',
    en: slot.translation,
    secondary: slot.sentence,
    detail: particleLabel(slot),
    note: particleNote(slot),
  );
}
