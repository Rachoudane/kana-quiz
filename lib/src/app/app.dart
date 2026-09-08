import 'package:flutter/material.dart';

import '../core/data/dataset.dart';
import '../core/storage/progress_store.dart';
import '../features/home/home_page.dart';
import 'theme.dart';

/// Donne accès au stockage local et aux données depuis n'importe quel écran.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.dataset,
    required super.child,
  });

  final ProgressStore store;
  final Dataset dataset;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      store != oldWidget.store || dataset != oldWidget.dataset;
}

class KanaQuizApp extends StatelessWidget {
  const KanaQuizApp({super.key, required this.store, required this.dataset});

  final ProgressStore store;
  final Dataset dataset;

  static const themeSetting = 'theme';
  static const romajiSetting = 'romaji';

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      dataset: dataset,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final mode = switch (store.setting(themeSetting)) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: 'Kana Quiz',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: mode,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
