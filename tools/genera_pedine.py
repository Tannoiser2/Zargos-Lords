#!/usr/bin/env python3
"""Genera le facce delle pedine a partire dalle scansioni originali.

Dalle tavole viene ritagliata soltanto l'illustrazione centrale; il fondo
bianco del cartoncino diventa trasparente e la figura viene posata su una
faccia esagonale disegnata ex novo, con i valori ristampati in grande per
restare leggibili anche con la camera lontana dal tabellone.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import math

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "docs" / "original" / "pedine"
OUT = ROOT / "assets" / "units"
FONT = ROOT / "assets" / "fonts" / "Anton-Regular.ttf"
SIZE = 512

COUNTERS = {
    "alati": {"source": "zargos1.jpg", "signore": (690, 147), "falco": (842, 235),
              "fantarcere": (690, 411), "fante": (614, 543), "citta": (690, 851)},
    "cavalieri": {"source": "zargos2.jpg", "signore": (762, 111), "mago": (839, 239),
                  "fantarcere": (762, 289), "fante": (1068, 378), "citta": (685, 850)},
    "draghi": {"source": "zargos3.jpg", "signore": (530, 279), "serpente": (530, 369),
               "lanciafiamme": (530, 459), "fante": (839, 549), "citta": (762, 954)},
    "monaci": {"source": "zargos4.jpg", "signore": (535, 143), "illusionista": (690, 323),
               "cavaliere": (535, 413), "fante": (767, 548), "citta": (535, 855),
               "scomparso": (766, 288)},
}
VALUES = {
    "cavalieri": {"signore": (10, 7), "mago": (2, 5), "fantarcere": (2, 5), "fante": (5, 4)},
    "draghi": {"signore": (6, 5), "serpente": (10, 10), "lanciafiamme": (2, 5), "fante": (3, 5)},
    "alati": {"signore": (8, 15), "falco": (5, 12), "fantarcere": (2, 4), "fante": (4, 5)},
    "monaci": {"signore": (7, 10), "illusionista": (2, 6), "cavaliere": (5, 9), "fante": (4, 5)},
}
COLORS = {"cavalieri": (126, 150, 176), "draghi": (96, 128, 52), "alati": (150, 96, 170), "monaci": (214, 160, 40)}


def hex_points(cx, cy, r, flat=False):
    off = 0 if flat else -90
    return [(cx + r * math.cos(math.radians(60 * i + off)), cy + r * math.sin(math.radians(60 * i + off))) for i in range(6)]


def figura_esagono(sheet, centre):
    """Ritaglia un'intera pedina seguendo il suo contorno esagonale (per i
    segnalini senza valori, come la sparizione dei Monaci)."""
    cx, cy = centre
    r = 40
    crop = sheet.crop((cx - r, cy - r, cx + r, cy + r)).convert("RGBA")
    mask = Image.new("L", crop.size, 0)
    pts = [(r + (r - 5) * math.cos(math.radians(60 * i)), r + (r - 5) * math.sin(math.radians(60 * i)) * 0.95) for i in range(6)]
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    px = crop.load()
    for y in range(crop.height):
        for x in range(crop.width):
            rr, g, b, a = px[x, y]
            light = min(rr, g, b)
            if light > 225:
                px[x, y] = (rr, g, b, 0)
            elif light > 195:
                px[x, y] = (rr, g, b, int(255 * (225 - light) / 30))
    crop.putalpha(ImageChops.multiply(crop.getchannel("A"), mask))
    return crop


def figure(sheet, centre, wide):
    cx, cy = centre
    hw = 50 if wide else 27
    alto = 34 if wide == "basso" else 46
    crop = sheet.crop((cx - hw, cy - alto, cx + hw, cy + 44)).convert("RGBA")
    px = crop.load()
    for y in range(crop.height):
        for x in range(crop.width):
            r, g, b, a = px[x, y]
            light = min(r, g, b)
            if light > 225:
                px[x, y] = (r, g, b, 0)
            elif light > 195:
                px[x, y] = (r, g, b, int(255 * (225 - light) / 30))
    # Tiene soltanto la figura: scarta i numeri originali e i bordi del
    # cartoncino (componenti piccole lontane dal centro o tocchi del bordo).
    from scipy import ndimage
    import numpy as np
    arr = np.array(crop)
    alpha = arr[..., 3] > 40
    lab, n = ndimage.label(alpha)
    h, w = alpha.shape
    keep = np.zeros_like(alpha)
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        area = len(xs)
        cx0 = xs.mean() - w / 2
        cy0 = ys.mean() - h / 2
        touches = xs.min() == 0 or xs.max() == w - 1 or ys.min() == 0 or ys.max() == h - 1
        thin = (ys.max() - ys.min() < 5) or (xs.max() - xs.min() < 3 and area < 40)
        bw = xs.max() - xs.min() + 1
        bh = ys.max() - ys.min() + 1
        sparse = area / (bw * bh) < 0.22 and area < 260
        digit_zone = abs(cx0) > 13 and abs(cy0) < 24 and area < 300
        edge_zone = (abs(cy0) > 30 or abs(cx0) > 30) and area < 200
        if area < 12 or thin or sparse or edge_zone or (touches and area < 400) or digit_zone:
            continue
        keep |= lab == i
    keep = ndimage.binary_dilation(keep, iterations=1)
    arr[..., 3] = np.where(keep, arr[..., 3], 0)
    return Image.fromarray(arr)


def build(faction, kind, sheet, centre):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = SIZE / 2
    col = COLORS[faction]
    d.polygon(hex_points(c, c, 250), fill=(30, 22, 18, 255))
    d.polygon(hex_points(c, c, 240), fill=col + (255,))
    d.polygon(hex_points(c, c, 214), fill=(240, 232, 212, 255))
    wide = kind in ("citta", "serpente", "falco", "cavaliere", "scomparso")
    fig = figura_esagono(sheet, centre) if kind == "scomparso" else figure(sheet, centre, wide)
    scale = 4.9 if kind == "scomparso" else (3.6 if not wide else 3.0)
    fig = fig.resize((int(fig.width * scale), int(fig.height * scale)), Image.Resampling.LANCZOS)
    fig = fig.filter(ImageFilter.UnsharpMask(radius=2, percent=120, threshold=2))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(hex_points(c, c, 188), fill=255)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.alpha_composite(fig, (int(c - fig.width / 2), int(c - fig.height / 2 + 6)))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    img.alpha_composite(layer)
    if kind in VALUES[faction]:
        combat, move = VALUES[faction][kind]
        font = ImageFont.truetype(str(FONT), 92)
        for x in (c - 140, c + 140):
            d.ellipse((x - 58, c + 8 - 62, x + 58, c + 8 + 62), fill=(240, 232, 212, 255))
        for text, x in ((str(combat), c - 140), (str(move), c + 140)):
            d.text((x, c + 8), text, font=font, anchor="mm", fill=(24, 18, 16, 255),
                   stroke_width=7, stroke_fill=(240, 232, 212, 255))
    img.save(OUT / faction / f"{kind}.png", optimize=True)


for faction, entries in COUNTERS.items():
    sheet = Image.open(REF / entries["source"]).convert("RGB")
    (OUT / faction).mkdir(parents=True, exist_ok=True)
    for kind, centre in entries.items():
        if kind != "source":
            build(faction, kind, sheet, centre)
print("pedine generate")
