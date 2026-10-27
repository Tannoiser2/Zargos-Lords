import cv2, numpy as np, json
T=json.load(open('Tb.json')); fs=sorted(T)
W,H=11191,7616
def mask_of(im):
    m=(im.min(2)<232).astype(np.uint8)
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,np.ones((9,9),np.uint8))
    m[:12,:]=0;m[-12:,:]=0;m[:,:12]=0;m[:,-12:]=0
    return m
data={}
for f in fs:
    im=cv2.imread(f)
    w=cv2.distanceTransform(mask_of(im),cv2.DIST_L2,5)
    w=np.minimum(w,120.0)/120.0
    data[f]=(im,(w**3).astype(np.float32))
out=np.zeros((H,W,3),np.uint8)
SH=800
for y0 in range(0,H,SH):
    h=min(SH,H-y0)
    acc=np.zeros((h,W,3),np.float32); ws=np.zeros((h,W),np.float32)
    for f in fs:
        A=np.array(T[f]); A[1,2]-=y0
        im,w=data[f]
        ww=cv2.warpAffine(w,A,(W,h),flags=cv2.INTER_LINEAR,borderValue=0)
        if ww.max()<=0: continue
        ii=cv2.warpAffine(im,A,(W,h),flags=cv2.INTER_CUBIC)
        acc+=ii.astype(np.float32)*ww[...,None]; ws+=ww
    o=acc/np.maximum(ws,1e-6)[...,None]
    o[ws<1e-6]=(40,26,46)[::-1] if False else (24,30,44)
    out[y0:y0+h]=np.clip(o,0,255).astype(np.uint8)
    print(y0,flush=True)
cv2.imwrite('mosaico.png',out)
cv2.imwrite('mosaico_small.jpg',cv2.resize(out,(1600,int(1600*H/W)),interpolation=cv2.INTER_AREA))
