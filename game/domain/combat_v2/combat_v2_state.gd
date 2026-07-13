class_name CombatV2State
extends RefCounted

const MAX_RECENT_EVENTS := 64


class OperatorRuntime:
	extends RefCounted

	var operator_id: StringName
	var current_hp: float = 0.0
	var attack_remaining: float = INF
	var recovery_remaining: float = 0.0
	var damage_dealt: float = 0.0
	var damage_taken: float = 0.0
	var down_count: int = 0
	var active_time: float = 0.0
	var down_time: float = 0.0


	func _init(runtime_operator_id: StringName = &"") -> void:
		operator_id = runtime_operator_id


	func is_active() -> bool:
		return current_hp > 0.0 and recovery_remaining <= 0.0


	func deep_clone() -> OperatorRuntime:
		var copy := OperatorRuntime.new(operator_id)
		copy.current_hp = current_hp
		copy.attack_remaining = attack_remaining
		copy.recovery_remaining = recovery_remaining
		copy.damage_dealt = damage_dealt
		copy.damage_taken = damage_taken
		copy.down_count = down_count
		copy.active_time = active_time
		copy.down_time = down_time
		return copy


var progression: GameState = GameState.new()
var operators: Array[OperatorRuntime] = []

var enemy_attack_remaining: float = INF
var enemy_pattern_step: int = 0
var enemy_locked_target_id: StringName = &""
var boss_special_remaining: float = INF
var boss_rollback_remaining: float = INF
var qa_pulse_remaining: float = INF

var encounter_serial: int = 0
var total_elapsed: float = 0.0
var stage_elapsed: float = 0.0
var total_enemies_defeated: int = 0
var total_stages_cleared: int = 0
var total_damage_taken: float = 0.0
var total_down_count: int = 0
var total_down_time: float = 0.0
var total_boss_healed: float = 0.0

var stage_damage_taken: float = 0.0
var stage_down_count: int = 0
var stage_down_time: float = 0.0
var stage_boss_healed: float = 0.0

var recent_events: Array[Dictionary] = []


func get_operator(operator_id: StringName) -> OperatorRuntime:
	for runtime: OperatorRuntime in operators:
		if runtime.operator_id == operator_id:
			return runtime
	return null


func operator_index(operator_id: StringName) -> int:
	for index: int in range(operators.size()):
		if operators[index].operator_id == operator_id:
			return index
	return -1


func record_event(kind: StringName, details: Dictionary = {}) -> void:
	var event := details.duplicate(true)
	event["kind"] = kind
	event["time"] = total_elapsed
	event["stage"] = progression.stage
	event["enemy_index"] = progression.enemy_index
	event["encounter_serial"] = encounter_serial
	recent_events.append(event)
	if recent_events.size() > MAX_RECENT_EVENTS:
		recent_events.pop_front()


func reset_stage_metrics() -> void:
	stage_elapsed = 0.0
	stage_damage_taken = 0.0
	stage_down_count = 0
	stage_down_time = 0.0
	stage_boss_healed = 0.0


func deep_clone() -> CombatV2State:
	var copy := CombatV2State.new()
	copy.progression = _clone_progression(progression)
	for runtime: OperatorRuntime in operators:
		copy.operators.append(runtime.deep_clone())

	copy.enemy_attack_remaining = enemy_attack_remaining
	copy.enemy_pattern_step = enemy_pattern_step
	copy.enemy_locked_target_id = enemy_locked_target_id
	copy.boss_special_remaining = boss_special_remaining
	copy.boss_rollback_remaining = boss_rollback_remaining
	copy.qa_pulse_remaining = qa_pulse_remaining

	copy.encounter_serial = encounter_serial
	copy.total_elapsed = total_elapsed
	copy.stage_elapsed = stage_elapsed
	copy.total_enemies_defeated = total_enemies_defeated
	copy.total_stages_cleared = total_stages_cleared
	copy.total_damage_taken = total_damage_taken
	copy.total_down_count = total_down_count
	copy.total_down_time = total_down_time
	copy.total_boss_healed = total_boss_healed
	copy.stage_damage_taken = stage_damage_taken
	copy.stage_down_count = stage_down_count
	copy.stage_down_time = stage_down_time
	copy.stage_boss_healed = stage_boss_healed
	for event: Dictionary in recent_events:
		copy.recent_events.append(event.duplicate(true))
	return copy


func duplicate_state() -> CombatV2State:
	return deep_clone()


func _clone_progression(source: GameState) -> GameState:
	var copy := GameState.new()
	copy.stage = source.stage
	copy.highest_stage = source.highest_stage
	copy.bits = source.bits
	copy.patch_notes = source.patch_notes
	copy.run_count = source.run_count
	copy.legacy_cache_level = source.legacy_cache_level
	copy.operator_levels = source.operator_levels.duplicate(true)
	copy.unlocked_operator_ids.assign(source.unlocked_operator_ids)
	copy.discovered_patch_ids.assign(source.discovered_patch_ids)
	copy.equipped_patch_ids.assign(source.equipped_patch_ids)
	copy.unlocked_patch_slots = source.unlocked_patch_slots

	copy.enemy_index = source.enemy_index
	copy.enemy_health = source.enemy_health
	copy.boss_elapsed = source.boss_elapsed
	copy.boss_recovery_count = source.boss_recovery_count
	copy.boss_recovered_health = source.boss_recovered_health
	copy.boss_debuff_applied = source.boss_debuff_applied
	copy.boss_failure_count = source.boss_failure_count

	copy.is_maintenance = source.is_maintenance
	copy.maintenance_cycles_remaining = source.maintenance_cycles_remaining
	copy.can_prestige = source.can_prestige
	copy.free_patch_swaps = source.free_patch_swaps
	copy.status_message = source.status_message
	return copy
