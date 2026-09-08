import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../core/data/dataset.dart';
import '../../core/models/models.dart';
import '../../core/romaji/romaji_reading.dart';
import '../../core/storage/progress_store.dart';
import '../../modes/modes.dart';
import '../common/widgets.dart';
import '../results/results_page.dart';
import 'quiz_controller.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.mode,
    required this.config,
    required this.durationSeconds,
    required this.dataset,
    required this.store,
  });

  final QuizMode mode;
  final Map<String, String> config;
  final int durationSeconds;
  final Dataset dataset;
  final ProgressStore store;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final QuizController _quiz;
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _quiz = QuizController(
      mode: widget.mode,
      config: widget.config,
      durationSeconds: widget.durationSeconds,
      items: widget.mode.buildItems(widget.dataset, widget.config),
      store: widget.store,
    )..addListener(_onQuizChanged);
  }

  void _onQuizChanged() {
    if (_quiz.input.isEmpty && _field.text.isNotEmpty) _field.clear();
    if (_quiz.phase == QuizPhase.finished && !_navigated) {
      _navigated = true;
      if (_quiz.result == null) {
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultsPage(quiz: _quiz)),
      );
    }
  }

  @override
  void dispose() {
    _quiz.removeListener(_onQuizChanged);
    _quiz.dispose();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _quiz,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final board = _board(context);
                final history = _history(context);
                return Column(
                  children: [
                    _topBar(context),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: wide ? 1080 : 640,
                          ),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 5, child: board),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      flex: 4,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 24),
                                        child: history,
                                      ),
                                    ),
                                  ],
                                )
                              : ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  children: [
                                    board,
                                    const SizedBox(height: 24),
                                    history,
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // --- Barre supérieure ------------------------------------------------------

  Widget _topBar(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _quiz.remainingSeconds ~/ 60;
    final seconds = _quiz.remainingSeconds % 60;
    final low = _quiz.remainingSeconds <= 30;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Arrêter',
                onPressed: _confirmQuit,
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 4),
              Text(
                '$minutes:${seconds.toString().padLeft(2, '0')}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: low ? failure : theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              _counter(Icons.check, '${_quiz.correct}', success),
              const SizedBox(width: 16),
              _counter(Icons.close, '${_quiz.mistakes}', failure),
              const SizedBox(width: 16),
              _counter(
                Icons.local_fire_department_outlined,
                '${_quiz.streak}',
                highlight,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: _quiz.progress,
          minHeight: 3,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }

  Widget _counter(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  // --- Zone de jeu -----------------------------------------------------------

  Widget _board(BuildContext context) {
    final theme = Theme.of(context);
    final item = _quiz.current;
    final correcting = _quiz.correcting;

    // Par défaut la bordure ne dit rien pendant la frappe : signaler une
    // erreur, ou confirmer qu'on est sur la bonne voie, revient à souffler la
    // réponse lettre par lettre. Seule une lecture complète et juste réagit.
    final signalErrors =
        widget.store.setting(KanaQuizApp.typingSetting) == 'errors';
    final borderColor = signalErrors && _quiz.state == AnswerState.invalid
        ? failure
        : theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.mode.instruction,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.prompt,
              key: const Key('prompt'),
              textAlign: TextAlign.center,
              style: promptStyle(
                context,
                item.prompt.characters.length > 6 ? 56 : 76,
              ),
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _field,
            focusNode: _focus,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            style: romajiStyle.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: correcting ? 'recopie la lecture' : 'rōmaji',
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: 2),
              ),
            ),
            onChanged: _quiz.onInputChanged,
            onSubmitted: (_) => _quiz.giveUp(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 96,
            child: correcting ? _correction(context, item) : _hint(context),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Entrée : afficher la réponse (compté comme une faute).',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _correction(BuildContext context, QuizItem item) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: failure.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: failure.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.allReferences.take(3).join('  /  '),
            textAlign: TextAlign.center,
            style: romajiStyle.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: failure,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.fr.isNotEmpty ? item.fr : item.en,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (item.alternates.isNotEmpty)
            Text(
              'aussi accepté : ${item.alternates.join(', ')}',
              textAlign: TextAlign.center,
              style: romajiStyle.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  // --- Historique ------------------------------------------------------------

  Widget _history(BuildContext context) {
    final theme = Theme.of(context);
    if (_quiz.history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'La traduction de chaque mot s\'affiche ici dès qu\'il est validé.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      );
    }
    final entries = _quiz.history.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          Opacity(
            opacity: i == 0 ? 1 : 0.65,
            child: ItemRevealCard(
              item: entries[i].item,
              correct: entries[i].correct,
              dense: i > 0,
            ),
          ),
      ],
    );
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arrêter la partie ?'),
        content: const Text(
          'Une partie interrompue n\'est pas enregistrée au classement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    if (quit == true) await _quiz.finish(aborted: true);
  }
}
