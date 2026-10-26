#!/usr/bin/env python3
"""Rebuild the playable counter faces from the four original counter sheets."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
SIZE = 256

# Pixel centres measured on the original scans.  A complete counter is about
# 120 x 96 pixels; choosing isolated examples avoids artwork from neighbours.
COUNTERS = {
    "alati": {
        "source": "zargos1.jpg",
        "signore": (690, 147), "falco": (842, 235),
        "fantarcere": (690, 411), "fante": (614, 543), "citta": (690, 851),
    },
    "cavalieri": {
        "source": "zargos2.jpg",
        "signore": (762, 111), "mago": (839, 239),
        "fantarcere": (762, 289), "fante": (1068, 378), "citta": (685, 850),
    },
    "draghi": {
        "source": "zargos3.jpg",
        "signore": (530, 279), "serpente": (530, 369),
        "lanciafiamme": (530, 459), "fante": (839, 549), "citta": (762, 954),
    },
    "monaci": {
        "source": "zargos4.jpg",
        "signore": (535, 143), "illusionista": (690, 323),
        "cavaliere": (535, 413), "fante": (767, 548), "citta": (535, 855),
    },
}


def extract(source: Image.Image, centre: tuple[int, int]) -> Image.Image:
    cx, cy = centre
    crop = source.crop((cx - 62, cy - 49, cx + 62, cy + 49)).convert("RGBA")
    mask = Image.new("L", crop.size, 0)
    # Un piccolo margine interno elimina i frammenti delle pedine adiacenti
    # presenti nelle scansioni a nido d'ape senza tagliare l'illustrazione.
    ImageDraw.Draw(mask).polygon([(33, 4), (91, 4), (119, 49), (91, 94), (33, 94), (5, 49)], fill=255)
    crop.putalpha(mask)
    crop.thumbnail((246, 220), Image.Resampling.LANCZOS)
    crop = crop.filter(ImageFilter.UnsharpMask(radius=1.2, percent=135, threshold=3))
    result = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    result.alpha_composite(crop, ((SIZE - crop.width) // 2, (SIZE - crop.height) // 2))
    return result


for faction, entries in COUNTERS.items():
    source = Image.open(ROOT / entries["source"])
    output_dir = ROOT / "assets" / "units" / faction
    for name, centre in entries.items():
        if name == "source":
            continue
        extract(source, centre).save(output_dir / f"{name}.png", optimize=True)
