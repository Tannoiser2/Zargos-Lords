"""Basi delle miniature 3D: esagono avorio con il bordo del colore del popolo e
i soli valori (combattimento a sinistra, movimento a destra), senza disegno."""
import os, re, math
from PIL import Image, ImageDraw, ImageFont
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
COL = {'cavalieri': (122, 150, 184), 'draghi': (111, 143, 55), 'alati': (139, 92, 170),
       'monaci': (214, 170, 40), 'amazzoni': (196, 70, 60), 'aracnidi': (122, 154, 88), 'magia': (150, 60, 40)}
testo = open(os.path.join(R, 'scripts/core/regole.gd'), encoding='utf-8').read()
pezzi = {}
popolo = None
for riga in testo.split('const PEZZI', 1)[1].split('\n}', 1)[0].split('\n'):
    m = re.match(r'\s*"(\w+)": \{$', riga)
    if m:
        popolo = m.group(1).lower()
        continue
    m = re.match(r'\s*"(\w+)": \{"nome": "[^"]*", "c": (\d+), "m": (\d+)', riga)
    if m and popolo:
        pezzi[(popolo, m.group(1))] = (int(m.group(2)), int(m.group(3)))
font = ImageFont.truetype(os.path.join(R, 'assets/fonts/Anton-Regular.ttf'), 120)
S = 512; c = S / 2
def esagono(r):
    return [(c + r * math.cos(math.radians(60 * i - 90)), c + r * math.sin(math.radians(60 * i - 90))) for i in range(6)]
for (pop, tipo), (cv, mv) in pezzi.items():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon(esagono(250), fill=(30, 22, 18, 255))
    d.polygon(esagono(244), fill=COL[pop] + (255,))
    d.polygon(esagono(222), fill=(246, 242, 232, 255))
    # leggero anello interno dove poggia la miniatura
    d.ellipse((c - 92, c - 92, c + 92, c + 92), outline=COL[pop] + (90,), width=5)
    for v, x in ((cv, c - 150), (mv, c + 150)):
        d.text((x, c), str(v), font=font, anchor='mm', fill=(25, 20, 16, 255))
    os.makedirs(os.path.join(R, 'assets/units_basi', pop), exist_ok=True)
    im.save(os.path.join(R, 'assets/units_basi', pop, tipo + '.png'))
# basi delle città: senza valori
for pop in COL:
    if pop == 'magia':
        continue
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon(esagono(250), fill=(30, 22, 18, 255))
    d.polygon(esagono(244), fill=COL[pop] + (255,))
    d.polygon(esagono(222), fill=(222, 210, 186, 255))
    im.save(os.path.join(R, 'assets/units_basi', pop, 'citta.png'))
print(len(pezzi), 'basi')
