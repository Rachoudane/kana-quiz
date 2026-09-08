#!/usr/bin/env python3
"""Dessine l'icône de l'application : あ blanc sur un carré bleu.

Le glyphe vient de la police déjà embarquée, donc l'icône et l'interface
montrent exactement le même あ.

Prérequis : pip install pillow, et assets/fonts/NotoSansJP-Regular.otf
            (généré par tool/build_fonts.py)
Usage     : python tool/build_icon.py
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "NotoSansJP-Regular.otf")
WEB = os.path.join(ROOT, "web")

GLYPH = "あ"
TOP = (0x6E, 0x9B, 0xF5)
BOTTOM = (0x3F, 0x6B, 0xD8)
INK = (0xFF, 0xFF, 0xFF)

# Chaque icône : nom, taille, part du carré occupée par le glyphe, arrondi.
# Les variantes « maskable » gardent une marge : le système peut les rogner.
ICONS = [
    ("favicon.png", 32, 0.74, 0.22),
    ("icons/Icon-192.png", 192, 0.68, 0.22),
    ("icons/Icon-512.png", 512, 0.68, 0.22),
    ("icons/Icon-maskable-192.png", 192, 0.50, 0.0),
    ("icons/Icon-maskable-512.png", 512, 0.50, 0.0),
]


def background(size, radius_ratio):
    """Carré à coins arrondis, dégradé vertical."""
    scale = 4 if size < 256 else 2
    big = size * scale
    gradient = Image.new("RGB", (1, big))
    for y in range(big):
        t = y / (big - 1)
        gradient.putpixel(
            (0, y),
            tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)),
        )
    gradient = gradient.resize((big, big))

    mask = Image.new("L", (big, big), 0)
    radius = round(big * radius_ratio)
    if radius > 0:
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, big - 1, big - 1), radius=radius, fill=255
        )
    else:
        ImageDraw.Draw(mask).rectangle((0, 0, big - 1, big - 1), fill=255)

    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    image.paste(gradient, (0, 0), mask)
    return image, scale


def draw_glyph(image, box, scale):
    """Centre le glyphe optiquement dans l'image, à la taille demandée."""
    big = image.size[0]
    target = big * box
    size = round(target)
    # La hauteur d'un kana est inférieure à celle de la police : on ajuste
    # jusqu'à ce que le tracé réel occupe la part voulue.
    for _ in range(12):
        font = ImageFont.truetype(FONT, size)
        left, top, right, bottom = ImageDraw.Draw(image).textbbox(
            (0, 0), GLYPH, font=font
        )
        height = bottom - top
        if height == 0 or abs(height - target) <= max(1, target * 0.01):
            break
        size = round(size * target / height)

    font = ImageFont.truetype(FONT, size)
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = draw.textbbox((0, 0), GLYPH, font=font)
    x = (big - (right - left)) / 2 - left
    y = (big - (bottom - top)) / 2 - top
    draw.text((x, y), GLYPH, font=font, fill=INK)
    return image


def main():
    if not os.path.exists(FONT):
        raise SystemExit("police absente, lance d'abord tool/build_fonts.py")

    for name, size, box, radius in ICONS:
        image, scale = background(size, radius)
        draw_glyph(image, box, scale)
        image = image.resize((size, size), Image.LANCZOS)
        path = os.path.join(WEB, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.save(path)
        print("%s : %d×%d" % (name, size, size))


if __name__ == "__main__":
    main()
