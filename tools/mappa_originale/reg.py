exec(open('warp2.py').read().split('offs=np.stack')[0])
import pickle
r_,g_,b_=SRC[...,0],SRC[...,1],SRC[...,2]
seaO=((b_>r_+25)&(b_>140)).astype(float)
seaO=ndimage.gaussian_filter(seaO,1.0)
Image.fromarray((seaO*255).astype(np.uint8)).save('/home/claude/scratch/v/seaO.png')
# maschera TTS a risoluzione 1/4 (1024x688) dai dati esagonali
S=4.0
Ht,Wt=int(2749/S)+1,int(4096/S)
yy,xx=np.mgrid[0:Ht,0:Wt].astype(float)
X=xx*S+S/2; Y=yy*S+S/2
seaT=np.zeros((Ht,Wt))
# esagono più vicino
r0=np.round((Y-OY)/DY).astype(int)
best=np.full(X.shape,1e18); hc=np.zeros(X.shape,int); hr=np.zeros(X.shape,int)
for dr in (-1,0,1):
    rr=r0+dr
    off=np.where(rr%2==1,DX/2,0.0)
    cc=np.round((X-OX-off)/DX).astype(int)
    for dc in (-1,0,1):
        c2=cc+dc
        cxp=OX+c2*DX+off; cyp=OY+rr*DY
        d=(X-cxp)**2+(Y-cyp)**2
        m=d<best; best[m]=d[m]; hc[m]=c2[m]; hr[m]=rr[m]
inside=(hc>=0)&(hc<COLS)&(hr>=0)&(hr<ROWS)
T=np.array([list(row) for row in terr])
ch=np.full(X.shape,' ')
ch[inside]=T[hr[inside],hc[inside]]
seaT=np.isin(ch,['~','b']).astype(float)
seaT=ndimage.gaussian_filter(seaT,1.0)
# campionamento dell'originale nel riferimento TTS con gli affini iniziali
def sample_src(Xs,Ys,dx=None,dy=None):
    out=np.zeros(Xs.shape)
    q=np.where(Xs>=2048,2,np.where(Ys<1375,0,1))
    sx=np.zeros(Xs.shape); sy=np.zeros(Xs.shape)
    for k,name in enumerate(['NW','SW','R']):
        M=AFF[name]; m=q==k
        sx[m]=Xs[m]*M[0,0]+Ys[m]*M[1,0]+M[2,0]; sy[m]=Xs[m]*M[0,1]+Ys[m]*M[1,1]+M[2,1]
    return sx,sy
sx,sy=sample_src(X,Y)
warpO=ndimage.map_coordinates(seaO,[sy,sx],order=1)
pickle.dump((X,Y,sx,sy,seaT,warpO),open('reg.pkl','wb'))
vis=np.stack([warpO*255,seaT*255,np.zeros_like(seaT)],-1).astype(np.uint8)
Image.fromarray(vis).save('/home/claude/scratch/v/regvis.png')
