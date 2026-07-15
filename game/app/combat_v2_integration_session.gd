class_name CombatV2IntegrationSession
extends RefCounted

const SAVE_STATE_KEYS: PackedStringArray = [
	"combat", "diagnosis_history", "patch_history", "appeals",
]
const APPEAL_STATE_DTO: GDScript = preload(
	"res://game/persistence/combat_v2_appeal_state_dto.gd"
)
const MAX_HISTORY := 12
const TRIGGER_PRIORITIES := {
	"diagnosis_changed": 40,
	"operator_down": 60,
	"qa_rescue_succeeded": 70,
	"emergency_redeploy_used": 72,
	"qa_rescue_cancelled": 80,
	"watchdog_kill_signal": 82,
	"watchdog_rollback": 84,
	"normal_failure": 90,
	"boss_failure": 100,
}

var _prototype: CombatV2PrototypeSession
var _appeal_catalog: AppealCatalog
var _diagnosis_history: Array[String] = []
var _patch_history: Array[String] = []
var _history_diagnosis_kind := ""
var _last_error := ""

var _current_appeals: Array[OperatorAppealRules.AppealResult] = []
var _appeals_shown := 0
var _appeals_accepted := 0
var _appeals_dismissed := 0
var _appeal_acknowledgment := ""
var _seen_stage_dedupes: Dictionary = {}
var _operator_ready_at: Dictionary = {}
var _global_ready_at := 0.0
var _processed_event_ids: Dictionary = {}
var _processed_event_order: Array[String] = []
var _appeal_last_diagnosis_kind := ""
var _appeal_last_stage := 1
var _current_trigger_priority := 0


func _init(
	prototype_override: CombatV2PrototypeSession = null,
	appeal_catalog_override: AppealCatalog = null
) -> void:
	_prototype = prototype_override if prototype_override != null else CombatV2PrototypeSession.new()
	if appeal_catalog_override != null:
		_appeal_catalog = appeal_catalog_override
	else:
		var load_result := AppealLoader.load_default()
		assert(
			load_result.is_valid(),
			"Combat V2 appeal content failed validation: %s" % "; ".join(load_result.errors)
		)
		_appeal_catalog = load_result.catalog
	_reset_appeal_runtime()
	_record_diagnosis_if_changed()
	var initial_snapshot := _prototype.snapshot()
	_prime_processed_events(initial_snapshot)
	_process_snapshot(initial_snapshot, true)


func tick(delta_seconds: float) -> void:
	_last_error = ""
	_prototype.tick(delta_seconds)
	_record_diagnosis_if_changed()
	_process_snapshot(_prototype.snapshot())


func upgrade_operator(operator_id: StringName) -> bool:
	var was_appeal_target := _has_current_appeal_for(operator_id)
	var succeeded := _prototype.upgrade_operator(operator_id)
	var accepted_appeal := succeeded and was_appeal_target and _consume_operator_appeal(operator_id)
	if not _finish_prototype_command(succeeded):
		return false
	if accepted_appeal:
		_set_appeal_acknowledgment(operator_id)
	return true


func equip_patch(slot_index: int, patch_id: StringName) -> bool:
	var succeeded := _prototype.equip_patch(slot_index, patch_id)
	if succeeded:
		_append_history(_patch_history, "적용: %s (슬롯 %d)" % [patch_id, slot_index + 1])
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
	return _reject("Combat V2 테스트는 STAGE 10 결과 화면에서 종료합니다.")


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
	data["appeals"] = _appeal_snapshots(data["operators"] as Array)
	data["appeal_acknowledgment"] = _appeal_acknowledgment
	data["appeal_stats"] = {
		"shown": _appeals_shown,
		"accepted": _appeals_accepted,
		"ignored": _appeals_dismissed,
		"unresolved": _current_appeals.size(),
	}
	data["appeal_rule_count"] = _appeal_catalog.definitions.size()
	if not _last_error.is_empty():
		data["last_error"] = _last_error
	return data


func export_state() -> Dictionary:
	return {
		"combat": _prototype.export_state(),
		"diagnosis_history": _diagnosis_history.duplicate(),
		"patch_history": _patch_history.duplicate(),
		"appeals": _export_appeal_state(),
	}


func restore_state(data: Dictionary) -> PackedStringArray:
	var errors := _validate_restore_shape(data)
	if not errors.is_empty():
		return errors
	var candidate := CombatV2PrototypeSession.new()
	var combat_errors := candidate.restore_state(data["combat"] as Dictionary)
	for error_message: String in combat_errors:
		errors.append("combat: %s" % error_message)
	var appeal_errors: PackedStringArray = APPEAL_STATE_DTO.validation_errors(
		data["appeals"] as Dictionary, _appeal_catalog
	)
	for error_message: String in appeal_errors:
		errors.append(error_message)
	if not errors.is_empty():
		return errors

	_prototype = candidate
	_diagnosis_history = _to_string_array(data["diagnosis_history"] as Array)
	_patch_history = _to_string_array(data["patch_history"] as Array)
	_restore_appeal_state(data["appeals"] as Dictionary)
	_last_error = ""
	_history_diagnosis_kind = String(_prototype.get_diagnosis()["kind"])
	if _appeal_last_diagnosis_kind.is_empty():
		var restored_snapshot := _prototype.snapshot()
		_prime_processed_events(restored_snapshot)
		_process_snapshot(restored_snapshot, true)
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
		"appeals_shown": _appeals_shown,
		"appeals_accepted": _appeals_accepted,
		"appeals_ignored": _appeals_dismissed,
		"appeals_unresolved": _current_appeals.size(),
	}


func _finish_prototype_command(succeeded: bool) -> bool:
	var prototype_snapshot := _prototype.snapshot()
	if succeeded:
		_last_error = ""
		_record_diagnosis_if_changed()
		_process_snapshot(prototype_snapshot)
		return true
	_last_error = String(prototype_snapshot["last_error"])
	if _last_error.is_empty():
		_last_error = "Combat V2 command was rejected without an error."
	return false


func _process_snapshot(after: Dictionary, bootstrap: bool = false) -> void:
	var stage := int(after["stage"])
	var completed_now := bool(after["prestige_available"])
	var stage_changed := stage != _appeal_last_stage
	if stage_changed or completed_now:
		_dismiss_current_appeals()
		_appeal_acknowledgment = ""
		_current_trigger_priority = 0
	_appeal_last_stage = stage

	var chosen_event: Dictionary = {}
	var chosen_priority := -1
	for event: Dictionary in after["visible_appeal_events"] as Array:
		var event_id := String(event["id"])
		if _processed_event_ids.has(event_id):
			continue
		_remember_processed_event(event_id)
		var priority := _trigger_priority(StringName(String(event["trigger"])))
		if priority > chosen_priority:
			chosen_event = event
			chosen_priority = priority

	var diagnosis_kind := String((after["diagnosis"] as Dictionary)["kind"])
	var diagnosis_changed := diagnosis_kind != _appeal_last_diagnosis_kind
	_appeal_last_diagnosis_kind = diagnosis_kind
	if completed_now:
		return
	if not chosen_event.is_empty():
		_present_trigger(
			StringName(String(chosen_event["trigger"])),
			after,
			chosen_event,
			chosen_priority
		)
		return
	if diagnosis_changed or bootstrap:
		_present_trigger(&"diagnosis_changed", after, {}, _trigger_priority(&"diagnosis_changed"))


func _present_trigger(
	trigger: StringName,
	snapshot_data: Dictionary,
	event: Dictionary,
	trigger_priority: int
) -> void:
	if not _current_appeals.is_empty() and trigger_priority < _current_trigger_priority:
		return
	var evidence := (snapshot_data["appeal_evidence"] as Dictionary).duplicate(true)
	for key: String in [
		"event_operator_id", "event_target_id", "event_source", "event_attack", "event_reason",
	]:
		if event.has(key):
			evidence[key] = event[key]
	var now := float((snapshot_data["combat_metrics"] as Dictionary)["total_elapsed"])
	var ignore_cooldowns := (
		trigger_priority >= 90
		or (not _current_appeals.is_empty() and trigger_priority > _current_trigger_priority)
	)
	var selected := OperatorAppealRules.evaluate(
		_appeal_catalog,
		trigger,
		evidence,
		int(snapshot_data["stage"]),
		now,
		_seen_stage_dedupes,
		_operator_ready_at,
		_global_ready_at,
		ignore_cooldowns
	)
	if selected.is_empty():
		if not _current_appeals.is_empty() and trigger_priority > _current_trigger_priority:
			_dismiss_current_appeals()
			_current_trigger_priority = 0
			_appeal_acknowledgment = ""
		return
	_dismiss_current_appeals()
	_current_appeals = selected
	_current_trigger_priority = trigger_priority
	_appeal_acknowledgment = ""
	var next_global_ready := _global_ready_at
	for result: OperatorAppealRules.AppealResult in selected:
		var definition := _appeal_catalog.get_definition(result.rule_id)
		_seen_stage_dedupes["%d:%s" % [int(snapshot_data["stage"]), result.dedupe_key]] = true
		_operator_ready_at[result.operator_id] = now + definition.operator_cooldown_seconds
		next_global_ready = maxf(next_global_ready, now + definition.global_cooldown_seconds)
	_appeals_shown += selected.size()
	_global_ready_at = next_global_ready
	_trim_dictionary_to_limit(_seen_stage_dedupes, APPEAL_STATE_DTO.MAX_DEDUPE_KEYS)


func _consume_operator_appeal(operator_id: StringName) -> bool:
	var retained: Array[OperatorAppealRules.AppealResult] = []
	var accepted := false
	for appeal: OperatorAppealRules.AppealResult in _current_appeals:
		if appeal.operator_id == operator_id:
			accepted = true
			continue
		retained.append(appeal)
	if not accepted:
		return false
	_current_appeals = retained
	_appeals_accepted += 1
	if _current_appeals.is_empty():
		_current_trigger_priority = 0
	return true


func _set_appeal_acknowledgment(operator_id: StringName) -> void:
	var operator_name := operator_id
	for raw_operator: Variant in _prototype.snapshot()["operators"] as Array:
		var operator := raw_operator as Dictionary
		if StringName(String(operator["id"])) == operator_id:
			operator_name = StringName(String(operator["name"]))
			break
	_appeal_acknowledgment = "%s: 요청을 검토해 강화에 반영했습니다." % operator_name


func _has_current_appeal_for(operator_id: StringName) -> bool:
	for appeal: OperatorAppealRules.AppealResult in _current_appeals:
		if appeal.operator_id == operator_id:
			return true
	return false


func _dismiss_current_appeals() -> void:
	_appeals_dismissed += _current_appeals.size()
	_current_appeals.clear()


func _appeal_snapshots(operator_rows: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for appeal: OperatorAppealRules.AppealResult in _current_appeals:
		var row := appeal.to_snapshot()
		var operator := _operator_snapshot(appeal.operator_id, operator_rows)
		row["operator_name"] = String(operator["name"])
		row["role"] = String(operator["role"])
		rows.append(row)
	return rows


func _operator_snapshot(operator_id: StringName, operator_rows: Array) -> Dictionary:
	for raw_operator: Variant in operator_rows:
		var operator := raw_operator as Dictionary
		if StringName(String(operator["id"])) == operator_id:
			return operator
	assert(false, "Appeal references unknown operator: %s" % operator_id)
	return {}


func _record_diagnosis_if_changed() -> void:
	var diagnosis := _prototype.get_diagnosis()
	var kind := String(diagnosis["kind"])
	if kind == _history_diagnosis_kind:
		return
	_history_diagnosis_kind = kind
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


func _export_appeal_state() -> Dictionary:
	var rule_ids: Array[String] = []
	for appeal: OperatorAppealRules.AppealResult in _current_appeals:
		rule_ids.append(String(appeal.rule_id))
	var dedupes: Array[String] = []
	for raw_key: Variant in _seen_stage_dedupes.keys():
		dedupes.append(String(raw_key))
	return {
		"current_rule_ids": rule_ids,
		"shown_count": _appeals_shown,
		"accepted_count": _appeals_accepted,
		"dismissed_count": _appeals_dismissed,
		"acknowledgment": _appeal_acknowledgment,
		"seen_stage_dedupes": dedupes,
		"operator_ready_at": {
			"debugger": float(_operator_ready_at[&"debugger"]),
			"build_engineer": float(_operator_ready_at[&"build_engineer"]),
			"sprite_artist": float(_operator_ready_at[&"sprite_artist"]),
			"qa_imp": float(_operator_ready_at[&"qa_imp"]),
		},
		"global_ready_at": _global_ready_at,
		"processed_event_ids": _processed_event_order.duplicate(),
		"last_diagnosis_kind": _appeal_last_diagnosis_kind,
		"last_stage": _appeal_last_stage,
		"current_trigger_priority": _current_trigger_priority,
	}


func _restore_appeal_state(data: Dictionary) -> void:
	_current_appeals.clear()
	for raw_rule_id: Variant in data["current_rule_ids"] as Array:
		var definition := _appeal_catalog.get_definition(StringName(String(raw_rule_id)))
		_current_appeals.append(OperatorAppealRules.result_from_definition(definition))
	_appeals_shown = int(data["shown_count"])
	_appeals_accepted = int(data["accepted_count"])
	_appeals_dismissed = int(data["dismissed_count"])
	_appeal_acknowledgment = String(data["acknowledgment"])
	_seen_stage_dedupes.clear()
	for raw_dedupe: Variant in data["seen_stage_dedupes"] as Array:
		_seen_stage_dedupes[String(raw_dedupe)] = true
	_operator_ready_at.clear()
	var ready_times := data["operator_ready_at"] as Dictionary
	for operator_id: StringName in APPEAL_STATE_DTO.OPERATOR_IDS:
		_operator_ready_at[operator_id] = float(ready_times[String(operator_id)])
	_global_ready_at = float(data["global_ready_at"])
	_processed_event_ids.clear()
	_processed_event_order.clear()
	for raw_id: Variant in data["processed_event_ids"] as Array:
		_remember_processed_event(String(raw_id))
	_appeal_last_diagnosis_kind = String(data["last_diagnosis_kind"])
	_appeal_last_stage = int(data["last_stage"])
	_current_trigger_priority = int(data["current_trigger_priority"])


func _reset_appeal_runtime() -> void:
	_restore_appeal_state(APPEAL_STATE_DTO.default_state())


func _prime_processed_events(snapshot_data: Dictionary) -> void:
	for event: Dictionary in snapshot_data["visible_appeal_events"] as Array:
		_remember_processed_event(String(event["id"]))


func _remember_processed_event(event_id: String) -> void:
	if _processed_event_ids.has(event_id):
		return
	_processed_event_ids[event_id] = true
	_processed_event_order.append(event_id)
	if _processed_event_order.size() <= APPEAL_STATE_DTO.MAX_EVENT_IDS:
		return
	var removed: String = _processed_event_order.pop_front()
	_processed_event_ids.erase(removed)


func _trigger_priority(trigger: StringName) -> int:
	assert(TRIGGER_PRIORITIES.has(String(trigger)), "Unknown appeal trigger: %s" % trigger)
	return int(TRIGGER_PRIORITIES[String(trigger)])


func _trim_dictionary_to_limit(data: Dictionary, maximum: int) -> void:
	while data.size() > maximum:
		var first_key: Variant = data.keys()[0]
		data.erase(first_key)


func _reject(message: String) -> bool:
	_last_error = message
	return false


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
	if typeof(data["appeals"]) != TYPE_DICTIONARY:
		errors.append("appeals must be an object")
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
