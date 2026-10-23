#!/usr/bin/env python3
"""Validate resource coverage, placeholders, plist structure and release versions."""
import collections, json, pathlib, re, subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
RES=ROOT/'NextClockPrefs/Resources'
def plist(path):
    return json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
english=plist(RES/'en.lproj/Localizable.strings')
locales=[]
for path in sorted(RES.glob('*.lproj/Localizable.strings')):
    values=plist(path);locales.append(path.parent.stem)
    keys=re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=',path.read_text(),re.M)
    assert len(keys)==len(set(keys))==len(values),f'duplicate keys: {path}'
    assert values.keys()==english.keys(),f'localization coverage: {path}'
    for key,value in values.items():
        assert value.strip(),(path,key)
        formats=lambda s:collections.Counter(re.findall(r'%(?:\d+\$)?[@diuf]',s))
        assert formats(key)==formats(value),(path,key,'format placeholders')
        for token in ['static/','animated/','Info.plist','.nextclock']:
            if token in key:assert token in value,(path,key,token)
info=plist(RES/'Info.plist')
assert set(info['CFBundleLocalizations'])==set(locales)
header=(ROOT/'NextClockPrefs/NCLocalization.h').read_text()
assert all('@"'+lang+'"' in header for lang in locales)
for path in RES.glob('*.plist'):
    content=plist(path)
    for entry in content.get('items',[]):
        for key in ['label','footerText']:
            if key in entry and entry[key]:assert entry[key] in english,(path,entry[key])
        for title in entry.get('validTitles',[]):assert title in english,(path,title)
version=re.search(r'^Version:\s*(\S+)',(ROOT/'control').read_text(),re.M).group(1)
assert info['NextClockVersion']==version
assert '#define NC_VERSION @"'+version+'"' in (ROOT/'Shared/NCVersion.h').read_text()
assert any(x.get('nextClockVersion') for x in plist(RES/'About.plist')['items'])
print(f'PASS: {len(locales)} languages, {len(english)} keys each, all UI keys and release version {version}.')
