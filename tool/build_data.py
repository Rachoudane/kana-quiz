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
        kanjis = [k["text"] for k in entry["kanji"]]
        # Les graphies de l'entrée servent à écarter, plus bas, les écritures
        # d'un autre mot que les listes source ont rangées sous la même
        # lecture : 刷る n'est pas une autre façon d'écrire する. Le drapeau
        # dit si la graphie s'écrit encore : 為る est une graphie de する comme
        # de なる, mais plus personne ne l'écrit, et chercher des exemples
        # dessus mélangeait les deux verbes.
        writings = [
            (k["text"], not (set(k.get("tags") or []) & RARE_KANJI))
            for k in entry["kanji"]
        ]
        entries[entry["id"]] = (common, senses, writings)
        for kana in kanas:
            by_kana.setdefault(kana, []).append(entry["id"])
            for kanji in kanjis:
                by_pair.setdefault((kanji, kana), []).append(entry["id"])
    return entries, by_pair, by_kana


def writings_of(index, entry_id):
    """Graphies de l'entrée : (texte, encore en usage). Vide si introuvable."""
    record = index[0].get(entry_id)
    return record[2] if record else []


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
    if surface.startswith(stem_head):
        return stem_reading + surface[len(stem_head):]
    if surface == head:
        return reading
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


def load_examples():
    """Phrases (japonais, anglais, français) + index lemme -> phrases.

    Chaque entrée de l'index retient le numéro de sens annoté par le corpus,
    `する[1]` contre `する[2]` : sans lui, une phrase illustre un homonyme.

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
    # Les identifiants sont triés : le fichier de Tatoeba n'est pas garanti
    # dans l'ordre, et deux constructions doivent donner le même jeu.
    for sentence_id in sorted(indices, key=int):
        jp = japanese.get(sentence_id)
        if not jp or not 6 <= len(jp) <= 46:
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
            lemmas.append((head, sense, head))
            if reading and not reading.startswith("#"):
                lemmas.append((reading, sense, head))
                if HAS_KANJI.search(head):
                    kana = surface_reading(head, reading, surface or head)
                    if kana and not HAS_KANJI.search(kana):
                        readings[surface or head] = kana
        idx = len(sentences)
        sentences.append((jp, pair.get("eng", ""), pair.get("fra", ""), readings))
        for lemma, sense, head in set(lemmas):
            index.setdefault(lemma, []).append((idx, sense, head))
    return sentences, index


class KanaLine:
    """Transcrit une phrase japonaise en kana, sans kanji."""

    def __init__(self):
        import fugashi

        self.tagger = fugashi.Tagger()
        self.cache = {}

    def build(self, sentence, annotated):
        key = (sentence, tuple(sorted(annotated.items())))
        if key in self.cache:
            return self.cache[key]
        out = []
        for word in self.tagger(sentence):
            surface = word.surface
            if not HAS_KANJI.search(surface):
                out.append(surface)
                continue
            if surface in annotated:
                out.append(annotated[surface])
                continue
            reading = getattr(word.feature, "kana", None) or getattr(
                word.feature, "pron", None
            )
            if not reading:
                self.cache[key] = None
                return None
            out.append(kata_to_hira(reading))
        line = "".join(out)
        result = None if HAS_KANJI.search(line) else line
        self.cache[key] = result
        return result


def pick_examples(keys, kana, own, sense, sentences, index, kana_line, limit=2):
    """Phrases où le mot est employé, et au sens affiché.

Le corpus numérote le sens de chaque mot annoté, et ce numéro suit
    l'ordre des sens de JMdict : une phrase annotée sur un autre sens parle
    d'un autre mot et ne sert pas d'exemple.

    La recherche part des écritures du mot. Chercher aussi sur la lecture
    ramenait n'importe quel homophone — une phrase sur 他 illustrait 田 — mais
    l'écarter faisait perdre les phrases où le mot s'écrit autrement. La
    lecture reste donc interrogée en dernier, et seulement pour les phrases
    dont le sens annoté est celui qu'on affiche.

    Dernier garde-fou, le lemme annoté doit être une graphie du mot : はし
    ramenait les phrases de 橋 par sa lecture, et leur numéro de sens tombait
    juste par hasard, deux entrées différentes numérotant chacune à partir
    de 1.
    """
    wanted = None if sense is None else sense + 1
    allowed = set(keys) | set(own) | {kana}
    lookups = [(key, False) for key in keys]
    if kana not in keys:
        lookups.append((kana, True))

    seen = set()
    candidates = []
    for key, by_reading in lookups:
        for idx, tagged, head in index.get(key, []):
            if idx in seen or head not in allowed:
                continue
            exact = wanted is not None and tagged == wanted
            if not exact and tagged is not None and wanted is not None:
                continue
            if by_reading and not exact:
                continue
            seen.add(idx)
            # À sens égal, une phrase traduite en français passe devant : la
            # moitié des phrases de Tatoeba n'a que l'anglais, et l'application
            # est en français. La longueur départage ensuite, une phrase courte
            # se lit entre deux mots.
            candidates.append((
                0 if exact else 1,
                0 if sentences[idx][2] else 1,
                len(sentences[idx][0]),
                idx,
            ))
    candidates.sort()

    # Une phrase dont on ne sait pas reconstruire la ligne en kana est
    # écartée plus bas : il faut en garder assez sous la main pour ne pas
    # laisser un mot sans exemple à cause des premières.
    out = []
    for _exact, _translated, _length, idx in candidates[:40]:
        jp, en, fr, annotated = sentences[idx]
        line = kana_line.build(jp, annotated)
        if not line:
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


def build_vocab(sentences, index, kana_line, french, english, overrides,
                frequency):
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
        own = {text for text, _usual in written}
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
        if entry_id is not None and not override.get("en") and not override.get("fr"):
            others = []
            for position_other, text in senses_for(english, entry_id):
                # Deux sens voisins finissent parfois sur la même glose une
                # fois coupés à trois : バス valait « bus » deux fois.
                if position_other == position or text == en or text in others:
                    continue
                others.append(text)
                if len(others) == OTHER_SENSES:
                    break
            if others:
                entry["senses"] = others
        # Les graphies rares ne servent pas à chercher des exemples : 為る
        # est une écriture de する comme de なる, et les phrases de l'un
        # illustraient l'autre.
        keys = [display] if display == word else [display, word]
        keys += [
            text for text, usual in written
            if usual and text not in keys and text != kana
        ]
        examples = pick_examples(
            keys, kana, own, position, sentences, index, kana_line
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
            "fr": [m.lower() for m in info["fr"][:4]],
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
    sentences, index = load_examples()
    kana_line = KanaLine()

    words, missing_fr = build_vocab(
        sentences, index, kana_line, french, english, overrides, frequency
    )
    kanji = build_kanji(words)

    with open(os.path.join(OUT, "vocab.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 2,
            "count": len(words),
            "attribution": "Vocabulaire : open-anki-jlpt-decks, jlpt-vocab-api. "
                           "Sens et fréquences : JMdict / EDRDG (CC BY-SA 4.0). "
                           "Exemples et traductions : Tatoeba (CC BY 2.0 FR).",
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
    print("sens multiples : %d mots" % sum(1 for w in words if w.get("senses")))
    print("fréquence connue : %d mots" % sum(1 for w in words if "freq" in w))
    print("kanji : %d (%d au N5)" % (len(kanji), sum(1 for k in kanji if k["jlpt"] == 5)))

    if missing_fr:
        path = os.path.join(CACHE, "missing_fr.json")
        json.dump(missing_fr, io.open(path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print("%d mots sans sens français, écartés (liste : %s)" % (len(missing_fr), path))


if __name__ == "__main__":
    main()
