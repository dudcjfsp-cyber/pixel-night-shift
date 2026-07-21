# build_engineer Final QA

- Verdict: `PASS`
- Engine: `component-row` via sprite-gen `1.56.6`
- License: `LicenseRef-PixelNightShift-Original`
- Runtime: `32x32`, `Nearest`, binary alpha, safe margin `3`
- States: `idle` 4 frames at 4 fps loop; `upgrade` 4 frames at 6 fps non-loop
- Extraction and atlas reports passed before final-only delivery pruning.
- `idle`: restrained breathing loop, stable identity and baseline, seamless wrap, foot-centroid range `0.0px`.
- `upgrade`: readable brace/lift/settle sequence, stable anatomy and attached loop-ended tool, foot-centroid range `0.615385px`.
- Atlas: `128x64`, eight explicit `32x32` rectangles, no degraded static fallback.
- Atlas SHA-256: `46bb73368cea3a15525721486f1d0febed45d60d530c51f18fc82857e516139c`
- Manifest SHA-256: `83d6fd36692928ef112ecaae251fdd0a27504ab1a1e8aa08a5fbb42787644ec0`
- Delivery profile: `final-only`; generation rows, candidates, extracted frames and visual QA previews are intentionally not versioned.
