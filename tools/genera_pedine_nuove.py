"""Facce delle pedine nella nuova grafica (docs/nuova_grafica): ritaglia gli
esagoni piatti dei fogli, toglie la cornice grigia e li riporta su un esagono
a punta in alto con il bordo del colore del popolo (assets/units_nuove)."""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, json, math, os, sys
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..')
A=os.path.join(R,'docs/nuova_grafica')+'/'
OUT=os.path.join(R,'assets/units_nuove')
res=json.load(open(A+'esagoni.json'))
COL={'cavalieri':(122,150,184),'draghi':(111,143,55),'alati':(139,92,170),'monaci':(214,170,40),'amazzoni':(196,70,60),'aracnidi':(122,154,88)}
def hexpts(cx,cy,r,rot):
    return [(cx+r*math.cos(math.radians(60*i+rot)), cy+r*math.sin(math.radians(60*i+rot))) for i in range(6)]
S=512;c=S/2
fig=[]
for f,lst in res.items():
    f0=f
    src=Image.open(A+f+'.png').convert('RGB')
    for pop,tipo,cx,cy,R in lst:
        k=0.95
        # maschera esagono piatto interno
        box=(int(cx-R),int(cy-R),int(cx+R),int(cy+R))
        crop=src.crop(box)
        m=Image.new('L',crop.size,0)
        ImageDraw.Draw(m).polygon(hexpts(R,R,R*k,0),fill=255)
        m=m.filter(ImageFilter.GaussianBlur(1.5))
        # pulizia: bianco fuori dalla maschera
        bianco=Image.new('RGB',crop.size,(250,248,242))
        # sbianca il fondo quasi bianco a un unico tono
        a=np.array(crop).astype(int)
        quasi=(a.min(-1)>232)
        a[quasi]=(250,248,242)
        # cornice grigia: toni neutri nella fascia esterna
        yy,xx=np.mgrid[0:a.shape[0],0:a.shape[1]]
        dx=np.abs(xx-R); dy=np.abs(yy-R)
        # distanza esagonale (piatto): max(dy/0.866, (dx*0.5+dy*0.866)/0.866)
        hd=np.maximum(dy/0.866,(dx+dy/1.732)) / R
        sat=a.max(-1)-a.min(-1)
        cor=((hd>0.8)&(sat<45)&(a.mean(-1)>60))|((hd>0.7)&(sat<40)&(a.mean(-1)>140))
        a[cor]=(250,248,242)
        from scipy import ndimage as nd
        nonw=a.min(-1)<238
        lab,n=nd.label(nonw)
        if n:
            mn=nd.minimum(hd,lab,index=np.arange(1,n+1))
            via=np.zeros(n+1,bool); via[1:]=np.array(mn)>0.83
            a[via[lab]]=(250,248,242)
        crop=Image.fromarray(a.astype('uint8'))
        crop=Image.composite(crop,bianco,m)
        # scala: R*k -> 236 px
        sc=184.0/(R*0.86)
        crop=crop.resize((int(crop.width*sc),int(crop.height*sc)),Image.LANCZOS)
        face=Image.new('RGBA',(S,S),(0,0,0,0))
        d=ImageDraw.Draw(face)
        col=COL[pop]
        d.polygon(hexpts(c,c,250,-90),fill=(30,22,18,255))
        d.polygon(hexpts(c,c,244,-90),fill=col+(255,))
        d.polygon(hexpts(c,c,226,-90),fill=(250,248,242,255))
        inner=Image.new('L',(S,S),0)
        ImageDraw.Draw(inner).polygon(hexpts(c,c,224,-90),fill=255)
        tmp=Image.new('RGBA',(S,S),(0,0,0,0))
        tmp.paste(crop,(int(c-crop.width/2),int(c-crop.height/2)))
        tmp.putalpha(Image.fromarray(np.minimum(np.array(tmp.split()[3]),np.array(inner))))
        face.alpha_composite(tmp)
        os.makedirs(f'{OUT}/{pop}',exist_ok=True)
        face.save(f'{OUT}/{pop}/{tipo}.png')
        # figura per Meshy: senza numeri (solo fascia centrale)
        fig.append((pop,tipo))
print(len(fig))

# Il segnalino di sparizione dei Monaci non porta valori.
from scipy import ndimage as nd
p=OUT+'/monaci/scomparso.png'
a=np.array(Image.open(p))
dark=(a[...,:3].max(-1)<80)&(a[...,3]>0)
lab,n=nd.label(nd.binary_dilation(dark,iterations=2))
for i,sl in enumerate(nd.find_objects(lab)):
    x0,x1=sl[1].start,sl[1].stop; y0,y1=sl[0].start,sl[0].stop
    if (x1<200 or x0>312) and 180<y0<300 and (y1-y0)>30:
        m=lab[sl]==i+1
        sub=a[sl]; sub[m]=(250,248,242,255)
Image.fromarray(a).save(p)
