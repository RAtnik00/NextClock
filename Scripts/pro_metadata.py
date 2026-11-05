#!/usr/bin/env python3
"""Stage an explicit Pro prototype; leave the free release metadata untouched."""
import pathlib, plistlib, sys
stage=pathlib.Path(sys.argv[1]); control=stage/'DEBIAN/control'
values={'Package':'com.ratnik00.nextclock.pro','Name':'NextClock Pro',
        'Version':'0.1.0~alpha1','Description':'Experimental NextClock Pro preview and appearance profiles. Rootless iOS 15-17; device testing required.'}
lines=control.read_text().splitlines()
control.write_text('\n'.join(key+': '+values[key] if (key:=line.partition(':')[0]) in values else line for line in lines)+
    '\nConflicts: com.ratnik00.nextclock\nReplaces: com.ratnik00.nextclock\n')
bundle=stage/'Library/PreferenceBundles/NextClockPrefs.bundle'
path=bundle/'Info.plist'
with path.open('rb') as f:info=plistlib.load(f)
info.update(NextClockVersion='0.1.0~alpha1',CFBundleVersion='0.1.0~alpha1',CFBundleShortVersionString='0.1.0')
with path.open('wb') as f:plistlib.dump(info,f)
loader=stage/'Library/PreferenceLoader/Preferences/NextClockPrefs.plist'
with loader.open('rb') as f:entry=plistlib.load(f)
entry['entry']['label']='NextClock Pro'
with loader.open('wb') as f:plistlib.dump(entry,f)
