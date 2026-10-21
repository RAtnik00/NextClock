# NextClock

<img src="Assets/nextclock-icon.png" width="128" alt="NextClock logo">

Custom lock screen clocks for rootless iOS 15, with an experimental iOS 16–17 beta.

## Compatibility

- Rootless iOS 15: previously tested devices listed below
- iOS 16–17: experimental, no on-device verification yet
- Includes arm64 and arm64e binaries for both the tweak and preferences bundle
- Requires PreferenceLoader

Confirmed working:
- iPhone 7 Plus — iOS 15.8.8, Dopamine
- iPhone 12 — iOS 15.3.1 (confirmed by a tester)
- iPhone 13 Pro Max — iOS 15.1.1, Dopamine (compatibility fix confirmed by a tester)

The optional seconds display has been tested on iPhone 7 Plus; it has not yet been separately verified on iPhone 12 or iPhone 13 Pro Max. Other devices and iOS 15 versions require testing.

## 1.1.0~beta1 — public testing

This beta preserves the legacy iOS 15 renderer and adds a runtime-selected prominent-clock adapter for testing on iOS 16–17. Private selectors are based on an upstream iOS 18 class dump; their presence and correct behavior on 16/17 are not established. If required methods are missing, the legacy adapter is used and the stock clock may remain unchanged. A successful build is not device validation. Jailbreak and tweak injection are required; TrollStore alone is insufficient.

Settings → NextClock → Export diagnostics shares a structural report (iOS version, adapter/class availability and, when available, view frames/visibility). It does not capture label text, notifications or device identifiers and is not uploaded automatically. Send it with model, exact firmware/build, jailbreak, steps and a screenshot/video. Check charging status, lock/unlock, saved lock-screen styles, widgets, seconds, Low Power Mode and AOD on supported devices. Keep the stable 1.0.1 package available for rollback.

Circuit 1.2 is bundled with transparent APNG light effects and static fallbacks. Earlier visual drafts remain under Assets/PackDrafts and are not installed.

## Features
PNG/GIF/APNG; static and animated modes; exact frame delays; shared animation timeline; speed; still images in Low Power Mode; tint preserving shading; 12/24/system time; optional seconds display; hide date; size, spacing, offset; live preferences; pack details, import, selection, deletion; reset and respring. Automatic English, Russian and Ukrainian preferences localization (English fallback). Clock and date yield to temporary system status text, including charging.

## Packs
A folder contains optional Info.plist and static/, animated/, or both. Each variant contains all 11 glyphs (0–9 and colon) as GIF or PNG. APNG uses .png. Metadata: Name, Version, Author, optional FormatVersion = 1. Existing .flexpack folders work. ZIP and .nextclock files are ordinary ZIP archives containing a pack directly or in one enclosing folder. Each import creates a separate copy and preserves existing packs.

Bundled packs: /var/jb/Library/Application Support/NextClock/Packs. Imported packs: /var/mobile/Library/NextClock/Packs. User packs survive upgrades.

Image limits: 2048 px per dimension, 240 frames, 8 MB encoded and 96 MB decoded per glyph. Rendering also limits decoded glyph frames to 48 MB per clock row; a row exceeding this budget falls back to the system clock. ZIP limits: 64 MB compressed/expanded, 512 entries. Stored and deflated ZIP entries supported; encryption, ZIP64 and symlinks rejected.

## Build
Theos, Xcode, patched iOS 16.5 SDK. Run `make package FINALPACKAGE=1`. arm64 and arm64e, rootless, deployment iOS 15. The rootless package architecture remains `iphoneos-arm64`. PreferenceLoader required.

## Acknowledgements
NextClock is independently implemented, inspired by AniTime by yandevelop and FlexClock by tr3tol. The legacy adapter targets iOS 15 classes. The experimental prominent-clock adapter consults FlexClock private-interface names; compiler-specific C/runtime workarounds are not included.

Anime artwork is from AniTime; Pixel, CRT and Sakura artwork is from the supplied FlexClock reference. These are third-party assets, not original NextClock artwork. They are included with the creators’ permission, obtained by RAtnik00. AniTime source code is not included.

## Adaptations
Staged imports and confirmations preserve existing packs; every glyph is validated; reset clears all implemented preferences. iOS 15 clocks are bounded to screen width. Exact frame delays improve on uniform reference playback. About names NextClock and RAtnik00; acknowledgements are in this README.

## Device verification
Build success does not confirm runtime compatibility. Test modes, speed, low-power, tint, minute changes, screen off/on, folder/ZIP import, deletion, fallback and reset on the iPhone.

## License
NextClock source is provided under GPL-3.0. The settings layout is adapted from FlexClock (tr3tol, GPL-3.0); its attribution is retained here. This source license does not grant rights to third-party artwork.

## Support
NextClock is free. Optional support: [buycoffee.to/ratnik00](https://buycoffee.to/ratnik00). Supporting the developer does not unlock extra features.
