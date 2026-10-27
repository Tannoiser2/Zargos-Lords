import math, json, sys
from PIL import Image, ImageDraw
Image.MAX_IMAGE_PIXELS=None
R=35.55; DX=math.sqrt(3)*R; DY=1.5*R; OX,OY=46.0,94.0-2*1.5*35.55
COLS,ROWS=66,53
def centre(c,r): return OX+c*DX+(DX/2 if r&1 else 0), OY+r*DY
def hexpoly(x,y,rad=R):
    return [(x+rad*math.cos(math.radians(60*i-90)), y+rad*math.sin(math.radians(60*i-90))) for i in range(6)]
