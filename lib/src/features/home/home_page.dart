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

  /// La durée se retient par mode : chacun garde la sienne, et celle de
  /// départ est celle que le mode juge cohérente avec ce qu'il fait.
  late final Map<String, int> _durations = {
    for (final mode in quizModes) mode.id: mode.preferredDuration,
  };

  Map<String, String> get _config => _configs[_mode.id]!;

  int get _duration => _durations[_mode.id]!;

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
                    _modeGrid(context),
                    const SizedBox(height: 6),
                    Text(
                      '${_mode.subtitle} ${_mode.instruction}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
                      onSelected: (d) =>
                          setState(() => _durations[_mode.id] = d),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _start,
                      child: Text('Commencer · ${formatDuration(_duration)}'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _recordLine(best),
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

  /// Les modes en grille plutôt qu'empilés.
  ///
  /// À six modes, une carte pleine largeur par mode repoussait le bouton
  /// « Commencer » hors de l'écran. Ne reste sur la tuile que ce qui sert à
  /// choisir ; la phrase du mode retenu s'affiche sous la grille.
  Widget _modeGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final mode in quizModes)
              SizedBox(width: width, child: _modeTile(mode)),
          ],
        );
      },
    );
  }

  Widget _modeTile(QuizMode mode) {
    final theme = Theme.of(context);
    final selected = mode.id == _mode.id;
    return Card(
      margin: EdgeInsets.zero,
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _mode = mode),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                mode.emoji,
                style: promptStyle(context, 24).copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mode.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ce que vaut le record de cette configuration.
  ///
  /// Sans chrono, le nombre de bonnes réponses ne mesure que le temps passé :
  /// c'est la précision qui classe, au-delà d'un minimum de réponses.
  String _recordLine(RunResult? best) {
    if (_duration == openEnded) {
      if (best == null) {
        return 'Aucune partie classée ici : il en faut au moins '
            '${RunResult.minRankedAnswers} réponses.';
      }
      return 'Meilleure précision ici : '
          '${(best.accuracy * 100).round()} % sur ${best.attempts} réponses.';
    }
    if (best == null) {
      return 'Aucune partie dans cette configuration pour l\'instant.';
    }
    return 'Record ici : ${best.correct} bonnes réponses '
        '(${(best.accuracy * 100).round()} % de précision).';
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
