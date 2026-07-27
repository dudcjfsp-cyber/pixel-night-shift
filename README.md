# Pixel Night Shift · 픽셀 야간근무

> 서버가 살아있다

《픽셀 야간근무》는 서비스 종료 직전의 레트로 게임을 지키는 야간 운영팀을 다룬 세로형
운영 게임입니다. 현재 배포본은 연속 자동 전투이고, 개발 중인 Product V2는 주간 방치
정비와 짧은 야간 자동 디펜스를 결합합니다.

현재 실행 가능한 빌드는 **Godot 4.7용 20스테이지 V1 수직 슬라이스**입니다. 앱 셸,
schema 2 로컬 저장·복구와 오프라인 전투, 보스전 전용 역할·내구도·PROCESS DOWN·QA
자동 구조가 구현돼 있고 공개 GitHub Pages에서 테스트할 수 있습니다. 상세 회귀 기준은
[V1 전투 동결 기준선](docs/V1_COMBAT_BASELINE.md)에 남겨 두었습니다.

현재 개발 목표는 [Product V2 계획표](docs/PRODUCT_V2_PLAN.md)의 1~7단계입니다. 목표
전투는 [Product V2 혼합 디펜스 명세](docs/COMBAT_HYBRID_SPEC.md)를 따르며, Defense Lab
검증 전에는 현재 V1 실행 경로와 저장을 변경하지 않습니다.

**웹 테스트 플레이:** [https://dudcjfsp-cyber.github.io/pixel-night-shift/](https://dudcjfsp-cyber.github.io/pixel-night-shift/)

## 실행

Godot 4.7 Project Manager에서 `project.godot`을 가져온 뒤 프로젝트를 실행합니다. 메인 장면은 `res://game/app/app_root.tscn`이며 논리 해상도는 360×640입니다. 정상 콜드 부트는 타이틀에서 시작하며, 새 근무는 5단계 프롤로그 뒤 최초 저장에 성공한 다음 현장 온보딩으로 이어집니다.

Windows의 Godot 4.7 공식 빌드에는 GUI 종료 시 네이티브 오류 창이 나타날 수 있는 엔진 문제가 있습니다. 자동 검증에는 GUI 실행 파일이나 `godot.bat`을 직접 사용하지 말고 아래 전용 실행기를 사용합니다.

실제 화면과 소리를 확인하는 수동 E2E는 별도 세션 ID로 실행합니다. 새로운 ID는 빈 근무 기록으로 시작하고, 같은 ID를 다시 사용하면 방금 만든 테스트 기록을 이어갑니다. 실제 `user://`와 설정은 `.godot/manual-e2e-runtime/` 아래로 격리되며 종료 오류 대화상자도 억제됩니다.

```powershell
.\tools\run_godot_manual_e2e.ps1 -SessionId opening-check-001
```

### 웹 테스트 배포

`main` 브랜치에 푸시하거나 Actions에서 수동 실행하면 [Pages 워크플로](.github/workflows/deploy-pages.yml)가 Godot 4.7 Web 빌드를 내보내 위 테스트 URL에 배포합니다. JS·WASM·PCK 파일명에는 커밋 SHA가 들어가 이전 빌드 캐시와 섞이지 않으며, 사용자 진행은 브라우저별 로컬 저장에만 남습니다.

이 경로는 친구 대상 수직 슬라이스 테스트용입니다. 계정·클라우드 저장·PWA·정식 웹 플랫폼 지원을 뜻하지 않습니다. 배포 워크플로는 내보내기와 산출물 참조만 검사하고 아래 자동 테스트를 실행하지 않으므로, 검증을 통과한 변경만 푸시합니다.

## 검증

도메인 테스트는 별도 애드온 없이 Godot 자체의 스크립트 실행 기능으로 동작합니다. 헤드리스 전용 실행기는 Godot 프로세스를 하나씩 실행하고 로그와 `user://`를 프로젝트의 `.godot/` 아래에 격리합니다.

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

검증 명령은 파일을 바꾸지 않습니다. `tools/generate_pixel_assets.gd`와 `tools/generate_audio.gd`는 원본 에셋을 다시 쓰므로 재생성이 목적일 때만 별도로 실행합니다. 마지막 명령은 메인 장면이 헤드리스 환경에서 파서·리소스 오류 없이 시작되는지 확인합니다.

## 현재 배포본 V1 포함 범위

- 360×640 세로형 메인 화면
- 자동 전투와 20스테이지
- 고정 요원 4명
- 후보 패치 5개와 패치 슬롯 3개
- 스테이지 10·20에서 강화 재사용되는 Watchdog Process 보스
- 비트, 패치노트, 버전 업데이트 1회 순환
- 보스 실패 후 자동 유지보수 파밍과 재도전
- 보스전 전용 요원 역할·HP·PROCESS DOWN과 QA 자동 구조
- 실패 근거가 포함된 진단 카드와 최신 실패를 설명하는 최대 2행의 읽기 전용 현장 보고서
- 새 보고서 알림·재열람 모달과 비트·패치노트·스테이지 설명 말풍선
- 요원·적·패치·자원용 원본 픽셀 에셋과 서버실 전투 배경
- 타이틀·전투·보스·유지보수 BGM 4곡, 프로젝트 원본 전투 효과음 4종과 상황별 효과음
- 진단에서 패치 화면으로 이어지는 UI와 음악·효과음 토글
- 콜드 부트 타이틀, 5단계 첫 근무 프롤로그, 야간 운영실, 설정, 현장 온보딩과 버전 업데이트 확인·요약 흐름
- schema 2 로컬 저장, schema 1 마이그레이션, 백업 복구와 결정론적 오프라인 진행
- Android/iOS 일시정지·복귀와 Web/desktop 포커스 이탈·복귀의 저장·오프라인 중복 방지
- Android 뒤로가기·안전 영역, Web 전체 화면·세로 화면비·한글 폰트 폴백
- Godot Web 내보내기 프리셋과 GitHub Pages 자동 테스트 배포
- 결정론적 도메인 테스트와 콘텐츠 검증

기본 본편에는 V1 혼합 전투가 적용됐지만 이전 Combat V2 테스트 모드는 Product V2
Defense Lab과 별개의 Legacy 비교 기준입니다. Pages는 테스트 배포 경로일 뿐 정식 웹
서비스가 아니며 Android 패키징도 현재 보류 중입니다. Product V2 범위는
[범위 문서](docs/SCOPE.md), 제품 규칙은 [게임 설계](docs/GDD.md), 목표 전투는
[혼합 디펜스 명세](docs/COMBAT_HYBRID_SPEC.md), 현재 V1 사람 검증 기록은
[플레이테스트](docs/PLAYTEST.md), 앱 흐름은 [앱 셸 명세](docs/APP_SHELL_SPEC.md), 코드
의존 계약은 [아키텍처](docs/ARCHITECTURE.md)를 참고하세요.

## 구조

```text
game/content/       수치와 콘텐츠 원본 및 로딩 검증
game/domain/        전투·성장·진단·환생 규칙
game/app/           GameSession 명령 경계
game/presentation/  장면과 UI
game/assets/        생성된 픽셀 PNG·WAV와 출처 매니페스트
tools/              에셋·오디오 재생성 및 검증 스크립트
tests/              헤드리스 관찰 행동 테스트
docs/               설계·범위·아키텍처 계약
```

표현 계층은 도메인 상태를 직접 바꾸지 않습니다. 모든 입력은 `GameSession` 명령으로 전달되고, 화면과 테스트는 스냅숏을 읽습니다.
