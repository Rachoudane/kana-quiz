#!/usr/bin/env python3
"""Embarque Noto Sans JP, réduite aux caractères réellement affichés.

La police complète pèse 4,5 Mo. On ne garde que les caractères
présents dans assets/data (kana, kanji, phrases d'exemple, sens français et
anglais), plus le latin et la ponctuation : le fichier tombe sous le mégaoctet
et le rendu ne dépend plus des polices installées sur la machine.

Prérequis : pip install fonttools
Usage     : python tool/build_fonts.py
"""

import json
import os
import sys
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tool", ".cache")
DATA = os.path.join(ROOT, "assets", "data")
OUT = os.path.join(ROOT, "assets", "fonts")

BASE = "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans"
# Une seule graisse : le japonais n'est jamais mis en gras dans l'interface,
# et chaque graisse coûte plus d'un demi-mégaoctet une fois sous-ensemblée.
FACES = {
    "NotoSansJP-Regular.otf": BASE + "/SubsetOTF/JP/NotoSansJP-Regular.otf",
}
LICENSE_URL = BASE + "/LICENSE"

# Latin, chiffres, ponctuation, accents français, et les quelques signes
# japonais utilisés par l'interface elle-même.
ALWAYS = (
    "".join(chr(c) for c in range(0x20, 0x7F))
    + "àâäçéèêëîïôöùûüÿœæÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆ"
    + "…—–‘’“”·«»×÷°ō"
    + "、。「」『』（）・〜ー々"
)


def download(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        sys.stderr.write("download " + url + "\n")
        req = urllib.request.Request(url, headers={"User-Agent": "kana-quiz-build"})
        with urllib.request.urlopen(req, timeout=600) as response:
            data = response.read()
        with open(path, "wb") as f:
            f.write(data)
    return path


def collect_characters():
    """Tous les caractères que l'application peut afficher."""
    used = set(ALWAYS)

    def walk(node):
        if isinstance(node, str):
            used.update(node)
        elif isinstance(node, dict):
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    for name in sorted(os.listdir(DATA)):
        if name.endswith(".json"):
            with open(os.path.join(DATA, name), encoding="utf-8") as f:
                walk(json.load(f))

    # Les kana au complet : le moteur peut en afficher hors des données.
    used.update(chr(c) for c in range(0x3041, 0x30FF))
    return used


def build(characters):
    os.makedirs(OUT, exist_ok=True)
    text = "".join(sorted(characters))
    for name, url in FACES.items():
        source = download(url, name)
        font = TTFont(source)
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.notdef_outline = True
        options.recalc_bounds = True
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(text=text)
        subsetter.subset(font)
        target = os.path.join(OUT, name)
        font.save(target)
        font.close()
        before = os.path.getsize(source)
        after = os.path.getsize(target)
        print("%s : %.1f Mo -> %.0f Ko" % (name, before / 1e6, after / 1e3))

    license_path = download(LICENSE_URL, "NotoSansJP-LICENSE.txt")
    with open(license_path, encoding="utf-8") as src:
        with open(os.path.join(OUT, "OFL.txt"), "w", encoding="utf-8") as dst:
            dst.write(src.read())


def main():
    characters = collect_characters()
    print("%d caractères conservés" % len(characters))
    build(characters)


if __name__ == "__main__":
    main()
