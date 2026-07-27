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
		_save_now("자동 저장됨")


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
	if not _session.continue_to_day():
		_report_session_error("Return to day prep was rejected")
		_refresh(true)
		return
	_paused = false
	_speed = 1.0
	_save_now("주간 정비 저장됨")
	_refresh(true)


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
			return
		var backup_result: SaveLoadResult = _repository.load_backup()
		if (
			backup_result.has_session_candidate()
			and _restore_candidate(backup_result.session_data)
		):
			_save_status = "백업 복원됨"
			var promote_error := _repository.promote_backup()
			if promote_error != OK:
				push_warning(
					"Product loop backup promotion failed: %d" % promote_error
				)
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
			_save_status = "백업 복원됨"
			var promote_error := _repository.promote_backup()
			if promote_error != OK:
				push_warning(
					"Product loop backup promotion failed: %d" % promote_error
				)
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
	var error := _repository.save(
		{
			"session": _session.export_state(),
			"speed": _speed,
		},
		int(Time.get_unix_time_from_system())
	)
	if error != OK:
		_save_status = "저장 실패 %d" % error
		_save_remaining = SAVE_INTERVAL_SECONDS
		push_error("Product loop isolated save failed: %d" % error)
		return false
	_save_status = success_status
	_save_remaining = SAVE_INTERVAL_SECONDS
	return true


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
