/// Table de correspondance kana → rōmaji.
///
/// [kanaHepburn] donne la graphie de référence, une seule par mora : c'est la
/// bonne réponse et c'est ce qui s'affiche après validation.
/// [kanaVariants] liste les graphies d'autres systèmes (kunrei, saisie IME).
/// Elles ne sont acceptées qu'en mode tolérant.
const Map<String, String> kanaHepburn = {
  // --- Digrammes (yōon) -----------------------------------------------------
  'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
  'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
  'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
  'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
  'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
  'ぢゃ': 'ja', 'ぢゅ': 'ju', 'ぢょ': 'jo',
  'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
  'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
  'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
  'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
  'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
  'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',

  // --- Digrammes des emprunts (surtout en katakana) -------------------------
  'いぇ': 'ye',
  'うぃ': 'wi', 'うぇ': 'we', 'うぉ': 'wo',
  'ゔぁ': 'va', 'ゔぃ': 'vi', 'ゔぇ': 've', 'ゔぉ': 'vo',
  'しぇ': 'she', 'じぇ': 'je', 'ちぇ': 'che',
  'つぁ': 'tsa', 'つぃ': 'tsi', 'つぇ': 'tse', 'つぉ': 'tso',
  'てぃ': 'ti', 'てゅ': 'tyu', 'とぅ': 'tu',
  'でぃ': 'di', 'でゅ': 'dyu', 'どぅ': 'du',
  'ふぁ': 'fa', 'ふぃ': 'fi', 'ふぇ': 'fe', 'ふぉ': 'fo', 'ふゅ': 'fyu',
  'くぁ': 'kwa', 'ぐぁ': 'gwa',

  // --- Kana simples ---------------------------------------------------------
  'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
  'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
  'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
  'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
  'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
  'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
  'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
  'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
  'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
  'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
  'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
  'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
  'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
  'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
  'わ': 'wa', 'ゐ': 'i', 'ゑ': 'e', 'を': 'o',
  'ゔ': 'vu',

  // --- Petits kana isolés ---------------------------------------------------
  'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o',
  'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo', 'ゎ': 'wa',
};

/// Graphies d'autres systèmes, acceptées seulement en mode tolérant.
const Map<String, List<String>> kanaVariants = {
  'しゃ': ['sya'],
  'しゅ': ['syu'],
  'しょ': ['syo'],
  'じゃ': ['zya', 'jya'],
  'じゅ': ['zyu', 'jyu'],
  'じょ': ['zyo', 'jyo'],
  'ちゃ': ['tya', 'cya'],
  'ちゅ': ['tyu', 'cyu'],
  'ちょ': ['tyo', 'cyo'],
  'ぢゃ': ['dya'],
  'ぢゅ': ['dyu'],
  'ぢょ': ['dyo'],
  'てぃ': ['thi'],
  'でぃ': ['dhi'],
  'し': ['si', 'ci'],
  'じ': ['zi'],
  'ち': ['ti'],
  'つ': ['tu'],
  'ぢ': ['di', 'zi'],
  'づ': ['du'],
  'ふ': ['hu'],
  'を': ['wo'],
  'ゔ': ['bu'],
};

/// Lectures où un は final se prononce « wa ».
const Set<String> particleWaReadings = {'は', 'では', 'それでは'};

const String vowels = 'aiueo';

/// Sokuon : petite tsu.
const String sokuon = 'っ';

/// Marque d'allongement des katakana.
const String prolongedMark = 'ー';

/// Convertit les katakana en hiragana ; le reste est laissé intact.
String toHiragana(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    // Plage katakana ァ (0x30A1) .. ヶ (0x30F6), décalage fixe vers l'hiragana.
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Vrai si la chaîne contient au moins un katakana.
bool hasKatakana(String input) =>
    input.runes.any((r) => r >= 0x30A0 && r <= 0x30FF && r != 0x30FB);
