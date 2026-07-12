# 애니메이션 스프라이트 파이프라인

캐릭터 애니메이션은 `sprite-gen` 1.56.6의 `component-row` 경로만 사용합니다. 패치 아이콘, UI 아이콘, 배경과 아직 전환하지 않은 캐릭터의 정적 PNG는 기존 `tools/generate_pixel_assets.gd`가 계속 소유합니다. 정적 PNG를 확대하거나 다시 포장한 결과는 애니메이션 run으로 인정하지 않습니다.

## 단일 진실 공급원

각 run의 `sprite-request.json`이 셀 크기, 안전 여백, 상태, 프레임 수, FPS, 반복 여부, 크로마, 맞춤 방식과 픽셀 정규화의 숫자 계약입니다. Pixel Night Shift의 기본 계약은 다음과 같습니다.

- 요원·일반 적: `32x32`
- 보스: `48x48`
- 정렬: `foot-centroid`, `bottom`
- 필터: `Nearest`
- 런타임 프레임: `manifest.json.frame_layout`의 절대 사각형
- 필수 상태: 요원 `idle/upgrade`, 적·보스 `idle/hurt`

런타임은 알파를 분석하거나 그리드를 추측하지 않습니다. 매니페스트, 해시, 셀 크기 또는 사각형이 잘못되면 `PresentationAssets` 초기화가 명시적으로 실패합니다.

## Run 구조

```text
game/assets/generated/sprites/<asset-id>/
  sprite-request.json
  base-source.png
  references/layout-guides/<state>.png
  prompts/<state>.txt
  raw/<state>.png
  frames/
    frames-manifest.json
    <state>/frame-*.png
  qa/
    all-contact.png
    <state>-contact.png
    <state>.gif
  sprite-sheet-alpha.png
  sprite-sheet-alpha.report.json
  manifest.json
  qa-notes.md
```

Base 후보와 잠금 근거는 `game/assets/generated/sprites/_base-lock/`에 보존합니다. 한 대상에는 하나의 canonical base만 사용하며, 선택 파일의 SHA-256과 기술 근거를 감사 기록에 남깁니다.

## 재생성 순서

PowerShell에서 설치된 스킬 경로를 지정한 뒤 실행합니다.

```powershell
$env:SPRITE_GEN = "C:\Users\<user>\.codex\skills\.sources\aldegad-sprite-gen"
$run = "game\assets\generated\sprites\<asset-id>"

python "$env:SPRITE_GEN\scripts\prepare_sprite_run.py" --out-dir $run --character-id <asset-id> --base-image <locked-base.png>
# prompts/<state>.txt, base-source.png, layout guide를 함께 참조해 raw/<state>.png를 실제 이미지 생성으로 만듭니다.
python "$env:SPRITE_GEN\scripts\extract_sprite_row_frames.py" --run-dir $run
python "$env:SPRITE_GEN\scripts\preview_animation.py" --run-dir $run
python "$env:SPRITE_GEN\scripts\compose_sprite_atlas.py" --run-dir $run
python "$env:SPRITE_GEN\scripts\serve_curation.py" --run-dir $run --lang ko --port 0
```

실제 옵션은 run의 기존 `sprite-request.json`과 `qa-notes.md`를 먼저 확인합니다. 이미 잠긴 숫자 계약을 명령행 기본값으로 되돌리지 않습니다. 실패한 상태만 같은 base와 guide를 사용해 row 단위로 다시 생성합니다. 프레임을 손으로 고치거나 재타이밍해 실패를 숨기지 않습니다.

## Base Lock과 큐레이션 재개

Base Lock은 전신 비크롭, 최종 비율·스타일, 정체성/소품 보존, 작은 크기 실루엣, 단일 idle 포즈와 크로마 준비도를 확인하는 차단 게이트입니다. Base Lock 전에는 상태 행을 대량 생성하지 않습니다.

최종 후보 검토는 다음 명령으로 다시 엽니다.

```powershell
python "$env:SPRITE_GEN\scripts\serve_curation.py" --run-dir "game\assets\generated\sprites\debugger" --lang ko --port 0
```

서버가 출력한 로컬 URL을 열고 상태별 프레임·GIF를 확인합니다. 선택 정보는 run의 `curation/curation.json`에 남으므로 같은 run 디렉터리로 재개할 수 있습니다. 큐레이션 전후의 원본 row와 추출 프레임은 삭제하지 않습니다.

## QA 및 활성화

활성 run은 다음을 모두 만족해야 합니다.

- `frames/frames-manifest.json.ok == true`
- `sprite-sheet-alpha.report.json.ok == true`
- 요청한 상태별 프레임 수가 정확함
- 빈 프레임, 잘림, 분리 파편, 크로마 누출과 심한 앵커 이동이 없음
- loop의 마지막→첫 프레임과 non-loop의 시작→중간→끝이 읽힘
- canonical 프레임은 이진 알파와 프로젝트 팔레트 제한을 만족함
- `qa-notes.md`에 상태별 `pass`, `best-effort` 또는 `experimental`과 근거가 있음

`game/assets/manifest.json` schema 2의 `active_sprite_runs`가 원자적인 활성화 지점입니다. 각 항목은 run 매니페스트와 atlas의 SHA-256, 매니페스트 계약 버전, 생성기 버전과 라이선스를 기록합니다. 기존 정적 `assets` 23개 항목은 롤백·검증 자료로 계속 유지합니다.

활성 run의 `manifest.json` 권위 바이트는 `.gitattributes`와 동일한 LF입니다. CR 바이트가 있으면 검증에 실패하며, root의 `manifest_sha256`은 의미상 정규화한 JSON이 아니라 LF 실제 바이트의 SHA-256을 pin합니다. 생성 결과가 CRLF라면 먼저 LF로 정규화한 뒤 pin을 갱신해야 합니다. 런타임은 이 바이트를 자동 정규화하거나 폴백하지 않고 raw-byte SHA를 그대로 비교합니다.

## 출처와 라이선스

Base와 raw row는 이 프로젝트를 위해 새로 만든 독자 디자인입니다. 외부 다운로드 에셋을 섞지 않으며, 참고 게임의 캐릭터·실루엣·팔레트·UI 구도를 복제하지 않습니다. 프로젝트 소유 에셋의 라이선스 표기는 `LicenseRef-PixelNightShift-Original`입니다.
