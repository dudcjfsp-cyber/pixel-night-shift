# Pilot Base Lock Record

Decision date: 2026-07-12 (Asia/Seoul)

Gate result: `y` for both pilot assets. The user approved every candidate on
visual preference and authorized the work session to select one canonical base
per asset using the technical Base Lock criteria. The original alternatives
remain in `candidates/` for audit, but they must not be used as a second identity
anchor.

## debugger

Canonical base: `candidates/debugger/debugger-b.png`

SHA-256: `5281d05202826c4e067ae9c1024ced14070ffe75f23d72c9a7dacafaa31b910b`

Technical verdict: PASS.

- The full body is present with no crop. The detected subject bounds are
  `(417, 169)-(900, 1045)` inside a `1254x1254` image, leaving generous padding
  on every side.
- Its compact, straight silhouette and simpler cable/tool shape remain more
  readable at the target 32px cell than candidate A's longer cable loop and
  wider action footprint.
- The horizontal cyan visor, dark navy technical suit, steel boots, and handheld
  diagnostic probe preserve the existing debugger identity and required prop.
- The pose is a single planted idle with a clear front-right orientation.
- The magenta border is tightly clustered around RGB `(246, 6, 233)`; 95% of
  border pixels are within distance `9.90`, and the maximum observed border
  distance is `36.89`, safely below the pipeline's default hard-key threshold.
  It is therefore trivially keyable despite minor generated color variation.

Candidate A remains an approved visual alternative, not an anchor. It was not
chosen because the hanging cable loop, extended arm, and denser equipment create
more fragile detail and a less compact silhouette at 32px.

## broken_pixel

Canonical base: `candidates/broken_pixel/broken-pixel-a.png`

SHA-256: `7c1557ab06bfb15a7c1f8778f52860b261544bfd4f4e47131597fa8d5dc0ca07`

Technical verdict: PASS.

- The complete creature and both feet are present with no crop. The detected
  subject bounds are `(269, 317)-(968, 1060)` inside a `1254x1254` image, with
  ample padding on every side.
- The broad, squat block silhouette best preserves the existing broken-pixel
  identity at 32px. The two pale eyes, central white fracture, orange damaged
  corner, and two feet remain distinct at small size.
- All jagged damage is connected to the main body, which is safer for component
  extraction than detached debris.
- The pose is one stable front-left idle with a clear shared foot baseline.
- The green border is tightly clustered around RGB `(8, 248, 16)`; 95% of
  border pixels are within distance `8.66`, and the maximum observed border
  distance is `28.18`, safely below the pipeline's default hard-key threshold.

Candidate B remains an approved visual alternative, not an anchor. It was not
chosen because its taller, narrower body and raised orange corner weaken the
wide broken-block silhouette when reduced to the target cell.

## Ownership and next step

- `debugger-b.png` is the only identity source for the debugger pilot run.
- `broken-pixel-a.png` is the only identity source for the broken_pixel pilot
  run.
- Each accepted file must be copied by `prepare_sprite_run.py` into its own run
  as `base-source.*`; no other candidate may be attached to row generation.
- Runtime code must not reference this staging directory.
