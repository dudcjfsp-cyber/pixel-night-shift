class_name OperatorAppealRules
extends RefCounted

const MAX_VISIBLE_APPEALS := 2
const EPSILON := 0.000001
const STABLE_OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]
const REPEATABLE_FAILURE_TRIGGERS: Array[StringName] = [
	&"normal_failure", &"boss_failure",
]


class AppealResult:
	extends RefCounted

	var rule_id: StringName
	var operator_id: StringName
	var trigger: StringName
	var observation: String
	var request: String
	var priority: int
	var dedupe_key: StringName


	func _init(definition: AppealDefinition) -> void:
		rule_id = definition.id
		operator_id = definition.operator_id
		trigger = definition.trigger
		observation = definition.observation_template
		request = definition.request_template
		priority = definition.priority
		dedupe_key = definition.dedupe_key


	func to_snapshot() -> Dictionary:
		return {
			"rule_id": String(rule_id),
			"operator_id": String(operator_id),
			"trigger": String(trigger),
			"observation": observation,
			"request": request,
		}


static func evaluate(
	catalog: AppealCatalog,
	trigger: StringName,
	visible_evidence: Dictionary,
	stage: int,
	now_seconds: float,
	seen_stage_dedupes: Dictionary,
	operator_ready_at: Dictionary,
	global_ready_at: float,
	ignore_cooldowns: bool = false
) -> Array[AppealResult]:
	assert(catalog != null, "Appeal evaluation requires validated content")
	assert(stage >= 1, "Appeal evaluation requires a positive stage")
	assert(is_finite(now_seconds) and now_seconds >= 0.0, "Appeal time must be finite and non-negative")
	assert(
		visible_evidence.has("unlocked_operator_ids")
		and visible_evidence["unlocked_operator_ids"] is Array,
		"Appeal evaluation requires player-visible unlocked operator IDs"
	)
	var unlocked_operator_ids := visible_evidence["unlocked_operator_ids"] as Array
	var candidates: Array[AppealResult] = []
	if not ignore_cooldowns and now_seconds + EPSILON < global_ready_at:
		return candidates
	for definition: AppealDefinition in catalog.definitions_for_trigger(trigger):
		if not unlocked_operator_ids.has(String(definition.operator_id)):
			continue
		_assert_required_evidence(definition, visible_evidence)
		if not _matches(definition, visible_evidence):
			continue
		var stage_dedupe := "%d:%s" % [stage, definition.dedupe_key]
		if (
			not REPEATABLE_FAILURE_TRIGGERS.has(trigger)
			and seen_stage_dedupes.has(stage_dedupe)
		):
			continue
		if (
			not ignore_cooldowns
			and now_seconds + EPSILON < float(operator_ready_at[definition.operator_id])
		):
			continue
		candidates.append(AppealResult.new(definition))
	candidates.sort_custom(_result_precedes)
	var selected: Array[AppealResult] = []
	var selected_operators: Dictionary = {}
	for candidate: AppealResult in candidates:
		if selected_operators.has(candidate.operator_id):
			continue
		selected.append(candidate)
		selected_operators[candidate.operator_id] = true
		if selected.size() == MAX_VISIBLE_APPEALS:
			break
	return selected


static func result_from_definition(definition: AppealDefinition) -> AppealResult:
	assert(definition != null, "Appeal result requires a known definition")
	return AppealResult.new(definition)


static func _assert_required_evidence(
	definition: AppealDefinition,
	visible_evidence: Dictionary
) -> void:
	for condition: AppealDefinition.EvidenceCondition in definition.conditions:
		assert(
			visible_evidence.has(condition.key),
			"Appeal '%s' requires missing visible evidence '%s'" % [definition.id, condition.key]
		)


static func _matches(definition: AppealDefinition, evidence: Dictionary) -> bool:
	for condition: AppealDefinition.EvidenceCondition in definition.conditions:
		if not _condition_matches(evidence[condition.key], condition):
			return false
	return true


static func _condition_matches(
	actual: Variant,
	condition: AppealDefinition.EvidenceCondition
) -> bool:
	match condition.operator:
		&"eq":
			return actual == condition.value
		&"ne":
			return actual != condition.value
		&"gt":
			return float(actual) > float(condition.value) + EPSILON
		&"gte":
			return float(actual) + EPSILON >= float(condition.value)
		&"lt":
			return float(actual) + EPSILON < float(condition.value)
		&"lte":
			return float(actual) <= float(condition.value) + EPSILON
	assert(false, "Validated appeal contains unsupported comparison: %s" % condition.operator)
	return false


static func _result_precedes(left: AppealResult, right: AppealResult) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	var left_rank := STABLE_OPERATOR_IDS.find(left.operator_id)
	var right_rank := STABLE_OPERATOR_IDS.find(right.operator_id)
	assert(left_rank >= 0 and right_rank >= 0, "Appeal result has unknown operator")
	if left_rank != right_rank:
		return left_rank < right_rank
	return String(left.rule_id) < String(right.rule_id)
