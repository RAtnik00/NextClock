# Release checks

On macOS with Xcode command-line tools:

```
python3 Tests/check_resources.py
python3 Tests/run_pack_checks.py
make package FINALPACKAGE=1
```

The resource check validates plist syntax, duplicate/missing translation keys, format placeholders, visible plist strings and version metadata. The native harness compiles the actual shared pack/ZIP headers against Foundation and ImageIO, uses temporary fixtures, tests stored/deflated/data-descriptor ZIPs and rejects damaged, oversized, encrypted, symlink, duplicate and traversal archives. It fully decodes all bundled packs. It never reads or changes installed user packs.

Device checks remain necessary: charging with date on/off, Circuit/Anime/Halloween, seconds, Low Power Mode, screen sleep/wake, disabling/re-enabling the tweak, missing-pack fallback, folder/ZIP/.nextclock import, deleting user packs, wallpaper editing and music artwork transitions. Repeat the modern-adapter checks on iOS 16/17 before claiming a fix there.
