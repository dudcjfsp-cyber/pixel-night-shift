# Debugger Pilot QA Notes

## Base Lock

- Verdict: PASS (canonical base locked before row generation).
- Source: `../_base-lock/candidates/debugger/debugger-b.png`.
- SHA-256: `5281d05202826c4e067ae9c1024ced14070ffe75f23d72c9a7dacafaa31b910b`.
- Direction truth: the locked base's front-right presentation.
- Technical basis: complete uncropped body, stable final pixel-art proportions and palette, preserved cyan visor/chest display/handheld probe identity, readable small silhouette, one idle pose, and flat keyable background.

## Request and Chroma

- Engine: `component-row`.
- States: `idle` (4 frames, 4 fps, loop) and `upgrade` (4 frames, 6 fps, non-loop).
- Cell: 32x32 with a 3 px safe margin.
- Fit: pixel-perfect, logical height 26 (`32 - 2 * 3`, so the fit path preserves the requested safe area), shared palette 10, source-outline preservation (`outline = false`), k-centroid, foot-centroid/bottom.
- Chroma: auto-selected magenta `#FF00FF`; minimum subject distance 201.35 clears the 96 erase radius.

## Row Generation Audit

- Normal component-row generations used the stored `prompts/<state>.txt` verbatim and exactly two references: `base-source.png` for identity and the matching layout guide for layout only.
- During the later idle seam-recovery pass, two explicitly authorized fresh frame-escape generations added `references/motion-basis/idle-seam3.png` as a third, motion-only reference while retaining the base as the identity reference and the guide as the geometry reference. After both fresh generations failed, two whole-row image edits used that same seam-3 row as the edit target plus the base and guide. No extracted frame was edited, reordered, or retimed.
- `idle`, first phase: the initial row was visually valid but its 32-height extracted frames measured 348-368 opaque pixels under the generic 400-pixel threshold. It was regenerated once, and that result became the pre-independent-QA candidate.
- `upgrade`, first phase: the initial row produced a collapsed pixel-pitch consensus (32.78) and 97-102 opaque pixels, so it was rejected. Regeneration 1 was rejected before extraction for detached cyan visor effects. Regeneration 2 extracted cleanly but was rejected because one frame lost every cyan identity pixel. Regenerations 3 and 4 were rejected before extraction for detached cyan signal rays. Regeneration 5 became the pre-independent-QA candidate.
- No master sheet, slot fallback, local drawing, extracted-frame manipulation, manual retiming, or static fallback was used.

## Independent QA Correction and Total Regeneration History

- The pre-independent-QA conclusion marked regeneration 5 as `upgrade: PASS`. Independent review invalidated that conclusion: all four canonical frames had an 8-neighbor-detached 1 px black probe/antenna fragment, and one frame retained visor cyan but lost attached chest/tool cyan identity. The earlier visual and 4-neighbor-oriented checks were insufficient for this failure mode.
- The `upgrade` prompt was strengthened to require one thick 8-neighbor-connected character/probe silhouette, no isolated black/cyan pixels or signal marks, and attached visor, chest, and tool cyan markers sized to survive logical-height-26 extraction.
- Connectivity regeneration 1 failed at frames 1 and 3 with detached 1 px black fragments and weak tool cyan. Connectivity regeneration 2 failed at frame 0 with a detached 1 px fragment, while frame 1 retained visor cyan only. Connectivity regeneration 3 failed at frames 0, 1, and 3 with detached 1 px fragments and missing probe-body cyan.
- Connectivity regeneration 4 is the active `raw/upgrade.png`. It uses a chunky monolithic probe with an integrated short antenna and large attached cyan tool panel; all four extracted frames pass the independent-review gate.
- Independent review subsequently invalidated the pre-independent-QA `idle` identity verdict: connectivity, motion, and seam passed, but all four frames had `tool cyan = 0` even though the raw row contained a cyan probe tip.
- A deterministic `palette_size = 11` experiment preserved single-component alpha, binary alpha, safe margins, the color cap, and the final `upgrade`, but still produced `tool cyan = 0` in every idle frame. It was rejected and the run was deterministically restored to palette 10 before new generation.
- Idle identity regeneration 1 preserved attached tool cyan but failed because frames 0/1 lost chest cyan and frames 2/3 lost visor cyan during logical-height-26 extraction. Idle identity regeneration 2 used broad visor, chest, and monolithic-probe cyan blocks and passed the identity gates, but later independent motion QA rejected its loop seam; it is no longer active.
- Idle seam regeneration 1 retained identity and acceptable foot stability, but motion changes were back-loaded: consecutive alpha IoU/XOR were 0.984/5, 0.990/3, and 0.884/37, with last-to-first 0.890/35 and 0.388 px wrap foot drift. It was rejected.
- Idle seam regeneration 2 had a strong 0.988 wrap, but consecutive alpha IoU/XOR of 0.988/3, 0.984/4, and 0.992/2 made the loop nearly static. It was rejected as a near-hold.
- Idle seam regeneration 3 was preserved as `references/motion-basis/idle-seam3.png`. Its first alpha mask repeats, but the opaque RGBA content does not: frame 0 to 1 changes 21 RGBA pixels, including 5 visor, 4 chest, and 1 tool-region pixels, and turns on the cyan visor scan at `(14, 7)`. Its middle motion and wrap are controlled, so it became the technically preferred seam candidate.
- Fresh frame-escape generation 1, using the preserved seam-3 row only as a motion reference, failed with alpha IoU/XOR 0.922/21, 0.838/45, 0.992/2, and 0.907/24; frames 2 and 3 formed a hold and the wrap failed. Fresh frame-escape generation 2 failed automated extraction because idle frame 03 had only 224 opaque pixels.
- Whole-row image edit 1 failed identity because frame 2 lost visor cyan and also introduced excessive internal change; its alpha IoU/XOR was 0.893/29, 0.907/25, 0.938/16, and 0.953/12. Whole-row image edit 2 failed with oversized first/middle transitions and another hold edge: alpha IoU/XOR/RGBA-change triples were 0.865/37/113, 0.859/39/115, 0.980/5/29, and 0.980/5/33, with 0.269 px wrap foot drift.
- Stochastic regeneration was stopped after those failures. The preserved seam-3 source was restored byte-for-byte to `raw/idle.png`, then the preview, extraction, atlas composition, and reports were regenerated from it.
- Total `upgrade` image-generation history: 10 calls — one initial call plus nine regenerations. The active result is the ninth regeneration. Total `idle` image-generation/edit history: 11 calls — one initial call plus ten regenerations or whole-row edits. The active result is idle regeneration 6 (overall call 7), restored after the four later failed attempts.

## Extraction and Palette Calibration Status

- Target-size calibration reference: the shipped 32x32 debugger contains 356 opaque pixels. An interim 300-pixel floor is 84% of that known-good baseline and was used without slot fallback.
- With the final logical height 26, final extracted opaque counts are:
  - `idle`: 248, 248, 256, 247.
  - `upgrade`: 297, 299, 304, 292.
- These counts are consistent with the area-scaled baseline (`356 * (26 / 32)^2 ~= 235`). All eight frames were visually inspected as complete full-body silhouettes inside the 3 px safe area, with stable direction and identity.
- Final size-calibrated QA floor: 230 pixels. Basis: `356 * (26 / 32)^2 = 235.0`, so 230 is a strict approximately 98% floor. This floor passes the valid 247-304 pixel frames while the rejected 97-102 pixel upgrade attempt remains blocked.
- Calibration experiment: `fit.palette_size = 9` plus automatic outline enforcement produced 14-15 RGBA colors in some frames because the outline pass added derived dark shades. The final target-specific contract keeps the raw row's existing hard dark outline, disables derived outline enforcement, and restores the shared palette to 10.
- Final per-frame RGBA color counts are `idle` 9/11/9/9 and `upgrade` 10/9/9/9; every frame is at or below the 12-color project gate, has only alpha 0/255, and uses one clean transparent RGBA value.
- Every alpha bounding box stays within the 3 px vertical safe margin; all frames are full-body, bottom-aligned, and retain visible dark outline continuity and cyan identity details.
- Final `idle` 8-neighbor component counts are exactly 1/1/1/1 with component sizes 248/248/256/247. All cyan pixels belong to the main component. Semantic cyan counts `(visor/chest/tool)` are 4/1/1, 5/1/1, 4/1/1, and 5/1/1 respectively, so all three markers survive every frame.
- Final `upgrade` 8-neighbor component counts are exactly 1/1/1/1 with component sizes 297/299/304/292. All cyan pixels belong to that main component. Semantic cyan counts `(visor/chest/tool)` are 5/3/2, 4/2/2, 4/2/2, and 4/2/1 respectively, so no frame relies on visor cyan alone.
- Automated verdict: PASS. `frames/frames-manifest.json.ok` is true with no slot fallback.

## Motion Verdict

- `idle`: strict PASS after final independent motion review. Four complete humanoid frames retain helmet, visor, chest display, attached probe, two arms, and two legs. Consecutive alpha IoU is 1.000/0.953/0.957 and last-to-first is 0.996. The corresponding alpha-XOR/RGBA-change pairs are 0/21, 12/69, 11/69, and 1/26. Foot-centroid range is 0.260 px, last-to-first foot drift is 0.085 px, and every frame keeps the bottom baseline at y=29.
- The unchanged frame-0-to-1 alpha mask is not an exact animation hold. Across the common opaque subject, 21 RGB/RGBA pixels change: 5 in the visor region, 4 in the chest region, and 1 in the tool region. The cyan visor scan turns on at `(14, 7)` from `(2, 1, 3, 255)` to `(61, 239, 246, 255)`. The remaining color changes form restrained breathing/intermediate shading; the scan closes over frame 3 to 0, where 26 RGBA pixels change. The loop therefore has a readable low-amplitude first phase, substantive middle motion, and a quiet seam rather than a duplicated hold.
- `upgrade`: PASS after independent-QA correction. Start is near idle, middle frames lift the now-monolithic attached diagnostic probe and brighten the visor while both feet stay planted, and the final frame returns near idle. Consecutive alpha IoU is 0.904/0.933/0.892; final-to-start is 0.983, supporting a clear non-loop start/middle/end progression. No missing/extra limb, identity drift, or detached alpha component remains.
- Classification: both states are stable simple states, not experimental locomotion. The independent review's blocking connectivity, cyan-identity, and idle-seam conditions are satisfied by the final candidate.

## Atlas Verdict

- The first compose invocation used the script's generic 400-pixel default and failed loudly; it was not accepted. Compose was rerun with the same request-recorded 230-pixel calibrated floor used by extraction.
- `sprite-sheet-alpha.report.json.ok`: true.
- Runtime manifest: `game_input = sprite-sheet-alpha.png`, `degraded_static_fallback = false`, `frame_variant = pixel`.
- Layout: 128x64 atlas, 32x32 cells, four absolute `frame_layout` rectangles for each of `idle` and `upgrade`.
- Final atlas SHA-256: `0674C5AA53C6DEADEFE44491F023092ABC9CD9A9A6182F7A57935E09E3B1034D`.
- Final manifest SHA-256: `4DD7AFD9C0846A409095EED2439972BBF139765705BFC6651652835126F7CC63`.
- Final raw idle SHA-256: `110DE29DC3A6073273F1A76BB068A1A57C10D5B50F76468380343A573C6FE3A0`.
- Preserved seam-3 motion reference SHA-256: `110DE29DC3A6073273F1A76BB068A1A57C10D5B50F76468380343A573C6FE3A0` (byte-identical to final `raw/idle.png`).
- Final idle QA GIF SHA-256: `5743F540F25CF2DF27CED502DA6530BDE99DA8BC60EE87038F961F4C99C91F3C`.
- Curation server was not launched by this worker; the root agent owns the combined pilot curation handoff.
