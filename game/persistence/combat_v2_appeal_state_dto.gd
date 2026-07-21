extends RefCounted

const MAX_DEDUPE_KEYS := 256
const MAX_EVENT_IDS := 64
const MAX_ACKNOWLEDGMENT_LENGTH := 200
const REQUIRED_KEYS: PackedStringArray = [
	"current_rule_ids", "shown_count", "accepted_count", "dismissed_count",
	"acknowledgment", "seen_stage_dedupes", "operator_ready_at", "global_ready_at",
	"processed_event_ids", "last_diagnosis_kind", "last_stage", "current_trigger_priority",
]
const OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]


static func default_state() -> Dictionary:
	return {
		"current_rule_ids": [],
		"shown_count": 0,
		"accepted_count": 0,
		"dismissed_count": 0,
		"acknowledgment": "",
		"seen_stage_dedupes": [],
		"operator_ready_at": {
			"debugger": 0.0,
			"build_engineer": 0.0,
			"sprite_artist": 0.0,
			"qa_imp": 0.0,
		},
		"global_ready_at": 0.0,
		"processed_event_ids": [],
		"last_diagnosis_kind": "",
		"last_stage": 1,
		"current_trigger_priority": 0,
	}


static func validation_errors(data: Dictionary, catalog: AppealCatalog) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			errors.append("appeals.%s: required field is missing" % key)
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not REQUIRED_KEYS.has(String(raw_key)):
			errors.append("appeals.%s: unexpected field" % String(raw_key))
	if not errors.is_empty():
		return errors
	_validate_rule_ids(data["current_rule_ids"], catalog, errors)
	for key: String in ["shown_count", "accepted_count", "dismissed_count"]:
		_validate_non_negative_int(data[key], "appeals.%s" % key, errors)
	if (
		_is_integer_number(data["shown_count"])
		and _is_integer_number(data["accepted_count"])
		and _is_integer_number(data["dismissed_count"])
		and typeof(data["current_rule_ids"]) == TYPE_ARRAY
		and int(data["shown_count"]) != (
			int(data["accepted_count"])
			+ int(data["dismissed_count"])
			+ (data["current_rule_ids"] as Array).size()
		)
	):
		errors.append("appeals counters must partition shown appeals")
	if typeof(data["acknowledgment"]) != TYPE_STRING:
		errors.append("appeals.acknowledgment: string is required")
	elif String(data["acknowledgment"]).length() > MAX_ACKNOWLEDGMENT_LENGTH:
		errors.append("appeals.acknowledgment: text is too long")
	_validate_string_array(
		data["seen_stage_dedupes"], "appeals.seen_stage_dedupes", MAX_DEDUPE_KEYS, errors
	)
	_validate_ready_times(data["operator_ready_at"], errors)
	_validate_non_negative_number(data["global_ready_at"], "appeals.global_ready_at", errors)
	_validate_string_array(
		data["processed_event_ids"], "appeals.processed_event_ids", MAX_EVENT_IDS, errors
	)
	if typeof(data["last_diagnosis_kind"]) != TYPE_STRING:
		errors.append("appeals.last_diagnosis_kind: string is required")
	_validate_positive_int(data["last_stage"], "appeals.last_stage", errors)
	_validate_non_negative_int(
		data["current_trigger_priority"], "appeals.current_trigger_priority", errors
	)
	if _is_integer_number(data["current_trigger_priority"]) and typeof(data["current_rule_ids"]) == TYPE_ARRAY:
		var trigger_priority := int(data["current_trigger_priority"])
		var has_current := not (data["current_rule_ids"] as Array).is_empty()
		if has_current and trigger_priority <= 0:
			errors.append("appeals.current_trigger_priority must be positive while appeals are visible")
		if not has_current and trigger_priority != 0:
			errors.append("appeals.current_trigger_priority must be zero without visible appeals")
	return errors


static func _validate_rule_ids(
	value: Variant,
	catalog: AppealCatalog,
	errors: PackedStringArray
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("appeals.current_rule_ids: array is required")
		return
	var ids := value as Array
	if ids.size() > OperatorAppealRules.MAX_VISIBLE_APPEALS:
		errors.append("appeals.current_rule_ids: at most two entries are allowed")
	var seen_operators: Dictionary = {}
	var seen_rules: Dictionary = {}
	for index: int in ids.size():
		if typeof(ids[index]) != TYPE_STRING or String(ids[index]).is_empty():
			errors.append("appeals.current_rule_ids[%d]: non-empty string is required" % index)
			continue
		var rule_id := StringName(String(ids[index]))
		if catalog == null or not catalog.has_definition(rule_id):
			errors.append("appeals.current_rule_ids[%d]: unknown rule '%s'" % [index, rule_id])
			continue
		if seen_rules.has(rule_id):
			errors.append("appeals.current_rule_ids[%d]: duplicate rule '%s'" % [index, rule_id])
		seen_rules[rule_id] = true
		var operator_id := catalog.get_definition(rule_id).operator_id
		if seen_operators.has(operator_id):
			errors.append("appeals.current_rule_ids: duplicate operator '%s'" % operator_id)
		seen_operators[operator_id] = true


static func _validate_ready_times(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("appeals.operator_ready_at: object is required")
		return
	var times := value as Dictionary
	for operator_id: StringName in OPERATOR_IDS:
		var key := String(operator_id)
		if not times.has(key):
			errors.append("appeals.operator_ready_at.%s: required field is missing" % key)
			continue
		_validate_non_negative_number(
			times[key], "appeals.operator_ready_at.%s" % key, errors
		)
	for raw_key: Variant in times.keys():
		if typeof(raw_key) != TYPE_STRING or not OPERATOR_IDS.has(StringName(String(raw_key))):
			errors.append("appeals.operator_ready_at.%s: unexpected field" % String(raw_key))


static func _validate_string_array(
	value: Variant,
	context: String,
	maximum: int,
	errors: PackedStringArray
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: array is required" % context)
		return
	var values := value as Array
	if values.size() > maximum:
		errors.append("%s: exceeds %d entries" % [context, maximum])
	var seen: Dictionary = {}
	for index: int in values.size():
		if typeof(values[index]) != TYPE_STRING or String(values[index]).is_empty():
			errors.append("%s[%d]: non-empty string is required" % [context, index])
			continue
		if seen.has(values[index]):
			errors.append("%s[%d]: duplicate value" % [context, index])
		seen[values[index]] = true


static func _validate_non_negative_number(
	value: Variant,
	context: String,
	errors: PackedStringArray
) -> void:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
		errors.append("%s: non-negative finite number is required" % context)


static func _validate_non_negative_int(
	value: Variant,
	context: String,
	errors: PackedStringArray
) -> void:
	if not _is_integer_number(value) or int(value) < 0:
		errors.append("%s: non-negative integer is required" % context)


static func _validate_positive_int(
	value: Variant,
	context: String,
	errors: PackedStringArray
) -> void:
	if not _is_integer_number(value) or int(value) < 1:
		errors.append("%s: positive integer is required" % context)


static func _is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == float(int(value))
	)
