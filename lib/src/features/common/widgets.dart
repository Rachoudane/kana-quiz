import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/models/models.dart';

/// Titre de section, discret.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Chiffre mis en avant avec son libellé.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
  });

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Fiche affichée après une réponse : lecture, écriture, sens, exemple.
class ItemRevealCard extends StatelessWidget {
  const ItemRevealCard({
    super.key,
    required this.item,
    required this.correct,
    this.dense = false,
  });

  final QuizItem item;
  final bool correct;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = correct ? success : failure;
    final example = item.examples.isNotEmpty ? item.examples.first : null;

    return Card(
      margin: EdgeInsets.only(bottom: dense ? 8 : 12),
      child: Padding(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: dense ? 34 : 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        item.prompt,
                        style: promptStyle(context, dense ? 22 : 26),
                      ),
                      if (item.secondary != null)
                        Text(
                          item.secondary!,
                          style: promptStyle(context, dense ? 18 : 20).copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          item.allReferences.take(3).join(' / '),
                          style: romajiStyle.copyWith(
                            fontSize: dense ? 14 : 15,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.meaning,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (item.detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamilyFallback: japaneseFallback,
                      ),
                    ),
                  ],
                  if (item.alternates.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'aussi accepté : ${item.alternates.join(', ')}',
                      style: romajiStyle.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                  if (item.related.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.related
                          .take(3)
                          .map((w) => '${w.word}（${w.kana}）')
                          .join('   '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamilyFallback: japaneseFallback,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (example != null && !dense) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            example.jp,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamilyFallback: japaneseFallback,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            example.en,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Groupe de choix exclusifs.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(labelOf(value)),
            selected: value == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}
