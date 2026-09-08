#!/usr/bin/env python3
"""Génère les jeux de données JSON embarqués dans l'application.

Sources, téléchargées puis mises en cache dans tool/.cache/ :
  - open-anki-jlpt-decks  : listes de vocabulaire JLPT N5, N4, N3
  - jlpt-vocab-api        : seconde liste N5, pour compléter la première
  - JMdict (simplifié)    : sens français et anglais, dictionnaire de référence
  - Tanaka Corpus (EDRDG) : phrases d'exemple japonais / anglais, CC BY
  - kanji-data            : lectures, sens et niveau JLPT des kanji

Les lectures kana des phrases d'exemple sont reconstruites à partir des
lectures annotées du Tanaka Corpus, complétées par UniDic via fugashi.

Prérequis : pip install fugashi unidic-lite
Usage     : python tool/build_data.py
"""

import csv
import gzip
import io
import json
import os
import re
import sys
import tarfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tool", ".cache")
OUT = os.path.join(ROOT, "assets", "data")
OVERRIDES = os.path.join(ROOT, "tool", "meaning_overrides.json")

ANKI = "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/{}.csv"
VOCAB_API = "https://jlpt-vocab-api.vercel.app/api/words?level=5&limit=100&offset={}"
KANJI_DATA = "https://raw.githubusercontent.com/davidluzgouveia/kanji-data/master/kanji.json"
TANAKA = "http://ftp.edrdg.org/pub/Nihongo/examples.utf.gz"
JMDICT_RELEASE = "https://api.github.com/repos/scriptin/jmdict-simplified/releases/latest"

LEVELS = [5, 4, 3]

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
        entries[entry["id"]] = (common, senses)
        for kana in kanas:
            by_kana.setdefault(kana, []).append(entry["id"])
            for kanji in kanjis:
                by_pair.setdefault((kanji, kana), []).append(entry["id"])
    return entries, by_pair, by_kana


def pick_entry(index, word, kana, preferred=None):
    """Identifiant JMdict du mot, et vrai si on est passé par le radical する.

    Le choix se fait sur l'index anglais, le seul complet : le français n'a
    qu'une entrée sur quatorze et ne peut pas trancher. Mais une entrée que le
    français connaît passe devant, sinon いくら part sur イクラ, absent du
    français, et le mot est perdu faute de traduction.
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
    return sorted(ids, key=lambda i: (i not in known, not entries[i][0]))[0], suru



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


def load_examples():
    """Phrases (japonais, anglais) + index lemme -> phrases + lectures annotées."""
    raw = gzip.decompress(fetch(TANAKA, "examples.utf.gz", binary=True))
    text = raw.decode("utf-8", "replace")
    sentences = []   # (japonais, anglais, {surface: lecture})
    index = {}
    pending = None
    for line in text.splitlines():
        if line.startswith("A: "):
            body = line[3:].split("#ID=")[0]
            parts = body.split("\t")
            pending = (parts[0].strip(), parts[1].strip() if len(parts) > 1 else "")
        elif line.startswith("B: ") and pending:
            jp, en = pending
            pending = None
            if not en or not 6 <= len(jp) <= 46:
                continue
            readings = {}
            lemmas = []
            for token in line[3:].split():
                m = TOKEN_RE.match(token)
                if not m:
                    continue
                head, reading, _sense, surface = m.groups()
                lemmas.append(head)
                if reading and not reading.startswith("#"):
                    lemmas.append(reading)
                    if HAS_KANJI.search(head):
                        kana = surface_reading(head, reading, surface or head)
                        if kana and not HAS_KANJI.search(kana):
                            readings[surface or head] = kana
            idx = len(sentences)
            sentences.append((jp, en, readings))
            for lemma in set(lemmas):
                index.setdefault(lemma, []).append(idx)
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


def pick_examples(word, kana, sentences, index, kana_line, limit=2):
    seen = set()
    candidates = []
    for key in (word, kana):
        for idx in index.get(key, []):
            if idx in seen:
                continue
            seen.add(idx)
            candidates.append((len(sentences[idx][0]), idx))
    candidates.sort()

    out = []
    for _length, idx in candidates[:12]:
        jp, en, annotated = sentences[idx]
        line = kana_line.build(jp, annotated)
        if not line:
            continue
        out.append({"jp": jp, "kana": line, "en": en})
        if len(out) == limit:
            break
    return out


# ---------------------------------------------------------------------------
# Assemblage
# ---------------------------------------------------------------------------

def build_vocab(sentences, index, kana_line, french, english, overrides):
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
            if e["word"] != kana and e["word"] not in forms:
                forms.append(e["word"])
            for m in e["meaning"].split(","):
                m = m.strip()
                if m and m not in fallback:
                    fallback.append(m)
        word = forms[0] if forms else kana

        entry_id, suru = pick_entry(english, word, kana, french[0])
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
            if forms:
                forms[0] = display

        entry = {
            "kana": kana,
            "word": display,
            "forms": forms,
            "level": level,
            "fr": fr,
            "en": en,
            "script": "katakana" if HAS_KATAKANA.search(kana) else "hiragana",
        }
        examples = pick_examples(word, kana, sentences, index, kana_line)
        if examples:
            entry["examples"] = examples
        words.append(entry)

    words.sort(key=lambda w: (w["level"] * -1, w["kana"]))
    for i, w in enumerate(words):
        w["id"] = "v%04d" % i
    return words, missing_fr


def build_kanji(words):
    data = json.loads(fetch(KANJI_DATA, "kanji.json"))
    in_vocab = {}
    for w in sorted(words, key=lambda w: -w["level"]):
        for ch in w["word"]:
            if HAS_KANJI.match(ch):
                in_vocab.setdefault(ch, []).append(w["id"])

    chars = {c for c, v in data.items() if (v.get("jlpt_new") or 0) >= 3}
    chars |= set(in_vocab)

    def sort_key(c):
        info = data.get(c, {})
        return (-(info.get("jlpt_new") or 0), info.get("grade") or 99, c)

    out = []
    for ch in sorted(chars, key=sort_key):
        info = data.get(ch)
        if not info:
            continue
        on = [r for r in info.get("readings_on", []) if KANA_RE.match(r)][:4]
        kun = []
        for reading in info.get("readings_kun", []):
            reading = reading.split(".")[0].replace("-", "")
            if KANA_RE.match(reading) and reading not in kun:
                kun.append(reading)
        if not on and not kun:
            continue
        out.append({
            "kanji": ch,
            "on": on,
            "kun": kun[:4],
            "meanings": [m.lower() for m in info.get("meanings", [])[:4]],
            "strokes": info.get("strokes"),
            "grade": info.get("grade"),
            "jlpt": info.get("jlpt_new"),
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
    sys.stderr.write("chargement des exemples\n")
    sentences, index = load_examples()
    kana_line = KanaLine()

    words, missing_fr = build_vocab(sentences, index, kana_line, french, english, overrides)
    kanji = build_kanji(words)

    with open(os.path.join(OUT, "vocab.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 2,
            "count": len(words),
            "attribution": "Vocabulaire : open-anki-jlpt-decks, jlpt-vocab-api. "
                           "Sens : JMdict / EDRDG (CC BY-SA 4.0). "
                           "Exemples : Tanaka Corpus / Tatoeba (CC BY 2.0 FR).",
            "words": words,
        }, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(OUT, "kanji.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 2,
            "count": len(kanji),
            "attribution": "Kanji : kanji-data (davidluzgouveia), dérivé de "
                           "KANJIDIC2 / EDRDG (CC BY-SA 3.0).",
            "kanji": kanji,
        }, f, ensure_ascii=False, separators=(",", ":"))

    for level in LEVELS:
        pool = [w for w in words if w["level"] == level]
        kata = sum(1 for w in pool if w["script"] == "katakana")
        print("N%d : %d mots (%d katakana)" % (level, len(pool), kata))
    with_ex = sum(1 for w in words if w.get("examples"))
    print("total : %d mots, %d avec exemple" % (len(words), with_ex))
    print("kanji : %d (%d au N5)" % (len(kanji), sum(1 for k in kanji if k["jlpt"] == 5)))

    if missing_fr:
        path = os.path.join(CACHE, "missing_fr.json")
        json.dump(missing_fr, io.open(path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print("%d mots sans sens français, écartés (liste : %s)" % (len(missing_fr), path))


if __name__ == "__main__":
    main()
