#!/usr/bin/env python3
"""Inspect the actual DEB paths, dependencies and Mach-O slices/load commands."""
import io, lzma, pathlib, plistlib, re, subprocess, sys, tarfile, tempfile

package = pathlib.Path(sys.argv[1])
dual = sys.argv[2] == 'ios14'
data = package.read_bytes()
assert data[:8] == b'!<arch>\n'
members = {}
offset = 8
while offset < len(data):
    header = data[offset:offset+60]
    assert header[58:60] == b'`\n'
    size = int(header[48:58])
    members[header[:16].decode().strip().rstrip('/')] = data[offset+60:offset+60+size]
    offset += 60 + size + size % 2

def archive(prefix):
    name = next(k for k in members if k.startswith(prefix))
    value = members[name]
    if name.endswith(('.lzma', '.xz')):
        value = lzma.decompress(value)
    return tarfile.open(fileobj=io.BytesIO(value), mode='r:*')

with archive('control.tar') as control:
    text = control.extractfile(next(m for m in control.getmembers()
                                    if m.name.lstrip('./') == 'control')).read().decode()
assert 'Architecture: iphoneos-arm\n' in text
assert 'Version: 1.1.1~legacy1\n' in text
assert f'firmware (>= {"14.0" if dual else "12.0"})' in text
assert 'firmware (<< 15.0)' in text
assert 'oldabi' not in text

with archive('data.tar') as payload, tempfile.TemporaryDirectory() as temp:
    files = {m.name.lstrip('./'): m for m in payload.getmembers() if m.isfile()}
    assert not any(p.startswith('var/jb/') for p in files)
    bundle = 'Library/PreferenceBundles/NextClockPrefs.bundle/'
    info = plistlib.loads(payload.extractfile(files[bundle+'Info.plist']).read())
    assert info['NextClockVersion'] == '1.1.1~legacy1'
    assert len(info['CFBundleLocalizations']) == 9
    for name in ('Anime', 'CRT.flexpack', 'Pixel.flexpack', 'Sakura.flexpack', 'Circuit'):
        assert any(p.startswith('Library/Application Support/NextClock/Packs/'+name+'/') for p in files), name
    for name in ('Library/MobileSubstrate/DynamicLibraries/NextClock.dylib', bundle+'NextClockPrefs'):
        binary = pathlib.Path(temp)/pathlib.Path(name).name
        contents = payload.extractfile(files[name]).read()
        binary.write_bytes(contents)
        assert b'1.1.1~legacy1' in contents
        archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        assert set(archs) == ({'arm64', 'arm64e'} if dual else {'arm64'}), archs
        commands = subprocess.check_output(['otool', '-arch', 'all', '-l', str(binary)], text=True)
        # Only inspect deployment commands, not dylib current/compatibility versions.
        deployment = re.findall(r'(?:LC_BUILD_VERSION|LC_VERSION_MIN_IPHONEOS).*?(?=Load command|\Z)', commands, re.S)
        assert len(deployment) == len(archs)
        for block in deployment:
            assert re.search(r'\b(?:minos|version) '+('14.0' if dual else '12.0')+r'\b', block), block
        if name.endswith('NextClockPrefs'):
            uti = [b for b in commands.split('Load command') if '/UniformTypeIdentifiers.framework/' in b]
            assert uti and all('LC_LOAD_WEAK_DYLIB' in b for b in uti), uti
print('PASS:', package, 'rootful metadata, 6 packs, 9 locales, architecture and weak-link checks.')
