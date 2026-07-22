# 오디오 가이드

## 방향

《픽셀 야간근무》의 전투 음악과 UI·운영 효과음은 CC0로 공개된 완성형 8비트·디지털 오디오를 사용합니다. 반복해서 들리는 타격음과 전투 피드백 4종은 저장소의 Python 생성기로, 타이틀·유지보수 음악과 근무 승인음은 Godot 생성기로 직접 합성합니다. 외부 원본 링크, 저작자, 라이선스, 파일 해시는 `game/assets/audio/ATTRIBUTION.md`와 manifest에 남깁니다.

## 구성

- `title_loop.wav`: 16마디, 72 BPM, E단조의 첫 화면용 프로젝트 원본 루프
- `night_shift_loop.ogg`: 일반 자동 전투용 CC0 8비트 전투 루프
- `watchdog_loop.ogg`: 보스 교전용 CC0 145 BPM 루프
- `maintenance_loop.wav`: 자동 복구 파밍용 76 BPM 루프
- `shift_authorized.wav`: 근무 권한 이관을 알리는 0.95초 프로젝트 원본 전환음
- `combat_hit.wav`, `enemy_break.wav`, `operator_upgrade.wav`, `boss_warning.wav`: NumPy와 Pedalboard로 합성한 프로젝트 원본 전투 효과음
- 나머지 `game/assets/audio/sfx/*.ogg`: Kenney Digital Audio에서 선별한 선택, 오류, 단계 완료, 패치, 유지보수, 업데이트 효과음

음악은 `Music` 버스, 효과음은 `SFX` 버스로 분리합니다. 두 버스 모두 합산 시 여유가 남도록 기본 음량을 낮췄습니다. 헤더의 `♪`와 `FX` 버튼은 각각 현재 실행 중인 음악과 효과음을 끕니다.

## 재생 경계

`AudioDirector`는 `GameSession`을 불러오거나 전투 상태를 변경하지 않습니다. 화면 스냅숏의 `stage`, `stage_enemy_index`, `mode`, `prestige_available` 전환으로 자동 진행음을 재생하고, 플레이어가 누른 버튼의 성공·실패는 `MainView`가 의미 기반 cue로 전달합니다.

타이틀은 전투 스냅숏의 mode가 아니므로 프레젠테이션 경계에서 `play_title_music()`으로 시작합니다. 웹 브라우저가 자동 재생을 막은 경우 첫 사용자 클릭이나 터치에서 `retry_current_music_after_user_gesture()`를 한 번 호출합니다. 스토리 뒤 실제 세션으로 진입하면 기존 스냅숏 동기화가 전투 음악으로 전환합니다.

자동 전투 타격음은 화면이 같은 적의 실제 HP 감소를 확인하고 투사체가 닿는 순간에만 재생합니다. 연속 프레임마다 울리지 않도록 화면의 공격 cadence로 묶으며, 적 격파·스테이지 이동·보스·유지보수 진입과 운영 결정은 기존 의미 기반 cue로 구분합니다.

## 재생성 및 검증

```powershell
python .\tools\generate_original_sfx.py
.\tools\run_godot_headless.ps1 --script res://tools/generate_audio.gd
.\tools\run_godot_headless.ps1 --script res://tools/validate_audio.gd
```

첫 명령은 NumPy와 Pedalboard가 설치된 제작용 Python 환경에서 실행하며, 검토용 WAV와 분석 결과를 `.godot/audio-candidates/original-sfx-v1/`에 만듭니다. 채택한 4개 WAV를 `game/assets/audio/sfx/`에 반영한 뒤 Godot 생성기를 실행하면, 타이틀·유지보수 음악과 근무 승인음을 결정론적으로 합성하고 모든 실제 파일에서 길이와 SHA-256을 읽어 manifest를 갱신합니다.

생성 결과의 시드와 외부 파일의 출처를 포함한 길이, SHA-256, 라이선스는 `game/assets/audio/manifest.json`에 기록됩니다. 외부 팩 전체나 중간 후보는 Git에 넣지 않고 런타임에서 쓰는 최종 OGG/WAV만 보관하므로, 게임 실행 시 NumPy, Pedalboard, Python 또는 생성기가 필요하지 않습니다.
