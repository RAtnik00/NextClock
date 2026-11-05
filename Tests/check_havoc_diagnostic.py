#!/usr/bin/env python3
"""Validate the stable-baseline private diagnostic DEB, not runtime compatibility."""
import io,lzma,pathlib,plistlib,re,subprocess,sys,tarfile,tempfile
p=pathlib.Path(sys.argv[1]);raw=p.read_bytes();assert raw[:8]==b'!<arch>\n';offset=8;files={}
while offset<len(raw):
 h=raw[offset:offset+60];assert h[58:60]==b'`\n';size=int(h[48:58]);name=h[:16].decode().strip().rstrip('/');data=raw[offset+60:offset+60+size];offset+=60+size+size%2
 if name.startswith(('data.tar','control.tar')):
  if name.endswith(('.xz','.lzma')):data=lzma.decompress(data)
  with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as archive:
   files.update({m.name.lstrip('./'):archive.extractfile(m).read() for m in archive if m.isfile()})
assert 'Version: 1.1.1~diag1\n' in files['control'].decode()
assert 'Architecture: iphoneos-arm64\n' in files['control'].decode()
base='var/jb/Library/PreferenceBundles/NextClockPrefs.bundle/'
assert plistlib.loads(files[base+'Info.plist'])['NextClockVersion']=='1.1.1~diag1'
assert b'NCProController' not in files[base+'NextClockPrefs'], 'candidate must be stable baseline without new preview code'
with tempfile.TemporaryDirectory() as name:
 for binary in [base+'NextClockPrefs','var/jb/Library/MobileSubstrate/DynamicLibraries/NextClock.dylib']:
  f=pathlib.Path(name)/pathlib.Path(binary).name;f.write_bytes(files[binary]);assert b'1.1.1~diag1' in files[binary]
  assert set(subprocess.check_output(['lipo','-archs',str(f)],text=True).split())=={'arm64','arm64e'}
  commands=subprocess.check_output(['otool','-arch','all','-l',str(f)],text=True)
  versions=re.findall(r'\bminos\s+(\S+)',commands);assert versions==['15.0','15.0'], versions
  if f.name.endswith('dylib'):assert b'Layout safety: guarded' in files[binary]
print('PASS: diagnostic identity/version, stable-only UI, arm64+arm64e, min iOS 15.0 and safety diagnostics.')
