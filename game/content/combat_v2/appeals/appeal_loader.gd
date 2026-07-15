class_name AppealLoader
extends RefCounted

const CONTENT_PATH := "res://game/content/combat_v2/appeals/appeals.json"
const ROOT_KEYS: Array[String] = ["schema_version", "rules"]
const RULE_KEYS: Array[String] = [
	"id", "operator_id", "trigger", "conditions", "observation_template",
	"request_template", "priority", "operator_cooldown_seconds",
	"global_cooldown_seconds", "dedupe_key",
]
const CONDITION_KEYS: Array[String] = ["key", "op", "value"]
const SUPPORTED_TRIGGERS: Array[StringName] = [
	&"diagnosis_changed", &"operator_down", &"normal_failure", &"boss_failure",
	&"qa_rescue_cancelled", &"qa_rescue_succeeded", &"emergency_redeploy_used",
	&"watchdog_rollback", &"watchdog_kill_signal",
]
const SUPPORTED_EVIDENCE_KEYS: Array[StringName] = [
	&"diagnosis_kind", &"stage", &"is_boss", &"current_downs", &"failure_count",
	&"normal_failure_count", &"boss_failure_count", &"last_failure_reason",
	&"maintenance", &"emergency_available", &"emergency_affordable",
	&"emergency_remaining", &"qa_rescue_available", &"qa_rescue_pending",
	&"qa_rescue_count", &"paid_redeploy_count", &"enemy_hp_ratio", &"boss_time_left",
	&"next_action", &"unlocked_operator_count", &"event_operator_id",
	&"event_target_id", &"event_source", &"event_attack", &"event_reason",
]
const NUMERIC_EVIDENCE_KEYS: Array[StringName] = [
	&"stage", &"current_downs", &"failure_count", &"normal_failure_count",
	&"boss_failure_count", &"emergency_remaining", &"qa_rescue_count",
	&"paid_redeploy_count", &"enemy_hp_ratio", &"boss_time_left",
	&"unlocked_operator_count",
]
const BOOLEAN_EVIDENCE_KEYS: Array[StringName] = [
	&"is_boss", &"maintenance", &"emergency_available", &"emergency_affordable",
	&"qa_rescue_available", &"qa_rescue_pending",
]
const SUPPORTED_OPERATORS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]
const SUPPORTED_COMPARISONS: Array[StringName] = [&"eq", &"ne", &"gt", &"gte", &"lt", &"lte"]
const FORBIDDEN_CLAIMS: PackedStringArray = ["최적", "정답", "확실히", "반드시 승리"]


class LoadResult:
	extends RefCounted

	var catalog: AppealCatalog
	var errors: PackedStringArray = PackedStringArray()


	func is_valid() -> bool:
		return catalog != null and errors.is_empty()


static func load_default() -> LoadResult:
	var result := LoadResult.new()
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		result.errors.append("Unable to read Combat V2 appeal content: %s" % CONTENT_PATH)
		return result
	return load_from_json(file.get_as_text())


static func load_from_json(content_json: String) -> LoadResult:
	var result := LoadResult.new()
	var parser := JSON.new()
	var parse_error := parser.parse(content_json)
	if parse_error != OK:
		result.errors.append(
			"appeals: JSON parse error at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return result
	if typeof(parser.data) != TYPE_DICTIONARY:
		result.errors.append("appeals: root must be an object")
		return result
	var root := parser.data as Dictionary
	_validate_keys(root, ROOT_KEYS, "appeals", result.errors)
	if not result.errors.is_empty():
		return result
	if not _is_integer(root["schema_version"]) or int(root["schema_version"]) != 1:
		result.errors.append("appeals.schema_version: must equal integer 1")
	if typeof(root["rules"]) != TYPE_ARRAY:
		result.errors.append("appeals.rules: array is required")
		return result

	var catalog := AppealCatalog.new()
	var seen_ids: Dictionary = {}
	for index: int in (root["rules"] as Array).size():
		var raw_rule: Variant = (root["rules"] as Array)[index]
		var context := "appeals.rules[%d]" % index
		if typeof(raw_rule) != TYPE_DICTIONARY:
			result.errors.append("%s: object is required" % context)
			continue
		var definition := _parse_definition(raw_rule as Dictionary, context, result.errors)
		if definition == null:
			continue
		if seen_ids.has(definition.id):
			result.errors.append("%s.id: duplicate id '%s'" % [context, definition.id])
			continue
		seen_ids[definition.id] = true
		catalog.definitions.append(definition)
	_validate_coverage(catalog, result.errors)
	if not result.errors.is_empty():
		return result
	catalog.build_indexes()
	result.catalog = catalog
	return result


static func _parse_definition(
	data: Dictionary,
	context: String,
	errors: PackedStringArray
) -> AppealDefinition:
	var start_error_count := errors.size()
	_validate_keys(data, RULE_KEYS, context, errors)
	var id_text := _required_string(data, "id", context, errors)
	var operator_text := _required_string(data, "operator_id", context, errors)
	var trigger_text := _required_string(data, "trigger", context, errors)
	var observation := _required_string(data, "observation_template", context, errors)
	var request := _required_string(data, "request_template", context, errors)
	var dedupe_text := _required_string(data, "dedupe_key", context, errors)
	var operator_id := StringName(operator_text)
	var trigger := StringName(trigger_text)
	if not SUPPORTED_OPERATORS.has(operator_id):
		errors.append("%s.operator_id: unknown operator '%s'" % [context, operator_text])
	if not SUPPORTED_TRIGGERS.has(trigger):
		errors.append("%s.trigger: unknown trigger '%s'" % [context, trigger_text])
	_validate_claim_text(observation, "%s.observation_template" % context, errors)
	_validate_claim_text(request, "%s.request_template" % context, errors)
	var priority := _required_non_negative_int(data, "priority", context, errors)
	var operator_cooldown := _required_non_negative_float(
		data, "operator_cooldown_seconds", context, errors
	)
	var global_cooldown := _required_non_negative_float(
		data, "global_cooldown_seconds", context, errors
	)
	var conditions: Array[AppealDefinition.EvidenceCondition] = []
	if not data.has("conditions") or typeof(data["conditions"]) != TYPE_ARRAY:
		errors.append("%s.conditions: non-empty array is required" % context)
	else:
		var raw_conditions := data["conditions"] as Array
		if raw_conditions.is_empty():
			errors.append("%s.conditions: at least one visible evidence predicate is required" % context)
		for condition_index: int in raw_conditions.size():
			var condition := _parse_condition(
				raw_conditions[condition_index],
				"%s.conditions[%d]" % [context, condition_index],
				errors
			)
			if condition != null:
				conditions.append(condition)
	if errors.size() != start_error_count:
		return null
	return AppealDefinition.new(
		StringName(id_text), operator_id, trigger, conditions, observation, request,
		priority, operator_cooldown, global_cooldown, StringName(dedupe_text)
	)


static func _parse_condition(
	raw_condition: Variant,
	context: String,
	errors: PackedStringArray
) -> AppealDefinition.EvidenceCondition:
	if typeof(raw_condition) != TYPE_DICTIONARY:
		errors.append("%s: object is required" % context)
		return null
	var data := raw_condition as Dictionary
	var start_error_count := errors.size()
	_validate_keys(data, CONDITION_KEYS, context, errors)
	var key_text := _required_string(data, "key", context, errors)
	var comparison_text := _required_string(data, "op", context, errors)
	var key := StringName(key_text)
	var comparison := StringName(comparison_text)
	if not SUPPORTED_EVIDENCE_KEYS.has(key):
		errors.append("%s.key: unsupported visible evidence '%s'" % [context, key_text])
	if not SUPPORTED_COMPARISONS.has(comparison):
		errors.append("%s.op: unsupported comparison '%s'" % [context, comparison_text])
	if not data.has("value") or typeof(data["value"]) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		errors.append("%s.value: boolean, finite number, or string is required" % context)
	elif typeof(data["value"]) == TYPE_FLOAT and not is_finite(float(data["value"])):
		errors.append("%s.value: finite threshold is required" % context)
	elif NUMERIC_EVIDENCE_KEYS.has(key) and not _is_finite_number(data["value"]):
		errors.append("%s.value: numeric evidence requires a finite numeric threshold" % context)
	elif BOOLEAN_EVIDENCE_KEYS.has(key) and typeof(data["value"]) != TYPE_BOOL:
		errors.append("%s.value: boolean evidence requires a boolean threshold" % context)
	elif (
		not NUMERIC_EVIDENCE_KEYS.has(key)
		and not BOOLEAN_EVIDENCE_KEYS.has(key)
		and typeof(data["value"]) != TYPE_STRING
	):
		errors.append("%s.value: string evidence requires a string threshold" % context)
	elif comparison in [&"gt", &"gte", &"lt", &"lte"] and not NUMERIC_EVIDENCE_KEYS.has(key):
		errors.append("%s.op: ordered comparisons require numeric evidence" % context)
	if errors.size() != start_error_count:
		return null
	return AppealDefinition.EvidenceCondition.new(key, comparison, data["value"])


static func _validate_coverage(catalog: AppealCatalog, errors: PackedStringArray) -> void:
	if catalog.definitions.size() < 20 or catalog.definitions.size() > 24:
		errors.append("appeals.rules: 20 to 24 definitions are required")
	var counts: Dictionary = {}
	for operator_id: StringName in SUPPORTED_OPERATORS:
		counts[operator_id] = 0
	for definition: AppealDefinition in catalog.definitions:
		counts[definition.operator_id] = int(counts[definition.operator_id]) + 1
	for operator_id: StringName in SUPPORTED_OPERATORS:
		if int(counts[operator_id]) < 4:
			errors.append("appeals.rules: operator '%s' requires at least four definitions" % operator_id)


static func _validate_claim_text(text: String, context: String, errors: PackedStringArray) -> void:
	for forbidden: String in FORBIDDEN_CLAIMS:
		if forbidden in text:
			errors.append("%s: forbidden certainty claim '%s'" % [context, forbidden])
	if "{" in text or "}" in text:
		errors.append("%s: runtime interpolation placeholders are not supported" % context)


static func _validate_keys(
	data: Dictionary,
	expected: Array[String],
	context: String,
	errors: PackedStringArray
) -> void:
	for key: String in expected:
		if not data.has(key):
			errors.append("%s.%s: required field is missing" % [context, key])
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not expected.has(String(raw_key)):
			errors.append("%s.%s: unknown field" % [context, String(raw_key)])


static func _required_string(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> String:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING:
		errors.append("%s.%s: non-empty string is required" % [context, key])
		return ""
	var value := String(data[key]).strip_edges()
	if value.is_empty():
		errors.append("%s.%s: non-empty string is required" % [context, key])
	return value


static func _required_non_negative_int(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> int:
	if not data.has(key) or not _is_integer(data[key]) or int(data[key]) < 0:
		errors.append("%s.%s: non-negative integer is required" % [context, key])
		return 0
	return int(data[key])


static func _required_non_negative_float(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> float:
	if not data.has(key) or not _is_finite_number(data[key]) or float(data[key]) < 0.0:
		errors.append("%s.%s: non-negative finite number is required" % [context, key])
		return 0.0
	return float(data[key])


static func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == float(int(value))


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
