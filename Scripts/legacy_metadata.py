#!/usr/bin/env python3
"""Adjust only the staged rootful test package, never the stable control file."""
import pathlib, plistlib, sys

stage = pathlib.Path(sys.argv[1])
dual = len(sys.argv) > 2 and sys.argv[2] == '1'
minimum = '14.0' if dual else '12.0'
version = '1.1.1~legacy1'
control = stage / 'DEBIAN/control'
lines = control.read_text().splitlines()
replacements = {
    'Architecture': 'iphoneos-arm',
    'Version': version,
    'Description': 'Experimental rootful NextClock for iOS ' +
        ('14 (arm64/arm64e).' if dual else '12-14 (arm64 only; no A12/A13 on iOS 12-13).'),
    'Depends': f'firmware (>= {minimum}), firmware (<< 15.0), mobilesubstrate (>= 0.9.5000), preferenceloader',
}
control.write_text('\n'.join(
    key + ': ' + replacements[key] if (key := line.partition(':')[0]) in replacements else line
    for line in lines) + '\n')
info = stage / 'Library/PreferenceBundles/NextClockPrefs.bundle/Info.plist'
with info.open('rb') as handle:
    values = plistlib.load(handle)
values.update(NextClockVersion=version, CFBundleVersion=version,
              CFBundleShortVersionString='1.1.1')
with info.open('wb') as handle:
    plistlib.dump(values, handle)
