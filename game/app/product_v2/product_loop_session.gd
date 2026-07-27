class_name ProductLoopSession
extends RefCounted

const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const ProductV2Loader := preload(
	"res://game/content/product_v2/product_v2_loader.gd"
)
const DefenseLabSession := preload(
	"res://game/app/product_v2/defense_lab_session.gd"
)
const ProductLoopState := preload(
	"res://game/domain/product_v2/product_loop_state.gd"
)
const ProductLoopRules := preload(
	"res://game/domain/product_v2/product_loop_rules.gd"
)
const ProductLoopStateDto := preload(
	"res://game/app/product_v2/product_loop_state_dto.gd"
)

const DEFAULT_PRESET := &"first_two"
const EXPORT_KEYS: PackedStringArray = ["product_loop", "defense_lab"]

var _catalog: ProductV2Catalog
var _state := ProductLoopState.new()
var _defense_lab: DefenseLabSession
var _preset_id: StringName = DEFAULT_PRESET
var _last_error := ""


func _init(
	catalog_override: ProductV2Catalog = null,
	preset_id: StringName = DEFAULT_PRESET
) -> void:
	if catalog_override != null:
		_catalog = catalog_override
	else:
		var load_result := ProductV2Loader.load_default()
		assert(
			load_result.is_valid(),
			"Product V2 content failed validation: %s" % "; ".join(load_result.errors)
		)
		_catalog = load_result.catalog
	assert(_catalog != null, "Product loop requires Product V2 content")
	_preset_id = preset_id
	_defense_lab = DefenseLabSession.new(_catalog, _preset_id, 1)


func start_shift(shift_index: int) -> bool:
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		return _reject("주간 정비에서만 야간근무를 시작할 수 있습니다.")
	if not ProductLoopRules.is_shift_unlocked(_state, shift_index):
		return _reject("아직 해금되지 않은 야간근무입니다.")
	if not _catalog.has_shift(shift_index):
		return _reject("알 수 없는 Product V2 야간근무입니다: %d" % shift_index)
	if not _defense_lab.restart(_preset_id, shift_index):
		return _reject(String(_defense_lab.snapshot().get("last_error", "")))
	var candidate := _state.deep_clone()
	candidate.phase = ProductLoopState.Phase.NIGHT_ACTIVE
	candidate.active_shift_index = shift_index
	_state = candidate
	_last_error = ""
	return true


func tick(delta_seconds: float) -> bool:
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		return _reject("경과 시간은 0 이상의 유한한 값이어야 합니다.")
	_last_error = ""
	if _state.phase != ProductLoopState.Phase.NIGHT_ACTIVE:
		return true
	if not _defense_lab.tick(delta_seconds):
		return _reject(String(_defense_lab.snapshot().get("last_error", "")))
	var night_snapshot := _defense_lab.snapshot()
	if not bool(night_snapshot["terminal"]):
		return true

	var candidate := _state.deep_clone()
	ProductLoopRules.settle_terminal(
		candidate,
		night_snapshot,
		_catalog.balance.first_star_reward_bits
	)
	_state = candidate
	return true


func continue_to_day() -> bool:
	if _state.phase != ProductLoopState.Phase.SHIFT_RESULT:
		return _reject("근무 결과를 확인한 뒤에만 주간 정비로 돌아갈 수 있습니다.")
	var candidate := _state.deep_clone()
	candidate.phase = ProductLoopState.Phase.DAY_PREP
	candidate.active_shift_index = 0
	_state = candidate
	_last_error = ""
	return true


func mark_report_read(report_key: String) -> bool:
	if report_key.is_empty() or report_key != _state.report_key:
		return _reject("현재 현장 보고서와 일치하지 않는 키입니다.")
	if _state.report_read:
		_last_error = ""
		return true
	var candidate := _state.deep_clone()
	candidate.report_read = true
	_state = candidate
	_last_error = ""
	return true


func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for record: ProductLoopState.ShiftRecord in _state.shift_records:
		records.append({
			"shift_index": record.shift_index,
			"attempts": record.attempts,
			"highest_completed_waves": record.highest_completed_waves,
			"best_stars": record.best_stars,
			"claimed_reward_stars": record.claimed_reward_stars,
			"unlocked": ProductLoopRules.is_shift_unlocked(
				_state, record.shift_index
			),
			"retry_speed_2x_unlocked": record.best_stars == 3,
		})
	var report_rows: Array[Dictionary] = []
	for row: Dictionary in _state.report_rows:
		report_rows.append(row.duplicate(true))
	var has_report := not _state.report_key.is_empty()
	return {
		"prototype": "product_v2_product_loop",
		"phase": _state.phase,
		"phase_name": _phase_name(_state.phase),
		"version": _state.version,
		"bits": _state.bits,
		"active_shift_index": _state.active_shift_index,
		"shift_records": records,
		"unlocks": {
			"shift_2_unlocked": _state.shift_2_unlocked,
			"version_update_available": _state.version_update_available,
			"shift_1_retry_speed_2x": (
				_state.get_shift_record(1).best_stars == 3
			),
			"shift_2_retry_speed_2x": (
				_state.get_shift_record(2).best_stars == 3
			),
		},
		"night": (
			_defense_lab.snapshot()
			if _state.phase == ProductLoopState.Phase.NIGHT_ACTIVE
			else {}
		),
		"result": _state.last_result.duplicate(true),
		"report": {
			"available": has_report,
			"key": _state.report_key,
			"title": "현장 보고서" if has_report else "",
			"rows": report_rows,
			"read": _state.report_read,
			"unread": has_report and not _state.report_read,
		},
		"last_error": _last_error,
	}


func export_state() -> Dictionary:
	return {
		"product_loop": ProductLoopStateDto.export_state(_state),
		"defense_lab": _defense_lab.export_state(),
	}


func restore_state(data: Dictionary) -> PackedStringArray:
	var errors := _validate_export_wrapper(data)
	if not errors.is_empty():
		return errors
	var loop_result := ProductLoopStateDto.restore_candidate(
		data["product_loop"] as Dictionary,
		_catalog.balance.first_star_reward_bits
	)
	for error_message: String in loop_result.errors:
		errors.append("product_loop: %s" % error_message)
	if not errors.is_empty():
		return errors
	assert(loop_result.state != null, "Validated Product V2 loop requires a state")

	var defense_data := data["defense_lab"] as Dictionary
	if (
		not defense_data.has("preset")
		or typeof(defense_data["preset"]) != TYPE_STRING
		or String(defense_data["preset"]).is_empty()
	):
		errors.append("defense_lab.preset: non-empty string is required")
		return errors
	var candidate_preset := StringName(String(defense_data["preset"]))
	if not DefenseLabSession.PRESET_IDS.has(candidate_preset):
		errors.append(
			"defense_lab.preset: unknown Product V2 preset '%s'" % candidate_preset
		)
		return errors
	var candidate_lab := DefenseLabSession.new(_catalog, candidate_preset, 1)
	var lab_errors := candidate_lab.restore_state(defense_data)
	for error_message: String in lab_errors:
		errors.append("defense_lab: %s" % error_message)
	if not errors.is_empty():
		return errors

	_validate_cross_boundary(loop_result.state, candidate_lab.snapshot(), errors)
	if not errors.is_empty():
		return errors
	_state = loop_result.state
	_defense_lab = candidate_lab
	_preset_id = candidate_preset
	_last_error = ""
	return PackedStringArray()


func _validate_export_wrapper(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in EXPORT_KEYS:
		if not data.has(key):
			errors.append("%s: required Product V2 session field is missing" % key)
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not EXPORT_KEYS.has(String(raw_key)):
			errors.append("%s: unexpected Product V2 session field" % String(raw_key))
	if not errors.is_empty():
		return errors
	for key: String in EXPORT_KEYS:
		if typeof(data[key]) != TYPE_DICTIONARY:
			errors.append("%s: object is required" % key)
	return errors


func _validate_cross_boundary(
	loop_state: ProductLoopState,
	night_snapshot: Dictionary,
	errors: PackedStringArray
) -> void:
	var terminal := bool(night_snapshot.get("terminal", false))
	var night_shift_index := int(night_snapshot.get("shift_index", 0))
	match loop_state.phase:
		ProductLoopState.Phase.NIGHT_ACTIVE:
			if terminal:
				errors.append(
					"product_loop.phase: an active night cannot contain a terminal Lab state"
				)
			if night_shift_index != loop_state.active_shift_index:
				errors.append(
					"defense_lab.shift_index: must match the active Product V2 shift"
				)
		ProductLoopState.Phase.SHIFT_RESULT:
			if not terminal:
				errors.append(
					"product_loop.phase: result requires a terminal Lab state"
				)
			_validate_latest_result(loop_state, night_snapshot, errors)
		ProductLoopState.Phase.DAY_PREP:
			if not loop_state.last_result.is_empty():
				if not terminal:
					errors.append(
						"defense_lab: day prep with a result must retain its terminal state"
					)
				_validate_latest_result(loop_state, night_snapshot, errors)
			elif terminal:
				errors.append(
					"defense_lab: a fresh day cannot contain a terminal Lab state"
				)
			elif (
				night_shift_index != 1
				or int(night_snapshot.get("current_wave", -1)) != 0
				or float(
					(night_snapshot.get("timers", {}) as Dictionary).get(
						"total_elapsed", -1.0
					)
				) != 0.0
			):
				errors.append(
					"defense_lab: a fresh day requires the untouched first shift"
				)


func _validate_latest_result(
	loop_state: ProductLoopState,
	night_snapshot: Dictionary,
	errors: PackedStringArray
) -> void:
	var result := loop_state.last_result
	if result.is_empty():
		errors.append("product_loop.last_result: terminal Lab state requires a result")
		return
	var direct_pairs := {
		"shift_index": "shift_index",
		"success": "success",
		"terminal_reason": "terminal_reason",
		"completed_waves": "completed_waves",
		"stars": "stars",
		"stability": "stability",
		"max_stability": "max_stability",
	}
	for result_key: String in direct_pairs:
		var night_key := String(direct_pairs[result_key])
		if result.get(result_key) != night_snapshot.get(night_key):
			errors.append(
				"product_loop.last_result.%s: does not match terminal evidence"
				% result_key
			)
	for key: String in ["boss", "combat_metrics", "down_evidence", "qa_outcome"]:
		if result.get(key) != night_snapshot.get(key):
			errors.append(
				"product_loop.last_result.%s: does not match terminal evidence" % key
			)
	var expected_rows := ProductLoopRules.factual_report_rows(night_snapshot)
	if loop_state.report_rows != expected_rows:
		errors.append(
			"product_loop.report_rows: do not match the terminal factual evidence"
		)


func _phase_name(phase: int) -> String:
	match phase:
		ProductLoopState.Phase.DAY_PREP:
			return "day_prep"
		ProductLoopState.Phase.NIGHT_ACTIVE:
			return "night_active"
		ProductLoopState.Phase.SHIFT_RESULT:
			return "shift_result"
	assert(false, "Unknown Product V2 product-loop phase: %d" % phase)
	return "unknown"


func _reject(message: String) -> bool:
	_last_error = message
	return false
