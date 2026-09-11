import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/storage/progress_store.dart';
import '../../modes/modes.dart';
import '../common/widgets.dart';
import '../quiz/quiz_page.dart';
import '../scoreboard/scoreboard_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  QuizMode _mode = quizModes.first;
  late final Map<String, Map<String, String>> _configs = {
    for (final mode in quizModes) mode.id: {...mode.defaultConfig},
  };
  int _duration = defaultDuration;

  Map<String, String> get _config => _configs[_mode.id]!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.of(context);
    final store = scope.store;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final key = boardKeyFor(_mode.id, _duration, _config);
                final best = store.best(key);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                  children: [
                    _header(context),
                    const SizedBox(height: 32),
                    const SectionTitle('Mode'),
                    for (final mode in quizModes) _modeCard(mode),
                    const SizedBox(height: 24),
                    for (final option in _mode.options) ...[
                      SectionTitle(option.label),
                      ChoiceRow<ModeChoice>(
                        values: option.choices,
                        selected: option.choices.firstWhere(
                          (c) => c.id == _config[option.id],
                          orElse: () => option.choices.first,
                        ),
                        labelOf: (c) => c.label,
                        onSelected: (c) =>
                            setState(() => _config[option.id] = c.id),
                      ),
                      const SizedBox(height: 20),
                    ],
                    const SectionTitle('Durée'),
                    ChoiceRow<int>(
                      values: runDurations,
                      selected: _duration,
                      labelOf: formatDuration,
                      onSelected: (d) => setState(() => _duration = d),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _start,
                      child: Text('Commencer · ${formatDuration(_duration)}'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      best == null
                          ? 'Aucune partie dans cette configuration pour l\'instant.'
                          : 'Record ici : ${best.correct} bonnes réponses '
                                '(${(best.accuracy * 100).round()} % de précision).',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (store.runs.isNotEmpty) _recent(context, store),
                    _dataFootprint(context),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kana Quiz',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lecture chronométrée du japonais, niveau N5.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Scores',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ScoreboardPage())),
          icon: const Icon(Icons.leaderboard_outlined),
        ),
        IconButton(
          tooltip: 'Réglages',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          icon: const Icon(Icons.tune),
        ),
      ],
    );
  }

  Widget _modeCard(QuizMode mode) {
    final theme = Theme.of(context);
    final selected = mode.id == _mode.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _mode = mode),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  mode.emoji,
                  style: promptStyle(context, 30).copyWith(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recent(BuildContext context, ProgressStore store) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Dernières parties',
          trailing: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ScoreboardPage())),
            child: const Text('Tout voir'),
          ),
        ),
        for (final run in store.recent(limit: 4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${modeById(run.modeId).title} · '
                    '${formatDuration(run.durationSeconds)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${run.correct}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(run.accuracy * 100).round()} %',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
      ],
    );
  }

  ModeContext _context() {
    final scope = AppScope.of(context);
    return ModeContext(
      data: scope.dataset,
      config: _config,
      stats: scope.store.itemStats,
    );
  }

  Widget _dataFootprint(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _mode.summary(_context()),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    );
  }

  void _start() {
    final scope = AppScope.of(context);
    // Un mode peut n'avoir rien à proposer : les mots qui résistent tant
    // qu'aucune partie n'a été jouée. Mieux vaut le dire que lancer le chrono
    // sur une liste vide.
    final reason = _mode.emptyReason(_context());
    if (reason != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          mode: _mode,
          config: {..._config},
          durationSeconds: _duration,
          dataset: scope.dataset,
          store: scope.store,
        ),
      ),
    );
  }
}
