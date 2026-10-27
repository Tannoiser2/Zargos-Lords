import pickle, numpy as np, math
from scipy import ndimage
from PIL import Image, ImageDraw
Image.MAX_IMAGE_PIXELS=None
from grid import *
SRC=np.asarray(Image.open('/home/claude/zargos-lords/docs/original/immagini/zargos-carte.jpg').convert('RGB')).astype(np.float32)
field=pickle.load(open('field.pkl','rb'))
AFF={'NW':np.array([[0.4321,0.0017],[0.0072,0.4432],[-46.9432,-41.6305]]),
     'SW':np.array([[0.4276,0.0028],[0.0242,0.3967],[-78.2533,33.8593]]),
     'R':np.array([[0.4229,-0.0002],[-0.0058,0.4372],[-13.3481,-36.5103]])}
OUTW,OUTH=3072,2062
sc=4096/OUTW
yy,xx=np.mgrid[0:OUTH,0:OUTW].astype(np.float32)
X=(xx+0.5)*sc; Y=(yy+0.5)*sc
fx=ndimage.map_coordinates(field[...,0],[Y/4-0.5,X/4-0.5],order=1,mode='nearest')
fy=ndimage.map_coordinates(field[...,1],[Y/4-0.5,X/4-0.5],order=1,mode='nearest')
Xd=X+fx*4; Yd=Y+fy*4
q=np.where(X>=2048,2,np.where(Yd<1375,0,1))
sx=np.zeros_like(X); sy=np.zeros_like(X)
for k,n in enumerate(['NW','SW','R']):
    M=AFF[n]; m=q==k
    sx[m]=Xd[m]*M[0,0]+Yd[m]*M[1,0]+M[2,0]; sy[m]=Xd[m]*M[0,1]+Yd[m]*M[1,1]+M[2,1]
out=np.zeros((OUTH,OUTW,3),np.float32)
for c in range(3):
    out[...,c]=ndimage.map_coordinates(SRC[...,c],[sy,sx],order=3,mode='nearest')
img=Image.fromarray(np.clip(out,0,255).astype(np.uint8))
img=img.filter(__import__('PIL.ImageFilter',fromlist=['x']).UnsharpMask(radius=2,percent=60,threshold=2))
img.save('/home/claude/scratch/mappa_originale.jpg',quality=90)
# controllo: reticolo TTS sopra
d=ImageDraw.Draw(img)
for r in range(ROWS):
  for c in range(COLS):
    x,y=centre(c,r)
    d.polygon([(px/sc,py/sc) for px,py in hexpoly(x,y)],outline=(255,0,0))
img.save('/home/claude/scratch/mappa_originale_griglia.png')
for n,box in [('a',(300,1300,1100,1800)),('b',(300,300,1100,800)),('c',(1900,300,2700,800)),('d',(1900,1300,2700,1800)),('e',(200,1700,1000,2050))]:
    img.crop(box).save('/home/claude/scratch/v/mo_%s.png'%n)
