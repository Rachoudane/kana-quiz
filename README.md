# Kana Quiz

Entraînement chronométré à la lecture du japonais, niveau JLPT N5.
Un mot s'affiche en kana, on tape sa lecture en rōmaji. Le chrono tourne,
la traduction apparaît dès que le mot est validé, et chaque partie entre au
classement.

Application Flutter compilée pour le web, sans serveur : les données sont
embarquées, la progression reste dans le navigateur.

## Ce que ça fait

- **703 mots N5**, hiragana et katakana, dont 657 avec une phrase d'exemple
  japonais / anglais.
- **435 kanji**, dont les 79 du noyau N5, avec lectures on et kun.
- **Chrono réglable** : 1, 3, 5, 10 ou 15 minutes. Le classement sépare les
  durées et les réglages, deux parties ne se comparent que si elles sont
  comparables.
- **Correction bloquante** : sur une faute, la bonne lecture s'affiche et il
  faut la recopier pour repartir.
- **Fiche après chaque mot** : kana, kanji, lecture de référence, sens,
  exemple. Elle reste visible pendant que la partie continue.
- **Scores locaux** : records, courbe de progression, mots qui résistent.
  Export et import en JSON pour changer de machine.

## Les rōmaji

Le moteur est strict par défaut : une seule graphie est correcte, celle de la
transcription Hepburn.

| Kana | Attendu | Règle |
| --- | --- | --- |
| しゃしん | `shashin` | Hepburn : `shi`, `chi`, `tsu`, `fu`, `ji`, `sha`, `ja` |
| さんいん | `sanin` ou `san'in` | l'apostrophe de ん est facultative |
| こっち | `kotchi` | sokuon : consonne doublée, `tch` devant ち |
| とうきょう | `toukyou` | voyelle longue : on écrit ce qui est écrit en kana |
| コーヒー | `koohii` | ー répète la voyelle précédente |
| では | `dewa` | は particule |

Un réglage « toutes les graphies » accepte en plus le kunrei et les formes de
saisie IME (`syasin`, `huzi`, `kocchi`, `sannin`, `tokyo`).

## Modes

Chaque mode est une classe qui étend `QuizMode` et s'enregistre dans
`lib/src/modes/modes.dart`. Le chrono, la saisie, les scores et les
statistiques n'ont pas à changer pour en ajouter un.

- `Kana → rōmaji` — un mot en kana, on tape sa lecture.
- `Kanji → lecture` — un kanji, on tape une de ses lectures.

## Développement

```bash
flutter pub get
flutter test
flutter run -d chrome
```

Régénérer les jeux de données :

```bash
python tool/build_data.py
```

Le script télécharge ses sources, les met en cache dans `tool/.cache/` et écrit
`assets/data/vocab_n5.json` et `assets/data/kanji_n5.json`.

## Déploiement

Chaque poussée sur `main` compile le site et le publie sur GitHub Pages via
`.github/workflows/deploy.yml`.

## Sources

- Vocabulaire : [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks)
  et [jlpt-vocab-api](https://github.com/wkei/jlpt-vocab-api).
- Phrases d'exemple : [Tanaka Corpus](https://www.edrdg.org/wiki/index.php/Tanaka_Corpus)
  via Tatoeba, CC BY 2.0 FR.
- Kanji : [kanji-data](https://github.com/davidluzgouveia/kanji-data), dérivé de
  KANJIDIC2, CC BY-SA 3.0.
