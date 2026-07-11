# 오디오 가이드

## 방향

《픽셀 야간근무》의 오디오는 외부 샘플이나 기존 곡을 사용하지 않고 저장소의 Godot 생성기로 합성합니다. 펄스파·삼각파·고정 시드 노이즈만 사용해 낡은 야간 서버실, 자동 전투, 위험한 감시 프로세스의 분위기를 구분합니다.

## 구성

- `night_shift_loop.wav`: 일반 자동 전투용 96 BPM 루프
- `watchdog_loop.wav`: 보스 교전용 148 BPM 루프
- `maintenance_loop.wav`: 자동 복구 파밍용 76 BPM 루프
- `game/assets/audio/sfx/`: 선택, 오류, 적 격파, 단계 완료, 강화, 패치, 보스, 업데이트 효과음

음악은 `Music` 버스, 효과음은 `SFX` 버스로 분리합니다. 두 버스 모두 합산 시 여유가 남도록 기본 음량을 낮췄습니다. 헤더의 `♪`와 `FX` 버튼은 각각 현재 실행 중인 음악과 효과음을 끕니다.

## 재생 경계

`AudioDirector`는 `GameSession`을 불러오거나 전투 상태를 변경하지 않습니다. 화면 스냅숏의 `stage`, `stage_enemy_index`, `mode`, `prestige_available` 전환으로 자동 진행음을 재생하고, 플레이어가 누른 버튼의 성공·실패는 `MainView`가 의미 기반 cue로 전달합니다.

자동 전투에 반복 타격음을 넣지 않습니다. 적 격파, 스테이지 이동, 보스·유지보수 진입, 운영 결정처럼 플레이어가 구분해야 할 변화만 소리로 알립니다.

## 재생성 및 검증

```powershell
godot --headless --path . --script res://tools/generate_audio.gd
godot --headless --path . --script res://tools/validate_audio.gd
```

생성 결과의 시드, 길이, SHA-256, 출처는 `game/assets/audio/manifest.json`에 기록됩니다. WAV는 저장소에 포함되므로 게임 실행 시 생성기나 Python이 필요하지 않습니다.
