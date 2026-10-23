# NextClock 1.1.0 — release review

Date: 23 October 2026. Publication authorized by RAtnik00 after reporting that RC1 checks passed.

## Passed

- `git diff --check`.
- Nine languages, 80 keys each; no duplicates or missing UI keys; matching format placeholders; consistent control/header/bundle version.
- Native tests compile and execute the actual shared Objective-C pack and ZIP code on macOS. Stored, deflated and data-descriptor ZIPs pass; ten malformed/unsupported archive fixtures are rejected.
- All six bundled packs pass complete ImageIO decoding.
- Final Theos build succeeds for arm64 and arm64e for both the tweak and Preferences bundle.
- Final DEB metadata, localized resources and bundled pack contents checked. Development graphics sources/drafts and test scripts are excluded.

## Corrected during review

- Closing animation frame now matches the extra key time at 1.0.
- Import picker accepts unknown file-provider types, including unregistered .nextclock files; actual data still goes through bounded validation.
- ZIP central/local flags, sizes, CRC declarations, directory bounds and ambiguous path components validated.
- About and diagnostics use a shared version; obsolete version translations removed. Beta notice now states limited device testing.
- Diagnostic view traversal bounded to 120 queued views.
- Removed Finder metadata from the bundled-pack source directory. Graphic drafts preserved outside the installed layout.

## Device confirmation and remaining coverage

The charge9 video with Anime and a visible date showed no overlap and automatic return. After installing RC1, RAtnik00 reported that all requested device checks passed on the development iPhone 7 Plus (iOS 15.8.8). Native-speaker review of new translations and checks on additional devices remain useful. Repeat modern-adapter wallpaper/music/charging tests on iOS 16/17; current iOS 15 results do not prove modern compatibility.

The Halloween pack is built in and cannot be deleted in the pack UI. The greeting is intentionally persistent until a later update; no automatic holiday expiry has been added.
