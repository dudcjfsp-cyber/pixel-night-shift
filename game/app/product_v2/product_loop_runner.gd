class_name ProductLoopRunner
extends Node

const ProductLoopSessionScript := preload(
	"res://game/app/product_v2/product_loop_session.gd"
)
const DefenseLabSaveRepositoryScript := preload(
	"res://game/persistence/product_v2/defense_lab_save_repository.gd"
)
const SaveLoadResultScript := preload(
	"res://game/persistence/save_load_result.gd"
)

const SAVE_BASE_DIR := "user://product_v2_product_loop_lab"
const REFRESH_INTERVAL_SECONDS := 0.05
const SAVE_INTERVAL_SECONDS := 2.0
const SAVE_KEYS: PackedStringArray = ["session", "speed"]

var _session: ProductLoopSession
var _repository: DefenseLabSaveRepository
var _day_view: DayPrepView
var _night_view: DefenseLabView
var _result_view: ShiftResultView

var _paused := false
var _speed := 1.0
var _save_enabled := true
var _save_status := ""
var _refresh_remaining := 0.0
var _save_remaining := SAVE_INTERVAL_SECONDS
var _last_snapshot: Dictionary = {}
var _active_surface: StringName = &""
var _last_saved_at_unix := 0


func _ready() -> void:
	get_window().title = "Pixel Night Shift - Product V2 Loop"
	_day_view = get_node("DayPrepView") as DayPrepView
	_night_view = get_node("DefenseLabView") as DefenseLabView
	_result_view = get_node("ShiftResultView") as ShiftResultView
	assert(_day_view != null, "Product loop scene requires DayPrepView")
	assert(_night_view != null, "Product loop scene requires DefenseLabView")
	assert(_result_view != null, "Product loop scene requires ShiftResultView")
	_session = ProductLoopSessionScript.new()
	_repository = DefenseLabSaveRepositoryScript.new(SAVE_BASE_DIR)
	_connect_views()
	_night_view.set_product_mode(true, false)
	_restore_isolated_state()
	_arm_fresh_day_income()
	_refresh(true)


func _process(delta_seconds: float) -> void:
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		push_error("Product V2 loop frame delta must be a non-negative finite value")
		return
	if _active_surface == &"night_active" and not _paused:
		var tick_delta := _night_tick_delta(delta_seconds)
		if not _session.tick(tick_delta):
			_report_session_error("Night shift tick was rejected")
		elif StringName(String(
			_session.snapshot().get("phase_name", "")
		)) != _active_surface:
			_refresh(true)

	_refresh_remaining -= delta_seconds
	_save_remaining -= delta_seconds
	if _refresh_remaining <= 0.0:
		_refresh_remaining += REFRESH_INTERVAL_SECONDS
		_refresh(false)
	if _save_remaining <= 0.0:
		var day_income_before: Dictionary = {}
		if _active_surface == &"day_prep":
			day_income_before = _account_open_day_income()
		if not _save_now("자동 저장됨") and not day_income_before.is_empty():
			_restore_after_failed_save(day_income_before, "주간 수입 자동 저장")
			_refresh(true)
		elif not day_income_before.is_empty():
			_refresh(true)


func _exit_tree() -> void:
	if _session == null or not _save_enabled:
		return
	_save_now("종료 저장됨")


func snapshot_for_test() -> Dictionary:
	return _last_snapshot.duplicate(true)


func session_instance_id_for_test() -> int:
	return 0 if _session == null else _session.get_instance_id()


func active_surface_for_test() -> StringName:
	return _active_surface


func speed_for_test() -> float:
	return _speed


func _connect_views() -> void:
	_day_view.start_shift_requested.connect(_start_shift)
	_day_view.field_report_read_requested.connect(_mark_report_read)
	_day_view.upgrade_operator_requested.connect(_upgrade_operator)
	_day_view.patch_preview_requested.connect(_preview_patch)
	_day_view.patch_equip_requested.connect(_equip_patch)
	_day_view.version_update_requested.connect(_version_update)
	_day_view.legacy_cache_purchase_requested.connect(_buy_legacy_cache)
	_night_view.pause_requested.connect(_toggle_pause)
	_night_view.speed_requested.connect(_toggle_speed)
	_result_view.continue_to_day_requested.connect(_continue_to_day)


func _refresh(force: bool) -> void:
	var snapshot: Dictionary = _session.snapshot()
	var phase_name := StringName(String(snapshot.get("phase_name", "")))
	var changed := snapshot != _last_snapshot
	var surface_changed := phase_name != _active_surface
	if not force and not changed and not surface_changed:
		if phase_name == &"night_active":
			_configure_night_view(snapshot)
		return

	_last_snapshot = snapshot.duplicate(true)
	_active_surface = phase_name
	_day_view.visible = phase_name == &"day_prep"
	_night_view.visible = phase_name == &"night_active"
	_result_view.visible = phase_name == &"shift_result"
	match phase_name:
		&"day_prep":
			_speed = 1.0
			_day_view.refresh(_last_snapshot)
		&"night_active":
			_night_view.refresh(
				_last_snapshot.get("night", {}) as Dictionary
			)
			_configure_night_view(_last_snapshot)
		&"shift_result":
			_speed = 1.0
			_result_view.refresh(_last_snapshot)
			_mark_visible_result_report_read()
		_:
			push_error("Unknown Product V2 product phase: %s" % phase_name)

	if surface_changed:
		_save_remaining = 0.0


func _configure_night_view(snapshot: Dictionary) -> void:
	var shift_index := int(snapshot.get("active_shift_index", 1))
	var double_speed_unlocked := _is_double_speed_unlocked(
		snapshot, shift_index
	)
	if not double_speed_unlocked:
		_speed = 1.0
	_night_view.set_product_mode(true, double_speed_unlocked)
	_night_view.configure(
		_paused,
		_speed,
		&"first_two",
		shift_index,
		_save_status
	)


func _start_shift(shift_index: int) -> void:
	if not _session.start_shift(shift_index):
		_report_session_error("Night shift start was rejected")
		_refresh(true)
		return
	_paused = false
	_speed = 1.0
	_save_now("야간근무 시작 저장됨")
	_refresh(true)


func _continue_to_day() -> void:
	var now_unix := int(Time.get_unix_time_from_system())
	if not _session.continue_to_day(now_unix):
		_report_session_error("Return to day prep was rejected")
		_refresh(true)
		return
	_paused = false
	_speed = 1.0
	_save_now("주간 정비 저장됨")
	_refresh(true)


func _upgrade_operator(operator_id: StringName) -> void:
	_execute_saved_day_command(
		func() -> bool: return _session.upgrade_operator(operator_id),
		"Operator upgrade was rejected",
		"요원 강화 저장됨"
	)


func _preview_patch(slot_index: int, patch_id: StringName) -> void:
	var preview := _session.get_patch_preview(slot_index, patch_id)
	if preview.is_empty():
		_report_session_error("Patch preview was rejected")
	_day_view.set_patch_preview(preview)


func _equip_patch(slot_index: int, patch_id: StringName) -> void:
	if _execute_saved_day_command(
		func() -> bool: return _session.equip_patch(slot_index, patch_id),
		"Patch replacement was rejected",
		"패치 교체 저장됨"
	):
		_preview_patch(slot_index, patch_id)


func _version_update() -> void:
	var now_unix := int(Time.get_unix_time_from_system())
	_execute_saved_day_command(
		func() -> bool: return _session.version_update(now_unix),
		"Version update was rejected",
		"버전 업데이트 저장됨"
	)


func _buy_legacy_cache() -> void:
	_execute_saved_day_command(
		func() -> bool: return _session.buy_legacy_cache(),
		"Legacy cache purchase was rejected",
		"레거시 캐시 저장됨"
	)


func _mark_report_read(report_key: String) -> void:
	if report_key.is_empty():
		return
	if not _session.mark_report_read(report_key):
		_report_session_error("Field report read command was rejected")
		_refresh(true)
		return
	_save_now("현장 보고서 확인 저장됨")
	_refresh(true)


func _mark_visible_result_report_read() -> void:
	var report := _last_snapshot.get("report", {}) as Dictionary
	var report_key := String(report.get("key", report.get("report_key", "")))
	var already_read := bool(report.get("read", report.get("is_read", true)))
	if report_key.is_empty() or already_read:
		return
	if not _session.mark_report_read(report_key):
		_report_session_error("Visible field report could not be marked read")
		return
	_last_snapshot = _session.snapshot().duplicate(true)
	_result_view.refresh(_last_snapshot)
	_save_remaining = 0.0


func _toggle_pause() -> void:
	if _active_surface != &"night_active":
		return
	_paused = not _paused
	_configure_night_view(_last_snapshot)


func _toggle_speed() -> void:
	if _active_surface != &"night_active":
		return
	var shift_index := int(_last_snapshot.get("active_shift_index", 0))
	if not _is_double_speed_unlocked(_last_snapshot, shift_index):
		return
	_speed = 2.0 if is_equal_approx(_speed, 1.0) else 1.0
	_configure_night_view(_last_snapshot)
	_save_now("배속 저장됨")


func _restore_isolated_state() -> void:
	var load_result: SaveLoadResult = _repository.load()
	if load_result.has_session_candidate():
		if _restore_candidate(load_result.session_data):
			_last_saved_at_unix = load_result.saved_at_unix
			_save_status = (
				"백업 복원됨"
				if load_result.status == SaveLoadResult.Status.RECOVERED_BACKUP
				else "저장 복원됨"
			)
			if load_result.status == SaveLoadResult.Status.RECOVERED_BACKUP:
				var promote_error := _repository.promote_backup()
				if promote_error != OK:
					push_warning(
						"Product loop backup could not be promoted: %d"
						% promote_error
					)
			_apply_restored_day_income(load_result.saved_at_unix)
			return
		var backup_result: SaveLoadResult = _repository.load_backup()
		if (
			backup_result.has_session_candidate()
			and _restore_candidate(backup_result.session_data)
		):
			_last_saved_at_unix = backup_result.saved_at_unix
			_save_status = "백업 복원됨"
			var promote_error := _repository.promote_backup()
			if promote_error != OK:
				push_warning(
					"Product loop backup promotion failed: %d" % promote_error
				)
			_apply_restored_day_income(backup_result.saved_at_unix)
			return
		_preserve_invalid_records()
		return

	if load_result.status == SaveLoadResult.Status.NEWER_SCHEMA:
		_save_enabled = false
		_save_status = "새 버전 저장 보존"
		push_warning("Product loop save is newer than this build and was preserved")
		return
	if load_result.status == SaveLoadResult.Status.CORRUPT:
		var backup_result: SaveLoadResult = _repository.load_backup()
		if (
			backup_result.has_session_candidate()
			and _restore_candidate(backup_result.session_data)
		):
			_last_saved_at_unix = backup_result.saved_at_unix
			_save_status = "백업 복원됨"
			var promote_error := _repository.promote_backup()
			if promote_error != OK:
				push_warning(
					"Product loop backup promotion failed: %d" % promote_error
				)
			_apply_restored_day_income(backup_result.saved_at_unix)
			return
		_preserve_invalid_records()


func _restore_candidate(candidate: Dictionary) -> bool:
	for key: String in SAVE_KEYS:
		if not candidate.has(key):
			return false
	for raw_key: Variant in candidate.keys():
		if typeof(raw_key) != TYPE_STRING or not SAVE_KEYS.has(String(raw_key)):
			return false
	if (
		typeof(candidate["session"]) != TYPE_DICTIONARY
		or not _is_supported_speed(candidate["speed"])
	):
		return false
	var errors: PackedStringArray = _session.restore_state(
		candidate["session"] as Dictionary
	)
	if not errors.is_empty():
		push_warning(
			"Product loop state restore was rejected: %s" % "; ".join(errors)
		)
		return false
	var restored: Dictionary = _session.snapshot()
	_active_surface = StringName(String(restored.get("phase_name", "")))
	_paused = false
	_speed = float(candidate["speed"])
	var restored_shift := int(restored.get("active_shift_index", 0))
	if (
		_active_surface != &"night_active"
		or (
			is_equal_approx(_speed, 2.0)
			and not _is_double_speed_unlocked(restored, restored_shift)
		)
	):
		_speed = 1.0
	return true


func _preserve_invalid_records() -> void:
	_save_enabled = false
	_save_status = "손상 저장 보존"
	push_warning(
		"Product loop records were preserved because no candidate could be restored"
	)


func _save_now(success_status: String) -> bool:
	if not _save_enabled:
		return false
	var saved_at_unix := maxi(
		_last_saved_at_unix,
		int(Time.get_unix_time_from_system())
	)
	var error := _repository.save(
		{
			"session": _session.export_state(),
			"speed": _speed,
		},
		saved_at_unix
	)
	if error != OK:
		_save_status = "저장 실패 %d" % error
		_save_remaining = SAVE_INTERVAL_SECONDS
		push_error("Product loop isolated save failed: %d" % error)
		return false
	_last_saved_at_unix = saved_at_unix
	_save_status = success_status
	_save_remaining = SAVE_INTERVAL_SECONDS
	return true


func _execute_saved_day_command(
	command: Callable,
	error_context: String,
	success_status: String
) -> bool:
	var before := _session.export_state()
	if not bool(command.call()):
		_report_session_error(error_context)
		_refresh(true)
		return false
	if not _save_now(success_status):
		_restore_after_failed_save(before, success_status)
		_refresh(true)
		return false
	_refresh(true)
	return true


func _apply_restored_day_income(saved_at_unix: int) -> void:
	var before_snapshot := _session.snapshot()
	if String(before_snapshot.get("phase_name", "")) != "day_prep":
		return
	var before_state := _session.export_state()
	var now_unix := int(Time.get_unix_time_from_system())
	var offline := before_snapshot.get("offline", {}) as Dictionary
	if int(offline.get("anchor_unix", 0)) == 0 and saved_at_unix > 0:
		_session.account_day_income(saved_at_unix)
	var income: Dictionary = _session.account_day_income(now_unix)
	if income.is_empty():
		_report_session_error("Restored day income was rejected")
		return
	var after_snapshot := _session.snapshot()
	var awarded_bits := maxi(
		0,
		int(income.get(
			"awarded_bits",
			int(after_snapshot.get("bits", 0)) - int(before_snapshot.get("bits", 0))
		))
	)
	var state_changed := _session.export_state() != before_state
	if state_changed and not _save_now("주간 수입 반영 저장됨"):
		_restore_after_failed_save(before_state, "주간 수입 반영")
		return
	if awarded_bits <= 0:
		return
	var elapsed_seconds := int(income.get(
		"elapsed_seconds",
		maxi(0, now_unix - saved_at_unix)
	))
	_day_view.show_offline_handoff({
		"awarded_bits": awarded_bits,
		"elapsed_seconds": elapsed_seconds,
		"reached_cap": bool(income.get(
			"reached_cap",
			elapsed_seconds >= 12 * 60 * 60
		)),
	})


func _arm_fresh_day_income() -> void:
	if not _save_enabled:
		return
	var snapshot := _session.snapshot()
	if String(snapshot.get("phase_name", "")) != "day_prep":
		return
	var offline := snapshot.get("offline", {}) as Dictionary
	if int(offline.get("anchor_unix", 0)) != 0:
		return
	var before := _session.export_state()
	_session.account_day_income(int(Time.get_unix_time_from_system()))
	if _session.export_state() == before:
		return
	if not _save_now("주간 기준 시각 저장됨"):
		_restore_after_failed_save(before, "주간 기준 시각 저장")


func _account_open_day_income() -> Dictionary:
	if _active_surface != &"day_prep":
		return {}
	var before := _session.export_state()
	var income: Dictionary = _session.account_day_income(
		int(Time.get_unix_time_from_system())
	)
	if income.is_empty():
		_report_session_error("Open day income was rejected")
		return {}
	if _session.export_state() == before:
		return {}
	return before


func _restore_after_failed_save(
	before: Dictionary,
	context: String
) -> void:
	var restore_errors := _session.restore_state(before)
	if restore_errors.is_empty():
		return
	_save_enabled = false
	push_error(
		"%s could not roll back after a save failure: %s"
		% [context, "; ".join(restore_errors)]
	)


func _report_session_error(context: String) -> void:
	var snapshot: Dictionary = _session.snapshot()
	var detail := String(snapshot.get("last_error", "unknown error"))
	push_error("%s: %s" % [context, detail])


func _is_double_speed_unlocked(
	snapshot: Dictionary,
	shift_index: int
) -> bool:
	for raw_record: Variant in snapshot.get("shift_records", []) as Array:
		if (
			raw_record is Dictionary
			and int((raw_record as Dictionary).get("shift_index", 0)) == shift_index
		):
			return bool(
				(raw_record as Dictionary).get(
					"retry_speed_2x_unlocked", false
				)
			)
	return false


func _is_supported_speed(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return (
		is_finite(numeric)
		and (
			is_equal_approx(numeric, 1.0)
			or is_equal_approx(numeric, 2.0)
		)
	)


func _night_tick_delta(real_delta: float) -> float:
	if not is_equal_approx(_speed, 2.0):
		return real_delta
	var current := _session.snapshot() as Dictionary
	var night := current.get("night", {}) as Dictionary
	var night_phase := String(night.get("phase_name", ""))
	return (
		real_delta * 2.0
		if night_phase in ["normal_active", "boss_active"]
		else real_delta
	)
