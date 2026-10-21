# Circuit 1.2

The approved industrial-yellow direction is implemented with fixed transparent RGBA base artwork, cyan light sweeps and pulsing red colon modules. Atlas generated with image_gen from the approved concept; the six was separately corrected. Generated artwork extends the reference style and is not a pixel-identical extraction of every concept numeral.

Source atlas: Circuit-original-style-atlas.png; corrected six: Circuit-original-style-6.png. To rebuild: Python 3 + Pillow and FFmpeg (or imageio-ffmpeg), then run package_circuit_release.py. Override FFMPEG_BINARY if necessary. Writes transparent PNG/APNGs to layout/.../Packs/Circuit and a .nextclock archive/MP4 preview under outputs/circuit-release. The colored video backdrop is not included in glyphs.

24 frames at 100 ms per frame; fixed alpha per glyph; 2.4-second periodic loop. All 11 APNGs decoded by Apple ImageIO. Validate appearance and performance on iPhone before treating as stable. Older draft source files are not part of this release.
