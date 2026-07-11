class_name PatchDefinition
extends RefCounted

var id: StringName
var display_name: String
var description: String
var benefit: String
var drawback: String
var unlock_stage: int
var damage_multiplier: float
var attack_speed_multiplier: float
var bit_multiplier: float
var enemy_health_multiplier: float
var boss_recovery_multiplier: float
var boss_special_interval_multiplier: float


func _init(
	patch_id: StringName,
	patch_name: String,
	patch_description: String,
	patch_benefit: String,
	patch_drawback: String,
	patch_unlock_stage: int,
	patch_damage_multiplier: float,
	patch_attack_speed_multiplier: float,
	patch_bit_multiplier: float,
	patch_enemy_health_multiplier: float,
	patch_boss_recovery_multiplier: float,
	patch_boss_special_interval_multiplier: float
) -> void:
	id = patch_id
	display_name = patch_name
	description = patch_description
	benefit = patch_benefit
	drawback = patch_drawback
	unlock_stage = patch_unlock_stage
	damage_multiplier = patch_damage_multiplier
	attack_speed_multiplier = patch_attack_speed_multiplier
	bit_multiplier = patch_bit_multiplier
	enemy_health_multiplier = patch_enemy_health_multiplier
	boss_recovery_multiplier = patch_boss_recovery_multiplier
	boss_special_interval_multiplier = patch_boss_special_interval_multiplier
