#!/usr/bin/env python3
"""Génère assets/data/particles.json : des phrases à trou pour les particules.

Le principe : une phrase du corpus Tanaka, entièrement en kana, avec une
particule remplacée par un trou. Ce qui compte n'est pas de trouver la
particule mais de savoir pourquoi c'est celle-là — chaque trou est donc
rattaché à un motif grammatical nommé, et un trou dont le motif n'est pas
reconnu est jeté. Mieux vaut moins de questions que des questions sans raison.

Deux précautions.

L'analyse morphologique se fait sur la version à kanji, jamais sur la version
en kana : sans kanji, UniDic découpe こうえんで en こう・え・んで. La phrase en
kana est ensuite reconstruite depuis l'analyse, et la phrase n'est retenue que
si elle tombe exactement sur celle que build_data.py avait produite. C'est ce
qui garantit que le trou est au bon endroit. Environ 9 % des phrases partent
ainsi, sur des désaccords de lecture (私 lu わたくし) sans rapport avec les
particules.

Et は vaut à lui seul 40 % des trous du corpus. Sans plafond, le mode
apprendrait à répondre は les yeux fermés.

Prérequis : pip install fugashi unidic-lite
Usage     : python tool/build_particles.py
"""

import collections
import hashlib
import io
import json
import os
import random
import re
import sys

import fugashi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "data")

KATAKANA_ONLY = re.compile("^[゠-ヿー]+$")
BLANK = "＿"

# Particules enseignées. Les autres — か final, ね, よ, ば, のに — ne sont pas
# des choix de cas : elles ne se devinent pas, elles se savent.
TARGET = {"は", "が", "を", "に", "で", "と", "へ", "も", "から", "まで", "の"}
KEEP_POS2 = {"格助詞", "係助詞", "副助詞"}

V_THROUGH = {"出る", "通る", "渡る", "歩く", "走る", "降りる", "離れる", "飛ぶ",
             "曲がる", "過ぎる", "下りる", "発つ", "出発"}
V_GOAL = {"行く", "来る", "帰る", "入る", "乗る", "着く", "戻る", "向かう",
          "登る", "出かける", "通う", "引っ越す"}
V_EXIST = {"有る", "在る", "居る", "住む", "泊まる", "座る", "立つ", "勤める"}
V_GIVE = {"上げる", "呉れる", "教える", "見せる", "話す", "送る", "渡す", "貸す",
          "頼む", "聞く", "書く"}
V_BECOME = {"成る"}
V_QUOTE = {"言う", "思う", "考える", "答える", "叫ぶ"}
V_TOGETHER = {"会う", "話す", "結婚", "遊ぶ", "喧嘩", "相談", "付き合う", "似る"}
A_EMOTION = {"好き", "嫌い", "上手", "下手", "欲しい", "出来る", "分かる", "要る",
             "上手い", "苦手", "必要", "見える", "聞こえる"}
EXIST_ONLY = {"有る", "在る", "居る"}
MEANS = {"電車", "バス", "車", "自転車", "飛行機", "船", "ペン", "箸", "手",
         "日本語", "英語", "鉛筆", "地下鉄"}
TIME_TAIL = {"時", "分", "日", "月", "年", "曜日", "週", "秒", "歳"}
QUESTION = {"誰", "何", "何処", "何方", "幾ら", "幾つ", "何時"}

# Part maximale d'un même motif dans le jeu final.
CAP = {"wa_open": 700, "wo_object": 700, "no_link": 600, "ga_open": 450}


def slot_id(sentence, at):
    """Identifiant stable d'un trou, dérivé de la phrase et de sa position.

    Les statistiques par question vivent dans le navigateur et survivent aux
    régénérations du jeu de données. Un identifiant positionnel les ferait
    pointer sur une autre phrase au premier changement de corpus.
    """
    digest = hashlib.sha1(("%s@%d" % (sentence, at)).encode("utf-8"))
    return "p" + digest.hexdigest()[:10]


def hiragana(text):
    return "".join(
        chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text
    )


def written(token):
    """Comment le mot s'écrit dans la phrase en kana.

    Un mot en katakana garde ses katakana : c'est son orthographe, pas sa
    lecture.
    """
    if KATAKANA_ONLY.match(token.surface):
        return token.surface
    return hiragana(token.feature.kana or token.surface)


def lemma(token):
    return token.feature.lemma or token.surface


def is_noun(token):
    return token.feature.pos1 in ("名詞", "代名詞")


def next_predicate(tokens, index):
    """Premier verbe ou adjectif après la position donnée.

    Un nom suivi de する compte comme un verbe : そうだんした.
    """
    for offset in range(index + 1, len(tokens)):
        token = tokens[offset]
        if token.feature.pos1 in ("動詞", "形容詞", "形状詞"):
            return token
        if token.feature.pos1 == "名詞" and offset + 1 < len(tokens):
            if lemma(tokens[offset + 1]) == "為る":
                return token
    return None


def particles_before_after(tokens, index):
    before, after = [], []
    for offset, token in enumerate(tokens):
        if token.feature.pos1 != "助詞" or token.feature.pos2 not in KEEP_POS2:
            continue
        if offset < index:
            before.append(token.surface)
        elif offset > index:
            after.append(token.surface)
    return before, after


def negated_after(tokens, index):
    for token in tokens[index + 1:]:
        if lemma(token) in ("ない", "ぬ"):
            return True
        if token.feature.pos1 == "助動詞" and token.surface.startswith("ませ"):
            return True
    return False


def classify(tokens, index):
    """Motif grammatical du trou, ou None si rien de sûr ne s'y reconnaît."""
    token = tokens[index]
    particle = token.surface
    prev = tokens[index - 1] if index > 0 else None
    nxt = tokens[index + 1] if index + 1 < len(tokens) else None
    predicate = next_predicate(tokens, index)
    verb = lemma(predicate) if predicate is not None else ""

    if particle == "を":
        if verb in V_THROUGH:
            return "wo_through"
        if predicate is not None and predicate.feature.pos1 == "動詞":
            return "wo_object"
        return None

    if particle == "に":
        # に は, に も : la particule est reprise en thème, ce n'est plus le
        # に de lieu ni celui de but. Le motif n'est pas celui qu'on enseigne.
        if nxt is not None and nxt.surface in ("は", "も"):
            return None
        if verb in V_EXIST and prev is not None and prev.feature.pos1 == "名詞":
            return "ni_exist"
        if verb in V_GOAL:
            return "ni_goal"
        if verb in V_BECOME:
            return "ni_become"
        if verb in V_GIVE:
            return "ni_recipient"
        if prev is not None and (lemma(prev) in TIME_TAIL
                                 or prev.feature.pos2 == "数詞"):
            return "ni_time"
        return None

    if particle == "で":
        if nxt is not None and nxt.surface in ("は", "も"):
            return None
        if prev is not None and lemma(prev) in MEANS:
            return "de_means"
        if (predicate is not None and predicate.feature.pos1 == "動詞"
                and prev is not None and is_noun(prev)):
            return "de_place"
        return None

    if particle == "と":
        if verb in V_QUOTE:
            return "to_quote"
        if verb in V_TOGETHER:
            return "to_with"
        if prev is not None and is_noun(prev) and nxt is not None and is_noun(nxt):
            return "to_and"
        return None

    if particle == "から":
        return "kara_origin"
    if particle == "まで":
        return "made_limit"
    if particle == "へ":
        return "he_direction"
    if particle == "も":
        return "mo_also"

    if particle == "の":
        if prev is not None and is_noun(prev) and nxt is not None and is_noun(nxt):
            return "no_link"
        return None

    before, after = particles_before_after(tokens, index)

    if particle == "が":
        if prev is not None and lemma(prev) in QUESTION:
            return "ga_question"
        if verb in EXIST_ONLY:
            return "ga_exist"
        if verb in A_EMOTION:
            return "ga_emotion"
        if "は" in before:
            return "ga_small_subject"
        return "ga_open"

    if particle == "は":
        if prev is not None and lemma(prev) in QUESTION:
            return None
        if negated_after(tokens, index) and ("は" in before or "は" in after):
            return "wa_contrast"
        if "が" in after:
            return "wa_big_topic"
        if not before:
            return "wa_open"
        return None

    return None


# Motifs où は et が se défendent tous les deux : le trou accepte les deux, et
# la fiche explique ce qui change. C'est le cœur du mode.
OPEN = {"wa_open", "ga_open"}


def sentences_from_vocab():
    path = os.path.join(OUT, "vocab.json")
    with io.open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    seen, out = set(), []
    for word in data["words"]:
        for example in word.get("examples", []):
            if example["kana"] in seen:
                continue
            seen.add(example["kana"])
            out.append(example)
    return out


def build():
    tagger = fugashi.Tagger()
    examples = sentences_from_vocab()

    sentences = []
    slots = []
    aligned = dropped = 0

    for example in examples:
        tokens = list(tagger(example["jp"]))
        if "".join(written(t) for t in tokens) != example["kana"]:
            dropped += 1
            continue
        aligned += 1

        found = []
        offset = 0
        for index, token in enumerate(tokens):
            form = written(token)
            if (token.feature.pos1 == "助詞"
                    and token.surface in TARGET
                    and token.feature.pos2 in KEEP_POS2):
                rule = classify(tokens, index)
                if rule is not None:
                    prev = tokens[index - 1] if index > 0 else None
                    found.append({
                        "at": offset,
                        "answer": token.surface,
                        "rule": rule,
                        "topic": written(prev) if prev is not None else "",
                    })
            offset += len(form)

        if not found:
            continue
        sentences.append({"k": example["kana"], "en": example["en"]})
        for slot in found:
            slot["s"] = len(sentences) - 1
            slots.append(slot)

    # Plafonds : sans eux は vaut 40 % du jeu et le mode apprend à répondre は.
    random.Random(20260914).shuffle(slots)
    kept, seen_rule = [], collections.Counter()
    for slot in slots:
        rule = slot["rule"]
        if rule in CAP and seen_rule[rule] >= CAP[rule]:
            continue
        seen_rule[rule] += 1
        kept.append(slot)

    used = sorted({slot["s"] for slot in kept})
    remap = {old: new for new, old in enumerate(used)}
    sentences = [sentences[old] for old in used]

    items = []
    for slot in sorted(kept, key=lambda s: (s["s"], s["at"])):
        sentence = sentences[remap[slot["s"]]]["k"]
        item = {
            "id": slot_id(sentence, slot["at"]),
            "s": remap[slot["s"]],
            "at": slot["at"],
            "a": slot["answer"],
            "r": slot["rule"],
        }
        if slot["rule"] in OPEN:
            item["alt"] = ["は", "が"]
            item["t"] = slot["topic"]
        items.append(item)

    payload = {
        "version": 1,
        "count": len(items),
        "attribution": "Phrases : Tanaka Corpus / Tatoeba (CC BY 2.0 FR), les mêmes que vocab.json.",
        "sentences": sentences,
        "items": items,
    }

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "particles.json")
    with io.open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")

    sys.stderr.write("phrases analysees  : %d\n" % (aligned + dropped))
    sys.stderr.write("  alignees         : %d\n" % aligned)
    sys.stderr.write("  ecartees         : %d\n" % dropped)
    sys.stderr.write("phrases retenues   : %d\n" % len(sentences))
    sys.stderr.write("trous retenus      : %d\n" % len(items))
    for rule, count in collections.Counter(i["r"] for i in items).most_common():
        sys.stderr.write("  %-18s %5d\n" % (rule, count))
    sys.stderr.write("ecrit %s (%d ko)\n" % (path, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    build()
