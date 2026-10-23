# Changelog

## 1.1.0 — October 23, 2026

- iOS 15 charging: hide custom and stock time at the start of the system content transition; delay restoration until the return animation has elapsed, explicitly schedule the final layout, and preserve date placement during fading.
- Charging with Anime and a visible date was verified from a tester video; RAtnik00 reported successful final RC1 device checks. iOS 16/17 support remains experimental and requires further regression testing.
- Bundle the animated, transparent Halloween pumpkin pack and static fallback. Add a localized greeting at the top of settings. Bundled packs cannot be deleted in pack management; the greeting remains until a later update removes it.
- Add Italian and French preferences. Nine languages are included.
- Correct the animation timeline's closing frame, support unknown file-provider types in the import picker, and reject inconsistent ZIP headers and paths.
- Use a shared version in diagnostics and About. Replace the outdated claim that no iOS 16/17 device testing exists with an experimental/limited-testing notice.
- Add native pack/ZIP checks and localization/version validation.

## 1.1.0~beta3

- German, Polish, Swedish and Norwegian Bokmål preferences.
- Experimental immediate layout and static-frame retention for screen wake/attachment.

## 1.1.0~beta2

- Select the modern adapter without requiring the missing displayDate getter.
- Experimental transient-status and stock-clock visibility fixes for iOS 16/17.
