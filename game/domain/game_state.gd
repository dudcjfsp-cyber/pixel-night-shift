class_name GameState
extends RefCounted

var stage: int = 1
var highest_stage: int = 1
var bits: float = 0.0
var patch_notes: int = 0
var run_count: int = 0
var legacy_cache_level: int = 0

var operator_levels: Dictionary = {}
var unlocked_operator_ids: Array[StringName] = []
var discovered_patch_ids: Array[StringName] = []
var equipped_patch_ids: Array[StringName] = [&"", &"", &""]
var unlocked_patch_slots: int = 0

var enemy_index: int = 1
var enemy_health: float = 0.0
var operator_combat_states: Array[OperatorCombatState] = []
var enemy_attack_remaining: float = INF
var boss_special_remaining: float = INF
var boss_rollback_remaining: float = INF
var boss_elapsed: float = 0.0
var boss_recovery_count: int = 0
var boss_recovered_health: float = 0.0
var boss_debuff_applied: bool = false
var boss_failure_count: int = 0
var boss_attempt_serial: int = 0
var last_boss_failure_reason: StringName = &""

var qa_rescue_consumed: bool = false
var qa_rescue_target_id: StringName = &""
var qa_rescue_remaining: float = 0.0
var qa_rescue_count: int = 0

var boss_event_serial: int = 0
var recent_boss_events: Array[Dictionary] = []
var total_operator_down_count: int = 0
var total_operator_down_time: float = 0.0

var is_maintenance: bool = false
var maintenance_cycles_remaining: int = 0
var can_prestige: bool = false
var free_patch_swaps: int = 0
var status_message: String = "야간 근무를 시작합니다."


func is_operator_unlocked(operator_id: StringName) -> bool:
	return unlocked_operator_ids.has(operator_id)


func is_patch_discovered(patch_id: StringName) -> bool:
	return discovered_patch_ids.has(patch_id)


func get_operator_combat_state(operator_id: StringName) -> OperatorCombatState:
	for runtime: OperatorCombatState in operator_combat_states:
		if runtime.operator_id == operator_id:
			return runtime
	return null


func deep_clone() -> GameState:
	var copy := GameState.new()
	copy.stage = stage
	copy.highest_stage = highest_stage
	copy.bits = bits
	copy.patch_notes = patch_notes
	copy.run_count = run_count
	copy.legacy_cache_level = legacy_cache_level

	copy.operator_levels = operator_levels.duplicate(true)
	copy.unlocked_operator_ids.assign(unlocked_operator_ids)
	copy.discovered_patch_ids.assign(discovered_patch_ids)
	copy.equipped_patch_ids.assign(equipped_patch_ids)
	copy.unlocked_patch_slots = unlocked_patch_slots

	copy.enemy_index = enemy_index
	copy.enemy_health = enemy_health
	for runtime: OperatorCombatState in operator_combat_states:
		copy.operator_combat_states.append(runtime.deep_clone())
	copy.enemy_attack_remaining = enemy_attack_remaining
	copy.boss_special_remaining = boss_special_remaining
	copy.boss_rollback_remaining = boss_rollback_remaining
	copy.boss_elapsed = boss_elapsed
	copy.boss_recovery_count = boss_recovery_count
	copy.boss_recovered_health = boss_recovered_health
	copy.boss_debuff_applied = boss_debuff_applied
	copy.boss_failure_count = boss_failure_count
	copy.boss_attempt_serial = boss_attempt_serial
	copy.last_boss_failure_reason = last_boss_failure_reason

	copy.qa_rescue_consumed = qa_rescue_consumed
	copy.qa_rescue_target_id = qa_rescue_target_id
	copy.qa_rescue_remaining = qa_rescue_remaining
	copy.qa_rescue_count = qa_rescue_count

	copy.boss_event_serial = boss_event_serial
	for event: Dictionary in recent_boss_events:
		copy.recent_boss_events.append(event.duplicate(true))
	copy.total_operator_down_count = total_operator_down_count
	copy.total_operator_down_time = total_operator_down_time

	copy.is_maintenance = is_maintenance
	copy.maintenance_cycles_remaining = maintenance_cycles_remaining
	copy.can_prestige = can_prestige
	copy.free_patch_swaps = free_patch_swaps
	copy.status_message = status_message
	return copy
