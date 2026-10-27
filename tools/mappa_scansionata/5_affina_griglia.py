import cv2, numpy as np, json, math
im=cv2.imread('mo_scan.jpg'); H,W=im.shape[:2]
d=json.load(open('/home/claude/zargos-lords/assets/data/board.json'))
k=W/4096
R=d['hex_radius_px']*k; ox,oy=[v*k for v in d['origin_px']]; dx=math.sqrt(3)*R
tpl=np.zeros((H,W),np.uint8)
for r in range(53):
  for c in range(66):
    x=ox+c*dx+(dx/2 if r&1 else 0); y=oy+r*1.5*R
    pts=np.array([(x+R*math.cos(math.radians(60*i-90)),y+R*math.sin(math.radians(60*i-90))) for i in range(6)],np.int32)
    cv2.polylines(tpl,[pts],True,255,2)
g=cv2.cvtColor(im,cv2.COLOR_BGR2GRAY).astype(np.float32)
bh=cv2.morphologyEx(g,cv2.MORPH_BLACKHAT,np.ones((7,7),np.uint8))
bh=np.clip(bh,0,60)
T=cv2.GaussianBlur(tpl.astype(np.float32),(0,0),1.5)
S=320; M=30
pts=[];off=[]
for y0 in range(M,H-S-M,S//2):
  for x0 in range(M,W-S-M,S//2):
    img=bh[y0-M:y0+S+M,x0-M:x0+S+M]; t=T[y0:y0+S,x0:x0+S]
    if t.sum()<1000 or img.std()<2: continue
    res=cv2.matchTemplate(img,t,cv2.TM_CCOEFF_NORMED)
    _,mx,_,loc=cv2.minMaxLoc(res)
    srt=np.sort(res.ravel())
    if mx<0.12: continue
    sx,sy=loc[0]-M,loc[1]-M
    if abs(sx)>=M-1 or abs(sy)>=M-1: continue
    pts.append((x0+S/2,y0+S/2)); off.append((sx,sy,mx))
pts=np.array(pts); off=np.array(off)
print(len(pts), 'mediana', np.median(np.abs(off[:,:2]),0), 'p90', np.percentile(np.abs(off[:,:2]),90,0))
# campo: media pesata gaussiana su griglia grossolana, scarti robusti
gs=64; gh,gw=H//gs+1,W//gs+1
fx=np.zeros((gh,gw),np.float32); fy=np.zeros((gh,gw),np.float32)
sig=500.0
for j in range(gh):
  for i in range(gw):
    p=np.array([i*gs,j*gs]); dd=np.sum((pts-p)**2,1)
    w=np.exp(-dd/(2*sig**2))*off[:,2]
    if w.sum()<1e-3: continue
    fx[j,i]=np.sum(w*off[:,0])/w.sum(); fy[j,i]=np.sum(w*off[:,1])/w.sum()
FX=cv2.resize(fx,(W,H),interpolation=cv2.INTER_CUBIC); FY=cv2.resize(fy,(W,H),interpolation=cv2.INTER_CUBIC)
yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
out=cv2.remap(im,xx+FX,yy+FY,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
cv2.imwrite('mo_scan_aff.jpg',out,[cv2.IMWRITE_JPEG_QUALITY,92])
np.save('off.npy',np.hstack([pts,off]))
