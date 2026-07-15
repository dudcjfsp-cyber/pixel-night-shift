class_name CombatV2ResultViewData
extends RefCounted

var clear_time: float
var normal_failures: int
var boss_failures: int
var total_failures: int
var qa_rescues: int
var paid_redeploy_count: int
var emergency_spent_bits: float
var gross_bits: float
var net_bits: float
var operator_levels: Dictionary
var diagnosis_history: Array[String]
var patch_history: Array[String]
var appeals_shown: int
var appeals_accepted: int
var appeals_ignored: int
var appeals_unresolved: int


func _init(source: Dictionary) -> void:
	var required: PackedStringArray = [
		"clear_time", "normal_failures", "boss_failures", "total_failures", "qa_rescues",
		"paid_redeploy_count", "emergency_spent_bits", "gross_bits", "net_bits",
		"operator_levels", "diagnosis_history", "patch_history",
		"appeals_shown", "appeals_accepted", "appeals_ignored", "appeals_unresolved",
	]
	for key: String in required:
		assert(source.has(key), "Combat V2 result is missing '%s'" % key)
	clear_time = float(source["clear_time"])
	normal_failures = int(source["normal_failures"])
	boss_failures = int(source["boss_failures"])
	total_failures = int(source["total_failures"])
	qa_rescues = int(source["qa_rescues"])
	paid_redeploy_count = int(source["paid_redeploy_count"])
	emergency_spent_bits = float(source["emergency_spent_bits"])
	gross_bits = float(source["gross_bits"])
	net_bits = float(source["net_bits"])
	operator_levels = (source["operator_levels"] as Dictionary).duplicate(true)
	diagnosis_history = _string_array(source["diagnosis_history"] as Array)
	patch_history = _string_array(source["patch_history"] as Array)
	appeals_shown = int(source["appeals_shown"])
	appeals_accepted = int(source["appeals_accepted"])
	appeals_ignored = int(source["appeals_ignored"])
	appeals_unresolved = int(source["appeals_unresolved"])
	var errors := validation_errors()
	assert(errors.is_empty(), "Invalid Combat V2 result: %s" % "; ".join(errors))


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for pair: Array in [
		["clear_time", clear_time], ["emergency_spent_bits", emergency_spent_bits],
		["gross_bits", gross_bits], ["net_bits", net_bits],
	]:
		if not is_finite(float(pair[1])) or float(pair[1]) < 0.0:
			errors.append("%s must be a non-negative finite number" % pair[0])
	for pair: Array in [
		["normal_failures", normal_failures], ["boss_failures", boss_failures],
		["total_failures", total_failures], ["qa_rescues", qa_rescues],
		["paid_redeploy_count", paid_redeploy_count],
		["appeals_shown", appeals_shown], ["appeals_accepted", appeals_accepted],
		["appeals_ignored", appeals_ignored], ["appeals_unresolved", appeals_unresolved],
	]:
		if int(pair[1]) < 0:
			errors.append("%s cannot be negative" % pair[0])
	if total_failures != normal_failures + boss_failures:
		errors.append("total_failures must equal normal plus boss failures")
	if appeals_shown != appeals_accepted + appeals_ignored + appeals_unresolved:
		errors.append("appeal counters must partition appeals_shown")
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		var key := String(operator_id)
		if not operator_levels.has(key) or int(operator_levels[key]) < 1:
			errors.append("operator_levels.%s must be at least 1" % key)
	return errors


func _string_array(source: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in source:
		result.append(String(value))
	return result
