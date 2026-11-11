#!/usr/bin/env python3
"""Disegna l'icona di Tivu. Concetto: un televisore color argento visto di fronte, con lo schermo scuro e tre barre di
volume che salgono, dal blu al viola. Fondo chiaro, bianco che sfuma appena nel grigio perla, come vetro smerigliato.

Due uscite, con la stessa geometria:
    python3 -I tools/render-icon.py                 Resources/Icon/AppIcon-1024.png (icona classica)
    python3 -I tools/render-icon.py --layers DIR    strati PNG per Icon Composer (Resources/Icon/Tivu.icon/Assets)
Nell'icona Liquid Glass vetro, riflessi e ombre li aggiunge il sistema: gli strati sono forme nette su trasparente.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 3                      # sovracampionamento
N = 1024 * S

BG_TOP = (255, 255, 255)
BG_BOTTOM = (222, 227, 234)
SILVER_TOP = (240, 241, 244)
SILVER_BOTTOM = (172, 178, 187)
SCREEN = (12, 14, 22)
BARS = [(64, 156, 255), (110, 120, 255), (168, 92, 246)]   # blu, indaco, viola


def px(v):
    return int(round(v * S))


def gradient(size, top, bottom):
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        column.putpixel((0, y), tuple(int(round(a + (b - a) * t)) for a, b in zip(top, bottom)))
    return column.resize((w, h))


def shape_mask(draw_fn):
    mask = Image.new("L", (N, N), 0)
    draw_fn(ImageDraw.Draw(mask))
    return mask


# Geometria, in punti su 1024.
TV = (192, 268, 832, 668)          # cornice
SCREEN_BOX = (216, 292, 808, 644)  # schermo
NECK = (472, 668, 552, 716)
FOOT = (352, 712, 672, 744)
BAR_W, BAR_GAP, BAR_BASE = 84, 44, 588
BAR_HEIGHTS = [96, 164, 232]


def tv_mask(d):
    d.rounded_rectangle([px(v) for v in TV], radius=px(44), fill=255)
    d.rectangle([px(v) for v in NECK], fill=255)
    d.rounded_rectangle([px(v) for v in FOOT], radius=px(16), fill=255)


def screen_mask(d):
    d.rounded_rectangle([px(v) for v in SCREEN_BOX], radius=px(26), fill=255)


def bar_boxes():
    total = 3 * BAR_W + 2 * BAR_GAP
    x = 512 - total / 2
    for h in BAR_HEIGHTS:
        yield (x, BAR_BASE - h, x + BAR_W, BAR_BASE)
        x += BAR_W + BAR_GAP


def layer_tv():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    img.paste(gradient((N, N), SILVER_TOP, SILVER_BOTTOM), (0, 0), shape_mask(tv_mask))
    return img


def layer_screen():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    img.paste(Image.new("RGB", (N, N), SCREEN), (0, 0), shape_mask(screen_mask))
    return img


def layer_bars():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for box, color in zip(bar_boxes(), BARS):
        d.rounded_rectangle([px(v) for v in box], radius=px(22), fill=color + (255,))
    return img


def finish(img):
    return img.resize((1024, 1024), Image.LANCZOS)


def classic():
    """L'icona intera: quadrato arrotondato con il margine delle icone macOS, ombra morbida sotto il televisore."""
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    plate = shape_mask(lambda d: d.rounded_rectangle([px(100), px(100), px(924), px(924)], radius=px(185), fill=255))
    canvas.paste(gradient((N, N), BG_TOP, BG_BOTTOM), (0, 0), plate)
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (N, N), (20, 30, 50, 90)), (0, px(14)), shape_mask(tv_mask))
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(18)))
    clipped = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    clipped.paste(shadow, (0, 0), plate)
    canvas = Image.alpha_composite(canvas, clipped)
    for layer in (layer_tv(), layer_screen(), layer_bars()):
        canvas = Image.alpha_composite(canvas, layer)
    return finish(canvas)


if __name__ == "__main__":
    if "--layers" in sys.argv:
        out = sys.argv[sys.argv.index("--layers") + 1]
        os.makedirs(out, exist_ok=True)
        # Negli strati il disegno riempie di più il quadrato: il margine lo mette il sistema.
        for name, layer in (("tv", layer_tv()), ("screen", layer_screen()), ("bars", layer_bars())):
            finish(layer).save(os.path.join(out, name + ".png"))
        print("Strati in", out)
    else:
        path = os.path.join(ROOT, "Resources", "Icon", "AppIcon-1024.png")
        classic().save(path)
        print("Icona in", path)
