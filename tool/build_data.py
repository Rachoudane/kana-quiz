#!/usr/bin/env python3
"""Génère les jeux de données JSON embarqués dans l'application.

Sources, téléchargées puis mises en cache dans tool/.cache/ :
  - open-anki-jlpt-decks  : listes de vocabulaire JLPT N5, N4, N3
  - jlpt-vocab-api        : seconde liste N5, pour compléter la première
  - JMdict (simplifié)    : sens français et anglais, dictionnaire de référence
  - JMdict (XML, EDRDG)   : bandes de fréquence nf01 à nf48
  - Tatoeba               : phrases d'exemple, leurs traductions et leurs
                            lectures annotées (successeur vivant du corpus
                            Tanaka, régénéré chaque semaine)
  - KANJIDIC2 (EDRDG)     : lectures et sens des kanji, anglais et français
  - kanji-data            : niveau JLPT des kanji, que KANJIDIC2 ne donne pas
                            sur l'échelle N5-N1

Les lectures kana des phrases d'exemple sont reconstruites à partir des
lectures annotées de Tatoeba, complétées par UniDic via fugashi.

Prérequis : pip install fugashi unidic-lite
Usage     : python tool/build_data.py
"""

import bz2
import csv
import gzip
import io
import json
import os
import re
import sys
import tarfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tool", ".cache")
OUT = os.path.join(ROOT, "assets", "data")
OVERRIDES = os.path.join(ROOT, "tool", "meaning_overrides.json")
KANJI_OVERRIDES = os.path.join(ROOT, "tool", "kanji_fr_overrides.json")
SENSE_OVERRIDES = os.path.join(ROOT, "tool", "sense_fr_overrides.json")

ANKI = "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/{}.csv"
VOCAB_API = "https://jlpt-vocab-api.vercel.app/api/words?level=5&limit=100&offset={}"
KANJI_DATA = "https://raw.githubusercontent.com/davidluzgouveia/kanji-data/master/kanji.json"
KANJIDIC2 = "http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz"
JMDICT_RELEASE = "https://api.github.com/repos/scriptin/jmdict-simplified/releases/latest"
JMDICT_XML = "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
TATOEBA = "https://downloads.tatoeba.org/exports/"
TATOEBA_INDICES = TATOEBA + "jpn_indices.tar.bz2"
TATOEBA_LINKS = TATOEBA + "per_language/jpn/jpn-%s_links.tsv.bz2"
TATOEBA_TEXTS = TATOEBA + "per_language/%(lang)s/%(lang)s_sentences.tsv.bz2"

# Langues de traduction des exemples, par ordre de préférence. L'application
# est en français : une phrase traduite en français vaut mieux qu'en anglais.
EXAMPLE_LANGS = ["fra", "eng"]

LEVELS = [5, 4, 3]

# Sens montrés en plus du principal. Au-delà de trois lignes la fiche devient
# une entrée de dictionnaire, et on ne la lit plus entre deux mots.
OTHER_SENSES = 2

HIRAGANA = "぀-ゟ"
KATAKANA = "゠-ヿー"
KANA_RE = re.compile("^[" + HIRAGANA + KATAKANA + "]+$")
HAS_KATAKANA = re.compile("[" + KATAKANA + "]")
HAS_KANJI = re.compile("[一-龯々]")
PARENS_RE = re.compile("[（(][^)）]*[）)]")


def fetch(url, name, binary=False):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        sys.stderr.write("download " + url + "\n")
        req = urllib.request.Request(url, headers={"User-Agent": "kana-quiz-build"})
        with urllib.request.urlopen(req, timeout=600) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, "rb") as f:
        raw = f.read()
    return raw if binary else raw.decode("utf-8")


def kata_to_hira(text):
    return "".join(
        chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text
    )


# ---------------------------------------------------------------------------
# Listes de vocabulaire
# ---------------------------------------------------------------------------

def split_variants(field):
    """« いい; よい » -> ['いい', 'よい'] ; retire ～ et les parenthèses."""
    out = []
    for part in re.split("[;；/]", field or ""):
        part = part.strip().replace("～", "").replace("〜", "").replace("~", "")
        part = PARENS_RE.sub("", part).strip()
        if part:
            out.append(part)
    return out


def clean_meaning(meaning):
    return re.sub(r"\s+", " ", (meaning or "").strip())


def load_anki(level):
    rows = list(csv.DictReader(io.StringIO(fetch(ANKI.format("n%d" % level), "n%d.csv" % level))))
    entries = []
    for row in rows:
        exprs = split_variants(row["expression"])
        readings = split_variants(row["reading"])
        meaning = clean_meaning(row["meaning"])
        if not readings:
            readings = [e for e in exprs if KANA_RE.match(e)]
        for i, reading in enumerate(readings):
            if not KANA_RE.match(reading):
                continue
            expr = exprs[i] if i < len(exprs) else (exprs[0] if exprs else reading)
            entries.append(
                {"kana": reading, "word": expr, "meaning": meaning, "level": level}
            )
    return entries


def load_api():
    entries = []
    offset = 0
    while True:
        try:
            page = json.loads(fetch(VOCAB_API.format(offset), "api_%d.json" % offset))
        except Exception as exc:  # source secondaire : on continue sans elle
            sys.stderr.write("jlpt-vocab-api indisponible (%s)\n" % exc)
            break
        for w in page.get("words", []):
            reading = (w.get("furigana") or w.get("word") or "").strip()
            word = (w.get("word") or "").strip()
            if not KANA_RE.match(reading):
                continue
            entries.append({
                "kana": reading,
                "word": word or reading,
                "meaning": clean_meaning(w.get("meaning")),
                "level": 5,
            })
        offset += 100
        if offset >= page.get("total", 0):
            break
    return entries


# ---------------------------------------------------------------------------
# JMdict : sens français et anglais
# ---------------------------------------------------------------------------

SKIP_MISC = {"arch", "obs", "obsc", "rare", "vulg", "derog", "sl"}

# Graphies que JMdict signale comme sorties de l'usage : rare, recherchée,
# ancienne, irrégulière.
RARE_KANJI = {"rK", "sK", "oK", "iK"}


def jmdict_url(lang):
    meta = json.loads(fetch(JMDICT_RELEASE, "jmdict_release.json"))
    tag = meta["tag_name"]
    name = "jmdict-%s-%s.json.tgz" % (lang, tag)
    for asset in meta["assets"]:
        if asset["name"] == name:
            return asset["browser_download_url"], name
    raise RuntimeError("asset JMdict introuvable : " + name)


def load_jmdict(lang):
    """Index (écriture, lecture) -> identifiants, lecture -> identifiants, et
    identifiant -> (courant, sens).

    Les sens gardent leur position d'origine, y compris ceux qui sont écartés,
    remplacés par une liste vide. C'est cette position qui permet ensuite de
    lire le français au même sens que l'anglais.
    """
    url, name = jmdict_url(lang)
    raw = fetch(url, name, binary=True)
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tar:
        member = next(m for m in tar.getmembers() if m.name.endswith(".json"))
        data = json.load(tar.extractfile(member))

    entries = {}
    by_pair = {}
    by_kana = {}
    for entry in data["words"]:
        senses = []
        for sense in entry["sense"]:
            if set(sense.get("misc") or []) & SKIP_MISC:
                senses.append([])
                continue
            senses.append([g["text"] for g in sense["gloss"]])
        if not any(senses):
            continue
        common = any(k.get("common") for k in entry["kana"]) or any(
            k.get("common") for k in entry["kanji"]
        )
        kanas = [k["text"] for k in entry["kana"]]
        # La lecture garde son rang, son drapeau « courante » et la graphie à
        # laquelle elle se limite. `appliesToKanji` vaut ["*"] quand elle vaut
        # pour toutes : le prendre au pied de la lettre n'en laissait aucune.
        spoken = [
            (
                k["text"],
                bool(k.get("common")),
                tuple(t for t in (k.get("appliesToKanji") or ()) if t != "*"),
            )
            for k in entry["kana"]
        ]
        kanjis = [k["text"] for k in entry["kanji"]]
        # Les graphies de l'entrée servent à écarter, plus bas, les écritures
        # d'un autre mot que les listes source ont rangées sous la même
        # lecture : 刷る n'est pas une autre façon d'écrire する. Le drapeau
        # dit si la graphie s'écrit encore : 為る est une graphie de する comme
        # de なる, mais plus personne ne l'écrit, et chercher des exemples
        # dessus mélangeait les deux verbes.
        # Le second drapeau dit si l'okurigana est régulier : 先き est une
        # écriture courante de さき, mais son okurigana est irrégulier (`io`)
        # et on ne peut rien en déduire — il ramenait le radical de さき à さ,
        # que contient n'importe quelle phrase disant なさい.
        writings = [
            (
                k["text"],
                not (set(k.get("tags") or []) & RARE_KANJI),
                "io" not in (k.get("tags") or []),
            )
            for k in entry["kanji"]
        ]
        # Les lectures servent à lire les mots que le corpus annote sans
        # donner leur lecture, voir `reading_map`.
        entries[entry["id"]] = (common, senses, writings, spoken)
        for kana in kanas:
            by_kana.setdefault(kana, []).append(entry["id"])
            for kanji in kanjis:
                by_pair.setdefault((kanji, kana), []).append(entry["id"])
    return entries, by_pair, by_kana


def writings_of(index, entry_id):
    """Graphies : (texte, encore en usage, okurigana régulier). Vide sinon."""
    record = index[0].get(entry_id)
    return record[2] if record else []


def reading_map(index):
    """Graphie -> sa lecture, quand elle n'en a qu'une.

    Sert à lire les mots que le corpus annote sans donner leur lecture. Une
    lecture courante l'emporte sur une lecture rare, ce qui suffit à trancher
    お母さん entre おかあさん et おかーさん. Ce qui reste ambigu est laissé de
    côté : deviner la lecture de 時 revient à choisir entre とき et じ, et le
    corpus donne justement la sienne quand elle compte.

    La restriction de graphie est respectée : une lecture qui ne vaut que pour
    une écriture ne déteint pas sur les autres.
    """
    out = {}
    for _entry_id, record in index[0].items():
        for writing, _usual, _regular in record[2]:
            ranked = out.setdefault(writing, [])
            for rank, (text, common, applies) in enumerate(record[3]):
                if applies and writing not in applies:
                    continue
                ranked.append((0 if common else 1, rank, text))
    resolved = {}
    for writing, ranked in out.items():
        texts = [text for _c, _r, text in sorted(set(ranked))]
        common = [
            text for level, _r, text in sorted(set(ranked)) if level == 0
        ]
        # Une graphie qui garde plusieurs lectures plausibles n'est pas
        # comblée : 時 vaut とき et じ, et 夜の八時 se lisait よるのはちとき.
        choice = common or texts
        if len(set(choice)) == 1:
            resolved[writing] = choice[0]
    return resolved


STOP_WORDS = {
    "a", "an", "the", "to", "of", "in", "on", "for", "with", "and", "or", "be",
    "is", "as", "at", "by", "from", "one", "s", "e", "g", "etc", "esp", "used",
    "something", "someone", "oneself", "that", "this", "it", "its", "not",
}


def words_in(text):
    """Mots significatifs d'une glose, pour comparer deux définitions."""
    return {
        w for w in re.split(r"[^a-z]+", (text or "").lower())
        if w and w not in STOP_WORDS
    }


def sense_overlap(record, meaning):
    """Nombre de mots communs entre le sens de la liste source et l'entrée.

    Une lecture écrite en kana n'a pas d'écriture pour désigner son entrée :
    はし ou よい renvoient une demi-douzaine d'homonymes et c'est le sens de la
    liste qui tranche, sinon よい part sur 宵, « le soir ».
    """
    if not meaning:
        return 0
    wanted = words_in(meaning)
    if not wanted:
        return 0
    best = 0
    for sense in record[1]:
        for gloss in sense:
            best = max(best, len(wanted & words_in(gloss)))
    return best


def pick_entry(index, word, kana, preferred=None, meaning=None):
    """Identifiant JMdict du mot, et vrai si on est passé par le radical する.

    Le choix se fait sur l'index anglais, le seul complet : le français n'a
    qu'une entrée sur quatorze et ne peut pas trancher. Mais une entrée que le
    français connaît passe devant, sinon いくら part sur イクラ, absent du
    français, et le mot est perdu faute de traduction. À égalité, c'est
    l'entrée qui dit la même chose que la liste source qui l'emporte.
    """
    entries, by_pair, by_kana = index
    ids = by_pair.get((word, kana)) or by_kana.get(kana)
    suru = False
    if not ids and kana.endswith("する"):
        stem = kana[:-2]
        ids = by_pair.get((word, stem)) or by_kana.get(stem)
        suru = bool(ids)
    if not ids:
        return None, False
    known = preferred or {}
    ranked = sorted(
        ids,
        key=lambda i: (
            i not in known,
            -sense_overlap(entries[i], meaning),
            not entries[i][0],
        ),
    )
    return ranked[0], suru


def glosses_for(index, entry_id, position=None, limit=3):
    """Gloses d'une entrée, et la position du sens retenu.

    `position` demande un sens précis, celui déjà retenu dans l'autre langue.
    Un sens non traduit fait retomber sur le premier sens disponible : mieux
    vaut un décalage de sens qu'un mot sans traduction.
    """
    entries = index[0]
    record = entries.get(entry_id)
    if not record:
        return None, None
    senses = record[1]
    order = [] if position is None else [position]
    order += [i for i in range(len(senses)) if i != position]
    for i in order:
        if not 0 <= i < len(senses):
            continue
        out = []
        for gloss in senses[i]:
            gloss = gloss.strip()
            if gloss and gloss not in out:
                out.append(gloss)
        if out:
            return ", ".join(out[:limit]), i
    return None, None


def senses_for(index, entry_id, limit=3):
    """Tous les sens d'une entrée : [(position, gloses)], les vides écartés.

    Même découpage que `glosses_for`, mais sans en choisir un. La position est
    conservée : c'est elle qui apparie le sens anglais et le sens français.
    """
    record = index[0].get(entry_id)
    if not record:
        return []
    out = []
    for i, sense in enumerate(record[1]):
        texts = []
        for gloss in sense:
            gloss = gloss.strip()
            if gloss and gloss not in texts:
                texts.append(gloss)
        if texts:
            out.append((i, ", ".join(texts[:limit])))
    return out


# ---------------------------------------------------------------------------
# Phrases d'exemple
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r"^([^()\[\]{}~|]+)(?:\(([^)]*)\))?(?:\[(\d+)\])?(?:\{([^}]*)\})?")

# Tatoeba est un corpus généraliste, pas un manuel : une poignée de phrases
# n'ont rien à faire dans une appli qu'on ouvre pour réviser ses kana. Liste
# tenue à la main, à compléter au fil des rencontres.
NOT_SPOKEN = re.compile(r"[0-9０-９A-Za-zＡ-Ｚａ-ｚ]")

SKIP_SENTENCES = {
    "先生、アソコがかゆいんです。",
}


def surface_stem(head, reading):
    """Lecture du lemme privée de l'okurigana : 会う(あう) donne あ."""
    i = 0
    while i < len(head) and i < len(reading) and head[-1 - i] == reading[-1 - i]:
        i += 1
    return reading[: len(reading) - i]


def surface_reading(head, reading, surface):
    """Lecture de la forme fléchie, déduite de la lecture du lemme.

    忙しい(いそがしい) avec la forme 忙しかった donne いそがしかった : on isole
    l'okurigana commun au lemme et à sa lecture, le reste suit la forme.
    """
    i = 0
    while i < len(head) and i < len(reading) and head[-1 - i] == reading[-1 - i]:
        i += 1
    stem_head = head[: len(head) - i]
    stem_reading = reading[: len(reading) - i]
    if surface == head or surface == stem_head:
        # L'okurigana peut ne pas être écrit sans cesser d'être prononcé :
        # 祭り(まつり) s'écrit aussi 祭, et se lit toujours まつり. Le rendre
        # comme le radical donnait まつ.
        return reading
    if surface.startswith(stem_head):
        return stem_reading + surface[len(stem_head):]
    return None


def tatoeba_texts(lang):
    """Phrases d'une langue de Tatoeba : identifiant -> texte."""
    raw = bz2.decompress(
        fetch(TATOEBA_TEXTS % {"lang": lang},
              "tatoeba_%s_sentences.tsv.bz2" % lang, binary=True)
    )
    out = {}
    for line in raw.decode("utf-8", "replace").splitlines():
        parts = line.split("	")
        if len(parts) >= 3 and parts[2].strip():
            out[parts[0]] = parts[2].strip()
    return out


def tatoeba_links(lang):
    """Traductions d'une phrase japonaise : identifiant -> identifiants."""
    raw = bz2.decompress(
        fetch(TATOEBA_LINKS % lang, "tatoeba_jpn-%s_links.tsv.bz2" % lang,
              binary=True)
    )
    out = {}
    for line in raw.decode("utf-8", "replace").splitlines():
        parts = line.split("	")
        if len(parts) >= 2:
            out.setdefault(parts[0], []).append(parts[1])
    return out


def tatoeba_indices():
    """Lectures annotées des phrases japonaises : identifiant -> ligne B.

    C'est l'annotation du corpus Tanaka, que Tatoeba régénère : chaque mot y
    est donné avec sa lecture, son numéro de sens et sa forme fléchie.
    """
    raw = fetch(TATOEBA_INDICES, "jpn_indices.tar.bz2", binary=True)
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:bz2") as tar:
        member = next(m for m in tar.getmembers() if m.name.endswith(".csv"))
        text = tar.extractfile(member).read().decode("utf-8", "replace")
    out = {}
    for line in text.splitlines():
        parts = line.split("	")
        if len(parts) >= 3 and parts[2].strip():
            out[parts[0]] = parts[2]
    return out


def load_examples(spoken):
    """Phrases (japonais, anglais, français) + index lemme -> phrases.

    Chaque entrée de l'index retient le numéro de sens annoté par le corpus,
    `する[1]` contre `する[2]` : sans lui, une phrase illustre un homonyme.

    Chaque phrase retient aussi la lecture de ses mots, pour la ligne en kana.
    Le corpus ne la donne que s'il doit lever une ambiguïté, et `spoken` — les
    lectures de JMdict par graphie — comble le reste : sans lui お母さん était
    découpé en お + 母 + さん et se lisait おははさん.

    Une phrase sans aucune traduction ne sert à rien et n'est pas gardée.
    """
    japanese = tatoeba_texts("jpn")
    indices = tatoeba_indices()
    translations = {}
    for lang in EXAMPLE_LANGS:
        texts = tatoeba_texts(lang)
        for source, targets in tatoeba_links(lang).items():
            if source not in indices:
                continue
            for target in targets:
                text = texts.get(target)
                if text:
                    translations.setdefault(source, {})[lang] = text
                    break

    sentences = []   # (japonais, anglais, français, {surface: lecture})
    index = {}
    derived = set()  # graphies dont la lecture est déduite, donc à confirmer
    # Les identifiants sont triés : le fichier de Tatoeba n'est pas garanti
    # dans l'ordre, et deux constructions doivent donner le même jeu.
    for sentence_id in sorted(indices, key=int):
        jp = japanese.get(sentence_id)
        if not jp or not 6 <= len(jp) <= 46 or jp in SKIP_SENTENCES:
            continue
        pair = translations.get(sentence_id)
        if not pair:
            continue
        readings = {}
        lemmas = []
        for token in indices[sentence_id].split():
            m = TOKEN_RE.match(token)
            if not m:
                continue
            head, reading, sense, surface = m.groups()
            sense = int(sense) if sense else None
            # Le corpus annote parfois un mot que la phrase ne contient pas :
            # あなたの名前は何ですか。 a été raccourci en 名前は何ですか。 et
            # garde son 貴方(あなた), qui remplissait la fiche あなた avec une
            # phrase où le mot n'apparaît plus.
            if (surface or head) not in jp:
                continue
            # Le champ entre parenthèses n'est pas toujours une lecture : le
            # corpus y met parfois l'identifiant JMdict du mot, 前(#1392580).
            if reading and reading.startswith("#"):
                reading = None
            lemmas.append((head, sense, head, reading))
            if reading:
                lemmas.append((reading, sense, head, reading))
            if HAS_KANJI.search(head):
                # La lecture du corpus d'abord ; à défaut celle de JMdict, la
                # plus probable pour cette graphie. 火曜日 n'est jamais annoté
                # et se lisait かようひ, le rendaku perdu au découpage.
                said = reading or spoken.get(head)
                shown = surface or head
                kana = None
                if said and shown != head:
                    kana = surface_reading(head, said, shown)
                    if kana:
                        derived.add(shown)
                elif said:
                    kana = said
                if not kana:
                    # La forme écrite dans la phrase a parfois sa propre
                    # entrée : le corpus annote 貸間 là où la phrase écrit
                    # 貸し間, que l'okurigana du lemme ne sait pas dériver.
                    kana = spoken.get(shown)
                if kana and not HAS_KANJI.search(kana):
                    readings[shown] = kana
        idx = len(sentences)
        sentences.append((jp, pair.get("eng", ""), pair.get("fra", ""), readings))
        for lemma, sense, head, reading in set(lemmas):
            index.setdefault(lemma, []).append((idx, sense, head, reading))
    return sentences, index, derived


class KanaLine:
    """Transcrit une phrase japonaise en kana, sans kanji."""

    def __init__(self, spoken=None, derived=()):
        import fugashi

        self.tagger = fugashi.Tagger()
        self.spoken = spoken or {}
        self.cache = {}
        # Les graphies dont la lecture a été déduite d'un lemme, et non lue
        # telle quelle : ce sont les seules à faire confirmer.
        self.derived = set(derived)

    def build(self, sentence, annotated):
        """Ligne en kana de la phrase, ou None si une lecture manque.

        Les mots annotés par le corpus sont posés d'abord, du plus long au
        plus court, et fugashi ne transcrit que ce qu'ils laissent. L'ordre
        compte : appliqué après le découpage, お母さん ne correspondait à
        aucun jeton — fugashi en fait お + 母 + さん — et la ligne annonçait
        おははさん. Même chose pour 火曜日, coupé en 火曜 + 日, qui perdait son
        rendaku et se lisait かようひ.
        """
        parts = self.parts(sentence, annotated)
        if parts is None:
            return None
        return "".join(reading for _text, reading in parts)

    def parts(self, sentence, annotated):
        """La phrase découpée en (écrit, lu), ou None si une lecture manque.

        L'alignement sert à vérifier la lecture d'un mot précis : la fiche 九
        « く » était illustrée par 九引く六, où 九 se lit きゅう.
        """
        key = (sentence, tuple(sorted(annotated.items())))
        if key in self.cache:
            return self.cache[key]
        derived = {
            reading for text, reading in annotated.items()
            if text in self.derived
        }
        spans = sorted(
            (text for text in annotated if text), key=len, reverse=True
        )
        out = []
        gap = []

        def flush():
            if not gap:
                return True
            text = "".join(gap)
            del gap[:]
            for word in self.tagger(text):
                if not HAS_KANJI.search(word.surface):
                    out.append((word.surface, word.surface))
                    continue
                reading = getattr(word.feature, "kana", None) or getattr(
                    word.feature, "pron", None
                )
                if not reading:
                    return False
                out.append((word.surface, kata_to_hira(reading)))
            return True

        i = 0
        while i < len(sentence):
            span, reading = self.longest_at(sentence, i, spans, annotated)
            if span:
                if not flush():
                    self.cache[key] = None
                    return None
                out.append((span, reading))
                i += len(span)
            else:
                gap.append(sentence[i])
                i += 1
        if not flush():
            self.cache[key] = None
            return None
        line = "".join(reading for _text, reading in out)
        result = None if HAS_KANJI.search(line) else out
        if result and not self.agrees(sentence, derived):
            result = None
        self.cache[key] = result
        return result

    def longest_at(self, sentence, i, spans, annotated):
        """Le plus long mot lisible qui commence ici, et sa lecture.

        Le corpus passe en premier, mais il découpe parfois plus fin qu'il ne
        faudrait : 夜の八時です y est annoté 八 時(とき), et la ligne annonçait
        はちとき. JMdict connaît 八時, sans ambiguïté, et l'analyse la plus
        longue l'emporte. À longueur égale c'est le corpus qui tranche, lui
        seul sait de quel mot parle la phrase.
        """
        for span in spans:
            if not sentence.startswith(span, i):
                continue
            # Une graphie de JMdict strictement plus longue corrige le
            # découpage ; hors de là on ne touche à rien, le corpus reste le
            # seul à savoir de quel mot la phrase parle.
            for size in range(len(sentence) - i, len(span), -1):
                wide = sentence[i:i + size]
                if wide in self.spoken:
                    return wide, self.spoken[wide]
            return span, annotated[span]
        return None, None

    def agrees(self, sentence, derived):
        """Vrai si fugashi confirme les lectures déduites par okurigana.

        La lecture d'un lemme se reporte sur sa forme fléchie en isolant
        l'okurigana commun : 忙しい(いそがしい) donne いそがしかった. Le procédé
        suppose que le radical se lit pareil, ce qui est faux des irréguliers —
        来る(くる) sur 来て donnait くて au lieu de きて.

        Les lectures que le corpus ou JMdict donnent telles quelles ne passent
        pas par là et n'ont rien à confirmer. Pour les autres, fugashi sert de
        second avis : un désaccord ne dit pas qui a tort, et une ligne dont on
        n'est pas sûr ne vaut pas d'être montrée. Le mot garde ses autres
        phrases.
        """
        if not derived:
            return True
        said = []
        for word in self.tagger(sentence):
            reading = getattr(word.feature, "kana", None) or getattr(
                word.feature, "pron", None
            )
            said.append(kata_to_hira(reading or word.surface))
        said = "".join(said)
        return all(reading in said for reading in derived)


def reads_as(parts, writings, kana):
    """Faux si une graphie du mot, isolée dans la phrase, s'y lit autrement.

    Le mot doit occuper un découpage à lui seul : dans 大発見家, le 家 de la
    fiche « -ien » est pris dans un composé dont la lecture entière ne se
    compare à rien. Une forme fléchie ne s'écrit pas comme le lemme et ne
    tombe pas non plus sous ce contrôle — c'est la ligne entière qui en
    répond.
    """
    for text, reading in parts:
        if text in writings and kata_to_hira(reading) != kana:
            return False
    return True


def pick_examples(keys, kana, own, regular, positions, sentences, index,
                  kana_line, limit=2):
    """Phrases où le mot est employé, à l'un des sens que la fiche affiche.

    Le corpus numérote le sens de chaque mot annoté, et ce numéro suit l'ordre
    des sens de JMdict. Une phrase annotée sur un sens que la fiche ne montre
    pas illustre autre chose et ne sert pas d'exemple — mais la fiche en montre
    trois depuis qu'un mot donne tous ses sens, et les trois comptent.

    Le corpus ne numérote que pour lever une ambiguïté : une phrase sans numéro
    porte le sens courant, c'est-à-dire le premier. 915 des phrases de 明日 sont
    dans ce cas, et elles passaient derrière les trois qui portent un numéro,
    faute d'être reconnues comme parlant du bon sens.

    La recherche part des écritures du mot. Chercher aussi sur la lecture
    ramenait n'importe quel homophone — une phrase sur 他 illustrait 田 — mais
    l'écarter faisait perdre les phrases où le mot s'écrit autrement. La
    lecture reste donc interrogée en dernier, et seulement pour les phrases
    dont le sens annoté est l'un de ceux qu'on affiche.

    Le lemme annoté doit être une graphie du mot : はし ramenait les phrases
    de 橋 par sa lecture, et leur numéro de sens tombait juste par hasard, deux
    entrées différentes numérotant chacune à partir de 1. Le kana ne compte
    comme graphie que si le mot s'écrit en kana : sinon la particule か
    illustrait 家 « -ien », に illustrait 二 et まい illustrait 枚.

    Le numéro de sens ne suffit pas non plus à départager deux homographes,
    pour la même raison : 月 vaut つき, げつ ou がつ, chacun sa propre entrée
    numérotée à partir de 1, et les phrases de la lune remplissaient la fiche
    du mois. La lecture annotée doit donc être celle de la fiche — pas une
    autre lecture de la même entrée : 辛い réunit からい et つらい, et la fiche
    « épicé » se voyait illustrée par « pénible ».

    La lecture est facultative dans le corpus, et son absence ne prouve rien :
    右[01] n'en a pas, et le seul 右 annoté l'est en ひだり, par erreur. Une
    phrase sans lecture annotée reste donc retenue.
    """
    wanted = {p + 1 for p in positions}
    written = set(keys) | set(own)
    allowed = set(written)
    if not any(HAS_KANJI.search(text) for text in written):
        allowed.add(kana)
    spoken = kata_to_hira(kana)
    lookups = [(key, False) for key in keys]
    if kana not in keys:
        lookups.append((kana, True))

    seen = set()
    candidates = []
    for key, by_reading in lookups:
        for idx, tagged, head, said in index.get(key, []):
            if idx in seen or head not in allowed:
                continue
            if said and HAS_KANJI.search(head) and kata_to_hira(said) != spoken:
                continue
            shown = tagged in wanted or (tagged is None and 1 in wanted)
            if not shown and tagged is not None and wanted:
                continue
            if by_reading and not shown:
                continue
            seen.add(idx)
            # À sens égal, une phrase traduite en français passe devant : la
            # moitié des phrases de Tatoeba n'a que l'anglais, et l'application
            # est en français. Vient ensuite la phrase qui s'écrit en entier :
            # un chiffre ou des capitales latines traversent la ligne en kana
            # sans rien apprendre, ５枚 restant ５まい faute de savoir compter
            # les objets plats. La longueur départage en dernier, une phrase
            # courte se lit entre deux mots.
            candidates.append((
                0 if shown else 1,
                0 if sentences[idx][2] else 1,
                1 if NOT_SPOKEN.search(sentences[idx][0]) else 0,
                len(sentences[idx][0]),
                idx,
            ))
    candidates.sort()

    # Une phrase dont on ne sait pas reconstruire la ligne en kana est
    # écartée plus bas : il faut en garder assez sous la main pour ne pas
    # laisser un mot sans exemple à cause des premières.
    out = []
    # Le radical de la lecture, okurigana mis à part : あう vaut pour あえて,
    # からい pour からかった. Une lecture sans kanji n'a rien à retrancher.
    stem = kata_to_hira(kana)
    for text in regular:
        if HAS_KANJI.search(text):
            stem = min(stem, surface_stem(text, kata_to_hira(kana)), key=len)

    for _shown, _translated, _written, _length, idx in candidates[:40]:
        jp, en, fr, annotated = sentences[idx]
        parts = kana_line.parts(jp, annotated)
        if not parts:
            continue
        # Dernière vérification, et la seule que l'utilisateur voit : la fiche
        # doit se lire dans sa propre ligne en kana. 辛い « épicé » était
        # illustré par つらい « pénible » et あちら par あっち — la fiche
        # annonçait une lecture que la phrase en dessous ne prononçait pas.
        line = "".join(reading for _text, reading in parts)
        if stem and stem not in kata_to_hira(line):
            continue
        # Là où le mot est écrit tel quel, sa lecture doit être celle de la
        # fiche, et pas seulement figurer quelque part : 九 « く » passait
        # grâce au く de 幾つ, dans une phrase qui le lit きゅう.
        if not reads_as(parts, regular, kata_to_hira(kana)):
            continue
        example = {"jp": jp, "kana": line, "en": en}
        if fr:
            example["fr"] = fr
        out.append(example)
        if len(out) == limit:
            break
    return out


# ---------------------------------------------------------------------------
# Assemblage
# ---------------------------------------------------------------------------

def load_frequency():
    """Rang de fréquence par graphie et par lecture, d'après JMdict.

    JMdict marque les 24 000 mots les plus fréquents de la presse en bandes
    de 500, `nf01` à `nf48` : plus la bande est basse, plus le mot est
    courant. La version simplifiée ne garde qu'un drapeau « courant » oui ou
    non, le XML d'origine garde les bandes.

    Un mot absent des bandes n'est pas rare, il est seulement hors des 24 000.
    """
    raw = gzip.decompress(fetch(JMDICT_XML, "JMdict_e.gz", binary=True))
    text = raw.decode("utf-8", "replace")
    out = {}
    for form in re.findall(r"<(?:k_ele|r_ele)>(.*?)</(?:k_ele|r_ele)>", text, re.S):
        written = re.search(r"<(?:keb|reb)>(.*?)</(?:keb|reb)>", form)
        bands = [int(n) for n in re.findall(r"<(?:ke|re)_pri>nf(\d+)</", form)]
        if not written or not bands:
            continue
        rank = min(bands)
        name = written.group(1)
        if name not in out or rank < out[name]:
            out[name] = rank
    return out


def load_sense_french():
    """Français des sens supplémentaires, glose anglaise -> glose française.

    JMdict ne les a pas : 2 700 de ses 2 954 entrées utiles ici n'ont qu'un
    seul bloc de sens français, quand l'anglais en découpe plusieurs. Ces
    traductions-là ne viennent donc pas du dictionnaire mais d'un modèle, et
    le fichier est là pour être relu et corrigé à la main.

    Le sens principal n'y touche pas : il garde le français de JMdict.
    """
    if not os.path.exists(SENSE_OVERRIDES):
        return {}
    data = json.load(io.open(SENSE_OVERRIDES, encoding="utf-8"))
    return {k: v for k, v in data.items() if not k.startswith("_")}


def build_vocab(sentences, index, kana_line, french, english, overrides,
                frequency, sense_french):
    merged = {}
    sources = load_api()
    for level in LEVELS:
        sources += load_anki(level)

    for entry in sources:
        if not entry["kana"]:
            continue
        key = (entry["kana"], entry["word"])
        previous = merged.get(key)
        if previous is None or entry["level"] > previous["level"]:
            merged[key] = entry

    by_kana = {}
    for (kana, _word), entry in merged.items():
        by_kana.setdefault(kana, []).append(entry)

    words = []
    missing_fr = []
    for kana in sorted(by_kana):
        override = overrides.get(kana) or {}
        if override.get("exclude"):
            continue
        group = sorted(by_kana[kana], key=lambda e: -e["level"])
        # Le niveau retenu est le plus accessible : un mot vu au N5 reste N5,
        # même si une autre écriture de la même lecture apparaît plus loin.
        level = max(e["level"] for e in group)
        forms = []
        fallback = []
        for e in group:
            if e["word"] not in forms:
                forms.append(e["word"])
            for m in e["meaning"].split(","):
                m = m.strip()
                if m and m not in fallback:
                    fallback.append(m)

        # L'écriture est celle de la liste source, au niveau le plus
        # accessible. Une ligne qui s'écrit déjà en kana comptait pour rien :
        # la ligne N5 する était ignorée et c'est le 刷る du N3, « imprimer »,
        # qui donnait le sens et les exemples de する.
        word = forms[0]
        entry_id, suru = pick_entry(
            english, word, kana, french[0], meaning=group[0]["meaning"]
        )
        en_auto, position = (None, None)
        if entry_id is not None:
            en_auto, position = glosses_for(english, entry_id)
        en = override.get("en") or en_auto
        fr = override.get("fr")
        if not fr and entry_id is not None:
            # Même entrée, et si possible même sens : sans ça les deux lignes
            # décrivent parfois deux mots différents. Le français reste plus
            # large quand il aplatit tous les sens en un seul, mais il porte
            # alors sur la bonne entrée, ce qui suffit.
            fr = glosses_for(french, entry_id, position)[0]
        if not en:
            en = ", ".join(fallback[:3])
        if not fr:
            missing_fr.append((kana, word, en))
            continue

        # 出発する n'a pas d'entrée propre, ses sens viennent du nom 出発 :
        # l'écriture affichée doit garder le する pour coller à la lecture.
        display = word
        if suru and not word.endswith("する"):
            display = word + "する"

        # Les autres graphies listées sont celles de l'entrée retenue, et
        # elles seules : les listes source regroupent par lecture, si bien que
        # する traînait 刷る et 擦る, qui sont deux autres mots.
        written = writings_of(english, entry_id)
        own = {text for text, _usual, _regular in written}
        forms = [display] + [
            f for f in forms if f in own and f != display and f != word
        ]

        entry = {
            "kana": kana,
            "word": display,
            "forms": forms,
            "level": level,
            "fr": fr,
            "en": en,
            "script": "katakana" if HAS_KATAKANA.search(kana) else "hiragana",
        }

        # La bande de fréquence du mot : la meilleure de ses graphies et de sa
        # lecture. Elle sert à présenter les mots courants d'abord, elle
        # n'entre pas dans le tirage d'une partie chronométrée.
        bands = [
            frequency[text]
            for text in [kana, word, display] + forms
            if text in frequency
        ]
        if bands:
            entry["freq"] = min(bands)

        # Les autres sens du mot, en anglais seulement. Le français de JMdict
        # n'a pas le même découpage : lu à la position du sens anglais il
        # renvoie autre chose, 掛ける donnait « to put on (a blanket) » en face
        # de « s'asseoir ». Il aplatit en revanche tous les sens sur sa ligne,
        # si bien qu'il les couvre déjà : 青 y vaut « bleu, vert ».
        # Un sens écrit à la main ne se complète pas, il remplace l'entrée.
        # `shown` retient la position de chaque sens affiché : c'est ce qui
        # permet ensuite de retenir une phrase annotée sur le deuxième ou le
        # troisième, qui illustre le mot tel que la fiche le montre.
        shown = [] if position is None else [position]
        if entry_id is not None and not override.get("en") and not override.get("fr"):
            others = []
            for position_other, text in senses_for(english, entry_id):
                # Deux sens voisins finissent parfois sur la même glose une
                # fois coupés à trois : バス valait « bus » deux fois.
                if position_other == position or text == en or text in others:
                    continue
                others.append(text)
                shown.append(position_other)
                if len(others) == OTHER_SENSES:
                    break
            if others:
                entry["senses"] = others
                # Le français de chaque sens en plus, quand il est traduit.
                # La liste garde la même longueur et le même ordre : une case
                # vide veut dire « pas de français pour ce sens-là ».
                translated = [sense_french.get(text, "") for text in others]
                if any(translated):
                    entry["senses_fr"] = translated
        # Les graphies rares ne servent pas à chercher des exemples : 為る
        # est une écriture de する comme de なる, et les phrases de l'un
        # illustraient l'autre.
        keys = [display] if display == word else [display, word]
        keys += [
            text for text, usual, _regular in written
            if usual and text not in keys and text != kana
        ]
        # Le radical de la lecture ne se déduit que d'un okurigana régulier.
        regular = [display] + [
            text for text, usual, ok in written
            if usual and ok and text not in (display, kana)
        ]
        examples = pick_examples(
            keys, kana, own, regular, shown, sentences, index, kana_line
        )
        if examples:
            entry["examples"] = examples
        words.append(entry)

    words.sort(key=lambda w: (w["level"] * -1, w["kana"]))
    for i, w in enumerate(words):
        w["id"] = "v%04d" % i
    return words, missing_fr


def load_kanjidic():
    """Lectures et sens des kanji, d'après KANJIDIC2.

    La source d'origine, tenue à jour par l'EDRDG, et la seule qui porte des
    sens en français. Les lectures on y sont en katakana, comme le veut
    l'usage des dictionnaires ; l'application les affiche en hiragana, à côté
    des lectures kun.

    Le niveau JLPT de KANJIDIC2 est l'ancienne échelle à quatre niveaux : il
    n'est pas lu ici, c'est kanji-data qui donne l'échelle N5-N1.
    """
    raw = gzip.decompress(fetch(KANJIDIC2, "kanjidic2.xml.gz", binary=True))
    root = ET.fromstring(raw)
    out = {}
    for character in root.findall("character"):
        literal = character.findtext("literal")
        if not literal:
            continue
        misc = character.find("misc")
        on, kun, meanings_en, meanings_fr = [], [], [], []
        for group in character.findall("reading_meaning/rmgroup"):
            for reading in group.findall("reading"):
                kind = reading.get("r_type")
                if kind == "ja_on":
                    on.append(kata_to_hira(reading.text or ""))
                elif kind == "ja_kun":
                    kun.append(reading.text or "")
            for meaning in group.findall("meaning"):
                language = meaning.get("m_lang")
                if language == "fr":
                    meanings_fr.append(meaning.text or "")
                elif language is None:
                    meanings_en.append(meaning.text or "")
        out[literal] = {
            "on": on,
            "kun": kun,
            "en": meanings_en,
            "fr": meanings_fr,
            "strokes": int(misc.findtext("stroke_count") or 0) or None
            if misc is not None else None,
            "grade": int(misc.findtext("grade") or 0) or None
            if misc is not None else None,
        }
    return out


def build_kanji(words):
    levels = json.loads(fetch(KANJI_DATA, "kanji.json"))
    data = load_kanjidic()
    # KANJIDIC2 ne traduit pas tout : 51 kanji hors listes officielles restent
    # sans français alors qu'ils portent du vocabulaire courant — 鍵, 椅子,
    # 醤油. Ces gloses-là sont écrites à la main.
    french_overrides = {}
    if os.path.exists(KANJI_OVERRIDES):
        french_overrides = {
            k: v for k, v in
            json.load(io.open(KANJI_OVERRIDES, encoding="utf-8")).items()
            if not k.startswith("_")
        }
    in_vocab = {}
    for w in sorted(words, key=lambda w: -w["level"]):
        for ch in w["word"]:
            if HAS_KANJI.match(ch):
                in_vocab.setdefault(ch, []).append(w["id"])

    def jlpt(ch):
        return (levels.get(ch) or {}).get("jlpt_new") or None

    chars = {c for c in levels if (jlpt(c) or 0) >= 3}
    chars |= set(in_vocab)

    def sort_key(c):
        return (-(jlpt(c) or 0), (data.get(c) or {}).get("grade") or 99, c)

    out = []
    for ch in sorted(chars, key=sort_key):
        info = data.get(ch)
        if not info:
            continue
        on = [r for r in info["on"] if KANA_RE.match(r)][:4]
        kun = []
        for reading in info["kun"]:
            # KANJIDIC2 sépare l'okurigana par un point et marque les préfixes
            # et suffixes par un tiret : 食.べる, -がわ. Seule la partie lue
            # dans le kanji lui-même nous intéresse.
            reading = reading.split(".")[0].replace("-", "")
            if KANA_RE.match(reading) and reading not in kun:
                kun.append(reading)
        if not on and not kun:
            continue
        out.append({
            "kanji": ch,
            "on": on,
            "kun": kun[:4],
            "meanings": [m.lower() for m in info["en"][:4]],
            "fr": [
                m.lower() for m in
                (info["fr"] or french_overrides.get(ch) or [])[:4]
            ],
            "strokes": info["strokes"],
            "grade": info["grade"],
            "jlpt": jlpt(ch),
            "words": in_vocab.get(ch, [])[:4],
        })
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    overrides = {}
    if os.path.exists(OVERRIDES):
        overrides = json.load(io.open(OVERRIDES, encoding="utf-8"))

    sys.stderr.write("chargement de JMdict\n")
    french = load_jmdict("fre")
    english = load_jmdict("eng")
    frequency = load_frequency()
    sys.stderr.write("chargement des exemples\n")
    spoken = reading_map(english)
    sentences, index, derived = load_examples(spoken)
    kana_line = KanaLine(spoken, derived)

    words, missing_fr = build_vocab(
        sentences, index, kana_line, french, english, overrides, frequency,
        load_sense_french()
    )
    kanji = build_kanji(words)

    with open(os.path.join(OUT, "vocab.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 2,
            "count": len(words),
            "attribution": "Vocabulaire : open-anki-jlpt-decks, jlpt-vocab-api. "
                           "Sens et fréquences : JMdict / EDRDG (CC BY-SA 4.0). "
                           "Exemples et traductions : Tatoeba (CC BY 2.0 FR). "
                           "Français des sens supplémentaires : traduit de "
                           "l'anglais de JMdict par un modèle.",
            "words": words,
        }, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(OUT, "kanji.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 2,
            "count": len(kanji),
            "attribution": "Kanji : KANJIDIC2 / EDRDG (CC BY-SA 4.0). "
                           "Niveaux JLPT : kanji-data (davidluzgouveia).",
            "kanji": kanji,
        }, f, ensure_ascii=False, separators=(",", ":"))

    for level in LEVELS:
        pool = [w for w in words if w["level"] == level]
        kata = sum(1 for w in pool if w["script"] == "katakana")
        print("N%d : %d mots (%d katakana)" % (level, len(pool), kata))
    with_ex = sum(1 for w in words if w.get("examples"))
    with_fr = sum(
        1 for w in words if any(e.get("fr") for e in w.get("examples", []))
    )
    print("total : %d mots, %d avec exemple, %d traduit en français"
          % (len(words), with_ex, with_fr))
    multiple = [w for w in words if w.get("senses")]
    senses_total = sum(len(w["senses"]) for w in multiple)
    senses_fr = sum(
        1 for w in multiple for t in w.get("senses_fr", []) if t
    )
    print("sens multiples : %d mots, %d sens en plus, %d traduits en français"
          % (len(multiple), senses_total, senses_fr))
    print("fréquence connue : %d mots" % sum(1 for w in words if "freq" in w))
    print("kanji : %d (%d au N5), %d avec sens français"
          % (len(kanji), sum(1 for k in kanji if k["jlpt"] == 5),
             sum(1 for k in kanji if k["fr"])))

    if missing_fr:
        path = os.path.join(CACHE, "missing_fr.json")
        json.dump(missing_fr, io.open(path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print("%d mots sans sens français, écartés (liste : %s)" % (len(missing_fr), path))


if __name__ == "__main__":
    main()
