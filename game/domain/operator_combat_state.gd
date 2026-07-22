class_name OperatorCombatState
extends RefCounted

var operator_id: StringName = &""
var current_hp: float = 0.0
var attack_remaining: float = INF
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var down_count: int = 0
var active_time: float = 0.0
var down_time: float = 0.0


func _init(runtime_operator_id: StringName = &"") -> void:
	operator_id = runtime_operator_id


func is_active() -> bool:
	return current_hp > 0.0


func deep_clone() -> OperatorCombatState:
	var copy := OperatorCombatState.new(operator_id)
	copy.current_hp = current_hp
	copy.attack_remaining = attack_remaining
	copy.damage_dealt = damage_dealt
	copy.damage_taken = damage_taken
	copy.down_count = down_count
	copy.active_time = active_time
	copy.down_time = down_time
	return copy
