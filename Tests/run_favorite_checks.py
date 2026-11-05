#!/usr/bin/env python3
import pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='nextclock-profiles-') as name:
    tmp=pathlib.Path(name);binary=tmp/'favorites-checks'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fmodules','-fmodules-cache-path='+str(tmp/'modules'),
        '-Werror','-Wno-incompatible-pointer-types','-I'+str(root/'Tests/Support'),str(root/'Tests/FavoritesValidation.m'),
        '-framework','Foundation','-framework','ImageIO','-o',str(binary)],check=True)
    subprocess.run([str(binary),str(tmp)],check=True)
