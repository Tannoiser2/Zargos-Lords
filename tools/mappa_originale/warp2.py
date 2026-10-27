from grid import *
import numpy as np, json, pickle, time
from scipy import ndimage
SRC=np.asarray(Image.open('/home/claude/zargos-lords/docs/original/immagini/zargos-carte.jpg').convert('RGB')).astype(float)
G=SRC.mean(2)
line=np.abs(ndimage.gaussian_filter(G,0.7)-ndimage.gaussian_filter(G,2.2))
line=np.minimum(line,12)
H,W=G.shape
AFF={'NW':np.array([[0.4321,0.0017],[0.0072,0.4432],[-46.9432,-41.6305]]),
     'SW':np.array([[0.4276,0.0028],[0.0242,0.3967],[-78.2533,33.8593]]),
     'R':np.array([[0.4229,-0.0002],[-0.0058,0.4372],[-13.3481,-36.5103]])}
def quad(x,y):
    if x>=2048: return 'R'
    return 'NW' if y<1375 else 'SW'
board=json.load(open('/home/claude/zargos-lords/assets/data/board.json'))
terr=board['terrain']
# punti sugli spigoli
cells=[(c,r) for r in range(ROWS) for c in range(COLS) if terr[r][c]!=' ']
ts=np.array([0.2,0.35,0.5,0.65,0.8])
def edge_points(c,r):
    x,y=centre(c,r); out=[]
    for s in range(6):
        a=math.radians(60*s-90); b=math.radians(60*s-30)
        for t in ts: out.append((x+R*((1-t)*math.cos(a)+t*math.cos(b)), y+R*((1-t)*math.sin(a)+t*math.sin(b))))
    return out
E={h:np.array(edge_points(*h)) for h in cells}
def to_src(P):
    out=np.zeros_like(P)
    for i,(x,y) in enumerate(P):
        M=AFF[quad(x,y)]; out[i]=np.array([x,y,1.0])@M
    return out
ES={h:to_src(E[h]) for h in cells}
offs=np.stack(np.meshgrid(np.arange(-9,9.1,1.0),np.arange(-9,9.1,1.0)),-1).reshape(-1,2)
anch=[]
STEP=3
for r0 in range(1,ROWS,STEP):
  for c0 in range(1,COLS,STEP):
    hs=[(c,r) for r in range(r0-4,r0+5) for c in range(c0-4,c0+5) if (c,r) in ES]
    if len(hs)<25: continue
    xc,yc=centre(c0,r0)
    if not any(abs(c-c0)<=1 and abs(r-r0)<=1 for c,r in hs): continue
    q=quad(xc,yc)
    hs=[h for h in hs if quad(*centre(*h))==q]
    if len(hs)<25: continue
    P=np.concatenate([ES[h] for h in hs])
    xs=P[:,0][None,:]+offs[:,0][:,None]; ys=P[:,1][None,:]+offs[:,1][:,None]
    v=ndimage.map_coordinates(line,[ys.ravel(),xs.ravel()],order=1,mode='constant').reshape(xs.shape)
    sc=v.mean(1)
    k=np.argmax(sc); base=sc[len(offs)//2]
    anch.append(dict(p=(xc,yc),q=q,off=tuple(offs[k]),gain=float(sc[k]-base),best=float(sc[k]),srt=float(np.sort(sc)[-1]-np.median(sc))))
pickle.dump(anch,open('anch2.pkl','wb'))
for a in anch: print(a['q'],[round(x) for x in a['p']],a['off'],round(a['gain'],2),round(a['srt'],2))
