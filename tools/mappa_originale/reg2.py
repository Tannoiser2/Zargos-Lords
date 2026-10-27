import pickle, numpy as np
from scipy import ndimage
from scipy.interpolate import RBFInterpolator
from PIL import Image
X,Y,sx,sy,seaT,warpO=pickle.load(open('reg.pkl','rb'))
H,W=seaT.shape
B=28; STEP=12; S=14
pts=[];disp=[];wts=[]
for cy in range(B,H-B,STEP):
  for cx in range(B,W-B,STEP):
    t=seaT[cy-B:cy+B,cx-B:cx+B]
    if t.std()<0.25: continue
    best=None
    for dy in range(-S,S+1):
      for dx in range(-S,S+1):
        y0=cy-B+dy;x0=cx-B+dx
        if y0<0 or x0<0 or y0+2*B>H or x0+2*B>W: continue
        o=warpO[y0:y0+2*B,x0:x0+2*B]
        if o.std()<0.15: continue
        c=np.corrcoef(t.ravel(),o.ravel())[0,1]
        if best is None or c>best[0]: best=(c,dx,dy)
    if best and best[0]>0.55:
        pts.append((cx,cy)); disp.append((best[1],best[2])); wts.append(best[0])
pts=np.array(pts,float); disp=np.array(disp,float)
print(len(pts))
pickle.dump((pts,disp,np.array(wts)),open('disp.pkl','wb'))
