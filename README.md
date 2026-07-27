# Pixel Night Shift · 픽셀 야간근무

> 서버가 살아있다

《픽셀 야간근무》는 낡은 게임 서버를 지키는 야간 관리자 역할의 세로형 자동 디펜스·방치
정비 게임입니다. 전투는 자동으로 진행되고, 플레이어는 낮에 요원을 강화하고 패치를
고른 뒤 밤의 방어 결과를 진단합니다.

현재 기본 실행 경로는 **Godot 4.7 Product V2 본편**입니다.

```text
타이틀 → 5장 프롤로그 → DAY_PREP
       → NIGHT_ACTIVE → SHIFT_RESULT → DAY_PREP
       → 둘째 야간 완료 뒤 선택적 버전 업데이트
```

야간은 일반 9웨이브와 30초 보스전으로 구성됩니다. 일반 웨이브는 최대 5초, 별 경계는
3·6·10웨이브이며, 적이 서버에 도달하면 서버 안정도가 감소합니다. 주간에는 방치 비트,
네 요원 강화, 패치 5종·슬롯 3칸, 실패 보고서와 버전 업데이트를 관리합니다.

**웹 테스트 플레이:** <https://dudcjfsp-cyber.github.io/pixel-night-shift/>

Pages는 친구 대상 테스트 배포입니다. 계정, 클라우드 저장, PWA, 결제나 정식 웹 서비스
운영은 포함하지 않으며 Android 네이티브 패키징은 현재 보류 중입니다.

## 실행

Godot 4.7 Project Manager에서 `project.godot`을 가져와 실행합니다.

- 메인 장면: `res://game/app/app_root.tscn`
- 논리 해상도: `360×640`
- 제품 세션 경계: `ProductLoopSession`
- 현재 저장 봉투: schema 3

정상 콜드 부트는 항상 타이틀에서 시작합니다. 새 게임은 프롤로그 뒤 첫 schema 3 저장에
성공해야 주간 정비로 들어갑니다. 이어하기는 저장한 `DAY_PREP`, `NIGHT_ACTIVE`,
`SHIFT_RESULT` 단계를 그대로 복구합니다. 주간에서만 오프라인 비트를 한 번 적용하고,
야간은 오프라인 동안 진행하지 않으며 결과 보상은 다시 정산하지 않습니다.

실제 화면과 소리를 확인하는 로컬 수동 E2E는 독립된 세션 ID로 실행합니다.

```powershell
.\tools\run_godot_manual_e2e.ps1 -SessionId product-v2-e2e-001
```

테스트 `user://`와 설정은 `.godot/manual-e2e-runtime/` 아래에 격리됩니다. 같은 ID를
다시 사용하면 테스트 기록을 이어가고, 새 ID는 빈 기록으로 시작합니다.

## Product V2 포함 범위

- 360×640 세로 화면과 Galaxy 계열 화면비·안전 영역 대응
- 낡은 게임 서버·야간근무·직장 코미디 톤의 타이틀과 5장 프롤로그
- 버전마다 두 번 진행하는 9+1웨이브 자동 디펜스
- 서버 안정도, 적 HP와 별도 제한시간, 침입·투사체·피격 표시
- 보스전 요원 HP, PROCESS DOWN과 QA 자동 구조
- 3·6·10웨이브 별, 최초 별 보상과 반복 근무 급여
- 주간 20분당 1비트, 최대 12시간·36비트의 방치 수입
- 네 요원 정수 강화, 패치 5종, 직접 교체하는 슬롯 3칸과 전후 예측
- 정확한 해금 조건·진행도와 결과 화면 해금 요약
- 실패 원인과 요원 의견을 담은 읽기 전용 현장 보고서
- 사용자가 주간에 선택하는 버전 업데이트와 레거시 빌드 캐시
- 타이틀·주간·야간·결과 오디오, 설정, 저장 복구와 플랫폼 수명주기
- 결정론적 전투와 원자적 로컬 저장

제품·수치 기준은 [Product V2 계획표](docs/PRODUCT_V2_PLAN.md), 전투 규칙은
[혼합 디펜스 명세](docs/COMBAT_HYBRID_SPEC.md), 앱 흐름과 저장 계약은
[앱 셸 명세](docs/APP_SHELL_SPEC.md)를 따릅니다. 웹 수동 검증은
[플레이테스트 계획](docs/PLAYTEST.md)에 기록합니다.

## 저장과 이전 버전

새 저장은 schema 3만 기록합니다. 기존 schema 1·2 기록은 먼저 기존 규칙으로 검증한 뒤
비트, 해금한 요원·패치·슬롯과 영구 성장처럼 안전하게 옮길 수 있는 메타 진행만
보존합니다. 진행 중이던 Legacy 전투, 장착 패치와 결과는 Product V2 야간으로 추측
변환하지 않고 `DAY_PREP`에서 새로 시작합니다. 손상되거나 더 최신인 저장은 진행을
부분 적용하거나 조용히 초기화하지 않고 복구 화면으로 보냅니다.

이전 20스테이지 V1, Legacy Combat V2와 Product V2 Defense Lab은 더 이상 기본 본편이
아닙니다. 다음 목적으로만 저장소에 남아 있습니다.

- schema 1·2 이관 입력 검증
- Product V2 도메인과 표시의 격리 회귀 테스트
- 이전 전투 결과와 밸런스 비교

[V1 전투 동결 기준선](docs/V1_COMBAT_BASELINE.md)은 현재 제품 명세가 아니라 이관·회귀
호환 기준입니다.

## 검증

Windows 자동 검증에는 GUI 실행 파일이나 `godot.bat`을 직접 사용하지 않고 전용
실행기를 사용합니다. 실행기는 Godot 프로세스, 로그와 `user://`를 프로젝트 `.godot/`
아래에 격리하며 테스트를 한 번에 하나씩 실행합니다.

### Product V2 핵심

```powershell
.\tools\run_godot_headless.ps1 --script res://tests/product_v2/night_shift_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/product_v2/defense_lab_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/product_v2/product_loop_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/product_v2/day_meta_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/product_v2/product_v2_migration_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/persistence/save_repository_schema_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/app_shell/app_root_integration_test.gd
.\tools\run_godot_headless.ps1 --quit-after 3
```

### 셸·에셋과 Legacy 호환

```powershell
.\tools\run_godot_headless.ps1 --script res://tools/validate_pixel_assets.gd
.\tools\run_godot_headless.ps1 --script res://tools/validate_audio.gd
.\tools\run_godot_headless.ps1 --script res://tests/app_shell/app_shell_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/balance_report.gd
.\tools\run_godot_headless.ps1 --script res://tests/hybrid_boss_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_appeal_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_integration_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_comparison_report.gd -- --hybrid-only
```

검증 명령은 원본 파일을 바꾸지 않습니다. `tools/generate_pixel_assets.gd`와
`tools/generate_audio.gd`는 에셋을 다시 쓰므로 재생성이 목적일 때만 별도로 실행합니다.

## 웹 테스트 배포

`main` 푸시 또는 GitHub Actions의 수동 실행으로
[Pages 워크플로](.github/workflows/deploy-pages.yml)를 시작합니다. 워크플로는 Godot 4.7
Web 빌드를 내보내고 JS·WASM·PCK 파일명에 커밋 SHA를 넣어 이전 브라우저 캐시와
섞이지 않게 합니다. 사용자 진행은 브라우저별 로컬 저장에만 남습니다.

배포 워크플로는 내보내기 산출물을 검사하지만 위 자동 테스트 전체를 대신 실행하지
않습니다. 검증을 통과한 커밋을 배포하고, 실제 PC·Galaxy 결과와 빌드 SHA는
[플레이테스트 기록](docs/PLAYTEST.md)에 남깁니다.

## 구조

```text
game/content/product_v2/  Product V2 웨이브·경제·해금 콘텐츠와 검증
game/domain/product_v2/   결정론적 야간 전투와 주야간·메타 규칙
game/app/product_v2/      ProductLoopSession, DTO와 schema 이관
game/app/                 AppRoot 화면·수명주기·저장 조정
game/presentation/        타이틀, 주간, 야간, 결과와 설정 UI
game/persistence/         schema 3 원자적 저장·백업·복구
game/assets/              원본 픽셀 PNG·WAV와 출처 매니페스트
tools/                    에셋·오디오 생성·검증과 Godot 실행기
tests/                    Product V2 핵심 및 Legacy 호환 테스트
docs/                     제품·전투·앱 셸·플레이테스트 계약
```

표현 계층은 도메인 상태를 직접 바꾸지 않습니다. 플레이어 입력은
`ProductLoopSession` 명령으로 전달되고, 화면과 테스트는 스냅숏을 읽습니다. `AppRoot`는
활성 세션 하나, 화면 전환, 시뮬레이션 tick, 저장 시점, 플랫폼 수명주기와 오디오 수명주기를
소유합니다.
