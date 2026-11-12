#!/usr/bin/env python3
"""Check built Pro and free packages, including exclusion of Pro executable code."""
import io, lzma, pathlib, plistlib, subprocess, sys, tarfile, tempfile

def unpack(path):
    data=path.read_bytes();assert data[:8]==b'!<arch>\n';offset=8;members={}
    while offset<len(data):
        h=data[offset:offset+60];size=int(h[48:58]);assert h[58:60]==b'`\n'
        members[h[:16].decode().strip().rstrip('/')]=data[offset+60:offset+60+size];offset+=60+size+size%2
    result=[]
    for prefix in ['control.tar','data.tar']:
        name=next(n for n in members if n.startswith(prefix));value=members[name]
        if name.endswith(('.xz','.lzma')):value=lzma.decompress(value)
        with tarfile.open(fileobj=io.BytesIO(value),mode='r:*') as t:
            result.append({m.name.lstrip('./'):t.extractfile(m).read() for m in t.getmembers() if m.isfile()})
    return result

pro=sys.argv[2]=='pro';control,files=unpack(pathlib.Path(sys.argv[1]));text=control['control'].decode()
assert ('Package: com.ratnik00.nextclock.pro\n' in text)==pro
assert 'Architecture: iphoneos-arm64\n' in text
if pro:
    assert 'Version: 0.1.0~alpha1\n' in text and text.count('Conflicts: com.ratnik00.nextclock\n')==1
    assert text.count('Replaces: com.ratnik00.nextclock\n')==1
else:assert 'Package: com.ratnik00.nextclock\n' in text and 'Conflicts:' not in text
if not pro:
    assert "firmware (>= 15.0), firmware (<< 19.0)" in text
base='var/jb/Library/PreferenceBundles/NextClockPrefs.bundle/'
info=plistlib.loads(files[base+'Info.plist'])
assert info['NextClockVersion']==('0.1.0~alpha1' if pro else '1.2.0~beta10')
loader=plistlib.loads(files['var/jb/Library/PreferenceLoader/Preferences/NextClockPrefs.plist'])
assert loader['entry']['label']==('NextClock Pro' if pro else 'NextClock')
root=plistlib.loads(files[base+'Root.plist'])['items']
assert [row['key'] for row in root if 'key' in row]==['enabled'], 'main page must not duplicate appearance controls'
assert {row['action'] for row in root if 'action' in row}=={'openProPreview','exportDiagnostics','restartSpringBoard','resetSettings'}
assert {row.get('nextClockPage') for row in root if row.get('nextClockPage')}=={'Favorites','ManagePacks','About'}
assert base+'Advanced.plist' not in files
assert root[-1].get('nextClockPage')=='About' and root[-2].get('footerText','').startswith('iOS 16–18')
about=plistlib.loads(files[base+'About.plist'])['items']
assert any(row.get('action')=='supportDeveloper' for row in about)

assert not any('/Packs/Halloween/' in name for name in files)
assert not any('ProProfiles.plist' in name for name in files), 'must never ship personal profiles'
assert b'NCProController' in files[base+'NextClockPrefs']
assert (b'saveProfile' in files[base+'NextClockPrefs'])==pro
assert (b'ProProfiles.plist' in files[base+'NextClockPrefs'])==pro
with tempfile.TemporaryDirectory() as temp:
    for name in [base+'NextClockPrefs','var/jb/Library/MobileSubstrate/DynamicLibraries/NextClock.dylib']:
        path=pathlib.Path(temp)/pathlib.Path(name).name;path.write_bytes(files[name])
        assert set(subprocess.check_output(['lipo','-archs',str(path)],text=True).split())=={'arm64','arm64e'}
print('PASS:', 'Pro' if pro else 'Free', 'package identity, conflicts, version, loader, executable isolation and both architectures.')
