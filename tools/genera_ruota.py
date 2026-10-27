#!/usr/bin/env python3
"""Genera le texture delle ruote originali (combattimenti e visioni; tiri) dalle fotografie.

- ruota_disco.png: il disco girevole (IMG_6186), ritagliato attorno al rivetto.
- ruota_coperchio.png: la metà superiore del cartoncino col calendario
  (IMG_6188), riportata nelle coordinate del disco e con la finestra a T
  resa trasparente.

Le misure (centri dei rivetti, raggi delle fasce) sono state prese sulle
fotografie srotolate in coordinate polari.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
FOTO = ROOT / "docs" / "original" / "wheels"
OUT = ROOT / "assets" / "ui"

R_DISCO = 1560          # raggio di lavoro, in pixel della foto del disco
LATO = 1024             # lato della texture del disco
SCALA = LATO / (2 * R_DISCO)

# Disco: rivetto e raggio del bordo nella foto IMG_6186.
DC = (1515.0, 1533.0)
R_BORDO = 1512.0
# Coperchio: rivetto in IMG_6188 e corrispondenza radiale con il disco
# (le linee delle fasce del coperchio coincidono con gli anelli del disco).
CC = (1470.0, 1419.0)
A_RAD, B_RAD = 964.0 / 880.0, -23.3


def disco(foto="IMG_6186.jpg", dc=DC, r_bordo=R_BORDO, nome="ruota_disco.png"):
    src = np.asarray(Image.open(FOTO / foto).convert("RGB")).astype(np.float32)
    yy, xx = np.mgrid[0:LATO, 0:LATO].astype(np.float32)
    dx = (xx + 0.5) / SCALA - R_DISCO
    dy = (yy + 0.5) / SCALA - R_DISCO
    sx, sy = dc[0] + dx, dc[1] + dy
    out = np.zeros((LATO, LATO, 4), np.float32)
    for k in range(3):
        out[..., k] = ndimage.map_coordinates(src[..., k], [sy, sx], order=1, mode="nearest")
    r = np.hypot(dx, dy)
    out[..., 3] = np.clip((r_bordo - r) * SCALA * 1.5, 0, 1) * 255
    Image.fromarray(out.astype(np.uint8), "RGBA").save(OUT / nome, optimize=True)


def coperchio(foto="IMG_6188.jpg", cc=CC, a_rad=A_RAD, b_rad=B_RAD, r_bordo=1395.0, ampiezza=24, nome="ruota_coperchio.png"):
    src = np.asarray(Image.open(FOTO / foto).convert("RGB")).astype(np.float32)
    alto = int(LATO * 0.62)
    yy, xx = np.mgrid[0:alto, 0:LATO].astype(np.float32)
    dx = (xx + 0.5) / SCALA - R_DISCO
    dy = (yy + 0.5) / SCALA - R_DISCO
    rd = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    rc = (rd - b_rad) / a_rad
    sx, sy = cc[0] + rc * np.cos(th), cc[1] + rc * np.sin(th)
    out = np.zeros((alto, LATO, 4), np.float32)
    for k in range(3):
        out[..., k] = ndimage.map_coordinates(src[..., k], [sy, sx], order=1, mode="nearest")
    rgb = out[..., :3]
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    # Bordo del cartoncino.
    alfa = np.clip((r_bordo - rc) * SCALA * 1.5, 0, 1)
    # Finestra a T: zona chiara e poco satura vicino alla verticale.
    ang = np.degrees(th) + 90.0
    zona = (np.abs(ang) < ampiezza) & (rc < 1440) & (rc > 120)
    chiaro = lum > 165
    chiaro = ndimage.binary_opening(chiaro, iterations=2)
    finestra = zona & chiaro
    lab, n = ndimage.label(finestra)
    if n:
        sizes = ndimage.sum(finestra, lab, range(1, n + 1))
        finestra = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 1500])
    finestra = ndimage.binary_fill_holes(finestra)
    finestra = ndimage.binary_dilation(finestra, iterations=2)
    morbido = ndimage.gaussian_filter(finestra.astype(np.float32), 0.8)
    alfa = alfa * (1.0 - morbido)
    out[..., 3] = alfa * 255
    Image.fromarray(out.astype(np.uint8), "RGBA").save(OUT / nome, optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    disco()
    coperchio()
    # Ruota dei tiri: fiamme (metà superiore) e frecce (metà inferiore) sul
    # disco IMG_6185, cartoncino con le distanze in IMG_6187.
    disco("IMG_6185.jpg", (1521.0, 1512.0), 1510.0, "ruota_tiri_disco.png")
    coperchio("IMG_6187.jpg", (1520.0, 1507.5), 1.01, 0.0, 1488.0, 45, "ruota_tiri_coperchio.png")
    print("ruota generata")


def allarga_finestra(nome, semi=6.2):
    """Allarga la fessura verticale del cartoncino fino a ±semi gradi, così
    le scritte lunghe (MAX-2, MAX-3…) si leggono per intero."""
    im = np.asarray(Image.open(OUT / nome)).copy()
    h, w = im.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx, dy = xx + 0.5 - LATO / 2, yy + 0.5 - LATO / 2
    r = np.hypot(dx, dy) / SCALA
    ang = np.degrees(np.arctan2(dy, dx)) + 90.0
    aperto = im[..., 3] < 100
    vicino = np.abs(ang) < 20
    # raggi in cui la fessura esiste già
    righe = np.round(r).astype(int)
    con_fessura = np.zeros(int(r.max()) + 2, bool)
    con_fessura[np.unique(righe[aperto & vicino])] = True
    con_fessura = ndimage.binary_erosion(ndimage.binary_closing(con_fessura, iterations=20), iterations=6)
    nuovo = vicino & (np.abs(ang) < semi) & con_fessura[righe]
    nuovo = ndimage.gaussian_filter(nuovo.astype(np.float32), 0.8)
    im[..., 3] = (im[..., 3] * (1.0 - nuovo)).astype(np.uint8)
    Image.fromarray(im).save(OUT / nome, optimize=True)


if __name__ == "__main__":
    allarga_finestra("ruota_coperchio.png")
    allarga_finestra("ruota_tiri_coperchio.png")
