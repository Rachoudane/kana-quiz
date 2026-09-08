import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/storage/progress_store.dart';
import '../../modes/modes.dart';
import '../common/widgets.dart';
import '../quiz/quiz_controller.dart';
import '../quiz/quiz_page.dart';
import '../scoreboard/scoreboard_page.dart';

class ResultsPage extends StatelessWidget {
  ResultsPage({super.key, required QuizController quiz})
      : mode = quiz.mode,
        config = quiz.config,
        durationSeconds = quiz.durationSeconds,
        result = quiz.result!,
        isRecord = quiz.isRecord,
        entries = List.unmodifiable(quiz.history);

  final QuizMode mode;
  final Map<String, String> config;
  final int durationSeconds;
  final RunResult result;
  final bool isRecord;
  final List<AnsweredEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missed = entries.where((e) => !e.correct).toList();
    final store = AppScope.of(context).store;
    final board = store.board(result.boardKey);
    final rank = board.indexWhere((r) => r.finishedAt == result.finishedAt) + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('${mode.title} · ${formatDuration(durationSeconds)}'),
        actions: [
          IconButton(
            tooltip: 'Scores',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScoreboardPage()),
            ),
            icon: const Icon(Icons.leaderboard_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: [
              if (isRecord)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: highlight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: highlight.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_outlined,
                          color: highlight, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nouveau record dans cette configuration.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result.correct}',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'bonnes réponses en ${formatDuration(durationSeconds)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 32,
                        runSpacing: 16,
                        children: [
                          StatTile(
                            value: '${(result.accuracy * 100).round()} %',
                            label: 'précision',
                          ),
                          StatTile(
                            value: result.perMinute.toStringAsFixed(1),
                            label: 'par minute',
                          ),
                          StatTile(
                            value: '${result.bestStreak}',
                            label: 'meilleure série',
                            color: highlight,
                          ),
                          StatTile(
                            value: '${result.mistakes}',
                            label: 'fautes',
                            color: result.mistakes > 0 ? failure : null,
                          ),
                          if (rank > 0)
                            StatTile(value: '#$rank', label: 'classement perso'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _replay(context),
                      child: const Text('Rejouer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: const Text('Accueil'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (missed.isNotEmpty) ...[
                SectionTitle('À revoir (${missed.length})'),
                for (final entry in missed)
                  ItemRevealCard(item: entry.item, correct: false),
                const SizedBox(height: 24),
              ],
              SectionTitle('Tous les mots de la partie (${entries.length})'),
              for (final entry in entries)
                ItemRevealCard(
                  item: entry.item,
                  correct: entry.correct,
                  dense: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _replay(BuildContext context) {
    final scope = AppScope.of(context);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          mode: mode,
          config: config,
          durationSeconds: durationSeconds,
          dataset: scope.dataset,
          store: scope.store,
        ),
      ),
    );
  }
}
