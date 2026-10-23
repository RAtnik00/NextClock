from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np
import math, plistlib, zipfile, shutil, json
import argparse
parser=argparse.ArgumentParser(description="Build the Halloween transparent APNG digit pack")
parser.add_argument('--atlas',type=Path,default=Path(__file__).with_name('Halloween-atlas.png'))
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--install',type=Path,help='Optional NextClock project directory')
args=parser.parse_args()
project=args.install
out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
source=args.atlas.resolve()
if source != out/'Halloween-atlas.png': shutil.copy2(source,out/'Halloween-atlas.png')
im=Image.open(source).convert('RGBA')
assert im.getchannel('A').getextrema()[0]==0, 'Expected transparent atlas'
folder=out/'Halloween'
for mode in ['static','animated']:(folder/mode).mkdir(parents=True,exist_ok=True)
animations={}
for index,name in enumerate(list('0123456789')+['colon']):
 col,row=index%4,index//4
 cell=im.crop((round(col*im.width/4),round(row*im.height/3),round((col+1)*im.width/4),round((row+1)*im.height/3)))
 mask=cell.getchannel('A').point(lambda x:255 if x>32 else 0)
 data=np.array(mask)>0
 seen=np.zeros(data.shape,dtype=bool);components=[]
 for yy,xx in zip(*np.where(data)):
  if seen[yy,xx]:continue
  stack=[(int(xx),int(yy))];seen[yy,xx]=True;pts=[]
  while stack:
   x,y=stack.pop();pts.append((x,y))
   for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
    if 0<=nx<data.shape[1] and 0<=ny<data.shape[0] and data[ny,nx] and not seen[ny,nx]:
     seen[ny,nx]=True;stack.append((nx,ny))
  if pts:components.append((len(pts),(min(x for x,y in pts),min(y for x,y in pts),max(x for x,y in pts)+1,max(y for x,y in pts)+1)))
 components.sort(reverse=True)
 boxes=[b for size,b in components[:2 if name=='colon' else 1]];assert boxes,name
 box=(max(0,min(b[0] for b in boxes)-2),max(0,min(b[1] for b in boxes)-2),min(cell.width,max(b[2] for b in boxes)+2),min(cell.height,max(b[3] for b in boxes)+2))
 cell=cell.crop(box)
 w,h=(80,224) if name=='colon' else (176,224)
 cell.thumbnail((64,190) if name=='colon' else (156,202),Image.Resampling.LANCZOS)
 base=Image.new('RGBA',(w,h));base.alpha_composite(cell,((w-cell.width)//2,(h-cell.height)//2))
 base.save(folder/'static'/f'{name}.png')
 pixels=np.array(cell,dtype=np.float32)
 # Animate warm carved areas while preserving dark contours, green stems and alpha.
 warm=np.clip((pixels[:,:,0]-pixels[:,:,2]-45)/140,0,1)*np.clip((pixels[:,:,1]-65)/130,0,1)
 frames=[]
 for frame in range(24):
  t=2*math.pi*frame/24
  glow=.10*math.sin(t)+.035*math.sin(3*t)
  arr=pixels.copy();arr[:,:,:3]*=(1+warm[:,:,None]*glow)
  sprite=Image.fromarray(np.uint8(np.clip(arr,0,255)))
  scale=1+.008*math.sin(t)
  sprite=sprite.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',(w,h));canvas.alpha_composite(sprite,((w-sprite.width)//2,(h-sprite.height)//2+round(1.5*math.sin(t))))
  frames.append(canvas)
 frames[0].save(folder/'animated'/f'{name}.png',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=0,blend=0,optimize=False)
 animations[name]=frames
with open(folder/'Info.plist','wb') as f:plistlib.dump({'Name':'Halloween','Version':'1.0','FormatVersion':1,'Author':'RAtnik00'},f)
preview=[]
for i in range(24):
 canvas=Image.new('RGBA',(900,300),(24,16,33,255));x=65
 for glyph in ['2','3','colon','5','9']:
  canvas.alpha_composite(animations[glyph][i],(x,38));x+=animations[glyph][i].width-6
 preview.append(canvas)
preview[0].save(out/'Halloween-live.png',save_all=True,append_images=preview[1:],duration=100,loop=0,disposal=0,blend=0)
preview[0].save(out/'Halloween-preview.png')
preview[0].convert('RGB').save(out/'Halloween-preview.gif',save_all=True,append_images=[x.convert('RGB') for x in preview[1:]],duration=100,loop=0)
with zipfile.ZipFile(out/'Halloween.nextclock','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(folder.rglob('*')):
  if p.is_file():z.write(p,Path('Halloween')/p.relative_to(folder))
for mode in ['static','animated']:
 for name in animations:
  with Image.open(folder/mode/f'{name}.png') as a:
   assert a.mode=='RGBA'
   assert a.getchannel('A').getextrema()[0]==0
   if mode=='animated':
    assert a.n_frames==24
    assert a.info.get('loop')==0
    for f in range(a.n_frames):a.seek(f);assert a.info['duration']==100
assert all(any(not np.array_equal(np.array(frames[0]),np.array(f)) for f in frames[1:]) for frames in animations.values())
if project:
 shutil.copytree(folder,project/'layout/Library/Application Support/NextClock/Packs/Halloween',dirs_exist_ok=True)
(out/'generation-prompt.txt').write_text('Built-in image_gen; transparent 4x3 atlas; chunky orange carved pumpkin numerals 0–9, two jack-o-lantern colon, green stems, dark plum contours, golden glowing grooves; hand-painted cartoon 2.5D game sprites; no background or labels.\nAnimation: 24 seamless 100 ms frames, warm-light flicker and gentle bob, alpha preserved.\n')
print('Validated 11 static sprites + 11 looping APNGs (24 frames each), alpha preserved.')
print('Import archive:',out/'Halloween.nextclock')
