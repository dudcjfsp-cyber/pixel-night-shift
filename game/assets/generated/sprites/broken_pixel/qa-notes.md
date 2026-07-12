# broken_pixel QA notes

## Base Lock

- Verdict: `PASS`.
- Canonical identity source: `base-source.png`.
- SHA-256: `7c1557ab06bfb15a7c1f8778f52860b261544bfd4f4e47131597fa8d5dc0ca07`.
- The source is one complete, uncropped full-body idle pose with the locked front-left presentation, readable 32 px silhouette, preserved white fracture/orange corner glitch/two feet, and a flat keyable background.
- No second candidate or identity reference was attached to row generation.

## Request and chroma contract

- Engine: `component-row`.
- States: `idle` (4 frames, 4 fps, loop) and `hurt` (4 frames, 8 fps, non-loop).
- Cell: 32x32, safe margin 3.
- Fit: pixel-perfect, logical height 26, shared palette 9, detail bias on, k-centroid, foot-centroid/bottom alignment.
- Auto chroma selected green `#00FF00`; nearest subject distance 248.38 clears the 96 erase radius. Extracted frames report zero chroma-adjacent pixels.

## Generation audit

- `idle`: first generated row accepted. Selected raw SHA-256: `354f03d1c30fe75e3425a17bdee2881ddcd17aec3e37c62f638130dbc8149209`.
- `hurt`: first generated row rejected because pose 3 contained detached white fracture particles, which violate the row prompt. The row alone was regenerated once with the exact same prompt and the same two references (`base-source.png` plus `references/layout-guides/hurt.png`). Selected raw SHA-256: `f24160056975f89f71fbb2e8ba1afcb6abac50869a2d1a44566ec7034dfb53aa`.
- Accepted rows each contain exactly four complete, separated poses with no crop, guide boxes, labels, shadows, or detached effects. Identity and locked facing remain stable.

## Automated QA

- `frames/frames-manifest.json.ok`: `true`.
- Extraction method: `components` for both states; four frames each; no slot fallback.
- `sprite-sheet-alpha.report.json.ok`: `true`.
- Atlas runtime variant: `pixel`; `manifest.json.frame_layout` contains eight absolute 32x32 rectangles.
- Initial extraction at logical height 32 passed the script threshold but consumed the entire 32 px cell and produced top/right/bottom edge-contact warnings. Independent canonical-versus-plain measurement found that the plain twins preserved margin but carried 388–443 colors and 51–71 partial-alpha pixels, so they were not suitable for shipping.
- SSoT calibration: `fit.logical_height` was changed from 32 to `32 - 2 * safe_margin = 26`. Extraction, preview, and compose were rerun from the same approved raw rows; no image was regenerated or locally repaired for this calibration.
- Palette calibration: the first 26 px extraction at palette size 10 left `idle` frame 3 at 13 total RGBA colors, one above the existing runtime validator's `<=12` contract. `fit.palette_size` was therefore changed from 10 to 9, and extraction, preview, and compose were rerun again from the same approved raw rows.
- Final canonical frames have binary alpha, 10–11 total RGBA colors per frame, zero edge pixels, and bboxes inside the cell: idle `(3–4, 3–7, 28–29, 29)` and hurt `(4–5, 3–4, 29, 29)`.
- Pixel pitch detection chose about 6.94/7.0 px and retained non-blocking collapsed-pitch/outlier warnings on `idle`; there are no final edge or chroma warnings.

## Motion verdicts

- `idle`: `pass`. A readable planted compression/pulse returns to a near-matching final pose, the frame 4 to frame 1 loop seam is stable, identity is coherent, and the feet remain bottom-aligned without anchor jumps.
- `hurt`: `pass`. Near-idle start, two clear rightward compression/recoil poses, and a readable recovery form a coherent start-middle-end sequence; no identity break, detached effect, or anchor jump remains.

Independent second motion opinion: `PASS` for both states on the final logical-height-26, palette-9 canonical previews. The reviewer measured an effectively seamless idle frame 3→0 alpha transition (IoU 0.995), stable feet/foot centroid, a clear hurt start→compression/flare→recovery sequence, one connected component per frame, and recommended shipping the canonical pixel-perfect variant. Minor non-blocking caveats: the idle squash is stronger than “subtle,” and the screen-left impact direction is less pronounced than the generic hurt reaction. No frame was redrawn, retimed, or substituted locally.
