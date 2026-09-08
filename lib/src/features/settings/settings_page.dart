import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/romaji/romaji_reading.dart';
import '../common/widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.of(context);
    final store = scope.store;

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final themeSetting =
                  store.setting(KanaQuizApp.themeSetting) ?? 'system';
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                children: [
                  const SectionTitle('Apparence'),
                  ChoiceRow<String>(
                    values: const ['system', 'light', 'dark'],
                    selected: themeSetting,
                    labelOf: (v) => switch (v) {
                      'light' => 'Clair',
                      'dark' => 'Sombre',
                      _ => 'Système',
                    },
                    onSelected: (v) =>
                        store.setSetting(KanaQuizApp.themeSetting, v),
                  ),
                  const SizedBox(height: 32),
                  const SectionTitle('Écrire les rōmaji'),
                  ChoiceRow<String>(
                    values: const ['strict', 'loose'],
                    selected: RomajiReading.strictMode ? 'strict' : 'loose',
                    labelOf: (v) => v == 'strict'
                        ? 'Hepburn strict'
                        : 'Toutes les graphies',
                    onSelected: (v) {
                      RomajiReading.setStrict(v == 'strict');
                      store.setSetting(KanaQuizApp.romajiSetting, v);
                    },
                  ),
                  const SizedBox(height: 16),
                  _help(context),
                  const SizedBox(height: 32),
                  const SectionTitle('Pendant la frappe'),
                  ChoiceRow<String>(
                    values: const ['none', 'errors'],
                    selected:
                        store.setting(KanaQuizApp.typingSetting) ?? 'none',
                    labelOf: (v) =>
                        v == 'none' ? 'Aucun retour' : 'Signaler les erreurs',
                    onSelected: (v) =>
                        store.setSetting(KanaQuizApp.typingSetting, v),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Sans retour, rien ne bouge tant que la lecture n'est pas "
                    "complète et juste : c'est le seul moyen de savoir si tu "
                    'connaissais vraiment le mot. Signaler les erreurs colore '
                    'le champ en rouge dès la première lettre fautive, ce qui '
                    'permet de retrouver la réponse à tâtons.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SectionTitle('Progression'),
                  Text(
                    'Tout est stocké dans ce navigateur. L\'export permet de '
                    'récupérer ses parties ailleurs.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _export(context),
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Exporter'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _import(context),
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Importer'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _reset(context),
                        style: OutlinedButton.styleFrom(foregroundColor: failure),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Tout effacer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  const SectionTitle('Données'),
                  for (final line in scope.dataset.attributions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _help(BuildContext context) {
    final theme = Theme.of(context);
    final strict = RomajiReading.strictMode;
    const rules = [
      ['しゃしん', 'shashin', 'hepburn : shi, chi, tsu, fu, ji, sha, ja'],
      ['さんいん', "sanin  ou  san'in", "ん : l'apostrophe est facultative"],
      ['こっち', 'kotchi', 'petite tsu : consonne doublée, tch devant ち'],
      ['とうきょう', 'toukyou', 'voyelle longue : on écrit les kana'],
      ['コーヒー', 'koohii', 'allongement ー : la voyelle est répétée'],
      ['では', 'dewa', 'は particule : se lit wa'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strict
              ? 'Une seule graphie est correcte : celle de la transcription '
                  "Hepburn. Elle s'affiche sur la fiche après chaque mot."
              : 'Les autres systèmes sont acceptés (syasin, huzi, kocchi, '
                  'tokyo). La graphie de référence reste affichée sur la fiche.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final rule in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(rule[0], style: promptStyle(context, 18)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule[1], style: romajiStyle.copyWith(fontSize: 14)),
                      Text(
                        rule[2],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final store = AppScope.of(context).store;
    final json = store.exportJson();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export'),
        content: SizedBox(
          width: 520,
          child: SelectableText(
            json.length > 4000 ? '${json.substring(0, 4000)}…' : json,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Copier'),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final store = AppScope.of(context).store;
    final field = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer une progression'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: field,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Colle ici le JSON exporté',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final ok = await store.importJson(raw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Progression importée.' : 'Fichier illisible.'),
        ),
      );
    }
  }

  Future<void> _reset(BuildContext context) async {
    final store = AppScope.of(context).store;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tout effacer ?'),
        content: const Text('Parties et statistiques seront perdues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: failure),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.clear();
  }
}
