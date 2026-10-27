import pickle, numpy as np
from scipy import ndimage
from scipy.interpolate import RBFInterpolator
from PIL import Image
X,Y,sx,sy,seaT,warpO=pickle.load(open('reg.pkl','rb'))
pts,disp,w=pickle.load(open('disp.pkl','rb'))
H,W=seaT.shape
# filtro robusto: scarta vettori lontani dalla mediana dei vicini
from scipy.spatial import cKDTree
kd=cKDTree(pts); keep=[]
for i,p in enumerate(pts):
    idx=kd.query_ball_point(p,40)
    med=np.median(disp[idx],0)
    if np.linalg.norm(disp[i]-med)<=3: keep.append(i)
pts,disp=pts[keep],disp[keep]; print(len(pts))
# metà sinistra e destra separate (la fenditura centrale è un taglio della mappa)
field=np.zeros((H,W,2))
yy,xx=np.mgrid[0:H,0:W]
grid=np.c_[xx.ravel(),yy.ravel()].astype(float)
for half in (0,1):
    m=(pts[:,0]<W/2) if half==0 else (pts[:,0]>=W/2)
    f=RBFInterpolator(pts[m],disp[m],kernel='thin_plate_spline',smoothing=50.0,degree=1)
    sel=(grid[:,0]<W/2) if half==0 else (grid[:,0]>=W/2)
    out=np.zeros((len(grid),2)); 
    for k in range(0,sel.sum(),200000):
        pass
    G=grid[sel]; vals=np.concatenate([f(G[i:i+50000]) for i in range(0,len(G),50000)])
    out[sel]=vals
    field.reshape(-1,2)[sel]=out[sel]
pickle.dump(field,open('field.pkl','wb'))
# verifica: rimappa la maschera
dx,dy=field[...,0],field[...,1]
check=ndimage.map_coordinates(warpO,[yy+dy,xx+dx],order=1)
vis=np.stack([check*255,seaT*255,np.zeros_like(seaT)],-1).astype(np.uint8)
Image.fromarray(vis).save('/home/claude/scratch/v/regvis2.png')
print(np.abs(disp).max(0), np.percentile(np.hypot(*disp.T),[50,90]))
