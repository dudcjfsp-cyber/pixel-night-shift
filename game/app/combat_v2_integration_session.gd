class_name CombatV2IntegrationSession
extends RefCounted

const SAVE_STATE_KEYS: PackedStringArray = [
	"combat", "diagnosis_history", "patch_history",
]
const MAX_HISTORY := 12

var _prototype: CombatV2PrototypeSession
var _diagnosis_history: Array[String] = []
var _patch_history: Array[String] = []
var _last_diagnosis_kind := ""
var _last_error := ""


func _init(prototype_override: CombatV2PrototypeSession = null) -> void:
	_prototype = prototype_override if prototype_override != null else CombatV2PrototypeSession.new()
	_record_diagnosis_if_changed()


func tick(delta_seconds: float) -> void:
	_last_error = ""
	_prototype.tick(delta_seconds)
	_record_diagnosis_if_changed()


func upgrade_operator(operator_id: StringName) -> bool:
	return _finish_prototype_command(_prototype.upgrade_operator(operator_id))


func equip_patch(slot_index: int, patch_id: StringName) -> bool:
	var succeeded := _prototype.equip_patch(slot_index, patch_id)
	if succeeded:
		_append_history(_patch_history, "장착: %s (슬롯 %d)" % [patch_id, slot_index + 1])
	return _finish_prototype_command(succeeded)


func remove_patch(slot_index: int) -> bool:
	var before := _prototype.snapshot()
	var slots := before["patch_slots"] as Array
	var removed_id := String(slots[slot_index]) if slot_index >= 0 and slot_index < slots.size() else ""
	var succeeded := _prototype.remove_patch(slot_index)
	if succeeded:
		_append_history(_patch_history, "제거: %s (슬롯 %d)" % [removed_id, slot_index + 1])
	return _finish_prototype_command(succeeded)


func emergency_redeploy(operator_id: StringName) -> bool:
	return _finish_prototype_command(_prototype.emergency_redeploy(operator_id))


func buy_legacy_cache() -> bool:
	return _reject("Combat V2 테스트에서는 레거시 캐시를 사용하지 않습니다.")


func prestige() -> bool:
	return _reject("Combat V2 테스트는 STAGE 10 결과 화면에서 종료됩니다.")


func get_diagnosis() -> Dictionary:
	return _prototype.get_diagnosis()


func get_patch_preview(slot_index: int, patch_id: StringName) -> Dictionary:
	var preview := _prototype.get_patch_preview(slot_index, patch_id).duplicate(true)
	var summary := "장착할 수 없는 패치입니다."
	if bool(preview.get("can_equip", false)):
		summary = "예상 처리 %.1f초 → %.1f초 · 비트 배율 %.2f → %.2f" % [
			float(preview["before_ttk"]),
			float(preview["after_ttk"]),
			float(preview["before_bits_multiplier"]),
			float(preview["after_bits_multiplier"]),
		]
	preview["summary"] = summary
	return preview


func snapshot() -> Dictionary:
	var data := _prototype.snapshot().duplicate(true)
	data["patch_notes"] = 0
	data["run_count"] = 0
	data["legacy_cache_level"] = 0
	data["legacy_cache_cost"] = 0
	data["maintenance_time_left"] = float(data["maintenance_remaining"])
	data["combat_v2_test_mode"] = true
	data["combat_v2_complete"] = bool(data["prestige_available"])
	data["offline_progress_supported"] = false
	if not _last_error.is_empty():
		data["last_error"] = _last_error
	return data


func export_state() -> Dictionary:
	return {
		"combat": _prototype.export_state(),
		"diagnosis_history": _diagnosis_history.duplicate(),
		"patch_history": _patch_history.duplicate(),
	}


func restore_state(data: Dictionary) -> PackedStringArray:
	var errors := _validate_restore_shape(data)
	if not errors.is_empty():
		return errors
	var candidate := CombatV2PrototypeSession.new()
	var combat_errors := candidate.restore_state(data["combat"] as Dictionary)
	for error_message: String in combat_errors:
		errors.append("combat: %s" % error_message)
	if not errors.is_empty():
		return errors
	var diagnosis_history := _to_string_array(data["diagnosis_history"] as Array)
	var patch_history := _to_string_array(data["patch_history"] as Array)
	_prototype = candidate
	_diagnosis_history = diagnosis_history
	_patch_history = patch_history
	_last_error = ""
	_last_diagnosis_kind = String(_prototype.get_diagnosis()["kind"])
	return PackedStringArray()


func is_complete() -> bool:
	return bool(_prototype.snapshot()["prestige_available"])


func result_data() -> Dictionary:
	var data := snapshot()
	assert(bool(data["combat_v2_complete"]), "Combat V2 result requires a completed test")
	var metrics := data["combat_metrics"] as Dictionary
	var levels: Dictionary = {}
	for raw_operator: Variant in data["operators"] as Array:
		var operator := raw_operator as Dictionary
		levels[String(operator["id"])] = int(operator["level"])
	return {
		"clear_time": float(metrics["total_elapsed"]),
		"normal_failures": int(data["normal_failure_count"]),
		"boss_failures": int(data["boss_failure_count"]),
		"total_failures": int(data["failure_count"]),
		"qa_rescues": int(data["qa_rescue_count"]),
		"paid_redeploy_count": int(data["paid_redeploy_count"]),
		"emergency_spent_bits": float(data["emergency_spent_bits"]),
		"gross_bits": float(data["gross_bits"]),
		"net_bits": float(data["net_bits"]),
		"operator_levels": levels,
		"diagnosis_history": _diagnosis_history.duplicate(),
		"patch_history": _patch_history.duplicate(),
	}


func _finish_prototype_command(succeeded: bool) -> bool:
	var prototype_snapshot := _prototype.snapshot()
	if succeeded:
		_last_error = ""
		_record_diagnosis_if_changed()
		return true
	_last_error = String(prototype_snapshot["last_error"])
	if _last_error.is_empty():
		_last_error = "Combat V2 command was rejected without an error."
	return false


func _reject(message: String) -> bool:
	_last_error = message
	return false


func _record_diagnosis_if_changed() -> void:
	var diagnosis := _prototype.get_diagnosis()
	var kind := String(diagnosis["kind"])
	if kind == _last_diagnosis_kind:
		return
	_last_diagnosis_kind = kind
	_append_history(
		_diagnosis_history,
		"ST%d · %s · %s" % [
			int(_prototype.snapshot()["stage"]),
			String(diagnosis["title"]),
			String(diagnosis["evidence"]),
		]
	)


func _append_history(history: Array[String], entry: String) -> void:
	history.append(entry)
	if history.size() > MAX_HISTORY:
		history.pop_front()


func _validate_restore_shape(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in SAVE_STATE_KEYS:
		if not data.has(key):
			errors.append("%s: required integration state field is missing" % key)
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not SAVE_STATE_KEYS.has(String(raw_key)):
			errors.append("%s: unexpected integration state field" % String(raw_key))
	if not errors.is_empty():
		return errors
	if typeof(data["combat"]) != TYPE_DICTIONARY:
		errors.append("combat must be an object")
	_validate_history(data["diagnosis_history"], "diagnosis_history", errors)
	_validate_history(data["patch_history"], "patch_history", errors)
	return errors


func _validate_history(value: Variant, context: String, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array" % context)
		return
	var entries := value as Array
	if entries.size() > MAX_HISTORY:
		errors.append("%s exceeds %d entries" % [context, MAX_HISTORY])
	for index: int in range(entries.size()):
		if typeof(entries[index]) != TYPE_STRING or String(entries[index]).is_empty():
			errors.append("%s[%d] must be a non-empty string" % [context, index])


func _to_string_array(source: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in source:
		result.append(String(value))
	return result
