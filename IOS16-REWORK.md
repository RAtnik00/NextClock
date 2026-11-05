# iOS 16/17 clock lifecycle — 1.2.0 beta 5 local candidate

The iPhone X / iOS 16.7.5 user reports native clock/date duplication in the
wallpaper gallery even with NextClock disabled; uninstalling removes it.
The exact installed version was not recorded. This establishes an interaction,
not the precise failing method.

Changes:
- Untouched disabled modern hosts pass directly to the system layout. They do
  not enter the shared renderer, cache/reset date alpha, or style date fonts.
- Previously managed hosts release only owned time/date modifications on
  disable, detachment or an editing context. System alpha requests received
  while replacement is active are retained instead of assuming alpha=1.
- Respect usesEditingLayout (runtime ABI checked), and exclude known editor,
  gallery and snapshot container name patterns in the responder chain.
  These heuristics need real-device verification; they are not a complete
  map of Apple's private wallpaper hierarchy.
- Restore prior date fonts and alpha when the system replaces the date view.
- didMoveToWindow and transient-subtitle updates request a coalesced layout;
  no immediate layoutIfNeeded in the modern lifecycle callback.
- Do not request modern date/subtitle layouts while disabled.

The custom clock stays in its existing host and follows the native time view's
bounds. Wallpaper editing/gallery intentionally shows the native clock.
This iteration does not add per-wallpaper settings or an interactive editor
inside Apple's picker. The NextClock settings editor remains separate.

## Device verification (required before publication)

On iPhone X / iOS 16.7.5, first install with NextClock disabled and respring.
Open/close the wallpaper gallery 10 times, enter/cancel customization, switch
wallpapers and lock/unlock. Compare with the no-tweak baseline.
Enable NextClock, repeat, and confirm the live screen has exactly one clock,
while gallery/editor retain stock clocks. Toggle off without respring and
check restoration. Repeat with hide date, custom date fonts and seconds.
Check charging, full-screen music, transitions, custom packs and missing-pack
fallback. Then regress on iOS 15 (clock/date/charging/disable).

If the live clock disappears or the gallery still duplicates, export diagnostics
and record the exact action and installed version. Container names vary by OS.
No public package has been replaced by this local candidate.

## Local beta 6 — native alpha transitions and editor prototype

The modern adapter no longer feeds native time alpha through the legacy
status/deadline policy. It follows system alpha requests in their UIKit
transaction and keeps decoded glyphs through ordinary charging fades.
A charging subtitle alone does not mean the system clock is hidden.
The modern date is no longer forced to a cached alpha on every layout;
only the explicit Hide date setting owns a date-alpha override.

Live and editing layouts now use the same renderer/geometry. The editor still
uses NextClock's global pack; this is not a new entry in Apple's font picker
and does not implement per-wallpaper persistence. Gallery/preview/snapshot
contexts stay native. The responder-name exclusion remains a heuristic;
separate wallpaper processes may not have SpringBoard tweak injection.
Double-tap favorite cycling is disabled when usesEditingLayout is true.

Diagnostics capture bounded class-only snapshots for live/unknown, editor and
gallery/snapshot contexts (at most once per context), serialized to avoid
out-of-order report writes. No label text or wallpaper image is included.

Verify on iPhone X: plug/unplug, wake while charging, rapid reconnect, wallpaper
editor enter/cancel/save and return to live. Stock font selection changes the
native clock, not image glyph design. Compare system charging animation with
the no-tweak baseline, and regress disabled behavior and iOS 15.
