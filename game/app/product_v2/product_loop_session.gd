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
const ProductMetaRules := preload(
	"res://game/domain/product_v2/product_meta_rules.gd"
)
const ProductV2Forecast := preload(
	"res://game/domain/product_v2/product_v2_forecast.gd"
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
var _forecast_cache: Dictionary = {}


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
	ProductMetaRules.initialize_new_game(
		_state, _catalog, preset_id == &"full_team"
	)
	_defense_lab = DefenseLabSession.new(_catalog, DEFAULT_PRESET, 1)
	assert(_restart_lab_with_current_loadout(1), "Initial Product V2 loadout is invalid")
	_refresh_forecast_cache()


func start_shift(shift_index: int) -> bool:
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		return _reject("주간 정비에서만 야간근무를 시작할 수 있습니다.")
	if not ProductLoopRules.is_shift_unlocked(_state, shift_index):
		return _reject("아직 해금되지 않은 야간근무입니다.")
	if not _catalog.has_shift(shift_index):
		return _reject("알 수 없는 Product V2 야간근무입니다: %d" % shift_index)
	if not _restart_lab_with_current_loadout(shift_index):
		return _reject(String(_defense_lab.snapshot().get("last_error", "")))
	var candidate := _state.deep_clone()
	candidate.phase = ProductLoopState.Phase.NIGHT_ACTIVE
	candidate.active_shift_index = shift_index
	candidate.playback_speed = 1
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
		_catalog
	)
	candidate.playback_speed = 1
	_state = candidate
	_refresh_forecast_cache()
	return true


func set_playback_speed(multiplier: int) -> bool:
	if multiplier not in [1, 2]:
		return _reject("재생 배속은 1배 또는 2배만 사용할 수 있습니다.")
	if multiplier == 2 and not _can_use_double_speed(_state):
		return _reject("2배속은 3성 완료한 야간근무의 재도전에서만 사용할 수 있습니다.")
	if _state.playback_speed == multiplier:
		_last_error = ""
		return true
	var candidate := _state.deep_clone()
	candidate.playback_speed = multiplier
	_state = candidate
	_last_error = ""
	return true


func continue_to_day(now_unix: int = 0) -> bool:
	if _state.phase != ProductLoopState.Phase.SHIFT_RESULT:
		return _reject("근무 결과를 확인한 뒤에만 주간 정비로 돌아갈 수 있습니다.")
	if now_unix < 0:
		return _reject("주간 정비 기준 시각은 0 이상이어야 합니다.")
	var candidate := _state.deep_clone()
	candidate.phase = ProductLoopState.Phase.DAY_PREP
	candidate.active_shift_index = 0
	candidate.playback_speed = 1
	ProductMetaRules.arm_day_income(candidate, now_unix)
	_state = candidate
	_refresh_forecast_cache()
	_last_error = ""
	return true


func account_day_income(now_unix: int) -> Dictionary:
	if now_unix < 0:
		_reject("주간 방치 기준 시각은 0 이상이어야 합니다.")
		return _offline_noop("invalid_time")
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		_last_error = ""
		return _offline_noop("not_day_prep")
	var candidate := _state.deep_clone()
	var result := ProductMetaRules.apply_day_income(candidate, _catalog, now_unix)
	_state = candidate
	_last_error = ""
	return result


func upgrade_operator(operator_id: StringName) -> bool:
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		return _reject("요원 강화는 주간 정비에서만 가능합니다.")
	if not _catalog.base_catalog.has_operator(operator_id):
		return _reject("존재하지 않는 요원입니다.")
	if not _state.unlocked_operator_ids.has(operator_id):
		return _reject("아직 해금되지 않은 요원입니다.")
	var definition := _catalog.base_catalog.get_operator(operator_id)
	var level := int(_state.operator_levels.get(operator_id, 0))
	var cost := ProductMetaRules.operator_upgrade_cost(level, definition)
	if cost < 0:
		return _reject("이 요원은 더 강화할 수 없습니다.")
	if _state.bits < cost:
		return _reject("비트가 부족합니다.")
	var candidate := _state.deep_clone()
	candidate.bits -= cost
	candidate.operator_levels[operator_id] = level + 1
	return _commit_day_meta_candidate(candidate)


func equip_patch(slot_index: int, patch_id: StringName) -> bool:
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		return _reject("패치 교체는 주간 정비에서만 가능합니다.")
	if slot_index < 0 or slot_index >= _state.unlocked_patch_slots:
		return _reject("아직 사용할 수 없는 패치 슬롯입니다.")
	if not _catalog.base_catalog.has_patch(patch_id):
		return _reject("존재하지 않는 패치입니다.")
	if not _state.discovered_patch_ids.has(patch_id):
		return _reject("아직 발견하지 않은 패치입니다.")
	if _state.equipped_patch_ids.has(patch_id):
		return _reject("같은 패치는 두 슬롯에 장착할 수 없습니다.")
	var cost := _catalog.balance.patch_equip_cost_bits
	if _state.bits < cost:
		return _reject("패치 교체에 필요한 비트가 부족합니다.")
	var candidate := _state.deep_clone()
	candidate.bits -= cost
	candidate.equipped_patch_ids[slot_index] = patch_id
	return _commit_day_meta_candidate(candidate)


func get_patch_preview(slot_index: int, patch_id: StringName) -> Dictionary:
	var patch_exists := _catalog.base_catalog.has_patch(patch_id)
	var can_equip := (
		_state.phase == ProductLoopState.Phase.DAY_PREP
		and slot_index >= 0
		and slot_index < _state.unlocked_patch_slots
		and patch_exists
		and _state.discovered_patch_ids.has(patch_id)
		and not _state.equipped_patch_ids.has(patch_id)
		and _state.bits >= _catalog.balance.patch_equip_cost_bits
	)
	var proposed: Array[StringName] = []
	proposed.assign(_state.equipped_patch_ids)
	if (
		patch_exists
		and slot_index >= 0
		and slot_index < proposed.size()
		and not _state.equipped_patch_ids.has(patch_id)
	):
		proposed[slot_index] = patch_id
	var target_shift := _forecast_shift_index()
	var before := _forecast_for(target_shift, _state.equipped_patch_ids)
	var after := _forecast_for(target_shift, proposed)
	var patch := _catalog.base_catalog.get_patch(patch_id) if patch_exists else null
	return {
		"can_equip": can_equip,
		"slot_index": slot_index,
		"patch_id": String(patch_id),
		"cost": _catalog.balance.patch_equip_cost_bits,
		"benefit": patch.benefit if patch != null else "",
		"drawback": patch.drawback if patch != null else "",
		"tradeoff": patch.drawback if patch != null else "",
		"before": before,
		"after": after,
		"delta": {
			"kill_time": float(after["kill_time"]) - float(before["kill_time"]),
			"enemies_leaked": int(after["enemies_leaked"]) - int(before["enemies_leaked"]),
			"bit_multiplier": float(after["bit_multiplier"]) - float(before["bit_multiplier"]),
		},
	}


func version_update(now_unix: int) -> bool:
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		return _reject("버전 업데이트는 주간 정비에서만 가능합니다.")
	if not _state.version_update_available:
		return _reject("아직 버전 업데이트 조건을 달성하지 못했습니다.")
	if now_unix < 0:
		return _reject("버전 업데이트 기준 시각은 0 이상이어야 합니다.")
	var candidate := _state.deep_clone()
	ProductMetaRules.reset_for_version_update(candidate, _catalog, now_unix)
	candidate.playback_speed = 1
	if not _restart_lab_with_loadout(candidate, 1):
		return _reject(String(_defense_lab.snapshot().get("last_error", "")))
	_state = candidate
	_refresh_forecast_cache()
	_last_error = ""
	return true


func buy_legacy_cache() -> bool:
	if _state.phase != ProductLoopState.Phase.DAY_PREP:
		return _reject("레거시 빌드 캐시는 주간 정비에서만 구매할 수 있습니다.")
	var balance := _catalog.base_catalog.balance
	if _state.legacy_cache_level >= balance.max_legacy_cache_level:
		return _reject("레거시 빌드 캐시는 이미 최대 단계입니다.")
	if _state.patch_notes < balance.legacy_cache_cost:
		return _reject("패치노트가 부족합니다.")
	var candidate := _state.deep_clone()
	candidate.patch_notes -= balance.legacy_cache_cost
	candidate.legacy_cache_level += 1
	return _commit_day_meta_candidate(candidate)


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
			"boss_encountered": record.boss_encountered,
			"unlocked": ProductLoopRules.is_shift_unlocked(
				_state, record.shift_index
			),
			"retry_speed_2x_unlocked": record.best_stars == 3,
		})
	var report_rows: Array[Dictionary] = []
	for row: Dictionary in _state.report_rows:
		report_rows.append(row.duplicate(true))
	var has_report := not _state.report_key.is_empty()
	var operator_rows := _operator_rows()
	var patch_rows := _patch_rows()
	var patch_slots: Array[String] = []
	var patch_slot_rows: Array[Dictionary] = []
	for slot_index: int in range(_state.equipped_patch_ids.size()):
		var patch_id := String(_state.equipped_patch_ids[slot_index])
		patch_slots.append(patch_id)
		patch_slot_rows.append({
			"index": slot_index,
			"slot_index": slot_index,
			"display_index": slot_index + 1,
			"unlocked": slot_index < _state.unlocked_patch_slots,
			"patch_id": patch_id,
			"equipped_patch_id": patch_id,
			"unlock_text": _patch_slot_unlock_text(slot_index),
		})
	var legacy_balance := _catalog.base_catalog.balance
	return {
		"prototype": "product_v2_product_loop",
		"phase": _state.phase,
		"phase_name": _phase_name(_state.phase),
		"version": _state.version,
		"bits": _state.bits,
		"patch_notes": _state.patch_notes,
		"legacy_cache_level": _state.legacy_cache_level,
		"legacy_cache_cost": legacy_balance.legacy_cache_cost,
		"legacy_cache_bonus": legacy_balance.legacy_cache_bonus,
		"can_buy_legacy_cache": (
			_state.phase == ProductLoopState.Phase.DAY_PREP
			and _state.legacy_cache_level < legacy_balance.max_legacy_cache_level
			and _state.patch_notes >= legacy_balance.legacy_cache_cost
		),
		"active_shift_index": _state.active_shift_index,
		"playback_speed": _state.playback_speed,
		"shift_records": records,
		"operators": operator_rows,
		"patches": patch_rows,
		"patch_slots": patch_slots,
		"patch_slot_rows": patch_slot_rows,
		"unlocked_patch_slots": _state.unlocked_patch_slots,
		"patch_equip_cost": _catalog.balance.patch_equip_cost_bits,
		"forecast": _forecast_cache.duplicate(true),
		"offline": {
			"available_bits": _state.last_day_income_bits,
			"elapsed_seconds": _state.last_day_income_elapsed_seconds,
			"last_award_bits": _state.last_day_income_bits,
			"remainder_seconds": _state.day_income_remainder_seconds,
			"report_available": _state.day_income_report_available,
			"anchor_unix": _state.day_income_anchor_unix,
			"interval_seconds": _catalog.balance.day_income_interval_seconds,
			"cap_seconds": _catalog.balance.day_income_cap_seconds,
			"cap_bits": _catalog.balance.day_income_cap_bits,
		},
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
		_catalog.balance.first_star_reward_bits,
		_catalog
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
	var candidate_lab := DefenseLabSession.new(_catalog, DEFAULT_PRESET, 1)
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
	_refresh_forecast_cache()
	_last_error = ""
	return PackedStringArray()


func restore_migrated_day_state(product_loop_data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var loop_result := ProductLoopStateDto.restore_candidate(
		product_loop_data,
		_catalog.balance.first_star_reward_bits,
		_catalog
	)
	for error_message: String in loop_result.errors:
		errors.append("product_loop: %s" % error_message)
	if not errors.is_empty():
		return errors
	assert(loop_result.state != null, "Validated migration requires a loop state")
	_validate_migration_seed(loop_result.state, errors)
	if not errors.is_empty():
		return errors

	var candidate_lab := DefenseLabSession.new(_catalog, DEFAULT_PRESET, 1)
	if not candidate_lab.restart_with_loadout(
		1,
		loop_result.state.operator_levels,
		loop_result.state.unlocked_operator_ids,
		loop_result.state.equipped_patch_ids,
		loop_result.state.legacy_cache_level
	):
		errors.append(
			"defense_lab: %s"
			% String(candidate_lab.snapshot().get("last_error", "invalid loadout"))
		)
		return errors
	_validate_cross_boundary(loop_result.state, candidate_lab.snapshot(), errors)
	if not errors.is_empty():
		return errors

	_state = loop_result.state
	_defense_lab = candidate_lab
	_preset_id = DefenseLabSession.PRODUCT_LOOP_PRESET
	_refresh_forecast_cache()
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


func _validate_migration_seed(
	loop_state: ProductLoopState,
	errors: PackedStringArray
) -> void:
	if loop_state.migration_source_schema not in [1, 2]:
		errors.append(
			"product_loop.migration_source_schema: legacy schema 1 or 2 is required"
		)
	if (
		loop_state.version
		!= loop_state.migration_source_run_count + 1
	):
		errors.append(
			"product_loop.version: migrated version must equal legacy run_count + 1"
		)
	if (
		loop_state.phase != ProductLoopState.Phase.DAY_PREP
		or loop_state.active_shift_index != 0
		or loop_state.playback_speed != 1
	):
		errors.append(
			"product_loop.phase: migration must enter fresh 1x DAY_PREP"
		)
	if (
		loop_state.result_serial != 0
		or loop_state.shift_2_unlocked
		or loop_state.version_update_available
		or not loop_state.last_result.is_empty()
		or not loop_state.report_key.is_empty()
		or not loop_state.report_rows.is_empty()
		or not loop_state.report_read
	):
		errors.append(
			"product_loop: migration cannot carry Product V2 run or report progress"
		)
	for record: ProductLoopState.ShiftRecord in loop_state.shift_records:
		if (
			record.attempts != 0
			or record.highest_completed_waves != 0
			or record.best_stars != 0
			or record.claimed_reward_stars != 0
			or record.boss_encountered
		):
			errors.append(
				"product_loop.shift_records: migration must start fresh shifts"
			)
			break
	for patch_id: StringName in loop_state.equipped_patch_ids:
		if patch_id != &"":
			errors.append(
				"product_loop.equipped_patch_ids: migration must clear equipped patches"
			)
			break
	if (
		loop_state.day_income_anchor_unix
		!= loop_state.migration_saved_at_unix
		or loop_state.day_income_remainder_seconds != 0
		or loop_state.last_day_income_elapsed_seconds != 0
		or loop_state.last_day_income_bits != 0
		or loop_state.day_income_report_available
	):
		errors.append(
			"product_loop.day_income_anchor_unix: migration must start at saved_at"
		)


func _validate_cross_boundary(
	loop_state: ProductLoopState,
	night_snapshot: Dictionary,
	errors: PackedStringArray
) -> void:
	var terminal := bool(night_snapshot.get("terminal", false))
	var night_shift_index := int(night_snapshot.get("shift_index", 0))
	match loop_state.phase:
		ProductLoopState.Phase.NIGHT_ACTIVE:
			_validate_active_loadout(loop_state, night_snapshot, errors, false)
			if terminal:
				errors.append(
					"product_loop.phase: an active night cannot contain a terminal Lab state"
				)
			if night_shift_index != loop_state.active_shift_index:
				errors.append(
					"defense_lab.shift_index: must match the active Product V2 shift"
				)
		ProductLoopState.Phase.SHIFT_RESULT:
			_validate_active_loadout(loop_state, night_snapshot, errors, true)
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
			else:
				_validate_active_loadout(loop_state, night_snapshot, errors, false)


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
		if not _json_evidence_equal(result.get(key), night_snapshot.get(key)):
			errors.append(
				"product_loop.last_result.%s: does not match terminal evidence" % key
			)
	var expected_rows := ProductLoopRules.factual_report_rows(night_snapshot)
	if not _json_evidence_equal(loop_state.report_rows, expected_rows):
		errors.append(
			"product_loop.report_rows: do not match the terminal factual evidence"
		)


func _json_evidence_equal(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	if (
		left_type in [TYPE_INT, TYPE_FLOAT]
		and right_type in [TYPE_INT, TYPE_FLOAT]
	):
		var left_number := float(left)
		var right_number := float(right)
		return (
			is_finite(left_number)
			and is_finite(right_number)
			and left_number == right_number
		)
	if (
		left_type in [TYPE_STRING, TYPE_STRING_NAME]
		and right_type in [TYPE_STRING, TYPE_STRING_NAME]
	):
		return String(left) == String(right)
	if left is Array and right is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index: int in left_array.size():
			if not _json_evidence_equal(left_array[index], right_array[index]):
				return false
		return true
	if left is Dictionary and right is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for raw_key: Variant in left_dictionary.keys():
			if (
				not right_dictionary.has(raw_key)
				or not _json_evidence_equal(
					left_dictionary[raw_key], right_dictionary[raw_key]
				)
			):
				return false
		return true
	return left_type == right_type and left == right


func _validate_active_loadout(
	loop_state: ProductLoopState,
	night_snapshot: Dictionary,
	errors: PackedStringArray,
	allow_result_unlocks: bool
) -> void:
	var night_unlocked: Array[String] = []
	for raw_operator: Variant in night_snapshot.get("operators", []) as Array:
		var operator := raw_operator as Dictionary
		var operator_id := StringName(String(operator.get("id", "")))
		var unlocked := bool(operator.get("unlocked", false))
		if unlocked:
			night_unlocked.append(String(operator_id))
		if (unlocked or not allow_result_unlocks) and int(
			operator.get("level", -1)
		) != int(
			loop_state.operator_levels.get(operator_id, 0)
		):
			errors.append(
				"defense_lab.operators: levels must match the Product V2 loadout"
			)
			break
	var expected_unlocked: Array[String] = []
	for operator_id: StringName in loop_state.unlocked_operator_ids:
		expected_unlocked.append(String(operator_id))
	var unlocked_match := night_unlocked == expected_unlocked
	if allow_result_unlocks:
		unlocked_match = true
		for operator_id: String in night_unlocked:
			if not expected_unlocked.has(operator_id):
				unlocked_match = false
				break
	if not unlocked_match:
		errors.append(
			"defense_lab.operators: unlocked operators must match the Product V2 loadout"
		)
	var expected_patches: Array[String] = []
	for patch_id: StringName in loop_state.equipped_patch_ids:
		expected_patches.append(String(patch_id))
	if night_snapshot.get("equipped_patch_ids", []) != expected_patches:
		errors.append(
			"defense_lab.equipped_patch_ids: must match the Product V2 loadout"
		)
	if int(night_snapshot.get("legacy_cache_level", -1)) != loop_state.legacy_cache_level:
		errors.append(
			"defense_lab.legacy_cache_level: must match the Product V2 loadout"
		)


func _restart_lab_with_current_loadout(shift_index: int) -> bool:
	return _restart_lab_with_loadout(_state, shift_index)


func _commit_day_meta_candidate(candidate: ProductLoopState) -> bool:
	if candidate.last_result.is_empty() and not _restart_lab_with_loadout(
		candidate, 1
	):
		return _reject(String(_defense_lab.snapshot().get("last_error", "")))
	_state = candidate
	_refresh_forecast_cache()
	_last_error = ""
	return true


func _restart_lab_with_loadout(
	loop_state: ProductLoopState,
	shift_index: int
) -> bool:
	return _defense_lab.restart_with_loadout(
		shift_index,
		loop_state.operator_levels,
		loop_state.unlocked_operator_ids,
		loop_state.equipped_patch_ids,
		loop_state.legacy_cache_level
	)


func _forecast_shift_index() -> int:
	return 2 if _state.shift_2_unlocked else 1


func _can_use_double_speed(loop_state: ProductLoopState) -> bool:
	if loop_state.phase != ProductLoopState.Phase.NIGHT_ACTIVE:
		return false
	var record := loop_state.get_shift_record(loop_state.active_shift_index)
	return record != null and record.best_stars == 3


func _forecast_for(
	shift_index: int,
	equipped_patch_ids: Array[StringName]
) -> Dictionary:
	return ProductV2Forecast.evaluate(
		_catalog,
		shift_index,
		_state.operator_levels,
		_state.unlocked_operator_ids,
		equipped_patch_ids,
		_state.legacy_cache_level
	)


func _refresh_forecast_cache() -> void:
	_forecast_cache = _forecast_for(
		_forecast_shift_index(), _state.equipped_patch_ids
	)


func _offline_noop(reason: String) -> Dictionary:
	return {
		"applied": false,
		"reason": reason,
		"elapsed_seconds": 0,
		"awarded_bits": 0,
		"remainder_seconds": _state.day_income_remainder_seconds,
		"reached_cap": false,
		"bits_after": _state.bits,
	}


func _operator_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var modifiers := ProgressionRules.patch_modifiers(
		_state.equipped_patch_ids, _catalog.base_catalog
	)
	var legacy_multiplier := (
		1.0
		+ _catalog.base_catalog.balance.legacy_cache_bonus
		* float(_state.legacy_cache_level)
	)
	for definition: OperatorDefinition in _catalog.base_catalog.operators:
		var unlocked := _state.unlocked_operator_ids.has(definition.id)
		var level := int(_state.operator_levels.get(definition.id, 0))
		var upgrade_cost := (
			ProductMetaRules.operator_upgrade_cost(level, definition)
			if unlocked else -1
		)
		var hp := (
			definition.base_hp
			* pow(_catalog.balance.operator_hp_growth, float(maxi(0, level - 1)))
			if unlocked else 0.0
		)
		var next_hp := (
			definition.base_hp
			* pow(_catalog.balance.operator_hp_growth, float(level))
			if upgrade_cost >= 0 else hp
		)
		var dps := (
			ProgressionRules.operator_dps(definition, level)
			* float(modifiers.damage)
			* float(modifiers.attack_speed)
			* legacy_multiplier
			if unlocked else 0.0
		)
		var next_dps := (
			ProgressionRules.operator_dps(definition, level + 1)
			* float(modifiers.damage)
			* float(modifiers.attack_speed)
			* legacy_multiplier
			if upgrade_cost >= 0 else dps
		)
		rows.append({
			"id": String(definition.id),
			"display_name": definition.display_name,
			"name": definition.display_name,
			"role": definition.role_name,
			"role_name": definition.role_name,
			"ability": definition.ability_description,
			"level": level,
			"unlocked": unlocked,
			"hp": floori(hp),
			"max_hp": floori(hp),
			"next_hp": floori(next_hp),
			"dps": floori(dps),
			"next_dps": floori(next_dps),
			"upgrade_cost": upgrade_cost,
			"can_upgrade": (
				_state.phase == ProductLoopState.Phase.DAY_PREP
				and unlocked
				and upgrade_cost >= 0
				and _state.bits >= upgrade_cost
			),
			"unlock_text": _operator_unlock_text(definition.id),
		})
	return rows


func _patch_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var new_patch_ids := (
		(_state.last_result.get("new_unlocks", {}) as Dictionary).get(
			"patch_ids", []
		) as Array
	)
	for definition: PatchDefinition in _catalog.base_catalog.patches:
		var discovered := _state.discovered_patch_ids.has(definition.id)
		var equipped_slot := _state.equipped_patch_ids.find(definition.id)
		rows.append({
			"id": String(definition.id),
			"display_name": definition.display_name,
			"name": definition.display_name,
			"description": definition.description,
			"benefit": definition.benefit,
			"drawback": definition.drawback,
			"tradeoff": definition.drawback,
			"discovered": discovered,
			"unlocked": discovered,
			"equipped": equipped_slot >= 0,
			"equipped_slot": equipped_slot,
			"new": new_patch_ids.has(String(definition.id)),
			"equip_cost": _catalog.balance.patch_equip_cost_bits,
			"unlock_text": _patch_unlock_text(definition.id),
		})
	return rows


func _operator_unlock_text(operator_id: StringName) -> String:
	match operator_id:
		&"debugger", &"build_engineer":
			return "Starting operator"
		&"sprite_artist":
			return "Earn 1 star on Shift 1"
		&"qa_imp":
			return "Earn 2 stars on Shift 1"
	return "Unknown unlock"


func _patch_unlock_text(patch_id: StringName) -> String:
	match patch_id:
		&"frame_skip":
			return "Earn 1 star on Shift 1"
		&"unsafe_build":
			return "Reach wave 5 on Shift 1"
		&"reward_bypass":
			return "Reach wave 7 on Shift 1"
		&"rollback_lock":
			return "Reach wave 9 on Shift 1"
		&"safe_mode":
			return "Encounter the boss on Shift 2"
	return "Unknown unlock"


func _patch_slot_unlock_text(slot_index: int) -> String:
	match slot_index:
		0:
			return "Earn 1 star on Shift 1"
		1:
			return "Earn 3 stars on Shift 1"
		2:
			return "Earn 2 stars on Shift 2"
	return "Unknown unlock"


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
