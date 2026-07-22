class_name OperatorDefinition
extends RefCounted

var id: StringName
var display_name: String
var role_name: String
var base_dps: float
var base_cost: float
var cost_growth: float
var dps_exponent: float
var unlock_stage: int
var base_hp: float
var attack_interval: float
var threat_weight: float
var outgoing_multiplier: float
var incoming_multiplier: float
var boss_multiplier: float
var team_interval_multiplier: float
var qa_rescue_enabled: bool


func _init(
	operator_id: StringName,
	operator_name: String,
	operator_role_name: String,
	operator_base_dps: float,
	operator_base_cost: float,
	operator_cost_growth: float,
	operator_dps_exponent: float,
	operator_unlock_stage: int,
	operator_base_hp: float,
	operator_attack_interval: float,
	operator_threat_weight: float,
	operator_outgoing_multiplier: float,
	operator_incoming_multiplier: float,
	operator_boss_multiplier: float,
	operator_team_interval_multiplier: float,
	operator_qa_rescue_enabled: bool
) -> void:
	id = operator_id
	display_name = operator_name
	role_name = operator_role_name
	base_dps = operator_base_dps
	base_cost = operator_base_cost
	cost_growth = operator_cost_growth
	dps_exponent = operator_dps_exponent
	unlock_stage = operator_unlock_stage
	base_hp = operator_base_hp
	attack_interval = operator_attack_interval
	threat_weight = operator_threat_weight
	outgoing_multiplier = operator_outgoing_multiplier
	incoming_multiplier = operator_incoming_multiplier
	boss_multiplier = operator_boss_multiplier
	team_interval_multiplier = operator_team_interval_multiplier
	qa_rescue_enabled = operator_qa_rescue_enabled
