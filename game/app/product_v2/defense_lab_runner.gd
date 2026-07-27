class_name DefenseLabRunner
extends Node

const DefenseLabSessionScript := preload(
	"res://game/app/product_v2/defense_lab_session.gd"
)
const DefenseLabSaveRepositoryScript := preload(
	"res://game/persistence/product_v2/defense_lab_save_repository.gd"
)

const REFRESH_INTERVAL_SECONDS := 0.05
const SAVE_INTERVAL_SECONDS := 2.0
const SPEED_STEPS: Array[float] = [1.0, 2.0, 4.0]

var _session: DefenseLabSession
var _repository: DefenseLabSaveRepository
var _view: DefenseLabView

var _paused := false
var _speed_index := 0
var _preset: StringName = &"first_two"
var _shift_index := 1
var _refresh_remaining := 0.0
var _save_remaining := SAVE_INTERVAL_SECONDS
var _terminal_latched := false
var _terminal_saved := false
var _save_enabled := true
var _save_status := ""
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	get_window().title = "Pixel Night Shift - Defense Lab"
	_view = get_node("DefenseLabView") as DefenseLabView
	assert(_view != null, "Defense Lab scene requires its presentation view")
	_session = DefenseLabSessionScript.new(null, _preset, _shift_index)
	_repository = DefenseLabSaveRepositoryScript.new()
	_connect_view()
	_restore_isolated_state()
	_refresh(true)


func _process(delta_seconds: float) -> void:
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		push_error("Defense Lab frame delta must be a non-negative finite value")
		return
	if not _paused and not _terminal_latched:
		_session.tick(delta_seconds * SPEED_STEPS[_speed_index])

	_refresh_remaining -= delta_seconds
	_save_remaining -= delta_seconds
	if _refresh_remaining <= 0.0:
		_refresh_remaining += REFRESH_INTERVAL_SECONDS
		_refresh(false)

	if _terminal_latched:
		if not _terminal_saved and _save_remaining <= 0.0:
			_terminal_saved = _save_now("결과 저장됨")
	elif _save_remaining <= 0.0:
		_save_remaining += SAVE_INTERVAL_SECONDS
		_save_now("자동 저장됨")


func _exit_tree() -> void:
	if _session == null or not _save_enabled:
		return
	if not _terminal_latched or not _terminal_saved:
		_save_now("종료 저장됨")


func snapshot_for_test() -> Dictionary:
	return _last_snapshot.duplicate(true)


func is_paused_for_test() -> bool:
	return _paused


func speed_for_test() -> float:
	return SPEED_STEPS[_speed_index]


func session_instance_id_for_test() -> int:
	return 0 if _session == null else _session.get_instance_id()


func _connect_view() -> void:
	_view.pause_requested.connect(_toggle_pause)
	_view.speed_requested.connect(_cycle_speed)
	_view.preset_requested.connect(_toggle_preset)
	_view.shift_requested.connect(_toggle_shift)
	_view.restart_requested.connect(_restart_current)


func _restore_isolated_state() -> void:
	var load_result := _repository.load()
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
						"Defense Lab backup was restored but could not be promoted: %d"
						% promote_error
					)
			return

		var backup_result := _repository.load_backup()
		if backup_result.has_session_candidate() and _restore_candidate(
			backup_result.session_data
		):
			_save_status = "백업 복원됨"
			var backup_promote_error := _repository.promote_backup()
			if backup_promote_error != OK:
				push_warning(
					"Defense Lab backup promotion failed: %d" % backup_promote_error
				)
			return
		_preserve_invalid_lab_records()
		return

	if load_result.status == SaveLoadResult.Status.NEWER_SCHEMA:
		_save_enabled = false
		_save_status = "새 버전 저장 보존"
		push_warning("Defense Lab save is newer than this build and was preserved")
		return
	if load_result.status == SaveLoadResult.Status.CORRUPT:
		var backup_result := _repository.load_backup()
		if (
			backup_result.has_session_candidate()
			and _restore_candidate(backup_result.session_data)
		):
			_save_status = "백업 복원됨"
			var promote_error := _repository.promote_backup()
			if promote_error != OK:
				push_warning(
					"Defense Lab backup promotion failed: %d" % promote_error
				)
			return
		_preserve_invalid_lab_records()


func _restore_candidate(candidate: Dictionary) -> bool:
	var errors := _session.restore_state(candidate)
	if not errors.is_empty():
		push_warning(
			"Defense Lab state restore was rejected: %s" % "; ".join(errors)
		)
		return false
	var restored := _session.snapshot()
	_preset = StringName(String(restored.get("preset", "first_two")))
	_shift_index = int(restored.get("shift_index", 1))
	_terminal_latched = bool(restored.get("terminal", false))
	_terminal_saved = _terminal_latched
	return true


func _preserve_invalid_lab_records() -> void:
	_save_enabled = false
	_save_status = "손상 저장 보존"
	push_warning(
		"Defense Lab records were preserved because no candidate could be restored"
	)


func _refresh(force: bool) -> void:
	var snapshot := _session.snapshot()
	var is_terminal := bool(snapshot.get("terminal", false))
	if is_terminal and not _terminal_latched:
		_terminal_latched = true
		_terminal_saved = false
		_save_remaining = 0.0
	if force or snapshot != _last_snapshot:
		_last_snapshot = snapshot.duplicate(true)
		_view.refresh(_last_snapshot)
	_view.configure(
		_paused,
		SPEED_STEPS[_speed_index],
		_preset,
		_shift_index,
		_save_status
	)


func _save_now(success_status: String) -> bool:
	if not _save_enabled:
		return false
	var error := _repository.save(
		_session.export_state(),
		int(Time.get_unix_time_from_system())
	)
	if error != OK:
		_save_status = "저장 실패 %d" % error
		_save_remaining = SAVE_INTERVAL_SECONDS
		push_error("Defense Lab isolated save failed: %d" % error)
		_view.configure(
			_paused,
			SPEED_STEPS[_speed_index],
			_preset,
			_shift_index,
			_save_status
		)
		return false
	_save_status = success_status
	_save_remaining = SAVE_INTERVAL_SECONDS
	return true


func _toggle_pause() -> void:
	if _terminal_latched:
		return
	_paused = not _paused
	_refresh(true)


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_STEPS.size()
	_refresh(true)


func _toggle_preset() -> void:
	var next_preset := &"full_team" if _preset == &"first_two" else &"first_two"
	_restart(next_preset, _shift_index)


func _toggle_shift() -> void:
	var next_shift := 2 if _shift_index == 1 else 1
	_restart(_preset, next_shift)


func _restart_current() -> void:
	_restart(_preset, _shift_index)


func _restart(preset: StringName, shift_index: int) -> void:
	if not _session.restart(preset, shift_index):
		var rejected := _session.snapshot()
		push_error(
			"Defense Lab restart was rejected: %s"
			% String(rejected.get("last_error", "unknown error"))
		)
		_refresh(true)
		return
	_preset = preset
	_shift_index = shift_index
	_paused = false
	_terminal_latched = false
	_terminal_saved = false
	_refresh_remaining = 0.0
	_save_remaining = SAVE_INTERVAL_SECONDS
	_save_now("새 기록 저장됨")
	_refresh(true)
