# 앱 셸 및 회색 상자 구현 계약

## 의존 방향

```text
AppRoot -> screens / overlays
        -> GameSession -> domain rules/content
        -> SaveRepository -> user:// files
        -> AudioDirector / PresentationAssets

GameplayView -> GameSession commands and snapshots
Domain -> no presentation, file, clock, lifecycle, or audio dependency
```

- `game/domain/` owns combat, progression, state, diagnosis, and prestige invariants.
- `game/content/` is the source of truth for operator, patch, and balance values.
- `game/app/game_session.gd` coordinates commands and exposes read-only snapshots to the view.
- `AppRoot` is the only composition root. It owns navigation, one active `GameSession`, simulation ticks, lifecycle coordination, save timing, and one `AudioDirector`.
- `game/persistence/` owns the save envelope and `user://` file operations. It treats session data as an opaque dictionary and does not import domain types.
- `game/presentation/` draws the state and forwards player intent; it never writes domain fields directly.
- `BattleLaneView` and `AudioDirector` receive presentation snapshots or semantic cues only. Neither imports `GameSession` nor changes simulation state.
- `game/assets/` contains generated runtime files and provenance manifests. `tools/` owns deterministic regeneration; the game does not generate assets at runtime.

## Animated presentation assets

`game/assets/manifest.json` schema 2 is the activation boundary for generated character animation. Its `active_sprite_runs` map points to per-character native `manifest.json` files and pins both manifest and atlas SHA-256 values. The original 23 static asset entries remain present and validated.

`PresentationAssets` is the only loader for this mapping. It validates the catalog, hashes, component-row contract, cell size, required states, atlas dimensions and every absolute `frame_layout` rectangle before exposing a fresh `SpriteFrames` resource to a caller. It never infers a grid or scans alpha at runtime, and an invalid active run stops presentation initialization instead of silently falling back.

`BattleLaneView` owns presentation-only playback clocks. Snapshot refreshes replace an enemy animation only when its visual asset ID changes. Operator upgrade cues start `upgrade`; enemy HP loss starts `hurt`; non-loop states return to `idle`. The existing bottom-centered upgrade pulse and hit tint are layered over those states. These cues do not change combat state or import domain rules.

The run layout, regeneration, curation and provenance contract is documented in [SPRITE_PIPELINE.md](SPRITE_PIPELINE.md).

## App shell ownership

Top-level screens are `BOOT`, `FIRST_START`, `OPERATIONS_ROOM`, `GAMEPLAY`, and `SAVE_RECOVERY`. At most one of `OFFLINE_REPORT`, `SETTINGS`, `VERSION_UPDATE_CONFIRM`, `RUN_SUMMARY`, or `ONBOARDING` may be open over the active screen.

- Views emit semantic requests; they do not open other scenes directly.
- `MainView` is retained as the gameplay view during this milestone and receives its session and audio director before entering the tree.
- A live run keeps ticking while the operations room or settings is visible.
- Background pause stops real-time ticks. `AppRoot` later applies a capped elapsed duration without exposing the system clock to the domain.
- The Android Back request closes the active overlay, returns gameplay to the operations room, and exits only from a root screen.

The full screen and lifecycle contract lives in [APP_SHELL_SPEC.md](APP_SHELL_SPEC.md).

## GameSession public surface

The presentation and tests may depend on these operations:

```text
tick(delta_seconds)
upgrade_operator(operator_id) -> bool
equip_patch(slot_index, patch_id) -> bool
remove_patch(slot_index) -> bool
prestige() -> bool
buy_legacy_cache() -> bool
snapshot() -> Dictionary
get_diagnosis() -> Dictionary
get_patch_preview(slot_index, patch_id) -> Dictionary
export_state() -> Dictionary
restore_state(data) -> PackedStringArray
```

`snapshot()` is a presentation DTO. Domain modules must not depend on its shape.
`export_state()` is a durable save DTO and must not reuse the presentation snapshot. `restore_state()` validates a complete candidate before replacing the active state and returns all validation errors without partially mutating the session.

`GameSession.new()` accepts no required argument. The greybox DTO uses these
stable keys so presentation and tests do not reach into domain state:

```text
stage, stage_enemy_index, stage_enemy_total
bits, patch_notes, run_count, mode
enemy { name, hp, max_hp, is_boss, time_left }
operators [{ id, name, level, unlocked, dps, upgrade_cost }]
patch_slots [patch_id]
patches [{ id, name, description, benefit, drawback, unlocked, equipped }]
unlocked_patch_slots, diagnosis
prestige_available, legacy_cache_level, legacy_cache_cost
maintenance_time_left, status_message, last_error
```

Diagnosis dictionaries use `kind`, `title`, `evidence`, and `severity`.
Patch previews use `can_equip`, `cost`, `summary`, `before_ttk`, `after_ttk`,
`before_bits_multiplier`, and `after_bits_multiplier`.

## Persistence boundary

The save envelope owner is `SaveRepository`, not `GameSession`.

```json
{
  "schema_version": 1,
  "saved_at_unix": 0,
  "last_gameplay_tab": 0,
  "session": {}
}
```

`SaveRepository.load()` distinguishes missing, valid, backup-recovered, corrupt, and newer-schema records. A write uses a temporary file, validation, backup rotation, and primary replacement. Invalid content never becomes a silent new game.

Offline results are applied to the session and saved before their read-only report is shown. A report is presentation data, not a claimable reward.

Stable content IDs are:

- Operators: `debugger`, `build_engineer`, `sprite_artist`, `qa_imp`
- Patches: `frame_skip`, `unsafe_build`, `reward_bypass`, `rollback_lock`, `safe_mode`

## Prototype rules

- A normal stage contains three enemies and has no failure timer.
- Stages 10 and 20 contain the Watchdog Process and use a 25-second timer.
- A failed boss enters automatic maintenance farming, earns enough bits to avoid a soft lock, then retries without a manual combat button.
- Patch slots unlock at stages 3, 11, and 15 on the first run. Discovered content and slot unlocks remain available on later runs, while equipped patches reset.
- Operators unlock progressively on the first run and all remain available after the first version update.
- Clearing stage 20 enables a voluntary version update. It resets run progress and grants one patch note.

## Test boundary

Required automated checks cover monotonic health/cost growth, deterministic simulation, patch tradeoffs, boss-failure recovery, prestige reset/preservation, content validation, and headless loading of the main scene.
