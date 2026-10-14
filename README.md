# NextClock

Custom lock screen clocks for rootless iOS 15. Developed for iPhone 7 Plus, iOS 15.8.8, Dopamine; other devices require testing.

## Features
PNG/GIF/APNG; static and animated modes; exact frame delays; shared animation timeline; speed; still images in Low Power Mode; tint preserving shading; 12/24/system time; hide date; size, spacing, offset; live preferences; pack details, import, selection, deletion; reset and respring.

## Packs
A folder contains optional Info.plist and static/, animated/, or both. Each variant contains all 11 glyphs (0–9 and colon) as GIF or PNG. APNG uses .png. Metadata: Name, Version, Author, optional FormatVersion = 1. Existing .flexpack folders work. ZIP and .nextclock files are ordinary ZIP archives containing a pack directly or in one enclosing folder. Each import creates a separate copy and preserves existing packs.

Bundled packs: /var/jb/Library/Application Support/NextClock/Packs. Imported packs: /var/mobile/Library/NextClock/Packs. User packs survive upgrades.

Image limits: 2048 px per dimension, 240 frames, 8 MB encoded and 96 MB decoded per glyph. ZIP limits: 64 MB compressed/expanded, 512 entries. Stored and deflated ZIP entries supported; encryption, ZIP64 and symlinks rejected.

## Build
Theos, Xcode, patched iOS 16.5 SDK. Run make package. arm64, rootless, deployment iOS 15. PreferenceLoader required.

## Acknowledgements
NextClock is independently implemented, inspired by AniTime by yandevelop and FlexClock by tr3tol. iOS 15 classes replace CoverSheetKit hooks; compiler-specific C/runtime workarounds are not included.

Anime artwork is from AniTime; Pixel, CRT and Sakura artwork is from the supplied FlexClock reference. These are third-party local development assets, not original NextClock artwork. Redistribution rights have not been established; replace with original or licensed artwork before public release. AniTime source code is not included.

## Adaptations
Staged imports and confirmations preserve existing packs; every glyph is validated; reset clears all implemented preferences. iOS 15 clocks are bounded to screen width. Exact frame delays improve on uniform reference playback. About names NextClock and RAtnik00; acknowledgements are in this README.

## Device verification
Build success does not confirm runtime compatibility. Test modes, speed, low-power, tint, minute changes, screen off/on, folder/ZIP import, deletion, fallback and reset on the iPhone.

## License
NextClock source is provided under GPL-3.0. The settings layout is adapted from FlexClock (tr3tol, GPL-3.0); its attribution is retained here. This source license does not grant rights to third-party artwork.
