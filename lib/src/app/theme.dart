import 'package:flutter/material.dart';

/// Police japonaise embarquée (assets/fonts), suivie des polices système au
/// cas où un caractère manquerait au sous-ensemble.
const List<String> japaneseFallback = [
  'NotoSansJP',
  'Hiragino Kaku Gothic ProN',
  'Yu Gothic',
  'Meiryo',
  'sans-serif',
];

const Color _seed = Color(0xFF5B8DEF);
const Color success = Color(0xFF3FB984);
const Color failure = Color(0xFFE0575B);
const Color highlight = Color(0xFFE8B84B);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF14171D) : const Color(0xFFF7F8FA);
  final card = isDark ? const Color(0xFF1C2027) : Colors.white;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme.copyWith(surface: surface),
    scaffoldBackgroundColor: surface,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: japaneseFallback),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}

/// Style des kana et kanji affichés en grand.
TextStyle promptStyle(BuildContext context, double size) => TextStyle(
      fontFamily: 'NotoSansJP',
      fontSize: size,
      height: 1.1,
      letterSpacing: 2,
      color: Theme.of(context).colorScheme.onSurface,
    );

/// Style des textes japonais courants (phrases d'exemple, lectures).
TextStyle japaneseStyle(TextStyle? base) =>
    (base ?? const TextStyle()).copyWith(fontFamily: 'NotoSansJP');

/// Style monospace pour les rōmaji, pour que les graphies s'alignent.
const TextStyle romajiStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Consolas', 'Menlo', 'Courier New', 'monospace'],
  letterSpacing: 0.5,
);
