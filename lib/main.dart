import 'package:flutter/material.dart';

import 'src/app/app.dart';
import 'src/core/data/dataset.dart';
import 'src/core/romaji/romaji_reading.dart';
import 'src/core/storage/progress_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.open();
  RomajiReading.strictMode =
      store.setting(KanaQuizApp.romajiSetting) != 'loose';
  final dataset = await Dataset.load();
  runApp(KanaQuizApp(store: store, dataset: dataset));
}
