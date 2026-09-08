#!/usr/bin/env python3
"""Génère les jeux de données JSON embarqués dans l'application.

Sources (téléchargées puis mises en cache dans tool/.cache/) :
  - open-anki-jlpt-decks  : liste de vocabulaire JLPT N5
  - jlpt-vocab-api        : seconde liste N5, pour compléter la première
  - kanji-data            : métadonnées kanji (lectures, sens, JLPT, traits)
  - Tanaka Corpus (EDRDG) : phrases d'exemple japonais/anglais, CC BY

Usage : python tool/build_data.py
"""

import csv
import gzip
import io
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tool", ".cache")
OUT = os.path.join(ROOT, "assets", "data")

ANKI_N5 = "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n5.csv"
KANJI_DATA = "https://raw.githubusercontent.com/davidluzgouveia/kanji-data/master/kanji.json"
TANAKA = "http://ftp.edrdg.org/pub/Nihongo/examples.utf.gz"
VOCAB_API = "https://jlpt-vocab-api.vercel.app/api/words?level=5&limit=100&offset={}"

HIRAGANA = "぀-ゟ"
KATAKANA = "゠-ヿー"
KANA_RE = re.compile("^[" + HIRAGANA + KATAKANA + "]+$")
HAS_KATAKANA = re.compile("[" + KATAKANA + "]")
IS_KANJI = re.compile("[一-龯]")


def fetch(url, name, binary=False):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        sys.stderr.write("download " + url + "\n")
        req = urllib.request.Request(url, headers={"User-Agent": "kana-quiz-build"})
        with urllib.request.urlopen(req, timeout=180) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, "rb") as f:
        raw = f.read()
    return raw if binary else raw.decode("utf-8")


# ---------------------------------------------------------------------------
# Nettoyage des entrées de vocabulaire
# ---------------------------------------------------------------------------

PARENS_RE = re.compile("[（(][^)）]*[）)]")


def split_variants(field):
    """« いい; よい » -> ['いい', 'よい'] ; retire ～, les parenthèses, les espaces."""
    out = []
    for part in re.split("[;；/]", field or ""):
        part = part.strip().replace("～", "").replace("〜", "").replace("~", "")
        part = PARENS_RE.sub("", part).strip()
        if part:
            out.append(part)
    return out


def clean_meaning(meaning):
    return re.sub(r"\s+", " ", (meaning or "").strip())


def load_anki():
    rows = list(csv.DictReader(io.StringIO(fetch(ANKI_N5, "n5.csv"))))
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
            entries.append({"kana": reading, "word": expr, "meaning": meaning})
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
            })
        offset += 100
        if offset >= page.get("total", 0):
            break
    return entries


# ---------------------------------------------------------------------------
# Phrases d'exemple (Tanaka Corpus)
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r"^([^(\[{~]+)(?:\(([^)]*)\))?")


def load_examples():
    raw = gzip.decompress(fetch(TANAKA, "examples.utf.gz", binary=True))
    text = raw.decode("utf-8", "replace")
    sentences = []   # (japonais, anglais)
    index = {}       # lemme -> [indices de phrases]
    pending = None
    for line in text.splitlines():
        if line.startswith("A: "):
            body = line[3:].split("#ID=")[0]
            parts = body.split("\t")
            pending = (parts[0].strip(), parts[1].strip() if len(parts) > 1 else "")
        elif line.startswith("B: ") and pending:
            jp, en = pending
            pending = None
            if not en or len(jp) > 60:
                continue
            idx = len(sentences)
            sentences.append((jp, en))
            for token in line[3:].split():
                m = TOKEN_RE.match(token)
                if not m:
                    continue
                index.setdefault(m.group(1), []).append(idx)
                if m.group(2):
                    index.setdefault(m.group(2), []).append(idx)
    return sentences, index


def pick_examples(word, kana, sentences, index, limit=2):
    seen = set()
    cands = []
    for key in (word, kana):
        for idx in index.get(key, []):
            if idx in seen:
                continue
            seen.add(idx)
            jp, en = sentences[idx]
            cands.append((len(jp), jp, en))
    cands.sort()
    return [{"jp": jp, "en": en} for _, jp, en in cands[:limit]]


# ---------------------------------------------------------------------------
# Assemblage
# ---------------------------------------------------------------------------

def build_vocab(sentences, index):
    merged = {}
    for entry in load_anki() + load_api():
        if not entry["kana"] or not entry["meaning"]:
            continue
        merged.setdefault((entry["kana"], entry["word"]), entry)

    by_kana = {}
    for (kana, _word), entry in merged.items():
        by_kana.setdefault(kana, []).append(entry)

    words = []
    for kana in sorted(by_kana):
        forms, meanings = [], []
        for e in by_kana[kana]:
            if e["word"] != kana and e["word"] not in forms:
                forms.append(e["word"])
            for m in e["meaning"].split(","):
                m = m.strip()
                if m and m not in meanings:
                    meanings.append(m)
        word = forms[0] if forms else kana
        entry = {
            "kana": kana,
            "word": word,
            "forms": forms,
            "meaning": ", ".join(meanings[:6]),
            "script": "katakana" if HAS_KATAKANA.search(kana) else "hiragana",
        }
        ex = pick_examples(word, kana, sentences, index)
        if ex:
            entry["examples"] = ex
        words.append(entry)

    for i, w in enumerate(words):
        w["id"] = "v%04d" % i
    return words


def build_kanji(words):
    data = json.loads(fetch(KANJI_DATA, "kanji.json"))
    in_vocab = {}
    for w in words:
        for ch in w["word"]:
            if IS_KANJI.match(ch):
                in_vocab.setdefault(ch, []).append(w["id"])

    chars = {c for c, v in data.items() if v.get("jlpt_new") == 5} | set(in_vocab)

    def sort_key(c):
        info = data.get(c, {})
        return (info.get("grade") or 99, -(info.get("freq") or 0), c)

    out = []
    for ch in sorted(chars, key=sort_key):
        info = data.get(ch)
        if not info:
            continue
        on = [r for r in info.get("readings_on", []) if KANA_RE.match(r)][:4]
        kun_raw = [r.split(".")[0].replace("-", "") for r in info.get("readings_kun", [])]
        kun = []
        for r in kun_raw:
            if KANA_RE.match(r) and r not in kun:
                kun.append(r)
        if not on and not kun:
            continue
        out.append({
            "kanji": ch,
            "on": on,
            "kun": kun[:4],
            "meanings": [m.lower() for m in info.get("meanings", [])[:4]],
            "strokes": info.get("strokes"),
            "grade": info.get("grade"),
            "core": info.get("jlpt_new") == 5,
            "words": in_vocab.get(ch, [])[:4],
        })
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    sentences, index = load_examples()
    words = build_vocab(sentences, index)
    kanji = build_kanji(words)

    with open(os.path.join(OUT, "vocab_n5.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 1,
            "level": "N5",
            "count": len(words),
            "attribution": "Vocabulaire : open-anki-jlpt-decks, jlpt-vocab-api. "
                           "Exemples : Tanaka Corpus / Tatoeba (CC BY 2.0 FR).",
            "words": words,
        }, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(OUT, "kanji_n5.json"), "w", encoding="utf-8") as f:
        json.dump({
            "version": 1,
            "level": "N5",
            "count": len(kanji),
            "attribution": "Kanji : kanji-data (davidluzgouveia), dérivé de KANJIDIC2 (CC BY-SA 3.0).",
            "kanji": kanji,
        }, f, ensure_ascii=False, separators=(",", ":"))

    kata = sum(1 for w in words if w["script"] == "katakana")
    with_ex = sum(1 for w in words if w.get("examples"))
    print("vocab_n5.json : %d mots (%d katakana, %d avec exemple)" % (len(words), kata, with_ex))
    print("kanji_n5.json : %d kanji (%d du noyau N5)" % (len(kanji), sum(1 for k in kanji if k["core"])))


if __name__ == "__main__":
    main()
