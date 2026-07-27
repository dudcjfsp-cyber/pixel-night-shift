class_name NightShiftState
extends RefCounted

const MAX_RECENT_EVENTS := 64
const MAX_OPERATOR_DOWN_RECORDS := 5


enum Phase {
	COUNTDOWN,
	NORMAL_ACTIVE,
	INTER_WAVE,
	BOSS_WARNING,
	BOSS_ACTIVE,
	SUCCESS,
	FAILURE,
}


class EnemyRuntime:
	extends RefCounted

	var serial: int
	var enemy_id: StringName
	var current_hp: float
	var max_hp: float
	var leak_damage: int


	func _init(
		runtime_serial: int = 0,
		runtime_enemy_id: StringName = &"",
		runtime_max_hp: float = 0.0,
		runtime_leak_damage: int = 0
	) -> void:
		serial = runtime_serial
		enemy_id = runtime_enemy_id
		max_hp = runtime_max_hp
		current_hp = runtime_max_hp
		leak_damage = runtime_leak_damage


	func is_alive() -> bool:
		return current_hp > 0.0


	func deep_clone() -> EnemyRuntime:
		var copy := EnemyRuntime.new(serial, enemy_id, max_hp, leak_damage)
		copy.current_hp = current_hp
		return copy


var shift_index: int = 1
var phase: int = Phase.COUNTDOWN
var current_wave: int = 0
var completed_waves: int = 0

var stability: int = 100
var phase_remaining: float = 0.0
var total_elapsed: float = 0.0
var combat_elapsed: float = 0.0
var wave_elapsed: float = 0.0

var operator_levels: Dictionary = {}
var unlocked_operator_ids: Array[StringName] = []
var equipped_patch_ids: Array[StringName] = []
var legacy_cache_level: int = 0

var enemies: Array[EnemyRuntime] = []
var next_enemy_serial: int = 1
var operator_combat_states: Array[OperatorCombatState] = []

var boss_hp: float = 0.0
var boss_max_hp: float = 0.0
var boss_elapsed: float = 0.0
var boss_poll_remaining: float = INF
var boss_special_remaining: float = INF
var boss_rollback_remaining: float = INF
var boss_debuff_applied: bool = false
var boss_recovery_count: int = 0
var boss_recovered_health: float = 0.0

var qa_rescue_consumed: bool = false
var qa_rescue_target_id: StringName = &""
var qa_rescue_remaining: float = 0.0
var qa_rescue_count: int = 0

var total_enemies_defeated: int = 0
var total_enemies_leaked: int = 0
var total_leak_damage: int = 0
var largest_wave_leak_damage: int = 0
var last_wave_leak_damage: int = 0
var total_operator_down_count: int = 0
var total_operator_down_time: float = 0.0
var operator_down_records: Array[Dictionary] = []

var qa_rescue_outcome: StringName = &"unused"
var qa_rescue_outcome_target_id: StringName = &""
var qa_rescue_outcome_reason: StringName = &""
var qa_rescue_outcome_time: float = 0.0

var terminal_reason: StringName = &""
var event_serial: int = 0
var recent_events: Array[Dictionary] = []


func is_terminal() -> bool:
	return phase == Phase.SUCCESS or phase == Phase.FAILURE


func is_success() -> bool:
	return phase == Phase.SUCCESS


func star_count(thresholds: PackedInt32Array) -> int:
	var result := 0
	for threshold: int in thresholds:
		if completed_waves >= threshold:
			result += 1
	return result


func get_operator_combat_state(operator_id: StringName) -> OperatorCombatState:
	for runtime: OperatorCombatState in operator_combat_states:
		if runtime.operator_id == operator_id:
			return runtime
	return null


func record_event(kind: StringName, details: Dictionary = {}) -> void:
	event_serial += 1
	var event := details.duplicate(true)
	event["serial"] = event_serial
	event["kind"] = kind
	event["time"] = total_elapsed
	event["combat_time"] = combat_elapsed
	event["shift"] = shift_index
	event["wave"] = current_wave
	event["phase"] = phase
	recent_events.append(event)
	if recent_events.size() > MAX_RECENT_EVENTS:
		recent_events.pop_front()


func record_operator_down(
	operator_id: StringName,
	attack_kind: StringName,
	boss_time: float
) -> void:
	assert(
		operator_down_records.size() < MAX_OPERATOR_DOWN_RECORDS,
		"A boss attempt cannot exceed the bounded Product V2 down record count"
	)
	operator_down_records.append({
		"operator_id": operator_id,
		"attack": attack_kind,
		"boss_time": boss_time,
	})


func record_qa_rescue_outcome(
	outcome: StringName,
	target_id: StringName,
	reason: StringName = &""
) -> void:
	qa_rescue_outcome = outcome
	qa_rescue_outcome_target_id = target_id
	qa_rescue_outcome_reason = reason
	qa_rescue_outcome_time = boss_elapsed


func deep_clone() -> NightShiftState:
	var copy := NightShiftState.new()
	copy.shift_index = shift_index
	copy.phase = phase
	copy.current_wave = current_wave
	copy.completed_waves = completed_waves
	copy.stability = stability
	copy.phase_remaining = phase_remaining
	copy.total_elapsed = total_elapsed
	copy.combat_elapsed = combat_elapsed
	copy.wave_elapsed = wave_elapsed

	copy.operator_levels = operator_levels.duplicate(true)
	copy.unlocked_operator_ids.assign(unlocked_operator_ids)
	copy.equipped_patch_ids.assign(equipped_patch_ids)
	copy.legacy_cache_level = legacy_cache_level

	for enemy: EnemyRuntime in enemies:
		copy.enemies.append(enemy.deep_clone())
	copy.next_enemy_serial = next_enemy_serial
	for runtime: OperatorCombatState in operator_combat_states:
		copy.operator_combat_states.append(runtime.deep_clone())

	copy.boss_hp = boss_hp
	copy.boss_max_hp = boss_max_hp
	copy.boss_elapsed = boss_elapsed
	copy.boss_poll_remaining = boss_poll_remaining
	copy.boss_special_remaining = boss_special_remaining
	copy.boss_rollback_remaining = boss_rollback_remaining
	copy.boss_debuff_applied = boss_debuff_applied
	copy.boss_recovery_count = boss_recovery_count
	copy.boss_recovered_health = boss_recovered_health

	copy.qa_rescue_consumed = qa_rescue_consumed
	copy.qa_rescue_target_id = qa_rescue_target_id
	copy.qa_rescue_remaining = qa_rescue_remaining
	copy.qa_rescue_count = qa_rescue_count

	copy.total_enemies_defeated = total_enemies_defeated
	copy.total_enemies_leaked = total_enemies_leaked
	copy.total_leak_damage = total_leak_damage
	copy.largest_wave_leak_damage = largest_wave_leak_damage
	copy.last_wave_leak_damage = last_wave_leak_damage
	copy.total_operator_down_count = total_operator_down_count
	copy.total_operator_down_time = total_operator_down_time
	for record: Dictionary in operator_down_records:
		copy.operator_down_records.append(record.duplicate(true))

	copy.qa_rescue_outcome = qa_rescue_outcome
	copy.qa_rescue_outcome_target_id = qa_rescue_outcome_target_id
	copy.qa_rescue_outcome_reason = qa_rescue_outcome_reason
	copy.qa_rescue_outcome_time = qa_rescue_outcome_time

	copy.terminal_reason = terminal_reason
	copy.event_serial = event_serial
	for event: Dictionary in recent_events:
		copy.recent_events.append(event.duplicate(true))
	return copy


func duplicate_state() -> NightShiftState:
	return deep_clone()
