# qa_imp Final QA

- Verdict: `PASS`
- Engine: `component-row` via sprite-gen `1.56.6`
- License: `LicenseRef-PixelNightShift-Original`
- Runtime: `32x32`, `Nearest`, binary alpha, safe margin `3`
- States: `idle` 4 frames at 4 fps loop; `upgrade` 4 frames at 6 fps non-loop
- Chroma: magenta `#FF00FF`; palette size `12`, `detail_bias = false`
- Extraction and atlas reports passed before final-only delivery pruning.
- `idle`: planted breathing loop with stable horns, checklist and one retained mint identity pixel per frame.
- `upgrade`: readable checklist raise/acknowledgement/settle sequence, stable anatomy and attached prop.
- Atlas: `128x64`, eight explicit `32x32` rectangles, no degraded static fallback.
- Atlas SHA-256: `e806c3f4f5dd3974f9d8ac83da29214bf214d57df51d27e55863b5e03f541ef7`
- Manifest SHA-256: `8862f920a5b17d606601f62a39d9726eda86122a606200b7a995385f1fff2936`
- Delivery profile: `final-only`; generation rows, candidates, extracted frames and visual QA previews are intentionally not versioned.
