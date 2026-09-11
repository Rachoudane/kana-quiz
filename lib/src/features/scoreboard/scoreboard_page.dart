import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/data/dataset.dart';
import '../../core/storage/progress_store.dart';
import '../../modes/modes.dart';
import '../common/widgets.dart';

class ScoreboardPage extends StatefulWidget {
  const ScoreboardPage({super.key});

  @override
  State<ScoreboardPage> createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  QuizMode _mode = quizModes.first;
  int _duration = defaultDuration;
  late final Map<String, Map<String, String>> _configs = {
    for (final mode in quizModes) mode.id: {...mode.defaultConfig},
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context).store;

    return Scaffold(
      appBar: AppBar(title: const Text('Scores')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final config = _configs[_mode.id]!;
              final key = boardKeyFor(_mode.id, _duration, config);
              final board = store.board(key);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                children: [
                  _lifetime(context, store),
                  const SizedBox(height: 28),
                  const SectionTitle('Classement'),
                  ChoiceRow<QuizMode>(
                    values: quizModes,
                    selected: _mode,
                    labelOf: (m) => m.title,
                    onSelected: (m) => setState(() => _mode = m),
                  ),
                  const SizedBox(height: 8),
                  for (final option in _mode.options) ...[
                    const SizedBox(height: 8),
                    ChoiceRow<ModeChoice>(
                      values: option.choices,
                      selected: option.choices.firstWhere(
                        (c) => c.id == config[option.id],
                        orElse: () => option.choices.first,
                      ),
                      labelOf: (c) => c.label,
                      onSelected: (c) =>
                          setState(() => config[option.id] = c.id),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ChoiceRow<int>(
                    values: runDurations,
                    selected: _duration,
                    labelOf: formatDuration,
                    onSelected: (d) => setState(() => _duration = d),
                  ),
                  const SizedBox(height: 20),
                  if (board.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Rien encore dans cette configuration.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else ...[
                    _Sparkline(runs: board),
                    const SizedBox(height: 16),
                    for (var i = 0; i < board.length && i < 15; i++)
                      _row(context, i + 1, board[i]),
                  ],
                  const SizedBox(height: 32),
                  _weakest(context, store),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _lifetime(BuildContext context, ProgressStore store) {
    final hours = store.totalTime.inMinutes / 60;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 32,
          runSpacing: 16,
          children: [
            StatTile(value: '${store.runs.length}', label: 'parties'),
            StatTile(value: '${store.totalAnswered}', label: 'mots validés'),
            StatTile(
              value: hours >= 1
                  ? '${hours.toStringAsFixed(1)} h'
                  : '${store.totalTime.inMinutes} min',
              label: 'temps cumulé',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int rank, RunResult run) {
    final theme = Theme.of(context);
    final date = run.finishedAt;
    final medal = switch (rank) {
      1 => highlight,
      2 => theme.colorScheme.onSurfaceVariant,
      3 => const Color(0xFFB07B4F),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: medal ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${run.correct}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${(run.accuracy * 100).round()} % · série ${run.bestStreak}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weakest(BuildContext context, ProgressStore store) {
    final theme = Theme.of(context);
    final data = AppScope.of(context).dataset;
    final weakest = store.weakest(limit: 24);
    if (weakest.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Ce qui résiste'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in weakest)
              Chip(
                label: Text(
                  '${_label(data, entry.key)} · ${entry.value.missed}',
                  style: TextStyle(
                    fontFamily: 'NotoSansJP',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                backgroundColor: failure.withValues(alpha: 0.12),
                side: BorderSide(color: failure.withValues(alpha: 0.3)),
              ),
          ],
        ),
      ],
    );
  }

  String _label(Dataset dataset, String id) {
    if (id.startsWith('k_')) return id.split('_')[1];
    final word = dataset.wordById(id);
    return word?.kana ?? id;
  }
}

/// Courbe des scores, du plus ancien au plus récent.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.runs});

  final List<RunResult> runs;

  @override
  Widget build(BuildContext context) {
    final ordered = [...runs]
      ..sort((a, b) => a.finishedAt.compareTo(b.finishedAt));
    final values = ordered.map((r) => r.correct.toDouble()).toList();
    if (values.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 72,
      child: CustomPaint(
        painter: _SparklinePainter(
          values.length > 30 ? values.sublist(values.length - 30) : values,
          Theme.of(context).colorScheme.primary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final span = (maximum - minimum).abs() < 1 ? 1.0 : maximum - minimum;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y =
          size.height - ((values[i] - minimum) / span) * (size.height - 8) - 4;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
