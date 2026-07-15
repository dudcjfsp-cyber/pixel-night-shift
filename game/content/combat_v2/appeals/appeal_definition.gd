class_name AppealDefinition
extends RefCounted


class EvidenceCondition:
	extends RefCounted

	var key: StringName
	var operator: StringName
	var value: Variant


	func _init(evidence_key: StringName, comparison: StringName, threshold: Variant) -> void:
		key = evidence_key
		operator = comparison
		value = threshold


var id: StringName
var operator_id: StringName
var trigger: StringName
var conditions: Array[EvidenceCondition] = []
var observation_template: String
var request_template: String
var priority: int
var operator_cooldown_seconds: float
var global_cooldown_seconds: float
var dedupe_key: StringName


func _init(
	definition_id: StringName,
	definition_operator_id: StringName,
	definition_trigger: StringName,
	definition_conditions: Array[EvidenceCondition],
	definition_observation_template: String,
	definition_request_template: String,
	definition_priority: int,
	definition_operator_cooldown_seconds: float,
	definition_global_cooldown_seconds: float,
	definition_dedupe_key: StringName
) -> void:
	id = definition_id
	operator_id = definition_operator_id
	trigger = definition_trigger
	conditions = definition_conditions
	observation_template = definition_observation_template
	request_template = definition_request_template
	priority = definition_priority
	operator_cooldown_seconds = definition_operator_cooldown_seconds
	global_cooldown_seconds = definition_global_cooldown_seconds
	dedupe_key = definition_dedupe_key
