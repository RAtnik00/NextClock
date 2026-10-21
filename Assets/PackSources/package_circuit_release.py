from PIL import Image
from pathlib import Path
import os
import subprocess, plistlib, zipfile, shutil
ROOT=Path(__file__).resolve().parents[2]
base=ROOT/'outputs/circuit-release'; folder=base/'Circuit'
for v in ['static','animated']:(folder/v).mkdir(parents=True,exist_ok=True)
src=ROOT/'Assets/PackSources/Circuit-original-style-atlas.png'
im=Image.open(src).convert('RGBA');cw,ch=im.width//4,im.height//3
ff=os.environ.get('FFMPEG_BINARY') or shutil.which('ffmpeg')
if not ff:
 import imageio_ffmpeg
 ff=imageio_ffmpeg.get_ffmpeg_exe()
mask='gt(g(X,Y),r(X,Y)*1.35)*gt(b(X,Y),r(X,Y)*1.35)*gt(g(X,Y),55)'
pulse='pow(max(0,cos(2*PI*(Y/H-T/2.4))),16)';red='gt(r(X,Y),g(X,Y)*1.8)*gt(r(X,Y),b(X,Y)*1.8)*gt(r(X,Y),65)'
factor=f'(1+({mask})*(-0.35+1.3*{pulse})+({red})*(0.18*sin(2*PI*T/2.4)))'
expr='geq='+':'.join(f"{c}='{c}(X,Y)*{factor}'" for c in ['r','g','b'])+":a='alpha(X,Y)'"
for n,g in enumerate(list('0123456789')+['colon']):
 x,y=n%4,n//4; cell=im.crop((x*cw,y*ch,(x+1)*cw,(y+1)*ch))
 if g=='6':cell=Image.open(ROOT/'Assets/PackSources/Circuit-original-style-6.png').convert('RGBA')
 # Extract the major connected sprite(s), excluding neighboring-cell specks.
 alpha=cell.getchannel('A'); aw,ah=cell.size; data=alpha.tobytes();seen=bytearray(aw*ah); components=[]
 for start,value in enumerate(data):
  if value<=96 or seen[start]:continue
  stack=[start];seen[start]=1;count=0;minx=aw;miny=ah;maxx=maxy=0
  while stack:
   q=stack.pop();qy,qx=divmod(q,aw);count+=1;minx=min(minx,qx);maxx=max(maxx,qx);miny=min(miny,qy);maxy=max(maxy,qy)
   for nx,ny in ((qx-1,qy),(qx+1,qy),(qx,qy-1),(qx,qy+1)):
    if 0<=nx<aw and 0<=ny<ah:
     v=ny*aw+nx
     if not seen[v] and data[v]>96:seen[v]=1;stack.append(v)
  components.append((count,(minx,miny,maxx+1,maxy+1)))
 components.sort(reverse=True); boxes=[c[1] for c in components[:2 if g=='colon' else 1]];assert boxes
 bbox=(max(0,min(b[0] for b in boxes)-1),max(0,min(b[1] for b in boxes)-1),min(aw,max(b[2] for b in boxes)+1),min(ah,max(b[3] for b in boxes)+1))
 cell=cell.crop(bbox);w,h=(52,224) if g=='colon' else (144,224)
 limit=(34,118) if g=='colon' else (122,204)
 scale=min(limit[0]/cell.width,limit[1]/cell.height)
 cell=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
 canvas=Image.new('RGBA',(w,h));canvas.alpha_composite(cell,((w-cell.width)//2,(h-cell.height)//2))
 p=folder/'static'/f'{g}.png';canvas.save(p)
 subprocess.run([ff,'-hide_banner','-loglevel','error','-loop','1','-framerate','10','-i',str(p),'-t','2.4','-vf','format=gbrap,'+expr+',format=rgba','-plays','0','-f','apng','-y',str(folder/'animated'/f'{g}.png')],check=True)
with open(folder/'Info.plist','wb') as f:plistlib.dump({'Name':'Circuit','Version':'1.2','FormatVersion':1,'Author':'RAtnik00'},f)
frames=[]
for n in range(24):
 c=Image.new('RGBA',(960,300),(0,0,0,0));x=170
 for g in ['2','1','colon','4','8']:
  a=Image.open(folder/'animated'/f'{g}.png');a.seek(n);c.alpha_composite(a.convert('RGBA'),(x,38));x+=a.width-4
 frames.append(c)
frames[0].save(base/'Circuit-live.png',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=0,blend=0)
with zipfile.ZipFile(base/'Circuit.nextclock','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(folder.rglob('*')):
  if p.is_file():z.write(p,Path('Circuit')/p.relative_to(folder))
root=ROOT
shutil.copytree(folder,root/'layout/Library/Application Support/NextClock/Packs/Circuit',dirs_exist_ok=True)
shutil.copy2(src,root/'Assets/PackSources/Circuit-atlas.png')
# A neutral backdrop only for the MP4 demonstration; glyph files keep alpha.
subprocess.run([ff,'-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=0x43335A:s=960x300:r=30:d=7.2','-stream_loop','2','-i',str(base/'Circuit-live.png'),'-filter_complex','[0:v][1:v]overlay=shortest=1,format=yuv420p[v]','-map','[v]','-t','7.2','-an','-c:v','libx264','-crf','18','-movflags','+faststart','-y',str(base/'Circuit-preview.mp4')],check=True)
print('Created',base/'Circuit.nextclock')
