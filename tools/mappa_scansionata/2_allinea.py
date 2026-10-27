import cv2, numpy as np, json, itertools
aff=json.load(open('aff.json')); S=1/0.297
fs=sorted(aff); n=len(fs)
T0={f:S*np.array(aff[f]) for f in fs}
def mask_of(im):
    m=(im.min(2)<232).astype(np.uint8)
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,np.ones((9,9),np.uint8))
    m[:12,:]=0;m[-12:,:]=0;m[:,:12]=0;m[:,-12:]=0
    return m
sift=cv2.SIFT_create(nfeatures=30000)
k=0.5; feats={}
for f in fs:
    im=cv2.imread(f); sm=cv2.resize(im,None,fx=k,fy=k,interpolation=cv2.INTER_AREA)
    kp,d=sift.detectAndCompute(cv2.cvtColor(sm,cv2.COLOR_BGR2GRAY),cv2.resize(mask_of(im),None,fx=k,fy=k))
    feats[f]=(np.float32([p.pt for p in kp])/k,d)
def apply(T,p): return p@T[:,:2].T+T[:,2]
# predicted footprint polygons for overlap test
corn=np.float32([[0,0],[2480,0],[2480,3507],[0,3507]])
pairs=[]
bf=cv2.BFMatcher()
for i,j in itertools.combinations(range(n),2):
    a,b=fs[i],fs[j]
    pa=apply(T0[a],corn); pb=apply(T0[b],corn)
    inter,_=cv2.intersectConvexConvex(pa.astype(np.float32),pb.astype(np.float32))
    if inter<2e5: continue
    pa_,da=feats[a]; pb_,db=feats[b]
    # restrict to points predicted inside the other footprint
    m=bf.knnMatch(da,db,k=2)
    good=[x for x,y in (z for z in m if len(z)==2) if x.distance<0.8*y.distance]
    if len(good)<15: print(a,b,'pochi',len(good)); continue
    src=pa_[[g.queryIdx for g in good]]; dst=pb_[[g.trainIdx for g in good]]
    # consistency with prior: predicted positions close
    d=np.linalg.norm(apply(T0[a],src)-apply(T0[b],dst),axis=1)
    sel=d<700
    src,dst=src[sel],dst[sel]
    if len(src)<12: print(a,b,'incoerenti'); continue
    A,inl=cv2.estimateAffinePartial2D(src,dst,method=cv2.RANSAC,ransacReprojThreshold=3,maxIters=20000)
    inl=inl.ravel().astype(bool)
    if inl.sum()<15: print(a,b,'inl',inl.sum()); continue
    s_,d_=src[inl],dst[inl]
    if len(s_)>400:
        idx=np.random.default_rng(0).choice(len(s_),400,replace=False); s_,d_=s_[idx],d_[idx]
    pairs.append((i,j,s_,d_)); print(a,b,'ok',int(inl.sum()))
# least squares: params per scan [a,b,tx,ty]
rows=[];rhs=[]
def r_pt(i,p,sign):
    x,y=p; r1=np.zeros(4*n); r2=np.zeros(4*n)
    r1[4*i:4*i+4]=[x,-y,1,0]; r2[4*i:4*i+4]=[y,x,0,1]
    return sign*r1,sign*r2
for i,j,s_,d_ in pairs:
    for p,q in zip(s_,d_):
        a1,a2=r_pt(i,p,1); b1,b2=r_pt(j,q,-1)
        rows+= [a1+b1,a2+b2]; rhs+=[0,0]
# anchor to prior (weak)
wA=0.05
grid=np.float32([[x,y] for x in (200,1240,2280) for y in (300,1750,3200)])
for i,f in enumerate(fs):
    for p in grid:
        t=apply(T0[f],p[None])[0]; a1,a2=r_pt(i,p,1)
        rows+=[wA*a1,wA*a2]; rhs+=[wA*t[0],wA*t[1]]
A=np.array(rows); bv=np.array(rhs)
x,*_=np.linalg.lstsq(A,bv,rcond=None)
T={}
for i,f in enumerate(fs):
    a,b,tx,ty=x[4*i:4*i+4]; T[f]=np.array([[a,-b,tx],[b,a,ty]])
res=[]
for i,j,s_,d_ in pairs:
    e=np.linalg.norm(apply(T[fs[i]],s_)-apply(T[fs[j]],d_),axis=1); res.append((fs[i],fs[j],float(np.median(e)),float(np.percentile(e,90))))
for r in res: print('residuo',r)
json.dump({f:T[f].tolist() for f in fs},open('Tb.json','w'))
