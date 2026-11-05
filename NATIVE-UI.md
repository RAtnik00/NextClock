# Native editor — beta 3

Implemented using UIKit, guided by Apple HIG. This is not an Apple certification or a completed accessibility/visual audit.

References:
- https://developer.apple.com/design/human-interface-guidelines/settings
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/design/human-interface-guidelines/layout

The editor is a native inset-grouped UITableViewController with related appearance/layout/time/color sections. Packs, color presets and time formats use pushed, scrollable, checkmarked selection lists. System table backgrounds adapt to light/dark appearance. Labels use preferred text styles, Dynamic Type and self-sizing rows; sliders provide a minimum 44-point-high area, native adjustable semantics and localized values. The canvas exposes a single VoiceOver summary rather than individual glyph images. Profile actions remain Pro-only.

Draft changes remain separate until Apply. Apply is disabled when the normalized draft matches the last applied appearance. A successful save updates that baseline and announces Applied to VoiceOver without a modal success alert. The enabled switch and favorite preferences are outside the appearance whitelist. Failed saves still report an error. Respring requires confirmation. Preview timers stop when the page or preview cell leaves the screen. The preview and renderer honor system Reduce Motion; no duplicate custom accessibility setting is added.

Automated checks cover complete/nonduplicate appearance-key reachability, exclusive profile actions, preference normalization/persistence, package resources, versions and both CPU architectures. Actual UIKit appearance and assistive technology behavior must be checked on devices:
1. Light and dark appearance on narrow/wide iPhone screens.
2. Default and largest accessibility text size; check multiline switches, subtitles and sliders for clipping.
3. VoiceOver order, switch state, adjustable sliders, selected choices and Apply announcement.
4. Scroll the preview out/in, select a pack, return and background/foreground Settings; confirm animation resumes only when visible.
5. System Reduce Motion on/off, with animation setting and Low Power Mode combinations.
6. Draft Back without Apply, changed/unchanged Apply state, and each Pro profile operation.
7. Cancel respring; confirm Settings stays open and no restart notification is sent.

No new claim of universal iOS 15.1 compatibility is made by this UI update. The earlier Havoc respring report still needs reproduction/device evidence.
