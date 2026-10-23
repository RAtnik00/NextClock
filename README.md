# NextClock

<img src="Assets/nextclock-icon.png" width="128" alt="NextClock logo">

Custom lock screen clocks for rootless iOS 15, with an experimental iOS 16–17 beta.

## Compatibility

- Rootless iOS 15: previously tested devices listed below
- iOS 16–17: experimental; limited tester reports, not universal compatibility
- Includes arm64 and arm64e binaries for both the tweak and preferences bundle
- Requires PreferenceLoader

Confirmed working:
- iPhone 7 Plus — iOS 15.8.8, Dopamine
- iPhone 12 — iOS 15.3.1 (confirmed by a tester)
- iPhone 13 Pro Max — iOS 15.1.1, Dopamine (compatibility fix confirmed by a tester)

The optional seconds display has been tested on iPhone 7 Plus; it has not yet been separately verified on iPhone 12 or iPhone 13 Pro Max. Other devices and iOS 15 versions require testing.

## 1.1.0 — October 23, 2026

Includes the iOS 15 charging transition fixes, transparent animated Halloween pack, a greeting at the top of settings, and Italian/French localization. See [CHANGELOG.md](CHANGELOG.md) for details and remaining validation.

Tester videos confirm charging returns correctly with Anime and a visible date on iOS 15.8.8. RAtnik00 subsequently reported that the final RC1 device checks passed on the development iPhone 7 Plus. The iOS 16/17 adapter remains experimental; these iOS 15 charging changes do not establish modern-adapter compatibility.

Tester reports: iPhone X, iOS 16.1.2, Roothide 2.4.9.27 (adapter, seconds and date hiding); iPhone 14, iOS 16.6, nathanLR (beta 2 working). Earlier reports also describe custom packs on iPhone SE 2020 / iOS 17.0.2 and iPad 8 / iPadOS 17.4; exact build/jailbreak details are incomplete. These are limited reports, not universal compatibility claims.

Settings → NextClock → Export diagnostics shares a structural report (version, iOS, adapter/class availability and a bounded view snapshot). It excludes label text, notifications and device identifiers and is not uploaded automatically. Include model, exact iOS, jailbreak, package version and reproduction steps with a report. Keep stable 1.0.1 available for rollback.

## Features
PNG/GIF/APNG; static and animated modes; exact frame delays; shared animation timeline; speed; still images in Low Power Mode; tint preserving shading; 12/24/system time; optional seconds display; hide date; size, spacing, offset; live preferences; pack details, import, selection, deletion; reset and respring. Automatic English, Russian, Ukrainian, German, Polish, Swedish, Norwegian Bokmål, Italian and French preferences localization (English fallback). Clock and date yield to temporary system status text, including charging.

## Packs
A folder contains optional Info.plist and static/, animated/, or both. Each variant contains all 11 glyphs (0–9 and colon) as GIF or PNG. APNG uses .png. Metadata: Name, Version, Author, optional FormatVersion = 1. Existing .flexpack folders work. ZIP and .nextclock files are ordinary ZIP archives containing a pack directly or in one enclosing folder. Each import creates a separate copy and preserves existing packs.

Bundled packs: /var/jb/Library/Application Support/NextClock/Packs. Imported packs: /var/mobile/Library/NextClock/Packs. User packs survive upgrades.

Image limits: 2048 px per dimension, 240 frames, 8 MB encoded and 96 MB decoded per glyph. Rendering also limits decoded glyph frames to 48 MB per clock row; a row exceeding this budget falls back to the system clock. ZIP limits: 64 MB compressed/expanded, 512 entries. Stored and deflated ZIP entries supported; encryption, ZIP64 and symlinks rejected.

## Build
Theos, Xcode, patched iOS 16.5 SDK. Run the checks in [Tests/README.md](Tests/README.md), then `make package FINALPACKAGE=1`. arm64 and arm64e, rootless, deployment iOS 15. The rootless package architecture remains `iphoneos-arm64`. PreferenceLoader required.

## Acknowledgements
NextClock is independently implemented, inspired by AniTime by yandevelop and FlexClock by tr3tol. The legacy adapter targets iOS 15 classes. The experimental prominent-clock adapter consults FlexClock private-interface names; compiler-specific C/runtime workarounds are not included.

Anime artwork is from AniTime; Pixel, CRT and Sakura artwork is from the supplied FlexClock reference. These are third-party assets, not original NextClock artwork. They are included with the creators’ permission, obtained by RAtnik00. AniTime source code is not included.

## Adaptations
Staged imports and confirmations preserve existing packs; every glyph is validated; reset clears all implemented preferences. iOS 15 clocks are bounded to screen width. Exact frame delays improve on uniform reference playback. About names NextClock and RAtnik00; acknowledgements are in this README.

## Device verification
Local release checks passed on the development device, alongside native pack/ZIP and resource tests. Other devices still need validation, especially iOS 16/17 wallpaper, music and charging transitions. Report model, exact iOS, jailbreak and installed version with any issue.

## Roadmap
An iOS 13–14 port is planned as a separate update. Version 1.1.0 requires iOS 15 or newer; it does not include that port.

## License
NextClock source is provided under GPL-3.0. The settings layout is adapted from FlexClock (tr3tol, GPL-3.0); its attribution is retained here. Halloween artwork was generated with the built-in image generation tool and animated with the accompanying pack builder. This source license does not grant rights to third-party artwork.

## Support
NextClock is free. Optional support: [buycoffee.to/ratnik00](https://buycoffee.to/ratnik00). Supporting the developer does not unlock extra features.

### Halloween pack

Animated pumpkin digits with flickering warm light and gentle motion; 24 APNG frames per glyph, transparent background, and a static option. Select Halloween in preferences. A localized Halloween greeting appears at the top of the settings page.
