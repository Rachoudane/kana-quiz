import '../models/models.dart';

/// Un motif grammatical : son nom court, et ce qu'il y a à comprendre.
class ParticleRule {
  const ParticleRule(this.label, this.explanation);

  /// Nom court du motif, pour le reconnaître quand il revient.
  final String label;

  /// La raison du choix, en français.
  final String explanation;
}

/// Ce que chaque motif enseigne.
///
/// Les identifiants sont ceux que pose `tool/build_particles.py`. Un trou dont
/// le motif n'est pas reconnu n'entre pas dans le jeu de données : une
/// question sans raison n'apprendrait rien.
const Map<String, ParticleRule> particleRules = {
  'wo_object': ParticleRule(
    'を objet',
    'を marque le complément d\'objet direct : ce sur quoi l\'action porte.',
  ),
  'wo_through': ParticleRule(
    'を de parcours',
    'を marque le lieu que l\'on traverse ou que l\'on quitte. でる, とおる, '
        'あるく n\'ont pas de complément d\'objet, et prennent pourtant を.',
  ),
  'ni_exist': ParticleRule(
    'に de position',
    'に marque le lieu où quelque chose se trouve. Avec ある et いる c\'est に, '
        'jamais で.',
  ),
  'ni_goal': ParticleRule(
    'に de destination',
    'に marque le point où le mouvement aboutit.',
  ),
  'ni_time': ParticleRule(
    'に de temps',
    'に marque l\'heure ou la date. Les mots qui situent sans chiffrer — '
        'きょう, あした, まいにち — n\'en prennent pas.',
  ),
  'ni_recipient': ParticleRule(
    'に de destinataire',
    'に marque celui à qui l\'action s\'adresse.',
  ),
  'ni_become': ParticleRule(
    'に de changement',
    'に marque l\'état vers lequel on change. なる prend に, jamais を.',
  ),
  'de_place': ParticleRule(
    'で de lieu',
    'で marque le lieu où l\'action se déroule. Être quelque part se dit に, '
        'y faire quelque chose se dit で.',
  ),
  'de_means': ParticleRule(
    'で de moyen',
    'で marque le moyen : par quoi, avec quoi.',
  ),
  'to_quote': ParticleRule(
    'と de citation',
    'と ferme ce qui est dit ou pensé. Tout ce qui précède est la citation.',
  ),
  'to_and': ParticleRule(
    'と de liste',
    'と relie deux noms. La liste est complète : と donne tout, や n\'en donne '
        'qu\'un échantillon.',
  ),
  'to_with': ParticleRule(
    'と d\'accompagnement',
    'と marque celui avec qui l\'action se fait.',
  ),
  'kara_origin': ParticleRule(
    'から de départ',
    'から marque le point de départ, dans l\'espace comme dans le temps.',
  ),
  'made_limit': ParticleRule(
    'まで de limite',
    'まで marque la limite où l\'on s\'arrête.',
  ),
  'he_direction': ParticleRule(
    'へ de direction',
    'へ marque la direction. に vise le point d\'arrivée, へ le sens du '
        'déplacement.',
  ),
  'mo_also': ParticleRule(
    'も d\'addition',
    'も remplace は, が ou を et ajoute « aussi ».',
  ),
  'no_link': ParticleRule(
    'の de lien',
    'の relie deux noms : le premier détermine le second.',
  ),
  'ga_question': ParticleRule(
    'が après interrogatif',
    'が est obligatoire après un mot interrogatif. La question porte sur le '
        'sujet lui-même, et un sujet inconnu ne peut pas être un thème : '
        'だれがきた, jamais だれはきた.',
  ),
  'ga_exist': ParticleRule(
    'が d\'existence',
    'が présente ce qui existe. ある et いる annoncent une chose neuve, et le '
        'neuf se marque が.',
  ),
  'ga_emotion': ParticleRule(
    'が d\'affect',
    'が marque ce qu\'on aime, ce qu\'on sait faire, ce qu\'on veut. Le '
        'français en fait un complément d\'objet, le japonais non : すき, '
        'ほしい, できる, わかる prennent が.',
  ),
  'wa_big_topic': ParticleRule(
    'は cadre, が sujet',
    'は pose le cadre, が désigne le sujet à l\'intérieur. C\'est le motif '
        'ぞうははながながい : « l\'éléphant, le nez est long ».',
  ),
  'ga_small_subject': ParticleRule(
    'が sous le cadre de は',
    'が désigne le sujet étroit, à l\'intérieur du cadre que は vient de '
        'poser. ぞうははながながい : le thème est l\'éléphant, ce qui est long '
        'est le nez.',
  ),
  'wa_contrast': ParticleRule(
    'は de contraste',
    'は oppose. Il détache ce dont on parle du reste, et ce qui suit est '
        'souvent une négation.',
  ),
  'wa_open': ParticleRule('は thème ou が sujet', _openExplanation),
  'ga_open': ParticleRule('は thème ou が sujet', _openExplanation),
};

const String _openExplanation =
    'Les deux se disent, et le sens change. は en fait le thème : on en '
    'parlait déjà, la phrase dit ce qu\'il en est. が l\'annonce comme du '
    'neuf — ce qu\'on vient de constater, ou la réponse à « lequel ? ».';

/// Ce que la fiche affiche après la réponse.
///
/// Sur un trou où は et が passent tous les deux, l'explication est reprise
/// avec le mot de la phrase, et se termine par le choix qu'a fait la phrase
/// source : c'est une information, pas un verdict.
String particleNote(ParticleSlot slot) {
  final rule = particleRules[slot.rule];
  if (rule == null) return '';
  if (!slot.isOpen) return rule.explanation;

  final subject = slot.topic.isEmpty ? 'ce mot' : slot.topic;
  return 'Les deux se disent, et le sens change. は fait de $subject le '
      'thème : on en parlait déjà, la phrase dit ce qu\'il en est. が '
      'l\'annonce comme du neuf — ce qu\'on vient de constater, ou la '
      'réponse à « lequel ? ». Ici la phrase dit ${slot.answer}.';
}

/// Nom court du motif, vide s'il n'est pas connu.
String particleLabel(ParticleSlot slot) =>
    particleRules[slot.rule]?.label ?? '';
