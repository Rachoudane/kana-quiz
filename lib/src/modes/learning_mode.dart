import 'kana_reading_mode.dart';
import 'quiz_mode.dart';
import '../core/models/models.dart';

/// Mode d'apprentissage : le mot est montré avant d'être demandé.
///
/// Les autres modes évaluent. Celui-ci enseigne : un mot jamais vu s'affiche
/// avec sa lecture et son sens, il suffit de recopier la lecture pour passer
/// au suivant, sans faute possible. Le mot revient ensuite à intervalles
/// croissants, et il faut le retrouver seul.
///
/// Les mots arrivent dans l'ordre du niveau, pas au hasard : on n'apprend pas
/// une liste en la mélangeant.
class LearningMode extends QuizMode {
  const LearningMode();

  @override
  String get id => 'learning';

  @override
  String get title => 'Apprendre le vocabulaire';

  @override
  String get subtitle => 'Chaque mot est montré, puis redemandé.';

  @override
  String get emoji => '学';

  @override
  String get instruction => 'Recopie la lecture, puis retrouve-la de mémoire.';

  @override
  bool get teachesFirst => true;

  @override
  List<ModeOption> get options => const [
        ModeOption(
          id: 'level',
          label: 'Niveau',
          choices: [
            ModeChoice('5', 'N5'),
            ModeChoice('4', 'N5 + N4'),
            ModeChoice('3', 'N5 + N4 + N3'),
          ],
        ),
        ModeOption(
          id: 'script',
          label: 'Écriture',
          choices: [
            ModeChoice('all', 'Hiragana + katakana'),
            ModeChoice('hiragana', 'Hiragana seul'),
            ModeChoice('katakana', 'Katakana seul'),
          ],
        ),
      ];

  @override
  List<QuizItem> buildItems(ModeContext context) {
    final words = context.data.select(
      script: context.option('script', 'all'),
      fromLevel: context.level,
    );
    // Le plus accessible d'abord, et un ordre stable d'une partie à l'autre :
    // reprendre l'apprentissage doit reprendre là où il en était.
    words.sort((a, b) {
      final byLevel = b.level.compareTo(a.level);
      return byLevel != 0 ? byLevel : a.id.compareTo(b.id);
    });
    // Les questions gardent l'identifiant du mode de lecture : lire un mot
    // reste lire un mot, les statistiques n'ont pas à se dédoubler.
    return words.map(KanaReadingMode.itemFor).toList();
  }

  @override
  String summary(ModeContext context) =>
      '${buildItems(context).length} mots à apprendre dans cette sélection.';
}
