import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Résultat d'une partie chronométrée.
class RunResult {
  const RunResult({
    required this.modeId,
    required this.config,
    required this.durationSeconds,
    required this.finishedAt,
    required this.correct,
    required this.mistakes,
    required this.bestStreak,
    required this.missedLabels,
  });

  factory RunResult.fromJson(Map<String, dynamic> json) => RunResult(
    modeId: json['mode'] as String,
    config: (json['config'] as Map).cast<String, String>(),
    durationSeconds: json['duration'] as int,
    finishedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
    correct: json['correct'] as int,
    mistakes: json['mistakes'] as int,
    bestStreak: json['streak'] as int? ?? 0,
    missedLabels: (json['missed'] as List?)?.cast<String>() ?? const [],
  );

  final String modeId;
  final Map<String, String> config;
  final int durationSeconds;
  final DateTime finishedAt;
  final int correct;
  final int mistakes;
  final int bestStreak;
  final List<String> missedLabels;

  Map<String, dynamic> toJson() => {
    'mode': modeId,
    'config': config,
    'duration': durationSeconds,
    'at': finishedAt.millisecondsSinceEpoch,
    'correct': correct,
    'mistakes': mistakes,
    'streak': bestStreak,
    'missed': missedLabels,
  };

  int get attempts => correct + mistakes;

  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  double get perMinute =>
      durationSeconds == 0 ? 0 : correct * 60 / durationSeconds;

  /// Clé de classement : un record se compare à durée et réglages identiques.
  String get boardKey => boardKeyFor(modeId, durationSeconds, config);
}

/// Deux parties ne se comparent que si mode, durée et réglages coïncident.
String boardKeyFor(String modeId, int duration, Map<String, String> config) {
  final options = config.entries.map((e) => '${e.key}=${e.value}').toList()
    ..sort();
  return '$modeId|$duration|${options.join(',')}';
}

/// Compteur de rencontres et d'échecs pour une question donnée.
class ItemStat {
  const ItemStat(this.seen, this.missed);

  final int seen;
  final int missed;

  ItemStat bump({bool failed = false}) =>
      ItemStat(seen + 1, missed + (failed ? 1 : 0));

  double get failureRate => seen == 0 ? 0 : missed / seen;
}

/// Persistance locale : parties, records, statistiques par mot, réglages.
///
/// Tout reste dans le navigateur. L'export JSON permet de récupérer ses
/// données ailleurs sans serveur.
class ProgressStore extends ChangeNotifier {
  ProgressStore._(this._prefs) {
    _read();
  }

  static const _runsKey = 'runs';
  static const _statsKey = 'item_stats';
  static const _settingsKey = 'settings';
  static const _maxRuns = 400;

  final SharedPreferences _prefs;

  List<RunResult> _runs = [];
  Map<String, ItemStat> _stats = {};
  Map<String, String> _settings = {};

  static Future<ProgressStore> open() async =>
      ProgressStore._(await SharedPreferences.getInstance());

  List<RunResult> get runs => List.unmodifiable(_runs);

  Map<String, ItemStat> get itemStats => Map.unmodifiable(_stats);

  void _read() {
    final rawRuns = _prefs.getString(_runsKey);
    if (rawRuns != null) {
      _runs = (jsonDecode(rawRuns) as List)
          .map((e) => RunResult.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final rawStats = _prefs.getString(_statsKey);
    if (rawStats != null) {
      _stats = (jsonDecode(rawStats) as Map).map(
        (k, v) => MapEntry(k as String, ItemStat(v[0] as int, v[1] as int)),
      );
    }
    final rawSettings = _prefs.getString(_settingsKey);
    if (rawSettings != null) {
      _settings = (jsonDecode(rawSettings) as Map).cast<String, String>();
    }
  }

  Future<void> _writeRuns() async {
    await _prefs.setString(
      _runsKey,
      jsonEncode(_runs.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> _writeStats() async {
    await _prefs.setString(
      _statsKey,
      jsonEncode(_stats.map((k, v) => MapEntry(k, [v.seen, v.missed]))),
    );
  }

  Future<void> saveRun(RunResult run, Map<String, bool> itemOutcomes) async {
    _runs = [run, ..._runs].take(_maxRuns).toList();
    itemOutcomes.forEach((id, ok) {
      _stats[id] = (_stats[id] ?? const ItemStat(0, 0)).bump(failed: !ok);
    });
    await _writeRuns();
    await _writeStats();
    notifyListeners();
  }

  /// Parties d'un même classement, de la meilleure à la moins bonne.
  List<RunResult> board(String boardKey) {
    final list = _runs.where((r) => r.boardKey == boardKey).toList();
    list.sort((a, b) {
      final byScore = b.correct.compareTo(a.correct);
      if (byScore != 0) return byScore;
      return b.accuracy.compareTo(a.accuracy);
    });
    return list;
  }

  RunResult? best(String boardKey) {
    final list = board(boardKey);
    return list.isEmpty ? null : list.first;
  }

  /// Vrai si la partie est un nouveau record pour son classement.
  bool isRecord(RunResult run) {
    final previous = _runs.where(
      (r) => r.boardKey == run.boardKey && r.finishedAt != run.finishedAt,
    );
    if (previous.isEmpty) return true;
    return previous.every((r) => r.correct < run.correct);
  }

  List<RunResult> recent({int limit = 8}) => _runs.take(limit).toList();

  int get totalAnswered => _runs.fold(0, (sum, r) => sum + r.correct);

  Duration get totalTime =>
      Duration(seconds: _runs.fold(0, (sum, r) => sum + r.durationSeconds));

  /// Questions les plus souvent ratées, pour un futur mode « à revoir ».
  List<MapEntry<String, ItemStat>> weakest({int limit = 20}) {
    final list = _stats.entries.where((e) => e.value.missed > 0).toList();
    list.sort((a, b) {
      final byRate = b.value.failureRate.compareTo(a.value.failureRate);
      if (byRate != 0) return byRate;
      return b.value.missed.compareTo(a.value.missed);
    });
    return list.take(limit).toList();
  }

  String? setting(String key) => _settings[key];

  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    await _prefs.setString(_settingsKey, jsonEncode(_settings));
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'runs': _runs.map((r) => r.toJson()).toList(),
    'itemStats': _stats.map((k, v) => MapEntry(k, [v.seen, v.missed])),
    'settings': _settings,
  });

  Future<bool> importJson(String raw) async {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _runs = (json['runs'] as List)
          .map((e) => RunResult.fromJson(e as Map<String, dynamic>))
          .toList();
      _stats = (json['itemStats'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, ItemStat(v[0] as int, v[1] as int)),
      );
      _settings = (json['settings'] as Map? ?? {}).cast<String, String>();
      await _writeRuns();
      await _writeStats();
      await _prefs.setString(_settingsKey, jsonEncode(_settings));
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    _runs = [];
    _stats = {};
    await _prefs.remove(_runsKey);
    await _prefs.remove(_statsKey);
    notifyListeners();
  }
}
