# Kana Quiz

Entraînement chronométré à la lecture du japonais, niveau JLPT N5.
Un mot s'affiche en kana, on tape sa lecture en rōmaji. Le chrono tourne,
la traduction apparaît dès que le mot est validé, et chaque partie entre au
classement.

Application Flutter compilée pour le web, sans serveur : les données sont
embarquées, la progression reste dans le navigateur.

## Ce que ça fait

- **2 989 mots** : 702 au N5, 623 au N4, 1 664 au N3, dont 231 en katakana.
  Le niveau se choisit avant la partie.
- **Sens en français et en anglais**, tirés de JMdict, pas d'une traduction
  automatique.
- **2 794 mots avec phrase d'exemple**, donnée deux fois : telle qu'elle
  s'écrit, puis entièrement en kana pour pouvoir la lire.
- **1 293 kanji**, dont les 79 du N5, avec lectures on et kun.
- **Chrono réglable** : 1, 3, 5, 10 ou 15 minutes. Le classement sépare les
  durées et les réglages, deux parties ne se comparent que si elles sont
  comparables.
- **Aucun retour pendant la frappe** : rien ne bouge tant que la lecture n'est
  pas complète et juste. Signaler l'erreur à la première lettre fautive
  permettrait de retrouver la réponse à tâtons, et le score ne voudrait plus
  rien dire. Un réglage permet de le réactiver.
- **Correction bloquante** : sur une faute, la bonne lecture s'affiche et il
  faut la recopier pour repartir.
- **Fiche après chaque mot** : kana, kanji, lecture de référence, sens,
  exemple. Elle reste visible pendant que la partie continue.
- **Scores locaux** : records, courbe de progression, mots qui résistent.
  Export et import en JSON pour changer de machine.
- **Police japonaise embarquée**, réduite aux caractères utilisés : le rendu
  ne dépend pas des polices installées sur la machine.

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

Régénérer les jeux de données et la police :

```bash
pip install fugashi unidic-lite fonttools
python tool/build_data.py    # assets/data/vocab.json, assets/data/kanji.json
python tool/build_fonts.py   # assets/fonts/NotoSansJP-Regular.otf
```

Les scripts téléchargent leurs sources et les mettent en cache dans
`tool/.cache/`. `build_data.py` reconstruit la lecture kana de chaque phrase
d'exemple à partir des lectures annotées du Tanaka Corpus, complétées par
UniDic. `tool/meaning_overrides.json` corrige à la main les rares entrées que
JMdict ne couvre pas.

## Déploiement

Chaque poussée sur `main` compile le site et le publie sur GitHub Pages via
`.github/workflows/deploy.yml`.

## Sources

- Vocabulaire : [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks)
  et [jlpt-vocab-api](https://github.com/wkei/jlpt-vocab-api).
- Phrases d'exemple : [Tanaka Corpus](https://www.edrdg.org/wiki/index.php/Tanaka_Corpus)
  via Tatoeba, CC BY 2.0 FR.
- Sens français et anglais : [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html)
  via [jmdict-simplified](https://github.com/scriptin/jmdict-simplified),
  EDRDG, CC BY-SA 4.0.
- Kanji : [kanji-data](https://github.com/davidluzgouveia/kanji-data), dérivé de
  KANJIDIC2, CC BY-SA 3.0.
- Police : [Noto Sans JP](https://github.com/notofonts/noto-cjk), SIL Open Font
  License 1.1 (`assets/fonts/OFL.txt`).
