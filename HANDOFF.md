# Pixel Night Shift 이전 및 작업 인수인계

작성일: 2026-07-21

조사 기준 checkout: `C:\Users\rycba\OneDrive\Desktop\자체제작게임\방치형게임2`

이 문서는 실제 저장소, 프로젝트 설정, 코드, 테스트, 에셋 manifest, 로컬 도구와 Git 상태를 확인해 작성했다. 비밀번호, API 키, 인증 토큰은 기록하지 않는다.

## 1. 프로젝트 이름과 한 줄 설명

- 프로젝트 이름: **Pixel Night Shift · 픽셀 야간근무**
- 한 줄 설명: 서비스 종료 직전의 레트로 게임을 지키는 야간 운영 책임자가 자동 전투의 병목을 진단하고, 요원을 강화하고, 장단점이 있는 패치를 선택하는 360×640 세로형 방치 관리 게임이다.

## 2. 게임의 목표와 핵심 플레이 방식

전투와 보스 재도전은 완전 자동이다. 플레이어의 의미 있는 행동은 다음과 같다.

1. 자동 전투와 화면의 진단 근거를 관찰한다.
2. 병목에 맞춰 네 요원 중 하나를 강화한다.
3. 후보 5개 중 최대 3개의 임시 패치를 선택한다. 모든 패치에는 이점과 부작용이 함께 있다.
4. 스테이지 10·20의 `Watchdog Process` 보스를 통과한다.
5. 스테이지 20 이후 자발적으로 버전 업데이트를 실행한다.
6. 패치노트와 영구 보너스를 남기고 더 빠른 다음 회차를 진행한다.

목표 플레이 감각은 반복 탭이 아니라 `관찰 → 진단 → 판단 → 결과 비교 → 버전 업데이트`다. 실패해도 진행을 삭제하지 않고 유지보수 파밍과 자동 재도전으로 복구한다.

## 3. 현재까지 완성된 기능

### 핵심 게임

- 20스테이지 자동 전투 회색 상자 루프
- 일반 적 3종 순환 및 유지보수 적 1종
- 스테이지 10·20의 보스 `Watchdog Process`
- 보스 제한 시간, 회복 행동, 스테이지 20 처리량 저하
- 보스 실패 후 유지보수 파밍과 자동 재도전
- 요원 4명과 개별 레벨업
  - `debugger`
  - `build_engineer`
  - `sprite_artist`
  - `qa_imp`
- 패치 5개, 동시 장착 슬롯 3개, 해금과 교체 비용
- 비트, 패치노트, 레거시 캐시 1레벨
- 스테이지 20 이후 버전 업데이트와 회차 초기화/메타 진행 보존
- 처리량 부족, 복구 과다, 보상 정체를 설명하는 진단
- 패치 적용 전후 처치 시간·수입 배율 미리보기
- 같은 상태와 경과 시간이 같은 결과를 만드는 결정론적 도메인

### 앱 셸, 저장과 복귀

- `AppRoot`를 메인 장면으로 사용하는 단일 앱 구성 루트
- 부트 라우팅, 최초 1회 첫 근무, 야간 운영실, 현장 복귀
- 현장 온보딩과 운영 매뉴얼 재열람
- 조건부 오프라인 보고서
- 버전 업데이트 확인 및 회차 요약
- 설정 화면
  - 음악·효과음 볼륨
  - 진동 지원 상태
  - 화면 흔들림, 번쩍임 줄이기, 동작 줄이기
- 명시적인 저장 복구 화면
- `user://pixel_night_shift` 아래 schema 1 저장 및 설정
- 주 저장 1개, 백업 1개, 임시 파일 검증 후 교체
- 잘못되거나 더 최신인 저장 데이터의 원자적 거부
- 30초 주기 저장
- 120초 이상 이탈 시 오프라인 보고, 최대 8시간 집계
- 오프라인 진행 중복 적용 방지
- Android pause/resume/Back/safe-area 동작을 코드와 통합 테스트로 구현

### 표현과 에셋

- 360×640 세로형 UI, 요원·패치·버전 탭
- 네 요원의 활성 스프라이트 atlas
- `broken_pixel` 적의 idle/hurt 애니메이션
- 투사체, 요원 공격 펄스, 적 피격 플래시, 피해 숫자
- 피해 표시는 프레젠테이션에서 별도 계산하지 않고 실제 `GameSession` 적 HP 감소량에서 파생한다. 요원 강화와 패치의 실제 피해 변화가 표시값에 자동 반영된다.
- 모션·번쩍임 감소 설정에 따른 전투 효과 축소
- 최종 런타임 픽셀 에셋 manifest 및 해시 검증
- BGM 3곡
  - 일반 전투: CC0 OGG
  - 보스 전투: CC0 OGG
  - 유지보수: 프로젝트 자체 절차 합성 WAV
- CC0 최종 효과음 13개
- 음악·효과음 버스와 상황별 cue 재생
- 오디오 출처와 해시를 `game/assets/audio/manifest.json` 및 `ATTRIBUTION.md`에 기록

### 2026-07-21 재검증 결과

- Godot: `4.7.stable.official.5b4e0cb0f`
- 픽셀 에셋: 정적 23개와 모든 활성 sprite run 검증 통과
- 오디오: 최종 에셋 16개 검증 통과
- 중앙 테스트: 12/12 통과
- 앱 셸 테스트: 6/6 통과
- AppRoot 통합 테스트: 8/8 통과
- 밸런스 리포트: 통과
  - 첫 회차 스테이지 20: 971.0초
  - 첫 보스 도달/클리어: 232.8초/242.8초
  - 두 번째 회차 첫 보스 도달: 163.8초
  - 첫 보스 도달 시간 감소: 29.6%
- 기본 메인 장면 headless 실행: 통과
- `git diff --check`: 통과

통합 테스트가 의도적으로 손상된 설정 fixture에서 백업 복구를 확인할 때 경고 한 건을 출력하지만 테스트 실패가 아니다.

## 4. 미완성 기능과 진행 중인 작업

### MVP 차단 항목

- `export_presets.cfg`가 없고 Android export preset이 구성되지 않았다.
- Android SDK/JDK, `adb`, `jarsigner`, Godot 4.7 export template이 현재 환경에서 확인되지 않았다.
- APK/AAB와 서명 설정이 없다.
- 실제 Android 기기에서 설치, 업데이트, pause/resume, 오프라인 진행, 저장 복구, Back, safe area, 음량과 루프를 검수하지 않았다.
- `docs/PLAYTEST.md`의 5인 플레이테스트를 수행하지 않았다.

### 진행 중이거나 별도 브랜치에 격리된 작업

- 커스텀 BGM·효과음 제작 도구는 준비했지만 새 프로젝트 자체 제작 음원은 아직 만들지 않았다. 현재 일반/보스 BGM과 13개 SFX는 CC0 최종 에셋이다.
- `codex/combat-v2-integration` 브랜치에 Combat V2 테스트 모드와 결정론적 요원 어필이 구현돼 있으나 현재 브랜치와 `main`에 병합하지 않았다.
- Combat V2는 기본 프로덕션 20스테이지를 대체하지 않으며 별도 `--combat-v2-test` 흐름으로 유지한다.
- 일부 적의 다중 프레임 애니메이션과 상용 수준의 캐릭터 표현은 미완성이다.
- 광고, 결제, 계정, 클라우드 저장, 분석, 라이브 이벤트, 장편 콘텐츠, 스테이지 21 이상은 현재 MVP 범위 밖이다.

## 5. 주요 폴더와 파일의 역할

| 경로 | 역할 |
|---|---|
| `project.godot` | Godot 프로젝트 진입점. 이름, `AppRoot` 메인 장면, 360×640, GL Compatibility 설정 |
| `default_bus_layout.tres` | Master/Music/SFX 오디오 버스와 기본 볼륨 |
| `AGENTS.md` | 제품 범위, 아키텍처와 품질 규칙 |
| `game/content/` | 밸런스·요원·패치 JSON 원본과 엄격한 loader/typed definition |
| `game/domain/` | 장면·파일·시계·오디오와 독립된 전투, 성장, 진단 규칙 |
| `game/app/game_session.gd` | 프레젠테이션이 사용하는 명령/스냅숏 경계와 저장 DTO 검증 |
| `game/app/app_root.gd` | 구성, 화면 전환, simulation tick, 수명주기, 저장 시점, 오디오 수명주기 소유자 |
| `game/app/app_policy.gd` | 오프라인 상한, 보고 임계값, 주기 저장 등 앱 정책 |
| `game/persistence/` | schema 1 저장·설정 파일, 백업, 복구와 원자적 교체 |
| `game/presentation/main_view.gd` | 전투 화면과 요원·패치·버전 UI |
| `game/presentation/battle_lane_view.gd` | 전투 레인, 실제 HP 차이 수집, 공격 피드백 연결 |
| `game/presentation/combat_effect_layer.gd` | 투사체, 명중, 피해 숫자 시각 효과 |
| `game/presentation/audio_director.gd` | 상태별 BGM 전환과 SFX cue |
| `game/presentation/app_shell/` | 부트, 첫 근무, 운영실, 오프라인 보고, 설정, 복구, 온보딩, 회차 요약 UI |
| `game/assets/manifest.json` | 정적 에셋과 활성 sprite run의 권위 manifest |
| `game/assets/audio/manifest.json` | 최종 오디오 16개의 출처, 라이선스, 해시와 생성 규격 |
| `tools/validate_pixel_assets.gd` | 픽셀 에셋 크기·해시·atlas 계약 검증 |
| `tools/validate_audio.gd` | 최종 오디오 manifest·해시·포맷 검증 |
| `tools/generate_pixel_assets.gd` | 기존 정적 픽셀 에셋 재생성. 실행하면 파일을 변경하므로 단순 검증 때 실행하지 않는다. |
| `tools/generate_audio.gd` | 프로젝트 자체 유지보수 음원과 과거 절차 음원 생성기. 실행하면 파일을 변경할 수 있다. |
| `tests/test_runner.gd` | 도메인·프레젠테이션 중앙 테스트 12개 |
| `tests/app_shell/app_shell_test.gd` | 앱 셸 화면 계약 테스트 6개 |
| `tests/app_shell/app_root_integration_test.gd` | 저장·복귀·오프라인·수명주기 통합 테스트 8개 |
| `tests/balance_report.gd` | 첫/두 번째 회차 자동 전략 밸런스 회귀 |
| `docs/` | GDD, 범위, 아키텍처, 앱 셸, 플레이테스트, 아트·오디오·스프라이트 규칙 |

## 6. 프로젝트 실행 방법

요구사항은 Godot 4.7이다. 현재 설치된 GUI 실행 파일은 다음 위치에 있다.

```text
C:\Users\rycba\AppData\Local\Programs\Godot\Godot-4.7-stable\Godot_v4.7-stable_win64.exe
```

Godot Project Manager에서 D드라이브로 옮긴 `project.godot`을 가져오거나, 새 프로젝트 루트에서 다음처럼 실행한다.

```powershell
$godot = 'C:\Users\rycba\AppData\Local\Programs\Godot\Godot-4.7-stable\Godot_v4.7-stable_win64.exe'
& $godot --path .
```

`godot`이 PATH에 등록돼 있다면 `godot --path .`로 실행할 수 있다. 메인 장면은 `res://game/app/app_root.tscn`이다.

## 7. 빌드 및 테스트 방법

### 현재 가능한 검증

Godot 로그·import와 `user://` 테스트 데이터를 프로젝트 및 실제 사용자 저장과 분리하기 위해 임시 프로필을 사용한다.

```powershell
$root = (Get-Location).Path
$godot = 'C:\Users\rycba\AppData\Local\Programs\Godot\Godot-4.7-stable\Godot_v4.7-stable_win64_console.exe'
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) 'PixelNightShift-GodotSandbox'

New-Item -ItemType Directory -Force `
  $sandbox, `
  "$sandbox\AppData\Roaming", `
  "$sandbox\AppData\Local", `
  "$sandbox\Temp" | Out-Null

$env:USERPROFILE = $sandbox
$env:APPDATA = "$sandbox\AppData\Roaming"
$env:LOCALAPPDATA = "$sandbox\AppData\Local"
$env:TEMP = "$sandbox\Temp"
$env:TMP = "$sandbox\Temp"

& $godot --headless --path $root --script res://tools/validate_pixel_assets.gd
& $godot --headless --path $root --script res://tools/validate_audio.gd
& $godot --headless --path $root --script res://tests/test_runner.gd
& $godot --headless --path $root --script res://tests/app_shell/app_shell_test.gd
& $godot --headless --path $root --script res://tests/app_shell/app_root_integration_test.gd
& $godot --headless --path $root --script res://tests/balance_report.gd
& $godot --headless --path $root --quit-after 2
git diff --check
git status --short --branch
```

각 명령의 종료 코드와 최종 `PASS`/`FAIL`을 확인한다. 에셋 생성기는 저장소 파일을 다시 쓰므로 이전 검증만 할 때 실행하지 않는다.

### 현재 불가능한 배포 빌드

`export_presets.cfg`, Android SDK/JDK, Godot export template이 없으므로 현재 checkout에서는 APK/AAB를 만들 수 없다. preset과 도구 체인을 준비한 뒤에만 다음 형태의 명령을 확정한다.

```powershell
godot --headless --path . --export-debug "Android" <output.apk>
```

현재는 `Android` preset 이름도 정의되지 않았으므로 위 명령을 그대로 실행하면 안 된다.

## 8. 엔진, 프레임워크, 라이브러리와 주요 버전

### 런타임

- Godot `4.7.stable.official.5b4e0cb0f`
- typed GDScript
- Godot GL Compatibility renderer
- 별도 Godot addon, 외부 게임 프레임워크, 네트워크 SDK 없음
- 저장 형식: 자체 JSON envelope schema 1
- 콘텐츠/에셋 manifest: schema 2

### 에셋 제작 및 외부 도구

- `sprite-gen` 1.56.6, component-row 파이프라인
- Waveform Free 14.0.41
- Surge XT 1.3.4 VST3
- Spotify Pedalboard 0.9.23
- Audacity 3.7.8
- Pedalboard가 사용하는 Codex Python: 3.12.13
- Git: 2.52.0.windows.1

Waveform은 설치됐지만 최초 실행 설정과 사용자 VST3 경로 스캔은 하지 않았다. Pedalboard 0.9.23이 Surge XT를 instrument로 불러와 775개 파라미터를 읽는 것은 확인했으며 첫 초기화에 약 97초가 걸렸다.

## 9. 현재 Git 브랜치와 마지막 커밋

- 현재 브랜치: `codex/sprite-roster-batch`
- HEAD: `b60e3a5c584e0ed808b0627f9adb711a4140d6bf`
- 마지막 커밋: `b60e3a5 feat: add live combat feedback and CC0 audio`
- 작성자: `dudcjfsp-cyber`
- 커밋 시각: `2026-07-16T19:12:58+09:00`
- 직전 주요 커밋: `88ec944 feat: ship final-only operator sprites`

별도 Combat V2 worktree:

- 브랜치: `codex/combat-v2-integration`
- HEAD: `012c6c008331a8b5e64550138e0ce77e52505e11`
- checkout: `C:\Users\rycba\.codex\worktrees\edfc\방치형게임2`
- 상태: 조사 시 clean

## 10. 커밋되지 않은 변경사항과 목적

이 문서를 만들기 직전 현재 브랜치는 clean이었다. 이 작업으로 생긴 유일한 미커밋 변경은 다음 파일이다.

- `HANDOFF.md` — D드라이브 이전 및 다음 세션 인수인계를 위한 문서

기능 코드, 설정, 에셋은 수정하지 않았다. 이 문서는 요청에 따라 커밋하거나 push하지 않는다.

## 11. 연결된 원격 저장소

- remote 이름: `origin`
- fetch/push URL: `https://github.com/dudcjfsp-cyber/pixel-night-shift.git`
- 확인된 원격 브랜치: `origin/main`
- `origin/main`: `b53acd6 Initial Pixel Night Shift prototype`
- 현재 HEAD는 `origin/main`보다 10개 커밋 앞이며 뒤처진 커밋은 없다.
- 현재 `codex/sprite-roster-batch`에는 upstream tracking branch가 없다.

**중요:** 원격에는 현재 앱 셸, 최종 요원 스프라이트, 전투 피드백과 최신 오디오 커밋이 없다. D드라이브에서 `origin`을 새로 clone하는 방식만 사용하면 최근 로컬 작업이 복원되지 않는다. 숨김 폴더 `.git`까지 포함해 저장소 전체를 옮기거나, 이동 전에 별도의 Git bundle/원격 백업을 만들어야 한다.

## 12. 확인된 오류, 주의사항과 기술 부채

### 현재 확인된 기능 오류

- 2026-07-21 headless 검증 범위에서는 실패가 없다.
- 실제 Android 기기와 GUI 장시간 플레이는 아직 검증하지 않았으므로 완전한 무결성을 의미하지 않는다.

### 이전 및 저장소 주의사항

- Android export 구성이 전혀 없어 설치 빌드를 만들 수 없다.
- 원격 저장소가 로컬 작업보다 뒤에 있어 재클론을 백업 수단으로 사용할 수 없다.
- `.git`에 약 3.06 MiB의 임시 garbage object 경고가 있다. 현재 동작을 막지는 않으며 이번 작업에서 정리하지 않았다.
- 저장소에 별도 linked worktree가 있다. `.git/worktrees/방치형게임2/gitdir`은 C드라이브 Combat V2 checkout을 절대경로로 가리킨다. 메인 저장소만 D로 이동하면 linked worktree 연결을 repair하거나 D에서 다시 만들어야 한다.
- `.godot/`은 Git에서 무시되는 약 18.47 MiB import/editor 캐시다. 과거 제거된 WAV import 기록과 C드라이브 Godot 실행 경로를 포함한다. D로 옮기지 않거나, 옮겼다면 삭제 후 Godot가 재생성하게 한다.

### 문서와 제품 기술 부채

- `README.md`는 저장·오프라인·앱 셸을 아직 다음 마일스톤이라고 설명해 현재 구현보다 뒤처져 있다.
- Android 동작은 통합 테스트로만 검증했고 기기별 safe area, 백그라운드 제한, 오디오와 진동은 실기 확인이 필요하다.
- 진동 설정은 Android 지원 여부를 노출하지만 실제 기기 피드백의 체감·호출 범위는 확인하지 않았다.
- 현재 BGM/SFX는 기술적으로 유효한 최종 CC0 에셋이지만, 프로젝트 고유의 커스텀 사운드 방향은 아직 제작 전이다.
- 나머지 적 애니메이션과 더 풍부한 공격 동작은 후속 표현 작업이다.
- Combat V2의 진단+어필 자동 정책과 장기 투자 효율 밸런스는 별도 브랜치에서 추가 튜닝이 필요하다.
- Windows 전체 창 자동 캡처는 과거 접근 거부가 발생해 OpenGL framebuffer 캡처로 대체했다. 이는 게임 런타임 오류는 아니다.

## 13. 다음 세션에서 우선 진행할 작업 3개

1. **D드라이브 이전 검증:** 숨김 `.git`을 포함한 전체 저장소를 옮긴 뒤 branch/HEAD/status/remote/worktree를 확인하고 `.godot`을 재생성한 다음 전체 headless 검증을 실행한다.
2. **Android MVP 빌드:** Godot 4.7 export template, JDK/Android SDK, export preset을 구성해 설치 가능한 APK를 만들고 실제 기기에서 저장·복귀·Back·safe area·오디오를 검수한다.
3. **프로젝트 고유 오디오 첫 묶음 제작:** Waveform/Surge XT/Pedalboard/Audacity로 일반 전투 BGM과 `combat_hit`, `enemy_break`, `operator_upgrade`, `boss_warning`을 먼저 제작해 현재 CC0 버전과 A/B 비교한다. 승인된 최종본만 Git에 둔다.

그다음 `docs/PLAYTEST.md` 기준 5인 플레이테스트를 수행하고 README/릴리스 체크리스트를 최신화한다.

## 14. 프로젝트 외부에 있어 별도로 옮겨야 하는 파일이나 도구

### 별도로 백업할 작업 자료

| 현재 경로 | 크기 | 필요성 |
|---|---:|---|
| `C:\Users\Public\Documents\ESTsoft\CreatorTemp\PixelNightShift\sprite-batch-archive-2026-07-16-019f6a18` | 약 60.0 MiB | 스프라이트 원본·후보·중간 작업을 다시 편집하려면 필요. 게임 실행에는 불필요 |
| `C:\Users\Public\Documents\ESTsoft\CreatorTemp\PixelNightShift\kenney_digital-audio` | 약 1.02 MiB | 미사용 CC0 오디오 후보 원본. 게임 실행에는 불필요 |
| `C:\Users\Public\Documents\ESTsoft\CreatorTemp\PixelNightShift\kenney_digital-audio.zip` | 약 0.94 MiB | Kenney 원본 팩 백업. 게임 실행에는 불필요 |
| `C:\Users\Public\Documents\ESTsoft\CreatorTemp\GodotSandbox\combat-visual-audio-captures` | 약 0.40 MiB | 전투/오디오 QA 캡처. 선택적 보존 |
| `C:\Users\Public\Documents\ESTsoft\CreatorTemp\GodotSandbox\combat-v2-appeals-authority-captures` | 약 0.39 MiB | Combat V2 기준 캡처. 선택적 보존 |

현재 저장소는 최종 런타임 에셋만 배송하는 방향이다. 위 원본·후보 묶음을 프로젝트 Git 폴더에 다시 넣지 않는다.

### C드라이브에 설치된 도구

- Godot 4.7 GUI/console: `C:\Users\rycba\AppData\Local\Programs\Godot\Godot-4.7-stable`
- Waveform 14: `C:\Program Files\Tracktion\Waveform 14`
- Audacity: `C:\Users\rycba\AppData\Local\Programs\Audacity`
- Surge XT: `C:\Users\rycba\AppData\Local\Programs\Common\VST3\Surge Synth Team`
- Pedalboard 0.9.23: `C:\Users\rycba\AppData\Roaming\Python\Python312\site-packages`
- Codex Python 3.12.13: `C:\Users\rycba\.cache\codex-runtimes\codex-primary-runtime\dependencies\python`
- sprite-gen 1.56.6 소스: `C:\Users\rycba\.codex\skills\.sources\aldegad-sprite-gen`

같은 Windows 설치에서 프로젝트 폴더만 D로 옮긴다면 위 프로그램은 그대로 사용할 수 있다. C드라이브를 비우거나 다른 PC로 옮긴다면 각각 재설치하거나 별도로 백업해야 한다.

스프라이트 파이프라인에서 사용하는 환경변수 이름은 `SPRITE_GEN` 하나가 확인됐다. 값은 이동 후 실제 sprite-gen 설치 경로로 다시 지정한다. 프로젝트에서 API 키, 인증 토큰, 비밀번호 환경변수는 발견되지 않았다.

### 실제 게임 저장 데이터

- 기본 저장 위치: `user://pixel_night_shift`
- Windows 예상 위치: `%APPDATA%\Godot\app_userdata\Pixel Night Shift\pixel_night_shift`
- 파일 이름: `work_record.json`, `work_record.backup.json`, `settings.json`

현재 실제 사용자 프로필에서는 위 저장 파일이 발견되지 않았고 Godot 로그와 shader cache만 있었다. 따라서 지금 옮길 실플레이 저장은 확인되지 않았다. 이후 저장이 생기면 프로젝트 폴더와 별도로 백업해야 한다.

## 15. C드라이브 또는 OneDrive 절대경로 검사 결과

### 런타임 코드와 주요 설정

- `game/**/*.gd`, `.tscn`, 콘텐츠 JSON, `project.godot`, 오디오 manifest의 런타임 경로는 `res://` 또는 `user://`를 사용한다.
- 런타임이 현재 OneDrive 프로젝트 경로를 직접 요구하는 코드는 발견되지 않았다.
- 따라서 일반 실행과 저장은 D드라이브 이동 자체로 깨질 것으로 보이지 않는다.

### 추적된 생성 메타데이터의 실제 절대경로

다음 파일에는 생성 당시의 C/OneDrive 경로가 문자열로 남아 있다.

- `game/assets/generated/sprites/_base-lock/curation/frames/frames-manifest.json`
- `game/assets/generated/sprites/_base-lock/curation/sprite-request.json`
- `game/assets/generated/sprites/_base-lock/curation/unpack-source.json`
- `game/assets/generated/sprites/broken_pixel/frames/frames-manifest.json`
- `game/assets/generated/sprites/debugger/frames/frames-manifest.json`

`run_dir`, `source_dir` 또는 설명용 provenance 값이다. 현재 런타임과 픽셀 validator는 활성 manifest의 `res://` 상대경로와 해시를 사용하며 이 절대경로 필드를 읽지 않으므로 D드라이브 실행 차단 요소는 아니다. 다만 예전 full-run을 외부 sprite-gen으로 재개할 때는 경로가 낡았으므로 새 위치 기준으로 재생성하거나 보정해야 한다.

문서의 다음 경로는 실행 의존성이 아니라 예시다.

- `docs/ART_GUIDE.md`: `C:\path\to\Godot...`
- `docs/SPRITE_PIPELINE.md`: `C:\Users\<user>\...`

### Git과 Godot의 로컬 메타데이터

- `.godot/editor/project_metadata.cfg`에 현재 Godot GUI 실행 파일의 C 경로가 있다. `.godot`은 무시되는 재생성 캐시다.
- `.git/worktrees/방치형게임2/gitdir`에 별도 Combat V2 checkout의 C 절대경로가 있다. 이것은 Git linked-worktree 연결에 실제 영향을 준다.
- `.agents/`와 `.codex/`에서 추가 절대경로 설정은 발견되지 않았다.

## 16. D드라이브 이전 후 반드시 확인할 항목

1. Godot, Codex, Git 관련 프로세스를 닫고 폴더를 옮긴다.
2. 원격 clone에 의존하지 말고 숨김 `.git`을 포함한 저장소 전체가 이동됐는지 확인한다.
3. 다음 값이 이 문서의 기준과 같은지 확인한다.

   ```powershell
   git status --short --branch
   git branch --show-current
   git rev-parse HEAD
   git remote -v
   git worktree list
   ```

   예상 branch는 `codex/sprite-roster-batch`, HEAD는 `b60e3a5c584e0ed808b0627f9adb711a4140d6bf`다. `HANDOFF.md`만 미커밋이어야 한다.

4. `.godot`을 복사하지 않았는지 확인하거나, 복사했다면 삭제한 뒤 D드라이브의 `project.godot`을 Godot 4.7에서 다시 import한다.
5. 별도 Combat V2 worktree를 함께 옮겼다면 `git worktree repair`로 경로를 복구한다. 옮기지 않았다면 clean/committed branch `codex/combat-v2-integration`에서 새 worktree를 만드는 편이 안전하다.
6. `SPRITE_GEN` 환경변수가 필요한 작업에서는 새 실제 경로를 다시 지정한다.
7. `project.godot`의 메인 장면이 `res://game/app/app_root.tscn`인지 확인한다.
8. 7절의 전체 validator·테스트·balance·headless 실행을 D드라이브 경로에서 다시 통과시킨다.
9. 오디오, sprite atlas와 `.import`가 새 위치에서 정상 재import되는지 확인한다.
10. 새 게임을 시작해 저장 후 `%APPDATA%\Godot\app_userdata\Pixel Night Shift\pixel_night_shift`에 파일이 생성되는지 확인한다. 프로젝트 위치가 바뀌어도 `user://` 데이터는 자동으로 D프로젝트 안으로 이동하지 않는다.
11. Android 작업을 시작하기 전에 export template, SDK/JDK, preset과 서명 파일 위치를 새 환경에서 다시 확인한다. 비밀값이나 서명 암호는 저장소와 이 문서에 기록하지 않는다.
12. D드라이브 checkout을 충분히 검증하기 전에는 기존 C/OneDrive 폴더와 외부 작업 보관소를 삭제하지 않는다.
