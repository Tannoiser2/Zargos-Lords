#!/usr/bin/env python3
"""Ritaglia i disegni dei Signori dai fogli delle pedine per il menu."""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "original" / "pedine"
OUT = ROOT / "assets" / "ui" / "signori"
# foglio, riquadro di ricerca (x0, y0, x1, y1)
SIGNORI = {
    "alati": ("zargos1.jpg", (175, 245, 315, 448)),
    "cavalieri": ("zargos2.jpg", (190, 205, 310, 408)),
    "draghi": ("zargos3.jpg", (150, 160, 325, 380)),
    "monaci": ("zargos4.jpg", (160, 172, 295, 385)),
    "amazzoni": ("zargos2-amazzoni.jpg", (200, 0, 320, 128)),
    "aracnidi": ("zargos2-aracnidi.jpg", (195, 0, 315, 128)),
}

OUT.mkdir(parents=True, exist_ok=True)
for nome, (foglio, box) in SIGNORI.items():
    im = Image.open(SRC / foglio).convert("RGB").crop(box)
    a = np.asarray(im).astype(int)
    non_bianco = a.min(axis=2) < 215
    non_bianco = ndimage.binary_closing(non_bianco, iterations=4)
    lab, n = ndimage.label(non_bianco)
    sizes = ndimage.sum(non_bianco, lab, range(1, n + 1))
    figura = lab == (np.argmax(sizes) + 1)
    figura = ndimage.binary_fill_holes(figura)
    ys, xs = np.nonzero(figura)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    rgba = np.dstack([a, np.zeros(a.shape[:2], int)]).astype(np.uint8)
    lum = a.min(axis=2)
    alfa = np.clip((240 - lum) * 255 / 40, 0, 255)
    interno = ndimage.binary_erosion(figura, iterations=2)
    alfa = np.where(interno, 255, np.where(ndimage.binary_dilation(figura, iterations=1), alfa, 0))
    rgba[..., 3] = alfa
    ritaglio = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
    scala = 420 / ritaglio.height
    ritaglio = ritaglio.resize((int(ritaglio.width * scala), 420), Image.LANCZOS)
    ritaglio.save(OUT / f"{nome}.png", optimize=True)
    print(nome, (x0 + box[0], y0 + box[1], x1 + box[0], y1 + box[1]))
