# sprite_artist Final QA

- Verdict: `PASS`
- Engine: `component-row` via sprite-gen `1.56.6`
- License: `LicenseRef-PixelNightShift-Original`
- Runtime: `32x32`, `Nearest`, binary alpha, safe margin `3`
- States: `idle` 4 frames at 4 fps loop; `upgrade` 4 frames at 6 fps non-loop
- Extraction and atlas reports passed before final-only delivery pruning.
- `idle`: restrained breathing/blink loop, stable beret and stylus identity, shared baseline and clean wrap.
- `upgrade`: readable focus/lift/finish sequence with stable anatomy, attached stylus and no detached effects.
- Atlas: `128x64`, eight explicit `32x32` rectangles, no degraded static fallback.
- Atlas SHA-256: `f0f8ca89cc5c0a0107cb6b2bf6aaf31d88ac6096eb78bf38403fd80e89d0c3f9`
- Manifest SHA-256: `9f52a2f17ce16da19e4f08d0877a075f3e015b7916c1c87be93998a1571c85b5`
- Delivery profile: `final-only`; generation rows, candidates, extracted frames and visual QA previews are intentionally not versioned.
