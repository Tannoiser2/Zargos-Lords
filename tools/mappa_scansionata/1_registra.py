import cv2, numpy as np, glob, json
ref=cv2.imread('/home/claude/scratch/psd.png')  # 3324x2262
REFS=1.0
sift=cv2.SIFT_create(nfeatures=40000)
gr=cv2.cvtColor(ref,cv2.COLOR_BGR2GRAY)
kr,dr=sift.detectAndCompute(gr,None)
print('ref kp',len(kr))
bf=cv2.FlannBasedMatcher(dict(algorithm=1,trees=5),dict(checks=64))
out={}
for f in sorted(glob.glob('p-*.jpg')):
    im=cv2.imread(f)
    # scale scan down to roughly reference scale for matching (ref ~ scan/3.2)
    k=0.5
    sm=cv2.resize(im,None,fx=k,fy=k,interpolation=cv2.INTER_AREA)
    g=cv2.cvtColor(sm,cv2.COLOR_BGR2GRAY)
    ks,ds=sift.detectAndCompute(g,None)
    m=bf.knnMatch(ds,dr,k=2)
    good=[a for a,b in m if a.distance<0.75*b.distance]
    src=np.float32([ks[a.queryIdx].pt for a in good])/k
    dst=np.float32([kr[a.trainIdx].pt for a in good])
    H,inl=cv2.estimateAffinePartial2D(src,dst,method=cv2.RANSAC,ransacReprojThreshold=4,maxIters=20000)
    ni=int(inl.sum()) if inl is not None else 0
    sc=np.sqrt(abs(np.linalg.det(H[:,:2]))) if H is not None else 0
    ang=np.degrees(np.arctan2(H[1,0],H[0,0])) if H is not None else 0
    print(f,len(good),ni,'scala %.4f ang %.1f'%(sc,ang))
    out[f]=H.tolist()
json.dump(out,open('aff.json','w'))
