extends RefCounted

const OPERATIONS_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/operations_room_view_data.gd"
)
const OFFLINE_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/offline_report_view_data.gd"
)

const SCREEN_BOOT: StringName = &"boot"
const SCREEN_FIRST_SHIFT: StringName = &"first_shift"
const SCREEN_OPERATIONS_ROOM: StringName = &"operations_room"
const SCREEN_OFFLINE_REPORT: StringName = &"offline_report"


static func states() -> Array[Dictionary]:
	return [
		{
			"id": &"boot",
			"label": "BOOT · 로컬 기록 확인",
			"screen": SCREEN_BOOT,
			"status": "근무 기록 확인 중…",
		},
		{
			"id": &"first_shift",
			"label": "FIRST SHIFT · 최초 진입",
			"screen": SCREEN_FIRST_SHIFT,
		},
		{
			"id": &"operations_normal",
			"label": "OPERATIONS · 정상 저장",
			"screen": SCREEN_OPERATIONS_ROOM,
			"data": operations_normal(),
		},
		{
			"id": &"operations_save_error",
			"label": "OPERATIONS · 저장 실패",
			"screen": SCREEN_OPERATIONS_ROOM,
			"data": OPERATIONS_DATA_SCRIPT.new(
				2,
				true,
				"자동 운영 중",
				14,
				"처리량 부족",
				2,
				3,
				"감시견 · ST 20",
				"저장되지 않음 · 다시 시도 필요",
				OPERATIONS_DATA_SCRIPT.SaveState.ERROR
			),
		},
		{
			"id": &"offline_bottleneck",
			"label": "OFFLINE · 정체 감지",
			"screen": SCREEN_OFFLINE_REPORT,
			"data": OFFLINE_DATA_SCRIPT.new(
				8040,
				12_400.0,
				14,
				17,
				true,
				17,
				"예상 처치가 4.8초 느림",
				false
			),
		},
		{
			"id": &"offline_clear",
			"label": "OFFLINE · 정체 없음",
			"screen": SCREEN_OFFLINE_REPORT,
			"data": OFFLINE_DATA_SCRIPT.new(
				930,
				2850.0,
				8,
				10,
				false,
				0,
				"",
				false
			),
		},
		{
			"id": &"offline_capped",
			"label": "OFFLINE · 8시간 집계 상한",
			"screen": SCREEN_OFFLINE_REPORT,
			"data": OFFLINE_DATA_SCRIPT.new(
				28_800,
				88_600.0,
				16,
				20,
				true,
				20,
				"감시견 복구 주기가 처리량을 앞섬",
				true
			),
		},
	]


static func operations_normal() -> OPERATIONS_DATA_SCRIPT:
	return OPERATIONS_DATA_SCRIPT.new(
		2,
		true,
		"자동 운영 중",
		14,
		"처리량 부족",
		2,
		3,
		"감시견 · ST 20",
		"방금 저장됨",
		OPERATIONS_DATA_SCRIPT.SaveState.SAVED
	)
