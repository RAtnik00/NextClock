# NextClock 1.1.1 source provenance

This tree contains the stable 1.1.1 source, separate from the unpublished
local 1.2.0 development changes and Pro prototype.

Reconstructed from 45685a3f5b0ddd92a98ac333d35580f223f690b0 (1.1.0),
using the retained Havoc diagnostic safety patch and replacing the diagnostic
version string with 1.1.1 in control, NCVersion.h and the preferences Info.plist.
No feature changes were added during source publication on 2026-11-04.
The acknowledgement documentation was clarified at that date.

Published 1.1.1 DEB SHA-256: `e7c165205de49aa022f39adbbafded570e67f4415102fd89e9ed065fbe955ec1`.

## Build

On macOS, install Xcode, Theos and the patched iOS 16.5 SDK expected by the Makefiles.
Set THEOS to your Theos installation, then run:

```sh
make clean package FINALPACKAGE=1
```

Both tweak and preferences bundle build for arm64 and arm64e, deployment target
iOS 15.0, rootless package scheme. PreferenceLoader is a runtime dependency.
The generated package is under packages/. General-purpose build tools and
Apple SDKs are not vendored in this repository.

## Checks

```sh
python3 Tests/check_resources.py
python3 Tests/run_pack_checks.py
python3 Tests/run_layout_safety_checks.py
```

See Tests/README.md for physical-device limitations. A fresh build need not have
an identical DEB hash because build paths, Mach-O metadata, signing and archive
metadata may vary. Binary comparison findings are recorded in the GitHub release.
