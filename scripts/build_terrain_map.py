#!/usr/bin/env python3
"""Sample Mappa 2.png at every engine hex and write the derived terrain map."""

import json
import math
from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
IMAGE = Image.open(ROOT / "Mappa 2.png").convert("RGB")
COLS, ROWS = 67, 52
RADIUS = 35.5645
DX, DY = math.sqrt(3.0) * RADIUS, 1.5 * RADIUS
ORIGIN_X, ORIGIN_Y = 24.6, -13.59


def centre(col: int, row: int) -> tuple[float, float]:
    return ORIGIN_X + col * DX + (DX / 2 if row & 1 else 0), ORIGIN_Y + row * DY


def neighbours(col: int, row: int):
    diagonal = ((-1, -1), (0, -1), (-1, 1), (0, 1)) if not row & 1 else ((0, -1), (1, -1), (0, 1), (1, 1))
    for dc, dr in ((-1, 0), (1, 0), *diagonal):
        if 0 <= col + dc < COLS and 0 <= row + dr < ROWS:
            yield col + dc, row + dr


raw: dict[tuple[int, int], str] = {}
for row in range(ROWS):
    for col in range(COLS):
        x, y = centre(col, row)
        if not (0 <= x < IMAGE.width and 0 <= y < IMAGE.height):
            raw[col, row] = "void"
            continue
        pixels = [
            IMAGE.getpixel((px, py))
            for py in range(max(0, int(y - 25)), min(IMAGE.height, int(y + 26)), 3)
            for px in range(max(0, int(x - 25)), min(IMAGE.width, int(x + 26)), 3)
            if (px - x) ** 2 + (py - y) ** 2 < 625
        ]
        total = len(pixels)
        dark = sum(max(rgb) < 85 for rgb in pixels) / total
        sea = sum(b > r * 1.08 and (b > g * .96 or g > r * 1.12) and b > 90 for r, g, b in pixels) / total
        forest = sum(g > r * 1.10 and g > b * .80 and g < 155 and r < 120 for r, g, b in pixels) / total
        red_rock = sum(r > g * 1.18 and r > b * 1.15 and 45 < r < 190 for r, g, b in pixels) / total
        grey_rock = sum(45 < r < 145 and abs(r - g) < 22 and abs(g - b) < 30 for r, g, b in pixels) / total
        brightness = sum(sum(rgb) / 3 for rgb in pixels) / total
        if dark > .42:
            raw[col, row] = "void"
        elif sea > .28:
            raw[col, row] = "sea"
        elif forest > .075:
            raw[col, row] = "forest"
        elif red_rock > .13 or (grey_rock > .34 and brightness < 150):
            raw[col, row] = "mountain"
        else:
            raw[col, row] = "plain"

# Artwork and vortices can satisfy a colour test in one isolated cell. Real
# woods and mountain chains continue into at least one neighbouring hex.
for position, kind in list(raw.items()):
    if kind in ("forest", "mountain") and not any(raw.get(other) == kind for other in neighbours(*position)):
        raw[position] = "plain"

result = {kind: [] for kind in ("sea", "forest", "mountain", "void")}
for (col, row), kind in raw.items():
    if kind in result:
        result[kind].append([col, row])

output = ROOT / "assets" / "data" / "terrain_map.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
print({kind: len(cells) for kind, cells in result.items()})
