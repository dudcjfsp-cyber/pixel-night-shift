class_name CombatV2Catalog
extends RefCounted

const STABLE_OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]
const STABLE_ENEMY_IDS: Array[StringName] = [
	&"broken_pixel", &"infinite_loop", &"missing_resource", &"watchdog_process",
]


class OperatorProfile:
	extends RefCounted

	var id: StringName
	var role_name: String
	var base_hp: float
	var attack_interval: float
	var threat_weight: float
	var outgoing_multiplier: float
	var damage_exponent_multiplier: float
	var incoming_multiplier: float
	var boss_multiplier: float
	var team_interval_multiplier: float


	func _init(
		operator_id: StringName,
		operator_role_name: String,
		operator_base_hp: float,
		operator_attack_interval: float,
		operator_threat_weight: float,
		operator_outgoing_multiplier: float,
		operator_damage_exponent_multiplier: float,
		operator_incoming_multiplier: float,
		operator_boss_multiplier: float,
		operator_team_interval_multiplier: float
	) -> void:
		id = operator_id
		role_name = operator_role_name
		base_hp = operator_base_hp
		attack_interval = operator_attack_interval
		threat_weight = operator_threat_weight
		outgoing_multiplier = operator_outgoing_multiplier
		damage_exponent_multiplier = operator_damage_exponent_multiplier
		incoming_multiplier = operator_incoming_multiplier
		boss_multiplier = operator_boss_multiplier
		team_interval_multiplier = operator_team_interval_multiplier


class EnemyProfile:
	extends RefCounted

	var id: StringName
	var display_name: String
	var pattern: StringName
	var attack_interval: float
	var attack_damage: float
	var burst_count: int
	var burst_gap: float
	var poll_interval: float
	var poll_damage: float
	var special_interval: float
	var special_damage: float
	var rollback_interval: float
	var rollback_fraction: float


	func _init(enemy_id: StringName, enemy_display_name: String, enemy_pattern: StringName) -> void:
		id = enemy_id
		display_name = enemy_display_name
		pattern = enemy_pattern


class BalanceProfile:
	extends RefCounted

	var max_stage: int
	var normal_enemy_count: int
	var hp_per_level: float
	var revive_fraction: float
	var qa_recovery_delay: float
	var emergency_redeploy_delay: float
	var emergency_cost_fraction: float
	var maintenance_seconds: float
	var damage_growth: float


class DiagnosisThresholds:
	extends RefCounted

	var ttk_regression_fraction: float
	var team_hp_loss_fraction: float
	var recovery_delay_seconds: float
	var minimum_uptime_fraction: float
	var patch_bits_regression_fraction: float
	var boss_heal_regression_fraction: float


var base_catalog: ContentCatalog
var operators: Array[OperatorProfile] = []
var enemies: Array[EnemyProfile] = []
var balance: BalanceProfile
var diagnosis: DiagnosisThresholds

var _operators_by_id: Dictionary = {}
var _enemies_by_id: Dictionary = {}


func build_indexes() -> void:
	_operators_by_id.clear()
	_enemies_by_id.clear()
	for profile: OperatorProfile in operators:
		_operators_by_id[profile.id] = profile
	for profile: EnemyProfile in enemies:
		_enemies_by_id[profile.id] = profile


func has_operator(operator_id: StringName) -> bool:
	return _operators_by_id.has(operator_id)


func get_operator(operator_id: StringName) -> OperatorProfile:
	return _operators_by_id.get(operator_id) as OperatorProfile


func has_enemy(enemy_id: StringName) -> bool:
	return _enemies_by_id.has(enemy_id)


func get_enemy(enemy_id: StringName) -> EnemyProfile:
	return _enemies_by_id.get(enemy_id) as EnemyProfile
