# 앱 셸 및 본편 전투 구현 계약

> 현재 구현 기준선은 완료된 앱 셸과 20스테이지 회색 상자입니다. 다음 구현에서 바뀌는 전투 규칙과 완료 기준은 [본편 혼합 전투 완성도 명세](COMBAT_HYBRID_SPEC.md)가 우선합니다.

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

혼합 전투 승격 시 schema 1 세션을 위한 순수 변환 경계를 추가합니다. 정확한 반환 DTO는 구현 전에 테스트로 고정하되 다음 책임은 바꾸지 않습니다.

- 변환은 활성 세션을 수정하지 않고 schema 2 후보 DTO와 전체 오류를 반환합니다.
- 새 후보 `GameSession`이 변환 결과를 `restore_state()`로 검증합니다.
- `AppRoot`는 검증된 후보를 schema 2 봉투로 저장한 뒤에만 활성 세션으로 교체합니다.
- 전투 중 긴급 재배포 같은 새 프레젠테이션 명령은 공개 표면에 추가하지 않습니다.

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

혼합 전투 승격 후 목표 봉투는 다음과 같습니다. 현재 구현과 완료된 앱 셸 기준선은 schema 1입니다.

```json
{
  "schema_version": 2,
  "saved_at_unix": 0,
  "last_gameplay_tab": 0,
  "session": {}
}
```

현재 구현은 schema 1을 사용하며 혼합 전투 승격과 함께 schema 2로 올립니다. `SaveRepository.load()`는 missing, valid, legacy-schema, backup-recovered, corrupt, newer-schema를 구분합니다. 저장소는 schema 1·2 봉투와 세션 딕셔너리를 전달할 뿐 세션 내부 필드를 변환하지 않습니다. schema 1 세션 변환·검증은 비활성 후보 `GameSession`, 실행 순서는 `AppRoot`가 맡습니다.

쓰기는 임시 파일, 검증, 백업 회전과 주 파일 교체 순서로 수행합니다. 마이그레이션은 검증된 schema 2 후보 저장이 성공하기 전까지 활성 세션과 기존 파일을 바꾸지 않습니다. 잘못된 내용은 조용히 새 게임으로 바뀌지 않습니다.

Offline results are applied to the session and saved before their read-only report is shown. A report is presentation data, not a claimable reward.

Stable content IDs are:

- Operators: `debugger`, `build_engineer`, `sprite_artist`, `qa_imp`
- Patches: `frame_skip`, `unsafe_build`, `reward_bypass`, `rollback_lock`, `safe_mode`

## 현재 구현 기준선과 혼합 전투 승격

- A normal stage contains three enemies and has no failure timer.
- Stages 10 and 20 contain the Watchdog Process and use a 25-second timer.
- A failed boss enters automatic maintenance farming, earns enough bits to avoid a soft lock, then retries without a manual combat button.
- Patch slots unlock at stages 3, 11, and 15 on the first run. Discovered content and slot unlocks remain available on later runs, while equipped patches reset.
- Operators unlock progressively on the first run and all remain available after the first version update.
- Clearing stage 20 enables a voluntary version update. It resets run progress and grants one patch note.

혼합 전투 승격은 위 20스테이지 흐름을 보존하면서 보스전에서만 요원 HP·DOWN·QA 자동 구조와 역할 효과를 활성화합니다. 일반전은 요원 피해나 전원 DOWN을 만들지 않습니다. 상세 수치, 실패 조건, 진단과 UI 정보 예산은 [COMBAT_HYBRID_SPEC.md](COMBAT_HYBRID_SPEC.md)를 따릅니다.

## Test boundary

Required automated checks cover monotonic health/cost growth, deterministic simulation, patch tradeoffs, boss-failure recovery, boss-only operator durability, QA rescue, schema migration, prestige reset/preservation, content validation, and headless loading of the main scene.
