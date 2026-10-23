#!/usr/bin/env python3
"""Run actual shared Objective-C pack/ZIP code on macOS with isolated fixtures."""
import io, os, pathlib, struct, subprocess, tempfile, warnings, zipfile, zlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
def png():
    def chunk(k, v): return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+b'\xff\x80\0\xff'*2)*2))+chunk(b'IEND',b'')
with tempfile.TemporaryDirectory(prefix='nextclock-check-') as tmp:
    tmp=pathlib.Path(tmp);pack=tmp/'pack'/'static';pack.mkdir(parents=True)
    for g in [*map(str,range(10)),'colon']:(pack/(g+'.png')).write_bytes(png())
    (tmp/'broken.png').write_bytes(b'not an image');(tmp/'image-link.png').symlink_to(pack/'0.png')
    files={f'Pack/static/{p.name}':p.read_bytes() for p in pack.iterdir()}
    def archive(name,method=zipfile.ZIP_DEFLATED,extras=()):
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(tmp/name,'w',method) as z:
                for k,v in files.items():z.writestr(k,v)
                for k,v in extras:z.writestr(k,v)
    archive('stored.zip',zipfile.ZIP_STORED);archive('deflated.zip')
    class Stream(io.BytesIO):
        def seekable(self):return False
        def seek(self,*a):raise io.UnsupportedOperation()
    stream=Stream()
    with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
        for k,v in files.items():z.writestr(k,v)
    (tmp/'descriptor.zip').write_bytes(stream.getvalue())
    archive('traversal.zip',extras=[('../static/0.png',png())])
    link=zipfile.ZipInfo('Pack/static/link.png');link.create_system=3;link.external_attr=0o120777<<16
    archive('symlink.zip',extras=[(link,b'0.png')])
    archive('duplicate.zip',extras=[('Pack/static/0.png',png())])
    archive('double-slash.zip',extras=[('Pack//static/0.png',png())])
    data=bytearray((tmp/'deflated.zip').read_bytes());central=data.index(b'PK\x01\x02')
    d=data.copy();d[central+16]^=1;(tmp/'crc.zip').write_bytes(d)
    d=data.copy();d[6]^=8;(tmp/'local-flags.zip').write_bytes(d)
    d=data.copy();end=d.rindex(b'PK\x05\x06');struct.pack_into('<I',d,end+12,struct.unpack_from('<I',d,end+12)[0]+1);d[end:end]=b'x';(tmp/'central-gap.zip').write_bytes(d)
    (tmp/'truncated.zip').write_bytes(data[:-10])
    d=data.copy();d[central+8]|=1;(tmp/'encrypted.zip').write_bytes(d)
    d=data.copy();struct.pack_into('<I',d,central+24,9*1024*1024);(tmp/'oversized.zip').write_bytes(d)
    binary=tmp/'pack-checks'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fmodules','-fmodules-cache-path='+str(tmp/'modules'),'-Werror','-Wno-incompatible-pointer-types','-I'+str(ROOT/'Tests/Support'),str(ROOT/'Tests/PackValidation.m'),'-framework','Foundation','-framework','ImageIO','-lz','-o',str(binary)],check=True)
    subprocess.run([str(binary),str(tmp),str(ROOT/'layout/Library/Application Support/NextClock/Packs')],check=True)
