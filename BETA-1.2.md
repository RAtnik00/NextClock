# NextClock 1.2.0 beta 4

Beta 4 adds a Date section: System/Rounded/Serif/Monospaced design, 60–160% relative size, and System/Regular/Medium/Semibold/Bold weight. Defaults preserve the native font. Preview and renderer share font construction; old profiles migrate to system defaults and Pro profiles include date style. Reset clears all three values. Rendering targets only date descendants with compatible font getter/setter methods, preserves native fonts/attributed content and bounds conflicting reapplication attempts. Glyph packs and transient charging text are not font targets.

Device testing is still needed for clipping/position, reset/disable restoration, date updates, and charging on iOS 15 and modern iOS 16–17. Automatic tests do not reproduce the private Lock Screen hierarchy.

## Beta 3

Beta 3 replaces the free-form editor with native inset-grouped tables, pushes scalable checkmark choice lists for packs/colors/time formats, adapts row labels to Dynamic Type, exposes native labeled switches/sliders and a single accessible preview summary. All appearance keys remain reachable. Apply is enabled only for a changed draft and saves without a success-alert interruption. Preview and Lock Screen animations respect system Reduce Motion; there is no redundant custom accessibility toggle. Exact layout, contrast, VoiceOver order and largest accessibility sizes still require device testing.

Apple references: https://developer.apple.com/design/human-interface-guidelines/settings, https://developer.apple.com/design/human-interface-guidelines/lists-and-tables, https://developer.apple.com/design/human-interface-guidelines/accessibility. This is an implementation guided by HIG, not an Apple approval or a completed accessibility audit.

## Beta 2

Beta 2 simplifies the main page to Enabled, Configure clock, Favorites, Manage packs, Advanced, About & Support. Configure clock contains all appearance controls including the original eleven-color palette and Still in Low Power Mode. Advanced contains diagnostics, stable releases, respring and reset. Support moves into About. All existing preference keys/defaults are reused. The legacy experiment retains its old controls in LegacyRoot.plist. Pro profile actions stay Pro-only. Includes the previously prepared layout reentry/ABI safeguards; the reported Havoc iOS 15.1 loop is still unconfirmed without a device reproduction.

This beta is prepared for local device testing; do not imply the Havoc failure is confirmed fixed.

## Beta 1 features

Free features: favorite pack selection, optional double-tap on the visible clock digits to cycle through at least two installed favorites, and animated draft preview with an explicit Apply button. Deleted packs are skipped; an empty or single-pack favorite list does nothing. The gesture defaults to off. System long-press recognizers are not forced to fail.

Preview uses actual pack assets and the current time but its layout is illustrative. Changing a draft does not change the Lock Screen until Apply; enabled state and favorite settings remain unchanged. Save/load/rename/delete profiles remains compiled only for Pro. Scheduling is not implemented in this beta.

Fixes: preview foreground notifications cannot restart a hidden page; preview animation phases are preserved across seconds redraws.

Rollback: Settings → NextClock → Stable releases / Downgrade opens https://ratnik00.github.io/repo/releases/. Stable 1.1.0 and older packages are retained. Download the selected .deb and open it in a package manager, or use its version selection. Preferences and imported packs are not deleted. Features added in this beta are unavailable after downgrade. Package managers may offer the beta again as an update.

## Validation

Run check_resources.py, run_favorite_checks.py, run_profile_checks.py and run_pack_checks.py under Tests. Build the default rootless package and verify it with check_pro_package.py <deb> free. Rebuild NC_PRO=1 and use the pro mode to confirm profile isolation. Both tweak and preferences binaries must contain arm64 and arm64e.

Device testing remains required: select at least two favorites, enable switching, tap both digits and empty space, try one/zero/deleted favorites, lock/wake, long-press wallpaper editing, charging/date/seconds and music transitions. Preview cancel/back must leave existing appearance unchanged; Apply must update the Lock Screen. Close the preview and background/foreground Settings; animations must remain paused. Test installation and rollback to stable 1.1.0 without deleting user packs. iOS 16–17 remains experimental.

## Local beta 5 candidate

Modern disabled/editor lifecycle rework; see [IOS16-REWORK.md](IOS16-REWORK.md). Not published or device-verified.

## Local beta 6 candidate

Native-alpha charging transitions and a shared modern editor renderer prototype. Gallery thumbnails stay native; no per-wallpaper selection yet. Device verification required.
