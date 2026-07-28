# 앱 셸·Product V2 구현 계약

> 현재 코드 기준선은 완료된 앱 셸, schema 3 로컬 저장과 Product V2 본편이다.
> V1과 Legacy Combat V2는 이관·회귀 비교용으로만 보존한다. 다음 변경은
> [Product V2.1 계획](PRODUCT_V2_1_PLAN.md)의 구조와 저장 게이트를 따른다.

## 의존 방향

```text
AppRoot -> screens / overlays
        -> ProductLoopSession -> product_v2 domain/content
        -> ProductV2SaveMigrator -> Legacy GameSession validation
        -> SaveRepository -> user:// files
        -> AudioDirector / PresentationAssets

Product V2 views -> ProductLoopSession commands and snapshots
Domain -> no presentation, file, clock, lifecycle, or audio dependency
```

- `game/domain/` owns combat, progression, state, diagnosis, and prestige invariants.
- `game/content/` is the source of truth for operator, patch, and balance values.
- `game/app/product_v2/product_loop_session.gd`가 현재 제품 명령과 읽기 전용 스냅숏을
  조정한다. `game/app/game_session.gd`는 Legacy 이관·회귀용이다.
- `AppRoot` is the only composition root. It owns navigation, one active product session, simulation ticks, lifecycle coordination, save timing, and one `AudioDirector`.
- `game/persistence/` owns the save envelope and `user://` file operations. It treats session data as an opaque dictionary and does not import domain types.
- `game/presentation/` draws the state and forwards player intent; it never writes domain fields directly.
- `BattleLaneView` and `AudioDirector` receive presentation snapshots or semantic cues only. Neither imports a session type nor changes simulation state.
- `game/assets/` contains generated runtime files and provenance manifests. `tools/` owns deterministic regeneration; the game does not generate assets at runtime.

## Product V2 설계 게이트

판정은 `PASS`다. 아래 격리 구현과 schema 3 본편 승격은 완료됐다.

```text
game/content/product_v2/ -> 기존 ContentCatalog의 요원·패치 정의를 참조
game/domain/product_v2/  -> 장면·파일·시계에 독립적인 야간 상태와 시뮬레이터
tests/product_v2/        -> 관찰 가능한 핵심 행동만 검증
```

- 2단계에서는 현재 `GameState`, `BattleSimulator`, `HybridBossSimulator`, Legacy
  `CombatV2State`에 Product V2 분기를 추가하지 않는다.
- Product V2 전용 카탈로그가 9+1웨이브, 안정도, 침입, 시간과 별 기준을 소유한다.
- 야간 상태가 하위 상태, 웨이브·완료 수, 타이머, 적·보스·요원 런타임과 종료 이유를
  소유하고 표시 계층은 위치·애니메이션만 계산한다.
- 2단계에서는 `GameSession`, `AppRoot`, `project.godot`과 본편 저장 schema를 변경하지 않는다.
- 3단계의 별도 `DefenseLabSession`이 격리 상태와 카탈로그를 소유한다. 해당 실행 경로의
  조정자만 세션 `tick()`을 호출하고 Defense Lab 화면은 사용자 명령을 전달하며
  `snapshot()`만 읽는다.
- 승인된 Product V2는 `ProductLoopSession`을 제품 경계로 사용하고 schema 3 전환을
  적용했다. Defense Lab은 격리 회귀 경로로 남는다.

## Animated presentation assets

`game/assets/manifest.json` schema 2 is the activation boundary for generated character animation. Its `active_sprite_runs` map points to per-character native `manifest.json` files and pins both manifest and atlas SHA-256 values. The original 23 static asset entries remain present and validated.

`PresentationAssets` is the only loader for this mapping. It validates the catalog, hashes, component-row contract, cell size, required states, atlas dimensions and every absolute `frame_layout` rectangle before exposing a fresh `SpriteFrames` resource to a caller. It never infers a grid or scans alpha at runtime, and an invalid active run stops presentation initialization instead of silently falling back.

`BattleLaneView` owns presentation-only playback clocks. Snapshot refreshes replace an enemy animation only when its visual asset ID changes. Operator upgrade cues start `upgrade`; enemy HP loss starts `hurt`; non-loop states return to `idle`. The existing bottom-centered upgrade pulse and hit tint are layered over those states. These cues do not change combat state or import domain rules.

The run layout, regeneration, curation and provenance contract is documented in [SPRITE_PIPELINE.md](SPRITE_PIPELINE.md).

## 현재 Product V2 App shell ownership

Current top-level screens are `BOOT`, `TITLE`, `PROLOGUE`, `DAY_PREP`,
`NIGHT_ACTIVE`, `SHIFT_RESULT`, and `SAVE_RECOVERY`. `OPERATIONS_ROOM`, `GAMEPLAY`,
and `COMBAT_V2_RESULT` remain Legacy or isolated-test routes. At most one app-shell
overlay may be open over the active screen.

- Views emit semantic requests; they do not open other scenes directly.
- A validated save remains a pending candidate while `TITLE` is visible. `AppRoot` activates it only after `이어하기`, so combat ticks, periodic saves, and offline application cannot begin on the title screen.
- A new `ProductLoopSession` becomes active only after `PROLOGUE` completes or is skipped and the first save succeeds.
- Product V2 views receive the active product session and audio director before entering the tree.
- Only `NIGHT_ACTIVE` advances combat. `DAY_PREP` and `SHIFT_RESULT` have no background battle, and opening settings during a night pauses it.
- Background pause stops real-time ticks. `AppRoot` later applies a capped elapsed duration without exposing the system clock to the domain.
- Android/iOS pause·resume과 Web/desktop focus-out·focus-in은 같은 `AppRoot` 진입점을 사용합니다. `_backgrounded` 상태가 겹치는 알림의 중복 저장과 중복 오프라인 적용을 막습니다.
- `ProductLoopSession`은 최신 실패 보고서의 key·행·읽음 상태를 schema 3에 보존합니다. 화면은 이를 복제해 알림과 읽기 전용 모달만 표시합니다.
- 현장 보고서 모달과 자원 설명 말풍선은 Product V2 화면 내부 표면이며 앱 셸의 단일 `OverlayHost` 슬롯을 소비하지 않습니다.
- The Android Back request closes the active app-shell overlay, returns to the preceding Product V2 surface, and exits only from a root screen.

The cold-boot title and first-shift entry contract lives in [OPENING_EXPERIENCE_SPEC.md](OPENING_EXPERIENCE_SPEC.md). The remaining screen and lifecycle contract lives in [APP_SHELL_SPEC.md](APP_SHELL_SPEC.md).

## Legacy V1 `GameSession` public surface

> 이 절은 schema 1·2 이관과 회귀 테스트 전용이다. 새 제품 기능은 이 공개 표면에
> 추가하지 않는다.

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

아래는 Legacy V1의 schema 1→2 변환 이력이다. 현재 schema 1·2→3 경계는 뒤의
Product V2 persistence 계약이 우선한다.

- 변환은 활성 세션을 수정하지 않고 schema 2 후보 DTO와 전체 오류를 반환합니다.
- 새 후보 `GameSession`이 변환 결과를 `restore_state()`로 검증합니다.
- `AppRoot`는 검증된 후보를 schema 2 봉투로 저장한 뒤에만 활성 세션으로 교체합니다.
- 전투 중 긴급 재배포 같은 새 프레젠테이션 명령은 공개 표면에 추가하지 않습니다.

`GameSession.new()` accepts no required argument. The legacy snapshot uses
these stable groups so presentation and tests do not reach into domain state:

```text
stage, stage_enemy_index, stage_enemy_total
bits, patch_notes, run_count, mode
enemy {
  name, hp, max_hp, is_boss, time_left,
  next_action, next_action_in
}
operators [{
  id, name, role, ability, level, unlocked,
  dps, effective_dps, hp, max_hp, down, process_down,
  attack_remaining, damage_dealt, damage_taken,
  down_count, active_time, down_time, upgrade_cost
}]
patch_slots [patch_id]
patches [{ id, name, description, benefit, drawback, unlocked, equipped }]
unlocked_patch_slots, diagnosis
appeals, appeal_limit
prestige_available, legacy_cache_level, legacy_cache_cost
maintenance_time_left
hybrid_combat_enabled, boss_failure_count, last_failure_reason
qa_rescue, recent_boss_events
combat_v2_test_mode, combat_v2_complete
offline_progress_supported, status_message, last_error
```

Diagnosis dictionaries use `kind`, `title`, `evidence`, and `severity`.
Patch previews use `can_equip`, `cost`, `summary`, `before_ttk`, `after_ttk`,
`before_bits_multiplier`, and `after_bits_multiplier`.

## 현재 Product V2 persistence boundary

The save envelope owner is `SaveRepository`, not either session type.

현재 본편 저장 봉투는 schema 3입니다.

```json
{
  "schema_version": 3,
  "saved_at_unix": 0,
  "last_gameplay_tab": 0,
  "session": {}
}
```

`SaveRepository.load()`는 missing, valid, legacy-schema, backup-recovered, corrupt, newer-schema를 구분합니다. 저장소는 schema 1·2·3 봉투와 세션 딕셔너리를 전달할 뿐 세션 내부 필드를 변환하지 않습니다. `ProductV2SaveMigrator`가 비활성 Legacy `GameSession`으로 schema 1·2 원본을 검증하고, 새 `ProductLoopSession` 후보로 schema 3 전체를 검증합니다. 실행 순서는 `AppRoot`가 맡습니다.

쓰기는 임시 파일, 검증, 백업 회전과 주 파일 교체 순서로 수행합니다. 마이그레이션은 검증된 schema 3 후보 저장이 성공하기 전까지 활성 세션과 기존 파일을 바꾸지 않습니다. 잘못된 내용은 조용히 새 게임으로 바뀌지 않습니다.

Offline results are applied to the session and saved before their read-only report is shown. A report is presentation data, not a claimable reward.

현장 실패 보고서는 보상 창이 아닙니다. Product V2는 최신 보고서 key·행·읽음 상태를 세션 DTO에 보존하고, 읽기 명령은 알림 상태만 바꿉니다.

Stable content IDs are:

- Operators: `debugger`, `build_engineer`, `sprite_artist`, `qa_imp`
- Patches: `frame_skip`, `unsafe_build`, `reward_bypass`, `rollback_lock`, `safe_mode`

## Legacy V1 구현 기준선

- A normal stage contains three enemies and has no failure timer.
- Stages 10 and 20 contain the Watchdog Process and use a 25-second timer.
- A failed boss enters automatic maintenance farming, earns enough bits to avoid a soft lock, then retries without a manual combat button.
- Patch slots unlock at stages 3, 11, and 15 on the first run. Discovered content and slot unlocks remain available on later runs, while equipped patches reset.
- Operators unlock progressively on the first run and all remain available after the first version update.
- Clearing stage 20 enables a voluntary version update. It resets run progress and grants one patch note.

Legacy V1은 위 20스테이지 흐름을 회귀 기준으로 보존한다. 현재 Product V2는
[혼합 디펜스 전투 명세](COMBAT_HYBRID_SPEC.md)의 주간·야간·결과 구조를 사용한다.

## Legacy V1 Test boundary

Required automated checks cover monotonic health/cost growth, deterministic simulation, patch tradeoffs, boss-failure recovery, boss-only operator durability, QA rescue, schema migration, prestige reset/preservation, content validation, and headless loading of the main scene. UI integration checks additionally cover field-report unread/read/reopen/update behavior, resource help hover·touch boundaries, integer HP without clipping, and lifecycle focus deduplication.
