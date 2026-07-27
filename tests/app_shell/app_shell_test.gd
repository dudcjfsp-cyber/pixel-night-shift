extends SceneTree

const BOOT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/boot_view.tscn"
)
const FIRST_SHIFT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/first_shift_view.tscn"
)
const TITLE_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/title_view.tscn"
)
const PROLOGUE_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/prologue_view.tscn"
)
const OPERATIONS_ROOM_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/operations_room_view.tscn"
)
const OFFLINE_REPORT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/offline_report_view.tscn"
)
const PREVIEW_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/app_shell_preview.tscn"
)
const BOOT_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/boot_view.gd"
)
const FIRST_SHIFT_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/first_shift_view.gd"
)
const TITLE_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/title_view.gd"
)
const PROLOGUE_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/prologue_view.gd"
)
const OPERATIONS_ROOM_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/operations_room_view.gd"
)
const OFFLINE_REPORT_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/offline_report_view.gd"
)
const PREVIEW_CONTROLLER_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/preview/app_shell_preview_controller.gd"
)
const OPERATIONS_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/operations_room_view_data.gd"
)
const OFFLINE_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/offline_report_view_data.gd"
)
const ARTWORK_SLOT_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/app_shell_artwork_slot.gd"
)

const LOGICAL_SIZE := Vector2(360.0, 640.0)
const TOUCH_MIN := 48.0
const PRIMARY_HEIGHT := 52.0
const SIZE_EPSILON := 0.01

var _passed_tests := 0
var _failed_tests := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	root.size = Vector2i(LOGICAL_SIZE)
	print("Pixel Night Shift app-shell tests")
	print("===================================")
	await _run_async_test("product and preview scene smoke load", _test_scene_smoke_load)
	await _run_async_test("boot and first-shift contracts", _test_boot_and_first_shift)
	await _run_async_test("title and prologue contracts", _test_title_and_prologue)
	await _run_async_test("view-data validation boundaries", _test_view_data_validation)
	await _run_async_test("operations-room states and signals", _test_operations_room)
	await _run_async_test("offline-report variants and signals", _test_offline_report)
	await _run_async_test("preview state navigation", _test_preview_navigation)

	print("===================================")
	print(
		"RESULT: %d passed, %d failed, %d assertion failures"
		% [_passed_tests, _failed_tests, _assertion_failures]
	)
	quit(0 if _failed_tests == 0 else 1)


func _run_async_test(test_name: String, test_method: Callable) -> void:
	var failures_before := _assertion_failures
	await test_method.call()
	if _assertion_failures == failures_before:
		_passed_tests += 1
		print("PASS  %s" % test_name)
		return
	_failed_tests += 1
	print("FAIL  %s" % test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_assertion_failures += 1
	print("      - %s" % message)


func _test_scene_smoke_load() -> void:
	var cases: Array[Dictionary] = [
		{"label": "boot", "scene": BOOT_SCENE},
		{"label": "first shift", "scene": FIRST_SHIFT_SCENE},
		{"label": "title", "scene": TITLE_SCENE},
		{"label": "prologue", "scene": PROLOGUE_SCENE},
		{"label": "operations room", "scene": OPERATIONS_ROOM_SCENE},
		{"label": "offline report", "scene": OFFLINE_REPORT_SCENE},
		{"label": "app-shell preview", "scene": PREVIEW_SCENE},
	]
	for case_data: Dictionary in cases:
		var label := String(case_data["label"])
		var scene := case_data["scene"] as PackedScene
		_check(scene != null and scene.can_instantiate(), "%s scene must load" % label)
		if scene == null or not scene.can_instantiate():
			continue
		var instance := scene.instantiate()
		var mounted := await _mount(instance, label)
		if mounted:
			_check_button_sizes(instance, label)
		await _unmount(instance)


func _test_boot_and_first_shift() -> void:
	var boot := BOOT_SCENE.instantiate() as BOOT_VIEW_SCRIPT
	_check(boot != null, "boot scene must instantiate with its product script")
	if boot != null:
		boot.configure("서비스 부팅 순서 확인 중…")
		if await _mount(boot, "boot contract"):
			_check_copy(
				boot,
				"boot",
				PackedStringArray([
					"PIXEL NIGHT SHIFT // BOOT",
					"서비스 부팅 순서 확인 중…",
					"[전환 상태]",
					"입력 없이 다음 화면으로 이동합니다.",
				])
			)
			var boot_buttons: Array[BaseButton] = []
			_collect_buttons(boot, boot_buttons)
			_check(boot_buttons.is_empty(), "boot must remain a transition state without menu actions")
		await _unmount(boot)

	var first_shift := FIRST_SHIFT_SCENE.instantiate() as FIRST_SHIFT_VIEW_SCRIPT
	_check(first_shift != null, "first-shift scene must instantiate with its product script")
	if first_shift == null:
		return
	var signal_counts: Array[int] = [0, 0]
	first_shift.first_shift_requested.connect(
		func() -> void: signal_counts[0] += 1
	)
	first_shift.settings_requested.connect(
		func() -> void: signal_counts[1] += 1
	)
	if await _mount(first_shift, "first-shift contract"):
		_check_copy(
			first_shift,
			"first shift",
			PackedStringArray([
				"PIXEL NIGHT SHIFT",
				"픽셀 야간근무",
				"서버가 살아있다",
				"전투는 요원들이 맡습니다.",
				"병목을 진단하고 장점과 부작용이 있는 패치를 선택하세요.",
				"첫 근무 시작",
				"설정",
			])
		)
		_check_button_sizes(first_shift, "first shift")
		var primary := _find_button(first_shift, "PrimaryActionButton", "first shift primary")
		var settings := _find_button(first_shift, "SettingsButton", "first shift settings")
		_emit_pressed(primary)
		_emit_pressed(settings)
		_check(signal_counts[0] == 1, "first-shift primary must emit first_shift_requested once")
		_check(signal_counts[1] == 1, "first-shift settings must emit settings_requested once")
		_check(first_shift.is_inside_tree(), "first-shift view must not navigate itself")
	await _unmount(first_shift)


func _test_title_and_prologue() -> void:
	var title := TITLE_SCENE.instantiate() as TITLE_VIEW_SCRIPT
	_check(title != null, "title scene must instantiate with its product script")
	if title == null:
		return
	title.configure(false)
	var title_signal_counts: Array[int] = [0, 0, 0]
	title.start_requested.connect(func() -> void: title_signal_counts[0] += 1)
	title.continue_requested.connect(func() -> void: title_signal_counts[1] += 1)
	title.prologue_replay_requested.connect(func() -> void: title_signal_counts[2] += 1)
	if not await _mount(title, "title contract"):
		await _unmount(title)
		return

	_check_copy(
		title,
		"title",
		PackedStringArray([
			"픽셀",
			"야간",
			"근무",
			"서버가 살아있다",
		])
	)
	_check_not_copy(title, "title", PackedStringArray(["PIXEL NIGHT SHIFT"]))
	var title_primary := _find_button(title, "PrimaryActionButton", "title primary")
	var account_link := _find_button(title, "AccountLinkButton", "title account link")
	var prologue_replay := _find_button(
		title, "PrologueReplayButton", "title prologue replay"
	)
	_check(title_primary != null and title_primary.text == "게임 시작", "new title must offer game start")
	_check(account_link != null and account_link.disabled, "account linking must remain disabled")
	_check(prologue_replay != null and not prologue_replay.visible, "new title must hide replay")
	_emit_pressed(title_primary)
	_check(title_signal_counts[0] == 1, "new title primary must emit start_requested once")
	_check(title_signal_counts[1] == 0, "new title primary must not emit continue_requested")

	title.configure(true)
	await _wait_frames(2)
	_check(title_primary.text == "이어하기", "saved title must offer continue")
	_check(prologue_replay.visible, "saved title must expose prologue replay")
	_emit_pressed(title_primary)
	_emit_pressed(prologue_replay)
	_check(title_signal_counts[1] == 1, "saved title primary must emit continue_requested once")
	_check(title_signal_counts[2] == 1, "title replay must emit prologue_replay_requested once")
	await _unmount(title)

	var prologue := PROLOGUE_SCENE.instantiate() as PROLOGUE_VIEW_SCRIPT
	_check(prologue != null, "prologue scene must instantiate with its product script")
	if prologue == null:
		return
	_check(prologue.configure(0, false, true), "first prologue step must configure")
	var prologue_signal_counts: Array[int] = [0, 0]
	prologue.advance_requested.connect(func() -> void: prologue_signal_counts[0] += 1)
	prologue.skip_requested.connect(func() -> void: prologue_signal_counts[1] += 1)
	if not await _mount(prologue, "prologue contract"):
		await _unmount(prologue)
		return

	_check_copy(
		prologue,
		"first prologue step",
		PackedStringArray([
			"야간 인수인계 1 / 5",
			"낡은 서버의 밤",
			"《픽셀 야간근무》에서 당신은 낡은 게임 서버를 밤새 지키는 야간 관리자입니다.",
		])
	)
	var prologue_primary := _find_button(
		prologue, "PrimaryActionButton", "prologue primary"
	)
	var prologue_skip := _find_button(prologue, "SkipButton", "prologue skip")
	_emit_pressed(prologue_primary)
	_emit_pressed(prologue_skip)
	_check(prologue_signal_counts[0] == 1, "prologue primary must emit advance_requested once")
	_check(prologue_signal_counts[1] == 1, "prologue skip must emit skip_requested once")

	_check(prologue.configure(4, true, true), "last replay prologue step must configure")
	await _wait_frames(2)
	_check_copy(
		prologue,
		"last replay prologue step",
		PackedStringArray(["야간 인수인계 5 / 5", "야간 인계"])
	)
	_check(
		prologue_primary.text == "타이틀로 돌아가기",
		"last replay primary must return to title"
	)
	_check(prologue_skip.text == "타이틀로 돌아가기", "replay skip must return to title")
	await _unmount(prologue)


func _test_operations_room() -> void:
	var normal_data: OPERATIONS_DATA_SCRIPT = _operations_normal_data()
	var view := OPERATIONS_ROOM_SCENE.instantiate() as OPERATIONS_ROOM_VIEW_SCRIPT
	_check(view != null, "operations-room scene must instantiate with its product script")
	if view == null:
		return
	view.configure(normal_data)
	var signal_counts: Array[int] = [0, 0, 0]
	view.continue_requested.connect(func() -> void: signal_counts[0] += 1)
	view.manual_requested.connect(func() -> void: signal_counts[1] += 1)
	view.settings_requested.connect(func() -> void: signal_counts[2] += 1)
	if not await _mount(view, "operations-room contract"):
		await _unmount(view)
		return

	_check_copy(
		view,
		"operations room normal",
		PackedStringArray([
			"야간 운영실",
			"야간근무 2회차",
			"[자동] 자동 운영 중",
			"현재 현장",
			"STAGE 14",
			"주요 병목",
			"처리량 부족",
			"장착 패치",
			"2 / 3",
			"다음 목표",
			"감시견 · ST 20",
			"[저장] 방금 저장됨",
			"현장 복귀",
			"운영 매뉴얼",
			"설정",
		])
	)
	_check_button_sizes(view, "operations room")
	_emit_pressed(_find_button(view, "PrimaryActionButton", "operations primary"))
	_emit_pressed(_find_button(view, "ManualButton", "operations manual"))
	_emit_pressed(_find_button(view, "SettingsButton", "operations header settings"))
	_emit_pressed(_find_button(view, "FooterSettingsButton", "operations footer settings"))
	_check(signal_counts[0] == 1, "operations primary must emit continue_requested once")
	_check(signal_counts[1] == 1, "operations manual must emit manual_requested once")
	_check(signal_counts[2] == 2, "both operations settings entries must emit settings_requested")
	_check(view.is_inside_tree(), "operations-room view must not navigate itself")

	var error_data: OPERATIONS_DATA_SCRIPT = OPERATIONS_DATA_SCRIPT.new(
		3,
		true,
		"자동 운영 중",
		15,
		"프레임 처리 지연",
		3,
		3,
		"감시견 · ST 20",
		"저장되지 않음 · 다시 시도 필요",
		OPERATIONS_DATA_SCRIPT.SaveState.ERROR
	)
	view.configure(error_data)
	await _wait_frames(2)
	_check_copy(
		view,
		"operations room save error",
		PackedStringArray([
			"야간근무 3회차",
			"[자동] 자동 운영 중",
			"STAGE 15",
			"프레임 처리 지연",
			"3 / 3",
			"[오류] 저장되지 않음 · 다시 시도 필요",
		])
	)
	_check_not_copy(view, "operations room save error", PackedStringArray(["[저장] 방금 저장됨"]))
	error_data.equipped_patch_count = error_data.patch_slot_count + 1
	var invalid_update_accepted: bool = view.configure(error_data)
	await _wait_frames(2)
	_check(not invalid_update_accepted, "operations room must reject an invalid reconfiguration")
	_check(
		not view.configuration_error().is_empty(),
		"operations room must retain an inspectable configuration error"
	)
	_check_copy(
		view,
		"operations room rejected update",
		PackedStringArray([
			"[오류] 운영실 데이터를 표시할 수 없습니다",
			"화면 구성 오류",
			"[오류] 화면 데이터가 올바르지 않음",
		])
	)
	_check_not_copy(
		view,
		"operations room rejected update",
		PackedStringArray(["저장되지 않음 · 다시 시도 필요"])
	)
	var rejected_primary := _find_button(
		view, "PrimaryActionButton", "operations rejected-update primary"
	)
	_check(
		rejected_primary != null and rejected_primary.disabled,
		"operations room must disable its primary action after a rejected update"
	)
	await _unmount(view)


func _test_view_data_validation() -> void:
	var operations_data: OPERATIONS_DATA_SCRIPT = _operations_normal_data()
	operations_data.equipped_patch_count = operations_data.patch_slot_count + 1
	_check(
		not operations_data.validation_errors().is_empty(),
		"operations data must reject an equipped count larger than its slot count"
	)

	var offline_data: OFFLINE_DATA_SCRIPT = OFFLINE_DATA_SCRIPT.new(
		120,
		10.0,
		2,
		3,
		true,
		3,
		"처리량 부족",
		false
	)
	offline_data.has_bottleneck = false
	_check(
		not offline_data.validation_errors().is_empty(),
		"non-bottleneck data must reject stale bottleneck details"
	)
	offline_data.has_bottleneck = true
	offline_data.recovered_bits = NAN
	_check(
		not offline_data.validation_errors().is_empty(),
		"offline data must reject a NaN recovered-bit value"
	)
	offline_data.recovered_bits = INF
	_check(
		not offline_data.validation_errors().is_empty(),
		"offline data must reject an infinite recovered-bit value"
	)

	var fitted_rect: Rect2 = ARTWORK_SLOT_SCRIPT.integer_fit_rect(
		Vector2(10.0, 6.0), Vector2(100.0, 100.0)
	)
	_check(
		fitted_rect == Rect2(0.0, 20.0, 100.0, 60.0),
		"artwork injection must preserve aspect ratio at the largest integer scale"
	)

	var operations_view := (
		OPERATIONS_ROOM_SCENE.instantiate() as OPERATIONS_ROOM_VIEW_SCRIPT
	)
	if operations_view != null:
		var operations_mounted := await _mount(
			operations_view, "unconfigured operations room"
		)
		if operations_mounted:
			var operations_primary := _find_button(
				operations_view, "PrimaryActionButton", "unconfigured operations primary"
			)
			_check(
				operations_primary != null and operations_primary.disabled,
				"unconfigured operations room must disable its primary action"
			)
	await _unmount(operations_view)

	var offline_view := OFFLINE_REPORT_SCENE.instantiate() as OFFLINE_REPORT_VIEW_SCRIPT
	if offline_view != null:
		var offline_mounted := await _mount(offline_view, "unconfigured offline report")
		if offline_mounted:
			var offline_primary := _find_button(
				offline_view, "PrimaryActionButton", "unconfigured offline primary"
			)
			var operations_entry := _find_button(
				offline_view, "OperationsRoomButton", "unconfigured offline operations entry"
			)
			_check(
				offline_primary != null and offline_primary.disabled,
				"unconfigured offline report must disable its primary action"
			)
			_check(
				operations_entry != null and operations_entry.disabled,
				"unconfigured offline report must disable its operations-room action"
			)
			_check_not_copy(
				offline_view,
				"unconfigured offline report",
				PackedStringArray(["[반영 완료]", "[집계 상한]"])
			)
	await _unmount(offline_view)


func _test_offline_report() -> void:
	await _test_offline_bottleneck()
	await _test_offline_clear()
	await _test_offline_capped()


func _test_offline_bottleneck() -> void:
	var data: OFFLINE_DATA_SCRIPT = OFFLINE_DATA_SCRIPT.new(
		8040,
		12_400.0,
		14,
		17,
		true,
		17,
		"예상 처치가 4.8초 느림",
		false
	)
	var before_signature := _offline_signature(data)
	var view := OFFLINE_REPORT_SCENE.instantiate() as OFFLINE_REPORT_VIEW_SCRIPT
	_check(view != null, "bottleneck report must instantiate with its product script")
	if view == null:
		return
	view.configure(data)
	var signal_counts: Array[int] = [0, 0, 0]
	view.bottleneck_requested.connect(func() -> void: signal_counts[0] += 1)
	view.continue_requested.connect(func() -> void: signal_counts[1] += 1)
	view.operations_room_requested.connect(func() -> void: signal_counts[2] += 1)
	if not await _mount(view, "offline bottleneck"):
		await _unmount(view)
		return
	_check_copy(
		view,
		"offline bottleneck",
		PackedStringArray([
			"야간 인수인계",
			"2시간 14분 동안의 자동 운영 결과입니다.",
			"+12.4K",
			"ST 14 → 17",
			"STAGE 17",
			"예상 처치가 4.8초 느림",
			"[반영 완료] 결과는 근무 기록에 이미 반영되었습니다.",
			"정체 지점 확인",
			"운영실 보기",
		])
	)
	_check_not_copy(
		view,
		"offline bottleneck",
		PackedStringArray(["8시간 이후의 결과는 집계되지 않았습니다."])
	)
	_check_modal_width(view, "offline bottleneck")
	_check_button_sizes(view, "offline bottleneck")
	var primary := _find_button(view, "PrimaryActionButton", "offline bottleneck primary")
	_emit_pressed(primary)
	_emit_pressed(_find_button(view, "OperationsRoomButton", "offline operations entry"))
	_check(signal_counts[0] == 1, "bottleneck primary must emit bottleneck_requested once")
	_check(signal_counts[1] == 0, "bottleneck primary must not emit continue_requested")
	_check(signal_counts[2] == 1, "operations entry must emit operations_room_requested once")
	_check(_offline_signature(data) == before_signature, "offline report interaction must not mutate view data")
	_check(view.is_inside_tree(), "offline report must not navigate itself")
	data.has_bottleneck = false
	_emit_pressed(primary)
	_check(
		signal_counts[0] == 2 and signal_counts[1] == 0,
		"rendered bottleneck action must keep its semantic signal if the source DTO later mutates"
	)
	data.has_bottleneck = true
	await _unmount(view)


func _test_offline_clear() -> void:
	var data: OFFLINE_DATA_SCRIPT = OFFLINE_DATA_SCRIPT.new(
		930,
		2850.0,
		8,
		10,
		false,
		0,
		"",
		false
	)
	var before_signature := _offline_signature(data)
	var view := OFFLINE_REPORT_SCENE.instantiate() as OFFLINE_REPORT_VIEW_SCRIPT
	_check(view != null, "clear offline report must instantiate with its product script")
	if view == null:
		return
	view.configure(data)
	var signal_counts: Array[int] = [0, 0]
	view.bottleneck_requested.connect(func() -> void: signal_counts[0] += 1)
	view.continue_requested.connect(func() -> void: signal_counts[1] += 1)
	if not await _mount(view, "offline clear"):
		await _unmount(view)
		return
	_check_copy(
		view,
		"offline clear",
		PackedStringArray([
			"야간 인수인계",
			"15분 30초 동안의 자동 운영 결과입니다.",
			"+2.9K",
			"ST 08 → 10",
			"정체 지점",
			"없음",
			"자동 운영 정상",
			"[반영 완료] 결과는 근무 기록에 이미 반영되었습니다.",
			"현장 복귀",
		])
	)
	_check_not_copy(
		view,
		"offline clear",
		PackedStringArray(["8시간 이후의 결과는 집계되지 않았습니다."])
	)
	_check_modal_width(view, "offline clear")
	_check_button_sizes(view, "offline clear")
	_emit_pressed(_find_button(view, "PrimaryActionButton", "offline clear primary"))
	_check(signal_counts[0] == 0, "clear report primary must not emit bottleneck_requested")
	_check(signal_counts[1] == 1, "clear report primary must emit continue_requested once")
	_check(_offline_signature(data) == before_signature, "clear report interaction must remain read-only")
	data.stage_to = 0
	var invalid_update_accepted: bool = view.configure(data)
	await _wait_frames(2)
	_check(not invalid_update_accepted, "offline report must reject an invalid reconfiguration")
	_check(
		not view.configuration_error().is_empty(),
		"offline report must retain an inspectable configuration error"
	)
	_check_copy(
		view,
		"offline rejected update",
		PackedStringArray([
			"[오류] 인수인계 데이터를 표시할 수 없습니다.",
			"화면 구성 오류",
			"데이터 확인 필요",
		])
	)
	_check_not_copy(
		view,
		"offline rejected update",
		PackedStringArray(["[반영 완료]", "자동 운영 정상"])
	)
	var rejected_primary := _find_button(
		view, "PrimaryActionButton", "offline rejected-update primary"
	)
	var rejected_operations := _find_button(
		view, "OperationsRoomButton", "offline rejected-update operations entry"
	)
	_check(
		rejected_primary != null and rejected_primary.disabled,
		"offline report must disable its primary action after a rejected update"
	)
	_check(
		rejected_operations != null and rejected_operations.disabled,
		"offline report must disable its operations entry after a rejected update"
	)
	await _unmount(view)


func _test_offline_capped() -> void:
	var data: OFFLINE_DATA_SCRIPT = OFFLINE_DATA_SCRIPT.new(
		28_800,
		88_600.0,
		16,
		20,
		true,
		20,
		"감시견 복구 주기가 처리량을 앞섬",
		true
	)
	var view := OFFLINE_REPORT_SCENE.instantiate() as OFFLINE_REPORT_VIEW_SCRIPT
	_check(view != null, "capped offline report must instantiate with its product script")
	if view == null:
		return
	view.configure(data)
	if not await _mount(view, "offline capped"):
		await _unmount(view)
		return
	_check_copy(
		view,
		"offline capped",
		PackedStringArray([
			"8시간 0분 동안의 자동 운영 결과입니다.",
			"+88.6K",
			"ST 16 → 20",
			"STAGE 20",
			"감시견 복구 주기가 처리량을 앞섬",
			"[집계 상한] 8시간 이후의 결과는 집계되지 않았습니다.",
		])
	)
	_check_modal_width(view, "offline capped")
	_check_button_sizes(view, "offline capped")
	await _unmount(view)


func _test_preview_navigation() -> void:
	var preview := PREVIEW_SCENE.instantiate() as PREVIEW_CONTROLLER_SCRIPT
	_check(preview != null, "preview scene must instantiate with its controller")
	if preview == null:
		return
	if not await _mount(preview, "preview navigation"):
		await _unmount(preview)
		return

	var expected_ids: Array[StringName] = [
		&"boot",
		&"first_shift",
		&"operations_normal",
		&"operations_save_error",
		&"offline_bottleneck",
		&"offline_clear",
		&"offline_capped",
	]
	var expected_copy: Array[String] = [
		"PIXEL NIGHT SHIFT // BOOT",
		"픽셀 야간근무",
		"[저장] 방금 저장됨",
		"[오류] 저장되지 않음",
		"정체 지점 확인",
		"자동 운영 정상",
		"[집계 상한]",
	]
	_check(preview.preview_state_count() == expected_ids.size(), "preview must expose all seven states")
	_check(preview.current_state_id() == &"boot", "preview must begin at boot")
	_check(preview.is_dev_chrome_visible(), "preview developer chrome must be visible initially")
	_check_copy(
		preview,
		"preview developer chrome",
		PackedStringArray(["DEV PREVIEW · 제품 UI가 아님"])
	)
	_check_button_sizes(preview, "preview initial state")

	var next_button := _find_button(preview, "PreviewNextButton", "preview next")
	var previous_button := _find_button(preview, "PreviewPreviousButton", "preview previous")
	var hide_button := _find_button(preview, "PreviewHideButton", "preview hide")
	_emit_pressed(next_button)
	await _wait_frames(2)
	_check(preview.current_state_id() == &"first_shift", "preview next button must advance state")
	_emit_pressed(previous_button)
	await _wait_frames(2)
	_check(preview.current_state_id() == &"boot", "preview previous button must return state")

	var product_host := preview.find_child("ProductHost", true, false) as Control
	_check(product_host != null, "preview must expose a distinct product host")
	for state_index: int in range(expected_ids.size()):
		preview.show_preview_state(state_index)
		await _wait_frames(2)
		_check(
			preview.current_state_id() == expected_ids[state_index],
			"preview state %d must resolve to %s" % [state_index, expected_ids[state_index]]
		)
		if product_host != null:
			_check_copy(
				product_host,
				"preview state %s" % expected_ids[state_index],
				PackedStringArray([expected_copy[state_index]])
			)
		_check_button_sizes(preview, "preview state %s" % expected_ids[state_index])

	preview.show_preview_state(1)
	await _wait_frames(2)
	if product_host != null:
		var first_shift_primary := _find_button(
			product_host, "PrimaryActionButton", "preview first-shift primary"
		)
		_emit_pressed(first_shift_primary)
		await _wait_frames(2)
		_check(
			preview.current_state_id() == &"operations_normal",
			"preview controller must own the transition requested by first-shift view"
		)

	_emit_pressed(hide_button)
	_check(not preview.is_dev_chrome_visible(), "preview hide control must hide only developer chrome")
	_check(preview.current_state_id() == &"operations_normal", "hiding developer chrome must preserve product state")
	await _unmount(preview)


func _operations_normal_data() -> OPERATIONS_DATA_SCRIPT:
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


func _offline_signature(data: OFFLINE_DATA_SCRIPT) -> String:
	return "%d|%.3f|%d|%d|%s|%d|%s|%s" % [
		data.absence_seconds,
		data.recovered_bits,
		data.stage_from,
		data.stage_to,
		str(data.has_bottleneck),
		data.bottleneck_stage,
		data.bottleneck_cause,
		str(data.reached_cap),
	]


func _mount(instance: Node, context: String) -> bool:
	_check(instance != null, "%s must instantiate" % context)
	if instance == null:
		return false
	root.add_child(instance)
	await _wait_frames(2)
	var survived := is_instance_valid(instance) and instance.is_inside_tree()
	_check(survived, "%s must survive two headless frames" % context)
	if survived:
		_check(instance.get_script() != null, "%s root script must load" % context)
		_check(instance is Control, "%s root must be a Control" % context)
		if instance is Control:
			var control := instance as Control
			_check(
				control.size.is_equal_approx(LOGICAL_SIZE),
				"%s must lay out at 360x640, got %s" % [context, control.size]
			)
	return survived


func _unmount(instance: Node) -> void:
	if is_instance_valid(instance):
		instance.queue_free()
	await process_frame


func _wait_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame


func _check_copy(node: Node, context: String, expected: PackedStringArray) -> void:
	var text := _visible_text(node)
	for phrase: String in expected:
		_check(text.contains(phrase), "%s must show '%s'" % [context, phrase])


func _check_not_copy(node: Node, context: String, unexpected: PackedStringArray) -> void:
	var text := _visible_text(node)
	for phrase: String in unexpected:
		_check(not text.contains(phrase), "%s must hide '%s'" % [context, phrase])


func _visible_text(node: Node) -> String:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return ""
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text
	for child: Node in node.get_children():
		var child_text := _visible_text(child)
		if child_text.is_empty():
			continue
		if not text.is_empty():
			text += "\n"
		text += child_text
	return text


func _collect_buttons(node: Node, buttons: Array[BaseButton]) -> void:
	if node is BaseButton:
		buttons.append(node as BaseButton)
	for child: Node in node.get_children():
		_collect_buttons(child, buttons)


func _check_button_sizes(node: Node, context: String) -> void:
	var buttons: Array[BaseButton] = []
	_collect_buttons(node, buttons)
	for button: BaseButton in buttons:
		if not button.is_visible_in_tree():
			continue
		_check(
			button.size.x + SIZE_EPSILON >= TOUCH_MIN,
			"%s button '%s' width must be at least 48, got %.1f"
			% [context, button.name, button.size.x]
		)
		_check(
			button.size.y + SIZE_EPSILON >= TOUCH_MIN,
			"%s button '%s' height must be at least 48, got %.1f"
			% [context, button.name, button.size.y]
		)
		if button.name == &"PrimaryActionButton":
			_check(
				button.size.y + SIZE_EPSILON >= PRIMARY_HEIGHT,
				"%s primary button height must be at least 52, got %.1f"
				% [context, button.size.y]
			)


func _find_button(node: Node, node_name: String, context: String) -> Button:
	var found := node.find_child(node_name, true, false)
	_check(found is Button, "%s button must exist" % context)
	return found as Button


func _emit_pressed(button: Button) -> void:
	if button != null:
		button.pressed.emit()


func _check_modal_width(view: Node, context: String) -> void:
	var panel := view.find_child("ModalPanel", true, false) as Control
	_check(panel != null, "%s modal panel must exist" % context)
	if panel == null:
		return
	_check(panel.size.x > 0.0, "%s modal panel must be laid out" % context)
	_check(
		panel.size.x <= 328.0 + SIZE_EPSILON,
		"%s modal width must not exceed 328, got %.1f" % [context, panel.size.x]
	)
