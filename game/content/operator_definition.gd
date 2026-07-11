class_name OperatorDefinition
extends RefCounted

var id: StringName
var display_name: String
var base_dps: float
var base_cost: float
var cost_growth: float
var dps_exponent: float
var unlock_stage: int


func _init(
	operator_id: StringName,
	operator_name: String,
	operator_base_dps: float,
	operator_base_cost: float,
	operator_cost_growth: float,
	operator_dps_exponent: float,
	operator_unlock_stage: int
) -> void:
	id = operator_id
	display_name = operator_name
	base_dps = operator_base_dps
	base_cost = operator_base_cost
	cost_growth = operator_cost_growth
	dps_exponent = operator_dps_exponent
	unlock_stage = operator_unlock_stage
