# Pixel Night Shift · 픽셀 야간근무

> 서버는 아직 살아 있다.

《픽셀 야간근무》는 서비스 종료 직전의 레트로 게임을 지키는 야간 운영팀을 다룬 세로형 방치 게임입니다. 전투와 재도전은 완전 자동이며, 플레이어는 화면의 진단 정보를 읽고 요원을 강화하거나 장단점이 함께 있는 임시 패치를 선택합니다.

현재 실행 가능한 빌드는 **Godot 4.7용 20스테이지 앱 셸 통합 프로토타입**입니다. `관찰 → 진단 → 패치 → 버전 업데이트` 순환 위에 야간 운영실, 로컬 저장·복구, 오프라인 진행, 재현 가능한 픽셀 에셋과 오디오를 연결했습니다. 다음 마일스톤은 [본편 혼합 전투 완성도 명세](docs/COMBAT_HYBRID_SPEC.md)에 따라 보스전 역할·내구도·자동 구조를 본편에 선별 승격하는 작업입니다.

![픽셀 야간근무 UI](docs/screenshots/ui-polish.png)

## 실행

Godot 4.7에서 `project.godot`을 열고 프로젝트를 실행하거나, 저장소 루트에서 다음 명령을 사용합니다.

```powershell
godot --path .
```

Godot 실행 파일이 `PATH`의 `godot` 이름으로 등록되지 않았다면 설치된 콘솔 실행 파일의 전체 경로를 사용합니다.

## 검증

도메인 테스트는 별도 애드온 없이 Godot 자체의 스크립트 실행 기능으로 동작합니다.

```powershell
godot --headless --path . --script res://tools/generate_pixel_assets.gd
godot --headless --path . --script res://tools/validate_pixel_assets.gd
godot --headless --path . --script res://tools/generate_audio.gd
godot --headless --path . --script res://tools/validate_audio.gd
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --script res://tests/app_shell/app_shell_test.gd
godot --headless --path . --script res://tests/app_shell/app_root_integration_test.gd
godot --headless --path . --script res://tests/balance_report.gd
godot --headless --path . --script res://tests/combat_v2/combat_v2_test_runner.gd
godot --headless --path . --script res://tests/combat_v2/combat_v2_appeal_test.gd
godot --headless --path . --script res://tests/combat_v2/combat_v2_integration_test.gd
godot --headless --path . --quit-after 2
```

에셋·오디오 명령은 원본 PNG와 WAV를 재생성하고 크기·해시를 검사합니다. 테스트 러너는 본편 도메인, 앱 셸·저장, 격리된 Combat V2 실험을 각각 검증합니다. 현재 밸런스 리포트는 승격 전 본편 기준선이며, 혼합 전투 구현 후에는 25~35분 목표를 검사하도록 갱신합니다. 마지막 명령은 메인 장면이 헤드리스 환경에서 파서·리소스 오류 없이 시작되는지 확인합니다.

## 현재 포함 범위

- 360×640 세로형 메인 화면
- 자동 전투와 20스테이지
- 고정 요원 4명
- 후보 패치 5개와 패치 슬롯 3개
- 스테이지 10·20에서 강화 재사용되는 Watchdog Process 보스
- 비트, 패치노트, 버전 업데이트 1회 순환
- 보스 실패 후 자동 유지보수 파밍과 재도전
- 요원·적·패치·자원용 원본 픽셀 에셋과 서버실 전투 배경
- 전투·보스·유지보수 BGM 3곡과 상황별 효과음
- 진단에서 패치 화면으로 이어지는 UI와 음악·효과음 토글
- 최초 근무, 야간 운영실, 설정, 온보딩과 버전 업데이트 확인·요약 흐름
- 버전이 있는 로컬 저장, 백업 복구와 결정론적 오프라인 진행
- Android 일시정지·복귀·뒤로가기·안전 영역 동작
- 결정론적 도메인 테스트와 콘텐츠 검증

현재 기본 본편에는 아직 Combat V2의 역할·요원 내구도·QA 구조가 적용되지 않았고, 부서, 사건, 장편 콘텐츠와 상용 수준의 다중 애니메이션도 없습니다. 상세한 제품 규칙은 [게임 설계 문서](docs/GDD.md), 현재 전투 마일스톤은 [본편 혼합 전투 완성도 명세](docs/COMBAT_HYBRID_SPEC.md), 완료된 회색 상자 기준은 [프로토타입 범위](docs/SCOPE.md), 앱 흐름은 [앱 셸 명세](docs/APP_SHELL_SPEC.md), 코드 의존 계약은 [아키텍처](docs/ARCHITECTURE.md)를 참고하세요.

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
