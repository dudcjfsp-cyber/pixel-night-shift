class_name GameSessionStateDto
extends RefCounted

const ROOT_KEYS: PackedStringArray = [
	"stage",
	"highest_stage",
	"bits",
	"patch_notes",
	"run_count",
	"legacy_cache_level",
	"operator_levels",
	"unlocked_operator_ids",
	"discovered_patch_ids",
	"equipped_patch_ids",
	"unlocked_patch_slots",
	"enemy_index",
	"enemy_health",
	"operator_combat_states",
	"enemy_attack_remaining",
	"boss_special_remaining",
	"boss_rollback_remaining",
	"boss_elapsed",
	"boss_recovery_count",
	"boss_recovered_health",
	"boss_debuff_applied",
	"boss_failure_count",
	"boss_attempt_serial",
	"last_boss_failure_reason",
	"qa_rescue_consumed",
	"qa_rescue_target_id",
	"qa_rescue_remaining",
	"qa_rescue_count",
	"boss_event_serial",
	"recent_boss_events",
	"total_operator_down_count",
	"total_operator_down_time",
	"is_maintenance",
	"maintenance_cycles_remaining",
	"can_prestige",
	"free_patch_swaps",
	"status_message",
]
const OPERATOR_RUNTIME_KEYS: PackedStringArray = [
	"operator_id",
	"current_hp",
	"attack_remaining",
	"damage_dealt",
	"damage_taken",
	"down_count",
	"active_time",
	"down_time",
]
const MAX_RECENT_BOSS_EVENTS := 64


static func export_state(state: GameState, catalog: ContentCatalog) -> Dictionary:
	assert(state != null, "GameSession state export requires a state")
	assert(catalog != null, "GameSession state export requires content")

	var operator_levels: Dictionary = {}
	for definition: OperatorDefinition in catalog.operators:
		operator_levels[String(definition.id)] = int(
			state.operator_levels.get(definition.id, 0)
		)

	var operator_runtimes: Array[Dictionary] = []
	if not state.operator_combat_states.is_empty():
		for definition: OperatorDefinition in catalog.operators:
			var runtime := state.get_operator_combat_state(definition.id)
			assert(runtime != null, "Runtime rows must cover every content operator")
			operator_runtimes.append({
				"operator_id": String(runtime.operator_id),
				"current_hp": runtime.current_hp,
				"attack_remaining": encode_timer(runtime.attack_remaining),
				"damage_dealt": runtime.damage_dealt,
				"damage_taken": runtime.damage_taken,
				"down_count": runtime.down_count,
				"active_time": runtime.active_time,
				"down_time": runtime.down_time,
			})

	return {
		"stage": state.stage,
		"highest_stage": state.highest_stage,
		"bits": state.bits,
		"patch_notes": state.patch_notes,
		"run_count": state.run_count,
		"legacy_cache_level": state.legacy_cache_level,
		"operator_levels": operator_levels,
		"unlocked_operator_ids": _string_array(state.unlocked_operator_ids),
		"discovered_patch_ids": _string_array(state.discovered_patch_ids),
		"equipped_patch_ids": _string_array(state.equipped_patch_ids),
		"unlocked_patch_slots": state.unlocked_patch_slots,
		"enemy_index": state.enemy_index,
		"enemy_health": state.enemy_health,
		"operator_combat_states": operator_runtimes,
		"enemy_attack_remaining": encode_timer(state.enemy_attack_remaining),
		"boss_special_remaining": encode_timer(state.boss_special_remaining),
		"boss_rollback_remaining": encode_timer(state.boss_rollback_remaining),
		"boss_elapsed": state.boss_elapsed,
		"boss_recovery_count": state.boss_recovery_count,
		"boss_recovered_health": state.boss_recovered_health,
		"boss_debuff_applied": state.boss_debuff_applied,
		"boss_failure_count": state.boss_failure_count,
		"boss_attempt_serial": state.boss_attempt_serial,
		"last_boss_failure_reason": String(state.last_boss_failure_reason),
		"qa_rescue_consumed": state.qa_rescue_consumed,
		"qa_rescue_target_id": String(state.qa_rescue_target_id),
		"qa_rescue_remaining": state.qa_rescue_remaining,
		"qa_rescue_count": state.qa_rescue_count,
		"boss_event_serial": state.boss_event_serial,
		"recent_boss_events": _export_events(state.recent_boss_events),
		"total_operator_down_count": state.total_operator_down_count,
		"total_operator_down_time": state.total_operator_down_time,
		"is_maintenance": state.is_maintenance,
		"maintenance_cycles_remaining": state.maintenance_cycles_remaining,
		"can_prestige": state.can_prestige,
		"free_patch_swaps": state.free_patch_swaps,
		"status_message": state.status_message,
	}


static func encode_timer(value: float) -> Variant:
	assert(
		is_inf(value) or (is_finite(value) and value >= 0.0),
		"Session timers must be inactive or non-negative and finite"
	)
	return null if is_inf(value) else value


static func decode_timer(value: Variant) -> float:
	return INF if value == null else float(value)


static func is_timer_value(value: Variant) -> bool:
	return (
		value == null
		or (
			typeof(value) in [TYPE_INT, TYPE_FLOAT]
			and is_finite(float(value))
			and float(value) >= 0.0
		)
	)


static func _string_array(source: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in source:
		result.append(String(value))
	return result


static func _export_events(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in source:
		result.append(_json_safe_dictionary(event))
	return result


static func _json_safe_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in source.keys():
		result[String(raw_key)] = _json_safe_value(source[raw_key])
	return result


static func _json_safe_value(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if typeof(value) == TYPE_DICTIONARY:
		return _json_safe_dictionary(value as Dictionary)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_json_safe_value(item))
		return result
	return value
