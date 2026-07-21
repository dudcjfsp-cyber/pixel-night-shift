class_name CombatV2StateDto
extends RefCounted

const ROOT_KEYS: PackedStringArray = [
	"progression", "operators", "timers", "attempt", "metrics", "stage_metrics", "recent_events",
]
const PROGRESSION_KEYS: PackedStringArray = [
	"stage", "highest_stage", "bits", "patch_notes", "run_count", "legacy_cache_level",
	"operator_levels", "unlocked_operator_ids", "discovered_patch_ids", "equipped_patch_ids",
	"unlocked_patch_slots", "enemy_index", "enemy_health", "boss_elapsed",
	"boss_recovery_count", "boss_recovered_health", "boss_debuff_applied",
	"boss_failure_count", "is_maintenance", "can_prestige", "free_patch_swaps",
	"status_message",
]
const OPERATOR_KEYS: PackedStringArray = [
	"id", "current_hp", "attack_remaining", "recovery_remaining", "recovery_source",
	"damage_dealt", "damage_taken", "down_count", "active_time", "down_time",
]
const TIMER_KEYS: PackedStringArray = [
	"enemy_attack_remaining", "enemy_pattern_step", "enemy_locked_target_id",
	"boss_special_remaining", "boss_rollback_remaining",
]
const ATTEMPT_KEYS: PackedStringArray = [
	"attempt_serial", "maintenance_remaining", "normal_failure_count", "last_failure_reason",
	"qa_rescue_consumed", "qa_recovery_target_id", "qa_rescue_count",
	"emergency_redeploy_used", "emergency_redeploy_target_id", "paid_redeploy_count",
	"emergency_spent_bits", "total_bits_earned",
]
const METRIC_KEYS: PackedStringArray = [
	"encounter_serial", "total_elapsed", "stage_elapsed", "total_enemies_defeated",
	"total_stages_cleared", "total_damage_taken", "total_down_count", "total_down_time",
	"total_boss_healed",
]
const STAGE_METRIC_KEYS: PackedStringArray = [
	"stage_damage_taken", "stage_down_count", "stage_down_time", "stage_boss_healed",
]
const RECOVERY_SOURCES: PackedStringArray = ["", "qa", "emergency"]
const FAILURE_REASONS: PackedStringArray = ["", "normal_all_down", "boss_all_down", "boss_timeout"]


class RestoreResult extends RefCounted:
	var state: CombatV2State
	var errors: PackedStringArray = PackedStringArray()


static func export_state(state: CombatV2State) -> Dictionary:
	assert(state != null, "Combat V2 state export requires a state")
	var progression := state.progression
	var operators: Array[Dictionary] = []
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		operators.append({
			"id": String(runtime.operator_id),
			"current_hp": runtime.current_hp,
			"attack_remaining": _encode_timer(runtime.attack_remaining),
			"recovery_remaining": runtime.recovery_remaining,
			"recovery_source": String(runtime.recovery_source),
			"damage_dealt": runtime.damage_dealt,
			"damage_taken": runtime.damage_taken,
			"down_count": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		})
	var events: Array[Dictionary] = []
	for event: Dictionary in state.recent_events:
		events.append(_export_event(event))
	return {
		"progression": {
			"stage": progression.stage,
			"highest_stage": progression.highest_stage,
			"bits": progression.bits,
			"patch_notes": progression.patch_notes,
			"run_count": progression.run_count,
			"legacy_cache_level": progression.legacy_cache_level,
			"operator_levels": _operator_levels_dictionary(progression.operator_levels),
			"unlocked_operator_ids": _string_array(progression.unlocked_operator_ids),
			"discovered_patch_ids": _string_array(progression.discovered_patch_ids),
			"equipped_patch_ids": _string_array(progression.equipped_patch_ids),
			"unlocked_patch_slots": progression.unlocked_patch_slots,
			"enemy_index": progression.enemy_index,
			"enemy_health": progression.enemy_health,
			"boss_elapsed": progression.boss_elapsed,
			"boss_recovery_count": progression.boss_recovery_count,
			"boss_recovered_health": progression.boss_recovered_health,
			"boss_debuff_applied": progression.boss_debuff_applied,
			"boss_failure_count": progression.boss_failure_count,
			"is_maintenance": progression.is_maintenance,
			"can_prestige": progression.can_prestige,
			"free_patch_swaps": progression.free_patch_swaps,
			"status_message": progression.status_message,
		},
		"operators": operators,
		"timers": {
			"enemy_attack_remaining": _encode_timer(state.enemy_attack_remaining),
			"enemy_pattern_step": state.enemy_pattern_step,
			"enemy_locked_target_id": String(state.enemy_locked_target_id),
			"boss_special_remaining": _encode_timer(state.boss_special_remaining),
			"boss_rollback_remaining": _encode_timer(state.boss_rollback_remaining),
		},
		"attempt": {
			"attempt_serial": state.attempt_serial,
			"maintenance_remaining": state.maintenance_remaining,
			"normal_failure_count": state.normal_failure_count,
			"last_failure_reason": String(state.last_failure_reason),
			"qa_rescue_consumed": state.qa_rescue_consumed,
			"qa_recovery_target_id": String(state.qa_recovery_target_id),
			"qa_rescue_count": state.qa_rescue_count,
			"emergency_redeploy_used": state.emergency_redeploy_used,
			"emergency_redeploy_target_id": String(state.emergency_redeploy_target_id),
			"paid_redeploy_count": state.paid_redeploy_count,
			"emergency_spent_bits": state.emergency_spent_bits,
			"total_bits_earned": state.total_bits_earned,
		},
		"metrics": {
			"encounter_serial": state.encounter_serial,
			"total_elapsed": state.total_elapsed,
			"stage_elapsed": state.stage_elapsed,
			"total_enemies_defeated": state.total_enemies_defeated,
			"total_stages_cleared": state.total_stages_cleared,
			"total_damage_taken": state.total_damage_taken,
			"total_down_count": state.total_down_count,
			"total_down_time": state.total_down_time,
			"total_boss_healed": state.total_boss_healed,
		},
		"stage_metrics": {
			"stage_damage_taken": state.stage_damage_taken,
			"stage_down_count": state.stage_down_count,
			"stage_down_time": state.stage_down_time,
			"stage_boss_healed": state.stage_boss_healed,
		},
		"recent_events": events,
	}


static func restore_candidate(data: Dictionary, catalog: CombatV2Catalog) -> RestoreResult:
	var result := RestoreResult.new()
	if catalog == null or catalog.base_catalog == null:
		result.errors.append("Combat V2 catalog is required")
		return result
	_validate_shape(data, catalog, result.errors)
	if not result.errors.is_empty():
		return result
	var candidate := _build_candidate(data)
	_validate_candidate(candidate, catalog, result.errors)
	if result.errors.is_empty():
		result.state = candidate
	return result


static func _validate_shape(
	data: Dictionary,
	catalog: CombatV2Catalog,
	errors: PackedStringArray
) -> void:
	_require_exact_keys(data, ROOT_KEYS, "state", errors)
	if not errors.is_empty():
		return
	for key: String in ["progression", "timers", "attempt", "metrics", "stage_metrics"]:
		if typeof(data[key]) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % key)
	if typeof(data["operators"]) != TYPE_ARRAY:
		errors.append("operators must be an array")
	if typeof(data["recent_events"]) != TYPE_ARRAY:
		errors.append("recent_events must be an array")
	if not errors.is_empty():
		return

	var progression := data["progression"] as Dictionary
	var timers := data["timers"] as Dictionary
	var attempt := data["attempt"] as Dictionary
	var metrics := data["metrics"] as Dictionary
	var stage_metrics := data["stage_metrics"] as Dictionary
	_require_exact_keys(progression, PROGRESSION_KEYS, "progression", errors)
	_require_exact_keys(timers, TIMER_KEYS, "timers", errors)
	_require_exact_keys(attempt, ATTEMPT_KEYS, "attempt", errors)
	_require_exact_keys(metrics, METRIC_KEYS, "metrics", errors)
	_require_exact_keys(stage_metrics, STAGE_METRIC_KEYS, "stage_metrics", errors)
	if not errors.is_empty():
		return

	for key: String in [
		"stage", "highest_stage", "patch_notes", "run_count", "legacy_cache_level",
		"unlocked_patch_slots", "enemy_index", "boss_recovery_count", "boss_failure_count",
		"free_patch_swaps",
	]:
		_require_nonnegative_int(progression, key, "progression", errors)
	for key: String in ["bits", "enemy_health", "boss_elapsed", "boss_recovered_health"]:
		_require_nonnegative_number(progression, key, "progression", errors)
	for key: String in ["boss_debuff_applied", "is_maintenance", "can_prestige"]:
		_require_bool(progression, key, "progression", errors)
	_require_string(progression, "status_message", "progression", errors)
	if typeof(progression["operator_levels"]) != TYPE_DICTIONARY:
		errors.append("progression.operator_levels must be an object")
	for key: String in ["unlocked_operator_ids", "discovered_patch_ids", "equipped_patch_ids"]:
		_validate_string_array(progression[key], "progression.%s" % key, errors)

	var operators := data["operators"] as Array
	if operators.size() != CombatV2Catalog.STABLE_OPERATOR_IDS.size():
		errors.append("operators must contain exactly four stable operator rows")
	for index: int in range(operators.size()):
		if typeof(operators[index]) != TYPE_DICTIONARY:
			errors.append("operators[%d] must be an object" % index)
			continue
		var row := operators[index] as Dictionary
		var row_error_count := errors.size()
		_require_exact_keys(row, OPERATOR_KEYS, "operators[%d]" % index, errors)
		if errors.size() != row_error_count:
			continue
		_require_string(row, "id", "operators[%d]" % index, errors)
		for key: String in [
			"current_hp", "recovery_remaining", "damage_dealt", "damage_taken",
			"active_time", "down_time",
		]:
			_require_nonnegative_number(row, key, "operators[%d]" % index, errors)
		_require_timer(row, "attack_remaining", "operators[%d]" % index, errors)
		_require_nonnegative_int(row, "down_count", "operators[%d]" % index, errors)
		_require_string(row, "recovery_source", "operators[%d]" % index, errors)

	for key: String in ["enemy_attack_remaining", "boss_special_remaining", "boss_rollback_remaining"]:
		_require_timer(timers, key, "timers", errors)
	_require_nonnegative_int(timers, "enemy_pattern_step", "timers", errors)
	_require_string(timers, "enemy_locked_target_id", "timers", errors)

	for key: String in [
		"attempt_serial", "normal_failure_count", "qa_rescue_count", "paid_redeploy_count",
	]:
		_require_nonnegative_int(attempt, key, "attempt", errors)
	for key: String in ["maintenance_remaining", "emergency_spent_bits", "total_bits_earned"]:
		_require_nonnegative_number(attempt, key, "attempt", errors)
	for key: String in ["qa_rescue_consumed", "emergency_redeploy_used"]:
		_require_bool(attempt, key, "attempt", errors)
	for key: String in [
		"last_failure_reason", "qa_recovery_target_id", "emergency_redeploy_target_id",
	]:
		_require_string(attempt, key, "attempt", errors)

	for key: String in METRIC_KEYS:
		if key in ["encounter_serial", "total_enemies_defeated", "total_stages_cleared", "total_down_count"]:
			_require_nonnegative_int(metrics, key, "metrics", errors)
		else:
			_require_nonnegative_number(metrics, key, "metrics", errors)
	for key: String in STAGE_METRIC_KEYS:
		if key == "stage_down_count":
			_require_nonnegative_int(stage_metrics, key, "stage_metrics", errors)
		else:
			_require_nonnegative_number(stage_metrics, key, "stage_metrics", errors)

	var events := data["recent_events"] as Array
	if events.size() > CombatV2State.MAX_RECENT_EVENTS:
		errors.append("recent_events exceeds the bounded event history")
	for index: int in range(events.size()):
		if typeof(events[index]) != TYPE_DICTIONARY:
			errors.append("recent_events[%d] must be an object" % index)
			continue
		_validate_event(events[index] as Dictionary, index, errors)

	_validate_content_ids(progression, operators, timers, attempt, catalog, errors)


static func _validate_content_ids(
	progression: Dictionary,
	operators: Array,
	timers: Dictionary,
	attempt: Dictionary,
	catalog: CombatV2Catalog,
	errors: PackedStringArray
) -> void:
	if typeof(progression["operator_levels"]) == TYPE_DICTIONARY:
		var levels := progression["operator_levels"] as Dictionary
		for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
			var key := String(operator_id)
			if not levels.has(key) or not _is_integer_number(levels[key]) or int(levels[key]) < 0:
				errors.append("progression.operator_levels.%s must be a non-negative integer" % key)
		for raw_key: Variant in levels.keys():
			if not CombatV2Catalog.STABLE_OPERATOR_IDS.has(StringName(String(raw_key))):
				errors.append("progression.operator_levels has unknown id '%s'" % String(raw_key))
	for key: String in ["unlocked_operator_ids", "discovered_patch_ids", "equipped_patch_ids"]:
		if typeof(progression[key]) != TYPE_ARRAY:
			continue
		var seen: Dictionary = {}
		for raw_id: Variant in progression[key] as Array:
			var id := StringName(String(raw_id))
			if id == &"" and key == "equipped_patch_ids":
				continue
			var valid := (
				CombatV2Catalog.STABLE_OPERATOR_IDS.has(id)
				if key == "unlocked_operator_ids"
				else catalog.base_catalog.has_patch(id)
			)
			if not valid:
				errors.append("progression.%s has unknown id '%s'" % [key, id])
			if seen.has(id):
				errors.append("progression.%s has duplicate id '%s'" % [key, id])
			seen[id] = true
	if typeof(progression["equipped_patch_ids"]) == TYPE_ARRAY and (progression["equipped_patch_ids"] as Array).size() != 3:
		errors.append("progression.equipped_patch_ids must contain three slots")
	for index: int in range(mini(operators.size(), CombatV2Catalog.STABLE_OPERATOR_IDS.size())):
		if typeof(operators[index]) != TYPE_DICTIONARY:
			continue
		var row := operators[index] as Dictionary
		if StringName(String(row.get("id", ""))) != CombatV2Catalog.STABLE_OPERATOR_IDS[index]:
			errors.append("operators[%d].id violates stable operator ordering" % index)
		if row.has("recovery_source") and not RECOVERY_SOURCES.has(String(row["recovery_source"])):
			errors.append("operators[%d].recovery_source is unknown" % index)
	var valid_operator_ids := CombatV2Catalog.STABLE_OPERATOR_IDS.duplicate()
	valid_operator_ids.append(&"")
	for pair: Array in [
		["timers.enemy_locked_target_id", timers.get("enemy_locked_target_id", "")],
		["attempt.qa_recovery_target_id", attempt.get("qa_recovery_target_id", "")],
		["attempt.emergency_redeploy_target_id", attempt.get("emergency_redeploy_target_id", "")],
	]:
		if not valid_operator_ids.has(StringName(String(pair[1]))):
			errors.append("%s is an unknown operator id" % pair[0])
	if attempt.has("last_failure_reason") and not FAILURE_REASONS.has(String(attempt["last_failure_reason"])):
		errors.append("attempt.last_failure_reason is unknown")


static func _validate_event(event: Dictionary, index: int, errors: PackedStringArray) -> void:
	var context := "recent_events[%d]" % index
	for key: String in ["kind", "time", "stage", "enemy_index", "encounter_serial"]:
		if not event.has(key):
			errors.append("%s.%s is required" % [context, key])
	if not event.has_all(["kind", "time", "stage", "enemy_index", "encounter_serial"]):
		return
	if typeof(event["kind"]) != TYPE_STRING or String(event["kind"]).is_empty():
		errors.append("%s.kind must be a non-empty string" % context)
	if not _is_finite_number(event["time"]) or float(event["time"]) < 0.0:
		errors.append("%s.time must be a non-negative finite number" % context)
	for key: String in ["stage", "enemy_index", "encounter_serial"]:
		if not _is_integer_number(event[key]) or int(event[key]) < 0:
			errors.append("%s.%s must be a non-negative integer" % [context, key])
	for raw_key: Variant in event.keys():
		if typeof(raw_key) != TYPE_STRING:
			errors.append("%s event keys must be strings" % context)
			continue
		var key := String(raw_key)
		var value: Variant = event[raw_key]
		if key in ["targets", "failure_count", "attempt_serial"]:
			if not _is_integer_number(value) or int(value) < 0:
				errors.append("%s.%s must be a non-negative integer" % [context, key])
		elif typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			if not _is_finite_number(value):
				errors.append("%s.%s must be finite" % [context, key])
		elif typeof(value) not in [TYPE_STRING, TYPE_BOOL]:
			errors.append("%s.%s must be a JSON scalar" % [context, key])


static func _build_candidate(data: Dictionary) -> CombatV2State:
	var candidate := CombatV2State.new()
	var progression := data["progression"] as Dictionary
	var p := GameState.new()
	p.stage = int(progression["stage"])
	p.highest_stage = int(progression["highest_stage"])
	p.bits = float(progression["bits"])
	p.patch_notes = int(progression["patch_notes"])
	p.run_count = int(progression["run_count"])
	p.legacy_cache_level = int(progression["legacy_cache_level"])
	for raw_key: Variant in (progression["operator_levels"] as Dictionary).keys():
		p.operator_levels[StringName(String(raw_key))] = int(progression["operator_levels"][raw_key])
	p.unlocked_operator_ids = _string_name_array(progression["unlocked_operator_ids"] as Array)
	p.discovered_patch_ids = _string_name_array(progression["discovered_patch_ids"] as Array)
	p.equipped_patch_ids = _string_name_array(progression["equipped_patch_ids"] as Array)
	p.unlocked_patch_slots = int(progression["unlocked_patch_slots"])
	p.enemy_index = int(progression["enemy_index"])
	p.enemy_health = float(progression["enemy_health"])
	p.boss_elapsed = float(progression["boss_elapsed"])
	p.boss_recovery_count = int(progression["boss_recovery_count"])
	p.boss_recovered_health = float(progression["boss_recovered_health"])
	p.boss_debuff_applied = bool(progression["boss_debuff_applied"])
	p.boss_failure_count = int(progression["boss_failure_count"])
	p.is_maintenance = bool(progression["is_maintenance"])
	p.can_prestige = bool(progression["can_prestige"])
	p.free_patch_swaps = int(progression["free_patch_swaps"])
	p.status_message = String(progression["status_message"])
	candidate.progression = p

	for raw_row: Variant in data["operators"] as Array:
		var row := raw_row as Dictionary
		var runtime := CombatV2State.OperatorRuntime.new(StringName(String(row["id"])))
		runtime.current_hp = float(row["current_hp"])
		runtime.attack_remaining = _decode_timer(float(row["attack_remaining"]))
		runtime.recovery_remaining = float(row["recovery_remaining"])
		runtime.recovery_source = StringName(String(row["recovery_source"]))
		runtime.damage_dealt = float(row["damage_dealt"])
		runtime.damage_taken = float(row["damage_taken"])
		runtime.down_count = int(row["down_count"])
		runtime.active_time = float(row["active_time"])
		runtime.down_time = float(row["down_time"])
		candidate.operators.append(runtime)

	var timers := data["timers"] as Dictionary
	candidate.enemy_attack_remaining = _decode_timer(float(timers["enemy_attack_remaining"]))
	candidate.enemy_pattern_step = int(timers["enemy_pattern_step"])
	candidate.enemy_locked_target_id = StringName(String(timers["enemy_locked_target_id"]))
	candidate.boss_special_remaining = _decode_timer(float(timers["boss_special_remaining"]))
	candidate.boss_rollback_remaining = _decode_timer(float(timers["boss_rollback_remaining"]))

	var attempt := data["attempt"] as Dictionary
	candidate.attempt_serial = int(attempt["attempt_serial"])
	candidate.maintenance_remaining = float(attempt["maintenance_remaining"])
	candidate.normal_failure_count = int(attempt["normal_failure_count"])
	candidate.last_failure_reason = StringName(String(attempt["last_failure_reason"]))
	candidate.qa_rescue_consumed = bool(attempt["qa_rescue_consumed"])
	candidate.qa_recovery_target_id = StringName(String(attempt["qa_recovery_target_id"]))
	candidate.qa_rescue_count = int(attempt["qa_rescue_count"])
	candidate.emergency_redeploy_used = bool(attempt["emergency_redeploy_used"])
	candidate.emergency_redeploy_target_id = StringName(String(attempt["emergency_redeploy_target_id"]))
	candidate.paid_redeploy_count = int(attempt["paid_redeploy_count"])
	candidate.emergency_spent_bits = float(attempt["emergency_spent_bits"])
	candidate.total_bits_earned = float(attempt["total_bits_earned"])

	var metrics := data["metrics"] as Dictionary
	candidate.encounter_serial = int(metrics["encounter_serial"])
	candidate.total_elapsed = float(metrics["total_elapsed"])
	candidate.stage_elapsed = float(metrics["stage_elapsed"])
	candidate.total_enemies_defeated = int(metrics["total_enemies_defeated"])
	candidate.total_stages_cleared = int(metrics["total_stages_cleared"])
	candidate.total_damage_taken = float(metrics["total_damage_taken"])
	candidate.total_down_count = int(metrics["total_down_count"])
	candidate.total_down_time = float(metrics["total_down_time"])
	candidate.total_boss_healed = float(metrics["total_boss_healed"])
	var stage_metrics := data["stage_metrics"] as Dictionary
	candidate.stage_damage_taken = float(stage_metrics["stage_damage_taken"])
	candidate.stage_down_count = int(stage_metrics["stage_down_count"])
	candidate.stage_down_time = float(stage_metrics["stage_down_time"])
	candidate.stage_boss_healed = float(stage_metrics["stage_boss_healed"])
	for raw_event: Variant in data["recent_events"] as Array:
		candidate.recent_events.append(_restore_event(raw_event as Dictionary))
	return candidate


static func _validate_candidate(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	errors: PackedStringArray
) -> void:
	var p := state.progression
	if p.stage < 1 or p.stage > catalog.balance.max_stage:
		errors.append("progression.stage must stay within Combat V2 stages 1..10")
	if p.highest_stage < p.stage or p.highest_stage > catalog.balance.max_stage:
		errors.append("progression.highest_stage is outside the Combat V2 range")
	if p.enemy_index < 1 or p.enemy_index > catalog.balance.normal_enemy_count:
		errors.append("progression.enemy_index is outside 1..3")
	if p.unlocked_patch_slots < 0 or p.unlocked_patch_slots > 3:
		errors.append("progression.unlocked_patch_slots is outside 0..3")
	if state.attempt_serial < 1 or state.encounter_serial < 1:
		errors.append("attempt and encounter serials must be positive")
	if p.is_maintenance != (state.maintenance_remaining > 0.0):
		errors.append("maintenance flag and countdown disagree")
	if p.can_prestige and (p.stage != catalog.balance.max_stage or p.enemy_health > 0.0):
		errors.append("completed Combat V2 state must be stage 10 with zero enemy HP")
	if not p.can_prestige:
		var enemy_max := CombatV2Forecast.enemy_max_hp(state, catalog)
		if p.enemy_health <= 0.0 or p.enemy_health > enemy_max + 0.000001:
			errors.append("progression.enemy_health is outside the current enemy range")
	if p.stage == catalog.balance.max_stage and p.enemy_index != 1:
		errors.append("Watchdog stage must use enemy index 1")

	var qa_targets := 0
	var emergency_targets := 0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		var unlocked := p.is_operator_unlocked(runtime.operator_id)
		var max_hp := CombatV2Simulator.operator_max_hp(state, catalog, runtime.operator_id) if unlocked else 0.0
		if runtime.current_hp > max_hp + 0.000001:
			errors.append("operator '%s' HP exceeds max HP" % runtime.operator_id)
		if not unlocked and runtime.current_hp > 0.0:
			errors.append("locked operator '%s' cannot have HP" % runtime.operator_id)
		if runtime.current_hp > 0.0:
			if is_inf(runtime.attack_remaining) or runtime.recovery_source != &"" or runtime.recovery_remaining > 0.0:
				errors.append("active operator '%s' has inconsistent timers" % runtime.operator_id)
		else:
			if not is_inf(runtime.attack_remaining):
				errors.append("down operator '%s' must have no scheduled attack" % runtime.operator_id)
			if runtime.recovery_source == &"" and runtime.recovery_remaining > 0.0:
				errors.append("down operator '%s' has a timer without a recovery source" % runtime.operator_id)
			if runtime.recovery_source != &"" and runtime.recovery_remaining <= 0.0:
				errors.append("down operator '%s' has a recovery source without a timer" % runtime.operator_id)
		if runtime.recovery_source == &"qa":
			qa_targets += 1
			if state.qa_recovery_target_id != runtime.operator_id:
				errors.append("QA recovery target id does not match the operator timer")
		elif runtime.recovery_source == &"emergency":
			emergency_targets += 1
			if state.emergency_redeploy_target_id != runtime.operator_id:
				errors.append("emergency recovery target id does not match the operator timer")
	if qa_targets > 1 or emergency_targets > 1:
		errors.append("only one target per recovery source may be scheduled")
	if (state.qa_recovery_target_id == &"") != (qa_targets == 0):
		errors.append("QA recovery target summary is inconsistent")
	if (state.emergency_redeploy_target_id == &"") != (emergency_targets == 0):
		errors.append("emergency recovery target summary is inconsistent")
	if qa_targets > 0 and not state.qa_rescue_consumed:
		errors.append("scheduled QA rescue must consume the stage allowance")
	if emergency_targets > 0 and not state.emergency_redeploy_used:
		errors.append("scheduled emergency redeploy must consume the attempt allowance")


static func _require_exact_keys(
	data: Dictionary,
	expected: PackedStringArray,
	context: String,
	errors: PackedStringArray
) -> void:
	for key: String in expected:
		if not data.has(key):
			errors.append("%s.%s is required" % [context, key])
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not expected.has(String(raw_key)):
			errors.append("%s.%s is unexpected" % [context, String(raw_key)])


static func _require_nonnegative_int(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_integer_number(data[key]) or int(data[key]) < 0:
		errors.append("%s.%s must be a non-negative integer" % [context, key])


static func _require_nonnegative_number(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_finite_number(data[key]) or float(data[key]) < 0.0:
		errors.append("%s.%s must be a non-negative finite number" % [context, key])


static func _require_timer(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_finite_number(data[key]):
		errors.append("%s.%s must be a finite timer" % [context, key])
		return
	var value := float(data[key])
	if value < 0.0 and not is_equal_approx(value, -1.0):
		errors.append("%s.%s must be -1 or non-negative" % [context, key])


static func _require_bool(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or typeof(data[key]) != TYPE_BOOL:
		errors.append("%s.%s must be boolean" % [context, key])


static func _require_string(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING:
		errors.append("%s.%s must be a string" % [context, key])


static func _validate_string_array(value: Variant, context: String, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array" % context)
		return
	for index: int in range((value as Array).size()):
		if typeof((value as Array)[index]) != TYPE_STRING:
			errors.append("%s[%d] must be a string" % [context, index])


static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == float(int(numeric))


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _encode_timer(value: float) -> float:
	return -1.0 if is_inf(value) else value


static func _decode_timer(value: float) -> float:
	return INF if is_equal_approx(value, -1.0) else value


static func _operator_levels_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		result[String(operator_id)] = int(source.get(operator_id, 0))
	return result


static func _string_array(source: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in source:
		result.append(String(value))
	return result


static func _string_name_array(source: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in source:
		result.append(StringName(String(value)))
	return result


static func _export_event(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in source.keys():
		var value: Variant = source[raw_key]
		result[String(raw_key)] = String(value) if value is StringName else value
	return result


static func _restore_event(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	for key: String in [
		"stage", "enemy_index", "encounter_serial", "targets", "failure_count", "attempt_serial",
	]:
		if result.has(key):
			result[key] = int(result[key])
	return result
