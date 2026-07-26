# Pixel Night Shift 작업 인수인계

최종 갱신: 2026-07-27

권위 checkout: `D:\자체제작게임\방치형게임2`

권위 브랜치: `main`

기준 구현 커밋: `cbf89c9`

이 문서는 현재 저장소 상태를 빠르게 이어받기 위한 기록입니다. 완료된 C→D 드라이브 이전 과정과 오래된 브랜치·커밋 정보는 Git 이력에 남아 있으며, 현재 작업 판단에는 이 문서를 우선합니다. 비밀번호, API 키, 인증 토큰과 서명 정보는 기록하지 않습니다.

## 1. 제품과 현재 상태

《Pixel Night Shift · 픽셀 야간근무》는 서비스 종료 직전의 레트로 게임을 지키는 야간 운영 책임자가 자동 전투의 병목을 진단하고, 요원을 강화하고, 장단점이 있는 패치를 선택하는 360×640 세로형 방치 관리 게임입니다.

현재 기본 본편은 20스테이지 혼합 전투 수직 슬라이스입니다.

- 일반전은 빠른 자동 전투와 기존 가독성을 유지합니다.
- 스테이지 10·20 보스전에서만 요원 역할, HP, PROCESS DOWN과 QA 자동 구조가 활성화됩니다.
- 진단 카드는 현재 병목과 예상 처치 시간·전원 DOWN 위험을 보여주고 요원·패치·버전 탭 중 맞는 화면으로 안내합니다.
- 보스 실패 뒤에는 실제 스냅숏 근거만 사용하는 최대 2행의 읽기 전용 현장 보고서가 도착합니다.
- 실패해도 진행을 삭제하지 않고 유지보수 파밍과 자동 재도전으로 복구합니다.
- 스테이지 20 이후 버전 업데이트로 패치노트와 영구 보너스를 남기고 다음 회차를 시작합니다.

권위 전투 명세는 `docs/COMBAT_HYBRID_SPEC.md`입니다. 구현·자동 검증 순서 1~7과 360×640 내부 한 회차 확인은 완료됐습니다. 콜드 부트와 첫 근무 진입은 `docs/OPENING_EXPERIENCE_SPEC.md`를 따릅니다. 현재 후보는 GitHub Pages에 공개 테스트 배포되며 다음 완료 관문은 5인 플레이테스트입니다.

## 2. 완료된 범위

### 핵심 게임

- 결정론적 20스테이지 자동 전투
- 고정 요원 4명과 개별 강화
- 일반 적 3종, 유지보수 적 1종, Watchdog Process 보스
- 후보 패치 5개, 장착 슬롯 3개, 해금과 교체 비용
- 보스 제한 시간, 행동 예고, 역할별 공격, 요원 내구도, DOWN과 QA 구조
- 병목별 목적 탭으로 이어지는 진단과 사실 기반 실패 보고서
- 보스 실패 후 유지보수 파밍과 자동 재도전
- 비트, 패치노트, 레거시 캐시와 버전 업데이트 1회 순환
- 콘텐츠 경계 검증과 정책별 20스테이지 밸런스 비교

### 앱 셸과 저장

- 하나의 `AppRoot`와 기본 본편용 `GameSession`
- 부트, 콜드 부트 타이틀, 5단계 첫 근무 프롤로그, 야간 운영실, 현장 온보딩, 현장 복귀
- 저장에서 검증한 후보 세션은 타이틀의 `이어하기` 전까지 비활성으로 대기하며, 새 세션은 프롤로그 뒤 최초 저장 성공 시에만 활성화
- 설정, 저장 복구, 오프라인 보고, 버전 업데이트 확인·요약
- schema 2 저장과 schema 1→2 원자적 마이그레이션
- 주 저장·백업·임시 파일 검증 후 교체
- 30초 주기 저장, 최대 8시간 오프라인 진행, 중복 적용 방지
- Android/iOS pause/resume과 Web/desktop focus-out/focus-in의 저장·복귀 집계
- 중복 수명주기 알림 방지, Android Back/safe-area의 코드와 통합 테스트

### 표현과 오디오

- 360×640 세로형 UI와 요원·패치·버전 탭
- 보스 행동·제한시간·QA 구조·PROCESS DOWN 상태 표시
- 요원별 보스 능력 설명, 정수 HP 표기와 보스 HP 텍스트 여백
- 새 실패 알림, 재열람 가능한 독립 현장 보고서 모달
- 비트·패치노트·스테이지 아이콘의 마우스·터치 설명 말풍선
- 투사체, 공격 펄스, 적 피격, 피해 숫자와 접근성 설정
- 원본 픽셀 에셋 manifest와 해시 검증
- 일반·보스·유지보수 BGM, Music/SFX 버스와 의미 기반 cue
- 일반·보스 BGM과 UI·운영 효과음은 CC0 최종 에셋입니다. 유지보수 BGM과 타격·격파·강화·보스 경고 효과음 4종은 프로젝트 자체 절차 합성입니다.
- 한글 폰트 폴백, 다양한 세로 화면비와 안전 영역을 처리하는 Web shell
- 커밋별 JS·WASM·PCK 파일명과 GitHub Pages 자동 배포

## 3. 본편과 Combat V2의 관계

기본 실행은 `GameSession.new()`를 사용하며 혼합 보스 전투가 기본 활성화돼 있습니다. 과거 Combat V2는 비교 기준과 회귀 검증을 위해 `--combat-v2-test` 전용 모드로 아직 남아 있습니다.

| 항목 | 기본 본편 | Combat V2 격리 모드 |
|---|---|---|
| 진행 범위 | 20단계, 보스 10·20 | 10단계 테스트 |
| 요원 내구도 | 보스전에서만 활성 | 일반전·보스전 모두 활성 |
| 실패 복구 | 유지보수 파밍 뒤 자동 재도전 | 고정 6초 복구 |
| 긴급 재배포 | 없음 | 테스트 전용 명령 |
| 현장 보고서 | 보스 실패만 | `normal_failure`·`boss_failure` |
| 역할 수치 원본 | `game/content/operators.json` | `game/content/combat_v2/combat_v2.json` |

두 모드는 같은 역할 이름과 능력 설명을 공유하지만 실제 수치는 다릅니다. 예를 들어 본편은 디버거 화력 `×0.50`, 빌드 엔지니어 보스 피해 `×2.60`, 스프라이트 장인 팀 주기 `×0.82`를 사용하고, V2는 디버거 성장 지수 `×0.30`, 빌드 엔지니어 보스 피해 `×1.35`, 팀 주기 `×0.90`을 사용합니다.

- 본편 저장과 V2 테스트 저장은 분리됩니다.
- 본편은 V2 전체를 사용하지 않습니다.
- 5인 플레이테스트 통과 전에는 V2를 비교 기준으로 보존합니다.
- 통과 후 명세 순서 9에 따라 V2 전용 엔진·저장·화면·분기를 제거합니다.

## 4. 실행과 자동 검증

요구 버전은 Godot `4.7.stable.official.5b4e0cb0f`입니다. 대화형 확인은 Godot Project Manager에서 `project.godot`을 가져와 실행합니다. 메인 장면은 `res://game/app/app_root.tscn`입니다.

Windows Godot 4.7 공식 빌드에는 GUI 종료 시 네이티브 메모리 오류 창이 나타날 수 있는 엔진 문제가 있습니다. 자동 테스트에는 GUI 실행 파일이나 `godot.bat`을 직접 사용하지 않습니다.

모든 자동 Godot 명령은 저장소 루트에서 전용 실행기를 사용합니다.

```powershell
.\tools\run_godot_headless.ps1 --script res://tools/validate_pixel_assets.gd
.\tools\run_godot_headless.ps1 --script res://tools/validate_audio.gd
.\tools\run_godot_headless.ps1 --script res://tests/test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/app_shell/app_shell_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/app_shell/app_root_integration_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/persistence/save_repository_schema_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/balance_report.gd
.\tools\run_godot_headless.ps1 --script res://tests/hybrid_boss_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_test_runner.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_appeal_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_integration_test.gd
.\tools\run_godot_headless.ps1 --script res://tests/combat_v2/combat_v2_comparison_report.gd -- --hybrid-only
.\tools\run_godot_headless.ps1 --quit-after 3
```

실행기는 Godot 프로세스를 하나씩 실행하고 `.godot/headless-runtime`과 `.godot/headless-logs`에 사용자 데이터와 로그를 격리합니다. 타임아웃 뒤에는 같은 프로젝트의 Godot 프로세스가 남아 있지 않은지 확인한 후 재시도합니다.

`tools/generate_pixel_assets.gd`와 `tools/generate_audio.gd`는 추적 파일을 다시 쓰므로 검증 목적으로 실행하지 않습니다.

Pages 워크플로는 Web 내보내기·산출물 참조·배포만 검사하며 위 테스트를 대신하지 않습니다.

### 웹 테스트 배포

- 공개 URL: `https://dudcjfsp-cyber.github.io/pixel-night-shift/`
- 워크플로: `.github/workflows/deploy-pages.yml`
- 시작 조건: `main` push 또는 수동 `workflow_dispatch`
- Godot `4.7` Web export template을 Actions에서 내려받아 빌드합니다.
- `pixel-night-shift-<commit-sha>.{js,wasm,pck}` 파일명으로 배포해 이전 고정 파일 캐시와 분리합니다.
- 진행은 브라우저별 로컬 저장이며 계정·클라우드 동기화는 없습니다.

## 5. 마지막 확인 결과

2026-07-22 혼합 전투 구현과 내부 1회차 확인에서 다음 항목이 통과했습니다.

- 픽셀·오디오 validator
- 핵심 도메인, 앱 셸과 AppRoot 통합 테스트
- 저장 schema 1→2 마이그레이션과 오프라인 중복 방지
- 혼합 보스 내구도·QA 구조·진단·실패 보고서 테스트
- 정책별 20스테이지 비교와 목표 밸런스
- 일반 headless 메인 장면 실행
- `git diff --check`
- 360×640 첫 근무부터 스테이지 20, 버전 업데이트 승인과 2회차 시작까지 1,229.4초 연속 실행
- 스테이지 10·20의 실패, PROCESS DOWN 12회와 QA 자동 구조 성공 4회를 포함한 실제 복구 순환
- 프로젝트 원본 전투 효과음 4종의 재현 가능한 생성, 길이·피크·겹침 검토와 오디오 validator

세부 수치와 발견 사항은 `docs/INTERNAL_PLAYTEST_2026-07-22.md`에 기록했습니다. 자동 검증과 내부 관찰은 5명의 실제 청음·글꼴 체감·이해도 확인을 대신하지 않습니다.

2026-07-26~27 웹 플레이테스트 보강에서 추가로 확인한 항목은 다음과 같습니다.

- 한글 폰트와 활성 스프라이트의 Web export 패키징
- 다양한 세로 화면비, 브라우저 안전 영역과 커밋별 Web 산출물
- 포커스 이탈 시 저장, 복귀 시 오프라인 진행과 중복 적용 방지
- 진단별 요원·패치·버전 탭 안내와 요원별 보스 능력
- 실패 보고서 알림·읽음·재열람·운영실 왕복과 독립 모달 레이아웃
- 정수 HP 표시, 얇은 요원 HP 바와 보스 HP 텍스트 여백
- `tests/test_runner.gd` 12/12, `combat_v2_appeal_test.gd` 7/7,
  `combat_v2_integration_test.gd` 5/5, `app_root_integration_test.gd` 9/9
- 일반 headless 메인 장면 실행
- 기준 커밋 `cbf89c9` Pages 배포 성공과 공개 URL HTTP 200 응답

## 6. 현재 남은 작업

우선순위는 다음과 같습니다.

1. Pages URL을 참가자별 브라우저에서 열어 `docs/PLAYTEST.md` 기준 5인 플레이테스트를 진행합니다.
   기기·브라우저·화면비, 첫 로딩, 한글, 첫 터치 오디오, 화면 전환 복귀,
   실패 보고서, 보스 HP와 새로고침 후 이어하기를 함께 기록합니다.
2. 발견된 차단 문제만 수정합니다.
3. 기준 통과 후 Combat V2 전용 코드와 테스트 분기를 정리합니다.

사용자 결정에 따라 Android 빌드와 실기기 검수는 현재 보류합니다. Android용 SDK/JDK, Android export template·preset과 서명 설정은 아직 없습니다. Web export preset은 테스트 배포용으로 이미 존재합니다.

## 7. 현재 범위 밖

- 신규 요원, 패치, 적, 보스, 스테이지 21 이상
- 부서, 사건, 장비, 인벤토리와 모집
- 광고, 결제, 분석, 계정, 클라우드 저장과 라이브 운영
- 수동 공격, 액티브 스킬, 회피와 실시간 재배포
- 대규모 아트·오디오와 콘텐츠 확장
- Android 패키징과 스토어 배포

핵심 순환 플레이테스트 전에는 콘텐츠 양을 늘리지 않습니다. 이해 문제가 나오면 규칙을 추가하기보다 진단 근거, 경고 표현과 수치를 먼저 조정합니다.

## 8. 오디오 제작 환경

현재 확인된 로컬 도구는 다음과 같습니다.

- Waveform Free 14.0.41
- Surge XT 1.3.4 VST3
- Spotify Pedalboard 0.9.23
- Audacity 3.7.8
- Python 3.12.13

런타임 최종 파일만 `game/assets/audio/`에 둡니다. 생성 후보와 분석 결과는 Git에서 제외한 `.godot/audio-candidates/`에 두며, 장기 보관이 필요한 DAW 프로젝트만 저장소 밖의 `D:\자체제작게임\PixelNightShift-Archive`에 보관합니다. 채택한 파일은 `game/assets/audio/manifest.json`과 `ATTRIBUTION.md`에 생성 방식·라이선스·해시를 기록합니다.

## 9. 저장소와 외부 자료

- 원격: `origin` (`https://github.com/dudcjfsp-cyber/pixel-night-shift.git`)
- 권위 브랜치: `main`
- 테스트 배포: `https://dudcjfsp-cyber.github.io/pixel-night-shift/`
- C드라이브 Combat V2 linked worktree는 제거됐습니다.
- D드라이브 이전과 재import는 완료됐습니다.
- 외부 원본·후보·QA 자료는 Git 밖의 `D:\자체제작게임\PixelNightShift-Archive`에 보관합니다.
- 실제 게임 저장은 프로젝트 밖의 Godot `user://pixel_night_shift`에 있으므로 저장소 이동과 별도로 취급합니다.

## 10. 작업 원칙

- 프레젠테이션은 `GameSession`에 명령을 보내고 스냅숏만 읽습니다.
- 도메인은 장면, 노드, 파일, 시계와 오디오에 의존하지 않습니다.
- 저장 복원은 원자적이며 더 최신이거나 잘못된 데이터는 명시적으로 거부합니다.
- 같은 상태와 경과 시간은 같은 전투 결과를 만들어야 합니다.
- 테스트는 내부 호출 순서가 아니라 관찰 가능한 행동을 검증합니다.
- 관련 없는 사용자 작업을 보존하고, 필요한 범위보다 테스트나 추상화를 늘리지 않습니다.
