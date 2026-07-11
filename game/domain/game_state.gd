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
var boss_elapsed: float = 0.0
var boss_recovery_count: int = 0
var boss_recovered_health: float = 0.0
var boss_debuff_applied: bool = false
var boss_failure_count: int = 0

var is_maintenance: bool = false
var maintenance_cycles_remaining: int = 0
var can_prestige: bool = false
var free_patch_swaps: int = 0
var status_message: String = "야간 근무를 시작합니다."


func is_operator_unlocked(operator_id: StringName) -> bool:
	return unlocked_operator_ids.has(operator_id)


func is_patch_discovered(patch_id: StringName) -> bool:
	return discovered_patch_ids.has(patch_id)
