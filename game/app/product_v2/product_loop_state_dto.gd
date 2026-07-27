class_name ProductLoopStateDto
extends RefCounted

const ProductLoopState := preload(
	"res://game/domain/product_v2/product_loop_state.gd"
)
const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)

const MAX_SAFE_INT := 2_000_000_000
const MAX_JSON_SAFE_INTEGER := 9_007_199_254_740_991
const MAX_UNIX_TIME := 9_000_000_000_000_000
const STATE_KEYS: PackedStringArray = [
	"phase",
	"version",
	"bits",
	"active_shift_index",
	"result_serial",
	"playback_speed",
	"shift_records",
	"shift_2_unlocked",
	"version_update_available",
	"last_result",
	"report_key",
	"report_rows",
	"report_read",
	"patch_notes",
	"legacy_cache_level",
	"operator_levels",
	"unlocked_operator_ids",
	"discovered_patch_ids",
	"unlocked_patch_slots",
	"equipped_patch_ids",
	"day_income_anchor_unix",
	"day_income_remainder_seconds",
	"last_day_income_elapsed_seconds",
	"last_day_income_bits",
	"day_income_report_available",
	"migration_source_schema",
	"migration_source_run_count",
	"migration_saved_at_unix",
]
const SHIFT_RECORD_KEYS: PackedStringArray = [
	"shift_index",
	"attempts",
	"highest_completed_waves",
	"best_stars",
	"claimed_reward_stars",
	"boss_encountered",
]
const RESULT_KEYS: PackedStringArray = [
	"key",
	"version",
	"shift_index",
	"success",
	"terminal_reason",
	"completed_waves",
	"stars",
	"stability",
	"max_stability",
	"previous_best_stars",
	"best_stars",
	"first_reward_bits",
	"new_reward_stars",
	"base_salary",
	"completion_reward",
	"boss_reward",
	"stability_reward",
	"performance_raw",
	"bit_multiplier",
	"performance_reward",
	"total_reward",
	"bits_before",
	"bits_after",
	"shift_2_unlocked_now",
	"version_update_available_now",
	"new_unlocks",
	"report_key",
	"boss",
	"combat_metrics",
	"down_evidence",
	"qa_outcome",
]
const NEW_UNLOCK_KEYS: PackedStringArray = [
	"operator_ids", "patch_ids", "patch_slots",
]
const REPORT_ROW_KEYS: PackedStringArray = [
	"kind",
	"operator_id",
	"operator_name",
	"summary",
	"primary_value",
	"primary_max",
	"count",
	"seconds",
]
const BOSS_KEYS: PackedStringArray = [
	"id",
	"name",
	"asset_id",
	"active",
	"hp",
	"max_hp",
	"time_limit",
	"time_left",
	"poll_remaining",
	"special_remaining",
	"rollback_remaining",
	"debuff_applied",
	"recovery_count",
	"recovered_health",
]
const COMBAT_METRIC_KEYS: PackedStringArray = [
	"enemies_defeated",
	"enemies_leaked",
	"leak_damage",
	"largest_wave_leak_damage",
	"last_wave_leak_damage",
]
const DOWN_EVIDENCE_KEYS: PackedStringArray = [
	"total_count", "total_time", "records",
]
const DOWN_RECORD_KEYS: PackedStringArray = [
	"operator_id", "attack", "boss_time",
]
const QA_OUTCOME_KEYS: PackedStringArray = [
	"consumed",
	"pending_target_id",
	"remaining",
	"rescue_count",
	"outcome",
	"target_id",
	"reason",
	"time",
]
const REPORT_KINDS: PackedStringArray = [
	"stability_depleted",
	"boss_timeout",
	"boss_all_down",
	"qa_outcome",
	"operator_down",
	"boss_defeated",
]
const TERMINAL_REASONS: PackedStringArray = [
	"boss_defeated", "stability_depleted", "boss_timeout", "boss_all_down",
]


class RestoreResult:
	extends RefCounted

	var state: ProductLoopState
	var errors: PackedStringArray = PackedStringArray()


static func export_state(state: ProductLoopState) -> Dictionary:
	assert(state != null, "ProductLoopStateDto requires a state")
	var records: Array[Dictionary] = []
	for record: ProductLoopState.ShiftRecord in state.shift_records:
		records.append({
			"shift_index": record.shift_index,
			"attempts": record.attempts,
			"highest_completed_waves": record.highest_completed_waves,
			"best_stars": record.best_stars,
			"claimed_reward_stars": record.claimed_reward_stars,
			"boss_encountered": record.boss_encountered,
		})
	var report_rows: Array[Dictionary] = []
	for row: Dictionary in state.report_rows:
		report_rows.append(row.duplicate(true))
	return {
		"phase": state.phase,
		"version": state.version,
		"bits": state.bits,
		"active_shift_index": state.active_shift_index,
		"result_serial": state.result_serial,
		"playback_speed": state.playback_speed,
		"shift_records": records,
		"shift_2_unlocked": state.shift_2_unlocked,
		"version_update_available": state.version_update_available,
		"last_result": state.last_result.duplicate(true),
		"report_key": state.report_key,
		"report_rows": report_rows,
		"report_read": state.report_read,
		"patch_notes": state.patch_notes,
		"legacy_cache_level": state.legacy_cache_level,
		"operator_levels": _export_levels(state.operator_levels),
		"unlocked_operator_ids": _export_ids(state.unlocked_operator_ids),
		"discovered_patch_ids": _export_ids(state.discovered_patch_ids),
		"unlocked_patch_slots": state.unlocked_patch_slots,
		"equipped_patch_ids": _export_ids(state.equipped_patch_ids),
		"day_income_anchor_unix": state.day_income_anchor_unix,
		"day_income_remainder_seconds": state.day_income_remainder_seconds,
		"last_day_income_elapsed_seconds": state.last_day_income_elapsed_seconds,
		"last_day_income_bits": state.last_day_income_bits,
		"day_income_report_available": state.day_income_report_available,
		"migration_source_schema": state.migration_source_schema,
		"migration_source_run_count": state.migration_source_run_count,
		"migration_saved_at_unix": state.migration_saved_at_unix,
	}


static func restore_candidate(
	data: Dictionary,
	first_reward_bits: PackedInt32Array,
	catalog: ProductV2Catalog = null
) -> RestoreResult:
	var result := RestoreResult.new()
	if first_reward_bits.size() != 3:
		result.errors.append(
			"product_loop: exactly three catalog first-star rewards are required"
		)
		return result
	_validate_keys(data, STATE_KEYS, "product_loop", result.errors)
	if not result.errors.is_empty():
		return result

	_require_int(data, "phase", 0, ProductLoopState.Phase.SHIFT_RESULT, result.errors)
	_require_int(data, "version", 1, MAX_JSON_SAFE_INTEGER, result.errors)
	_require_int(data, "bits", 0, MAX_JSON_SAFE_INTEGER, result.errors)
	_require_int(
		data, "active_shift_index", 0, ProductLoopState.SHIFT_COUNT, result.errors
	)
	_require_int(data, "result_serial", 0, MAX_SAFE_INT, result.errors)
	_require_int(data, "playback_speed", 1, 2, result.errors)
	_require_bool(data, "shift_2_unlocked", result.errors)
	_require_bool(data, "version_update_available", result.errors)
	_require_string(data, "report_key", true, result.errors)
	_require_bool(data, "report_read", result.errors)
	_require_int(data, "patch_notes", 0, MAX_JSON_SAFE_INTEGER, result.errors)
	_require_int(data, "legacy_cache_level", 0, MAX_SAFE_INT, result.errors)
	_require_int(data, "unlocked_patch_slots", 0, 3, result.errors)
	_require_int(data, "day_income_anchor_unix", 0, MAX_UNIX_TIME, result.errors)
	_require_int(
		data, "day_income_remainder_seconds", 0, MAX_SAFE_INT, result.errors
	)
	_require_int(
		data, "last_day_income_elapsed_seconds", 0, MAX_SAFE_INT, result.errors
	)
	_require_int(data, "last_day_income_bits", 0, MAX_SAFE_INT, result.errors)
	_require_bool(data, "day_income_report_available", result.errors)
	_require_int(data, "migration_source_schema", 0, 2, result.errors)
	_require_int(
		data,
		"migration_source_run_count",
		0,
		MAX_JSON_SAFE_INTEGER,
		result.errors
	)
	_require_int(data, "migration_saved_at_unix", 0, MAX_UNIX_TIME, result.errors)
	if typeof(data.get("shift_records")) != TYPE_ARRAY:
		result.errors.append("product_loop.shift_records: array is required")
	if typeof(data.get("last_result")) != TYPE_DICTIONARY:
		result.errors.append("product_loop.last_result: object is required")
	if typeof(data.get("report_rows")) != TYPE_ARRAY:
		result.errors.append("product_loop.report_rows: array is required")
	if typeof(data.get("operator_levels")) != TYPE_DICTIONARY:
		result.errors.append("product_loop.operator_levels: object is required")
	for key: String in [
		"unlocked_operator_ids", "discovered_patch_ids", "equipped_patch_ids",
	]:
		if typeof(data.get(key)) != TYPE_ARRAY:
			result.errors.append("product_loop.%s: array is required" % key)
	if not result.errors.is_empty():
		return result

	var records := _parse_shift_records(
		data["shift_records"] as Array, result.errors
	)
	var last_result := _parse_last_result(
		data["last_result"] as Dictionary, result.errors
	)
	var report_rows := _parse_report_rows(
		data["report_rows"] as Array, result.errors
	)
	var operator_levels := _parse_operator_levels(
		data["operator_levels"] as Dictionary, result.errors
	)
	var unlocked_operator_ids := _parse_id_array(
		data["unlocked_operator_ids"] as Array,
		"product_loop.unlocked_operator_ids",
		ProductV2Catalog.STABLE_OPERATOR_IDS,
		false,
		result.errors
	)
	var discovered_patch_ids := _parse_id_array(
		data["discovered_patch_ids"] as Array,
		"product_loop.discovered_patch_ids",
		ProductV2Catalog.STABLE_PATCH_IDS,
		false,
		result.errors
	)
	var equipped_patch_ids := _parse_id_array(
		data["equipped_patch_ids"] as Array,
		"product_loop.equipped_patch_ids",
		ProductV2Catalog.STABLE_PATCH_IDS,
		true,
		result.errors
	)
	if (data["equipped_patch_ids"] as Array).size() != 3:
		result.errors.append(
			"product_loop.equipped_patch_ids: exactly three slots are required"
		)
	if not result.errors.is_empty():
		return result

	var candidate := ProductLoopState.new()
	candidate.phase = int(data["phase"])
	candidate.version = int(data["version"])
	candidate.bits = int(data["bits"])
	candidate.active_shift_index = int(data["active_shift_index"])
	candidate.result_serial = int(data["result_serial"])
	candidate.playback_speed = int(data["playback_speed"])
	candidate.shift_records = records
	candidate.shift_2_unlocked = bool(data["shift_2_unlocked"])
	candidate.version_update_available = bool(data["version_update_available"])
	candidate.last_result = last_result
	candidate.report_key = String(data["report_key"])
	candidate.report_rows = report_rows
	candidate.report_read = bool(data["report_read"])
	candidate.patch_notes = int(data["patch_notes"])
	candidate.legacy_cache_level = int(data["legacy_cache_level"])
	candidate.operator_levels = operator_levels
	candidate.unlocked_operator_ids = unlocked_operator_ids
	candidate.discovered_patch_ids = discovered_patch_ids
	candidate.unlocked_patch_slots = int(data["unlocked_patch_slots"])
	candidate.equipped_patch_ids = equipped_patch_ids
	candidate.day_income_anchor_unix = int(data["day_income_anchor_unix"])
	candidate.day_income_remainder_seconds = int(data["day_income_remainder_seconds"])
	candidate.last_day_income_elapsed_seconds = int(
		data["last_day_income_elapsed_seconds"]
	)
	candidate.last_day_income_bits = int(data["last_day_income_bits"])
	candidate.day_income_report_available = bool(
		data["day_income_report_available"]
	)
	candidate.migration_source_schema = int(data["migration_source_schema"])
	candidate.migration_source_run_count = int(data["migration_source_run_count"])
	candidate.migration_saved_at_unix = int(data["migration_saved_at_unix"])
	_validate_cross_state(candidate, first_reward_bits, catalog, result.errors)
	if result.errors.is_empty():
		result.state = candidate
	return result


static func _export_levels(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_id: Variant in source.keys():
		result[String(raw_id)] = int(source[raw_id])
	return result


static func _export_ids(source: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in source:
		result.append(String(value))
	return result


static func _parse_operator_levels(
	data: Dictionary,
	errors: PackedStringArray
) -> Dictionary:
	var expected := PackedStringArray()
	for operator_id: StringName in ProductV2Catalog.STABLE_OPERATOR_IDS:
		expected.append(String(operator_id))
	_validate_keys(data, expected, "product_loop.operator_levels", errors)
	var result: Dictionary = {}
	for operator_id: StringName in ProductV2Catalog.STABLE_OPERATOR_IDS:
		var key := String(operator_id)
		_require_int_at(
			data, key, 0, 1000, "product_loop.operator_levels", errors
		)
		if data.has(key) and _is_integer(data[key]):
			result[operator_id] = int(data[key])
	return result


static func _parse_id_array(
	raw_values: Array,
	context: String,
	allowed_ids: Array[StringName],
	allow_empty: bool,
	errors: PackedStringArray
) -> Array[StringName]:
	var result: Array[StringName] = []
	var seen: Dictionary = {}
	for index: int in raw_values.size():
		var raw_value: Variant = raw_values[index]
		if typeof(raw_value) != TYPE_STRING:
			errors.append("%s[%d]: string is required" % [context, index])
			continue
		var value := StringName(String(raw_value))
		if value == &"" and allow_empty:
			result.append(value)
			continue
		if value == &"" or not allowed_ids.has(value):
			errors.append("%s[%d]: unknown id '%s'" % [context, index, value])
			continue
		if seen.has(value):
			errors.append("%s[%d]: duplicate id '%s'" % [context, index, value])
			continue
		seen[value] = true
		result.append(value)
	return result


static func _parse_new_unlocks(
	data: Dictionary,
	context: String,
	errors: PackedStringArray
) -> Dictionary:
	var error_count_before := errors.size()
	_validate_keys(data, NEW_UNLOCK_KEYS, context, errors)
	for key: String in NEW_UNLOCK_KEYS:
		if typeof(data.get(key)) != TYPE_ARRAY:
			errors.append("%s.%s: array is required" % [context, key])
	if errors.size() != error_count_before:
		return {}
	_parse_id_array(
		data["operator_ids"] as Array,
		"%s.operator_ids" % context,
		ProductV2Catalog.STABLE_OPERATOR_IDS,
		false,
		errors
	)
	_parse_id_array(
		data["patch_ids"] as Array,
		"%s.patch_ids" % context,
		ProductV2Catalog.STABLE_PATCH_IDS,
		false,
		errors
	)
	var seen_slots: Dictionary = {}
	var normalized_slots: Array[int] = []
	for index: int in (data["patch_slots"] as Array).size():
		var raw_slot: Variant = (data["patch_slots"] as Array)[index]
		if not _is_integer(raw_slot):
			errors.append(
				"%s.patch_slots[%d]: integer is required" % [context, index]
			)
			continue
		var slot := int(raw_slot)
		if slot < 0 or slot > 2 or seen_slots.has(slot):
			errors.append(
				"%s.patch_slots[%d]: unique slot from 0 to 2 is required"
				% [context, index]
			)
			continue
		seen_slots[slot] = true
		normalized_slots.append(slot)
	if errors.size() != error_count_before:
		return {}
	var result := data.duplicate(true)
	result["patch_slots"] = normalized_slots
	return result


static func _parse_shift_records(
	raw_records: Array,
	errors: PackedStringArray
) -> Array[ProductLoopState.ShiftRecord]:
	var records: Array[ProductLoopState.ShiftRecord] = []
	if raw_records.size() != ProductLoopState.SHIFT_COUNT:
		errors.append("product_loop.shift_records: exactly two records are required")
		return records
	for index: int in raw_records.size():
		var context := "product_loop.shift_records[%d]" % index
		var raw_record: Variant = raw_records[index]
		if typeof(raw_record) != TYPE_DICTIONARY:
			errors.append("%s: object is required" % context)
			continue
		var data := raw_record as Dictionary
		var error_count_before := errors.size()
		_validate_keys(data, SHIFT_RECORD_KEYS, context, errors)
		_require_int_at(data, "shift_index", index + 1, index + 1, context, errors)
		_require_int_at(data, "attempts", 0, MAX_SAFE_INT, context, errors)
		_require_int_at(
			data, "highest_completed_waves", 0, 10, context, errors
		)
		_require_int_at(data, "best_stars", 0, 3, context, errors)
		_require_int_at(data, "claimed_reward_stars", 0, 3, context, errors)
		_require_bool_at(data, "boss_encountered", context, errors)
		if errors.size() != error_count_before:
			continue
		var record := ProductLoopState.ShiftRecord.new(index + 1)
		record.attempts = int(data["attempts"])
		record.highest_completed_waves = int(data["highest_completed_waves"])
		record.best_stars = int(data["best_stars"])
		record.claimed_reward_stars = int(data["claimed_reward_stars"])
		record.boss_encountered = bool(data["boss_encountered"])
		if record.claimed_reward_stars != record.best_stars:
			errors.append(
				"%s.claimed_reward_stars: must match best_stars after settlement"
				% context
			)
		if record.best_stars != _stars_for_waves(record.highest_completed_waves):
			errors.append(
				"%s.best_stars: must match the completed-wave record" % context
			)
		if record.attempts == 0 and (
			record.highest_completed_waves > 0
			or record.best_stars > 0
			or record.claimed_reward_stars > 0
			or record.boss_encountered
		):
			errors.append("%s: an unattempted shift cannot have progress" % context)
		records.append(record)
	return records


static func _parse_last_result(
	data: Dictionary,
	errors: PackedStringArray
) -> Dictionary:
	if data.is_empty():
		return {}
	var context := "product_loop.last_result"
	_validate_keys(data, RESULT_KEYS, context, errors)
	for key: String in ["key", "terminal_reason", "report_key"]:
		_require_nonempty_string_at(data, key, context, errors)
	for key: String in ["success", "shift_2_unlocked_now", "version_update_available_now"]:
		_require_bool_at(data, key, context, errors)
	_require_int_at(data, "version", 1, MAX_JSON_SAFE_INTEGER, context, errors)
	_require_int_at(data, "shift_index", 1, 2, context, errors)
	_require_int_at(data, "completed_waves", 0, 10, context, errors)
	_require_int_at(data, "stars", 0, 3, context, errors)
	_require_int_at(data, "stability", 0, MAX_SAFE_INT, context, errors)
	_require_int_at(data, "max_stability", 1, MAX_SAFE_INT, context, errors)
	_require_int_at(data, "previous_best_stars", 0, 3, context, errors)
	_require_int_at(data, "best_stars", 0, 3, context, errors)
	_require_int_at(data, "first_reward_bits", 0, MAX_SAFE_INT, context, errors)
	for key: String in [
		"base_salary",
		"completion_reward",
		"boss_reward",
		"stability_reward",
		"performance_raw",
		"performance_reward",
		"total_reward",
	]:
		_require_int_at(data, key, 0, MAX_SAFE_INT, context, errors)
	_require_int_at(
		data, "bits_before", 0, MAX_JSON_SAFE_INTEGER, context, errors
	)
	_require_nonnegative_number_at(data, "bit_multiplier", context, errors)
	_require_int_at(
		data, "bits_after", 0, MAX_JSON_SAFE_INTEGER, context, errors
	)
	if (
		data.has("terminal_reason")
		and typeof(data["terminal_reason"]) == TYPE_STRING
		and not TERMINAL_REASONS.has(String(data["terminal_reason"]))
	):
		errors.append("%s.terminal_reason: unknown terminal reason" % context)
	var normalized_reward_stars: Array[int] = []
	if typeof(data.get("new_reward_stars")) != TYPE_ARRAY:
		errors.append("%s.new_reward_stars: array is required" % context)
	else:
		var previous := 0
		for index: int in (data["new_reward_stars"] as Array).size():
			var raw_star: Variant = (data["new_reward_stars"] as Array)[index]
			if not _is_integer(raw_star):
				errors.append(
					"%s.new_reward_stars[%d]: integer is required"
					% [context, index]
				)
				continue
			var star := int(raw_star)
			if star <= previous or star < 1 or star > 3:
				errors.append(
					"%s.new_reward_stars: tiers must be increasing values from 1 to 3"
					% context
				)
			previous = star
			normalized_reward_stars.append(star)
	var normalized_new_unlocks: Dictionary = {}
	if typeof(data.get("new_unlocks")) != TYPE_DICTIONARY:
		errors.append("%s.new_unlocks: object is required" % context)
	else:
		normalized_new_unlocks = _parse_new_unlocks(
			data["new_unlocks"] as Dictionary,
			"%s.new_unlocks" % context,
			errors
		)
	_validate_result_evidence(data, context, errors)
	if not errors.is_empty():
		return {}
	var restored := data.duplicate(true)
	restored["new_reward_stars"] = normalized_reward_stars
	restored["new_unlocks"] = normalized_new_unlocks
	return restored


static func _parse_report_rows(
	raw_rows: Array,
	errors: PackedStringArray
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for index: int in raw_rows.size():
		var context := "product_loop.report_rows[%d]" % index
		var raw_row: Variant = raw_rows[index]
		if typeof(raw_row) != TYPE_DICTIONARY:
			errors.append("%s: object is required" % context)
			continue
		var data := raw_row as Dictionary
		_validate_keys(data, REPORT_ROW_KEYS, context, errors)
		_require_nonempty_string_at(data, "kind", context, errors)
		for key: String in ["operator_id", "operator_name"]:
			if not data.has(key) or typeof(data[key]) != TYPE_STRING:
				errors.append("%s.%s: string is required" % [context, key])
		_require_nonempty_string_at(data, "summary", context, errors)
		for key: String in ["primary_value", "primary_max", "seconds"]:
			_require_nonnegative_number_at(data, key, context, errors)
		_require_int_at(data, "count", 0, MAX_SAFE_INT, context, errors)
		if (
			data.has("kind")
			and typeof(data["kind"]) == TYPE_STRING
			and not REPORT_KINDS.has(String(data["kind"]))
		):
			errors.append("%s.kind: unknown factual report row" % context)
		if not data.has("operator_id") or typeof(data["operator_id"]) != TYPE_STRING:
			continue
		var identity := "%s:%s" % [String(data.get("kind", "")), String(data["operator_id"])]
		if seen_ids.has(identity):
			errors.append("%s: duplicate factual report row" % context)
			continue
		seen_ids[identity] = true
		rows.append(data.duplicate(true))
	if rows.size() > 2:
		errors.append("product_loop.report_rows: at most two factual rows are allowed")
	return rows


static func _validate_result_evidence(
	data: Dictionary,
	context: String,
	errors: PackedStringArray
) -> void:
	for key: String in ["boss", "combat_metrics", "down_evidence", "qa_outcome"]:
		if typeof(data.get(key)) != TYPE_DICTIONARY:
			errors.append("%s.%s: object is required" % [context, key])
	if not errors.is_empty():
		return
	var boss := data["boss"] as Dictionary
	_validate_keys(boss, BOSS_KEYS, "%s.boss" % context, errors)
	for key: String in ["id", "name", "asset_id"]:
		_require_nonempty_string_at(boss, key, "%s.boss" % context, errors)
	for key: String in ["active", "debuff_applied"]:
		_require_bool_at(boss, key, "%s.boss" % context, errors)
	for key: String in [
		"hp",
		"max_hp",
		"time_limit",
		"time_left",
		"poll_remaining",
		"special_remaining",
		"rollback_remaining",
		"recovered_health",
	]:
		_require_nonnegative_number_at(boss, key, "%s.boss" % context, errors)
	_require_int_at(
		boss, "recovery_count", 0, MAX_SAFE_INT, "%s.boss" % context, errors
	)

	var metrics := data["combat_metrics"] as Dictionary
	_validate_keys(
		metrics, COMBAT_METRIC_KEYS, "%s.combat_metrics" % context, errors
	)
	for key: String in COMBAT_METRIC_KEYS:
		_require_int_at(
			metrics, key, 0, MAX_SAFE_INT, "%s.combat_metrics" % context, errors
		)

	var down := data["down_evidence"] as Dictionary
	_validate_keys(
		down, DOWN_EVIDENCE_KEYS, "%s.down_evidence" % context, errors
	)
	_require_int_at(
		down, "total_count", 0, MAX_SAFE_INT, "%s.down_evidence" % context, errors
	)
	_require_nonnegative_number_at(
		down, "total_time", "%s.down_evidence" % context, errors
	)
	if typeof(down.get("records")) != TYPE_ARRAY:
		errors.append("%s.down_evidence.records: array is required" % context)
	else:
		for index: int in (down["records"] as Array).size():
			var raw_record: Variant = (down["records"] as Array)[index]
			var record_context := "%s.down_evidence.records[%d]" % [context, index]
			if typeof(raw_record) != TYPE_DICTIONARY:
				errors.append("%s: object is required" % record_context)
				continue
			var record := raw_record as Dictionary
			_validate_keys(record, DOWN_RECORD_KEYS, record_context, errors)
			for key: String in ["operator_id", "attack"]:
				_require_nonempty_string_at(record, key, record_context, errors)
			_require_nonnegative_number_at(
				record, "boss_time", record_context, errors
			)

	var qa := data["qa_outcome"] as Dictionary
	_validate_keys(qa, QA_OUTCOME_KEYS, "%s.qa_outcome" % context, errors)
	_require_bool_at(qa, "consumed", "%s.qa_outcome" % context, errors)
	for key: String in [
		"pending_target_id", "outcome", "target_id", "reason",
	]:
		if not qa.has(key) or typeof(qa[key]) != TYPE_STRING:
			errors.append("%s.qa_outcome.%s: string is required" % [context, key])
	for key: String in ["remaining", "time"]:
		_require_nonnegative_number_at(
			qa, key, "%s.qa_outcome" % context, errors
		)
	_require_int_at(
		qa, "rescue_count", 0, MAX_SAFE_INT, "%s.qa_outcome" % context, errors
	)


static func _validate_cross_state(
	state: ProductLoopState,
	first_reward_bits: PackedInt32Array,
	catalog: ProductV2Catalog,
	errors: PackedStringArray
) -> void:
	var first := state.get_shift_record(1)
	var second := state.get_shift_record(2)
	if first == null or second == null:
		errors.append("product_loop.shift_records: both shift records are required")
		return
	if state.shift_2_unlocked != (first.best_stars == 3):
		errors.append(
			"product_loop.shift_2_unlocked: must match first-shift three-star progress"
		)
	if state.version_update_available != (second.best_stars == 3):
		errors.append(
			"product_loop.version_update_available: must match second-shift three-star progress"
		)
	if second.attempts > 0 and not state.shift_2_unlocked:
		errors.append(
			"product_loop.shift_records[1]: second shift cannot be attempted while locked"
		)
	_validate_meta_state(state, catalog, errors)
	if state.playback_speed == 2:
		var speed_record := state.get_shift_record(state.active_shift_index)
		if (
			state.phase != ProductLoopState.Phase.NIGHT_ACTIVE
			or speed_record == null
			or speed_record.best_stars != 3
		):
			errors.append(
				"product_loop.playback_speed: 2x requires a three-star NIGHT retry"
			)
	match state.phase:
		ProductLoopState.Phase.DAY_PREP:
			if state.active_shift_index != 0:
				errors.append(
					"product_loop.active_shift_index: day prep requires zero"
				)
		ProductLoopState.Phase.NIGHT_ACTIVE:
			if (
				state.active_shift_index < 1
				or state.active_shift_index > ProductLoopState.SHIFT_COUNT
			):
				errors.append(
					"product_loop.active_shift_index: active night requires a shift"
				)
			elif state.active_shift_index == 2 and not state.shift_2_unlocked:
				errors.append(
					"product_loop.active_shift_index: second shift is still locked"
				)
		ProductLoopState.Phase.SHIFT_RESULT:
			if state.last_result.is_empty():
				errors.append("product_loop.last_result: result phase requires a result")
			elif (
				state.active_shift_index
				!= int(state.last_result.get("shift_index", 0))
			):
				errors.append(
					"product_loop.active_shift_index: result must match its shift"
				)
	if state.last_result.is_empty():
		if (
			not state.report_key.is_empty()
			or not state.report_rows.is_empty()
			or not state.report_read
		):
			errors.append(
				"product_loop: an empty result cannot have a field report"
			)
		return
	if state.report_key != String(state.last_result.get("report_key", "")):
		errors.append("product_loop.report_key: must match the latest result")
	if state.report_rows.is_empty():
		errors.append("product_loop.report_rows: latest result requires operator facts")
	if int(state.last_result.get("version", 0)) != state.version:
		errors.append("product_loop.last_result.version: must match current version")
	var result_shift := int(state.last_result.get("shift_index", 0))
	var record := state.get_shift_record(result_shift)
	if record == null:
		errors.append("product_loop.last_result.shift_index: missing shift record")
		return
	if int(state.last_result.get("best_stars", -1)) != record.best_stars:
		errors.append(
			"product_loop.last_result.best_stars: must match the shift record"
		)
	if record.attempts <= 0:
		errors.append(
			"product_loop.last_result: its shift must have at least one attempt"
		)
	var completed_waves := int(state.last_result.get("completed_waves", -1))
	var achieved_stars := int(state.last_result.get("stars", -1))
	if achieved_stars != _stars_for_waves(completed_waves):
		errors.append(
			"product_loop.last_result.stars: must match completed_waves"
		)
	var success := bool(state.last_result.get("success", false))
	var terminal_reason := String(state.last_result.get("terminal_reason", ""))
	if success != (
		terminal_reason == "boss_defeated"
		and completed_waves == 10
		and achieved_stars == 3
	):
		errors.append(
			"product_loop.last_result.success: must match boss defeat evidence"
		)
	if (
		state.phase == ProductLoopState.Phase.SHIFT_RESULT
		and int(state.last_result.get("bits_after", -1)) != state.bits
	):
		errors.append(
			"product_loop.last_result.bits_after: must match result-phase bits"
		)
	var previous_best := int(state.last_result.get("previous_best_stars", -1))
	var expected_best := maxi(previous_best, achieved_stars)
	if int(state.last_result.get("best_stars", -1)) != expected_best:
		errors.append(
			"product_loop.last_result.best_stars: must be the achieved or previous best"
		)
	var expected_reward_stars: Array[int] = []
	for star: int in range(previous_best + 1, achieved_stars + 1):
		expected_reward_stars.append(star)
	if state.last_result.get("new_reward_stars", []) != expected_reward_stars:
		errors.append(
			"product_loop.last_result.new_reward_stars: do not match the new tiers"
		)
	var expected_reward_bits := 0
	for star: int in expected_reward_stars:
		expected_reward_bits += first_reward_bits[star - 1]
	if int(state.last_result.get("first_reward_bits", -1)) != expected_reward_bits:
		errors.append(
			"product_loop.last_result.first_reward_bits: does not match new tiers"
		)
	_validate_salary(state.last_result, catalog, errors)
	var expected_key := "v%d:s%d:r%d" % [
		state.version, result_shift, state.result_serial,
	]
	if (
		String(state.last_result.get("key", "")) != expected_key
		or state.report_key != expected_key
	):
		errors.append(
			"product_loop.last_result.key: must match version, shift, and result serial"
		)
	var expected_shift_unlock := (
		result_shift == 1 and previous_best < 3 and expected_best == 3
	)
	if (
		bool(state.last_result.get("shift_2_unlocked_now", false))
		!= expected_shift_unlock
	):
		errors.append(
			"product_loop.last_result.shift_2_unlocked_now: inconsistent unlock"
		)
	var expected_update_unlock := (
		result_shift == 2 and previous_best < 3 and expected_best == 3
	)
	if (
		bool(state.last_result.get("version_update_available_now", false))
		!= expected_update_unlock
	):
		errors.append(
			"product_loop.last_result.version_update_available_now: inconsistent unlock"
		)


static func _validate_meta_state(
	state: ProductLoopState,
	catalog: ProductV2Catalog,
	errors: PackedStringArray
) -> void:
	for required_id: StringName in [&"debugger", &"build_engineer"]:
		if not state.unlocked_operator_ids.has(required_id):
			errors.append(
				"product_loop.unlocked_operator_ids: starting operators are required"
			)
			break
	for operator_id: StringName in ProductV2Catalog.STABLE_OPERATOR_IDS:
		var level := int(state.operator_levels.get(operator_id, -1))
		var unlocked := state.unlocked_operator_ids.has(operator_id)
		if (unlocked and level <= 0) or (not unlocked and level != 0):
			errors.append(
				"product_loop.operator_levels.%s: must match unlock state"
				% operator_id
			)
	for patch_id: StringName in state.equipped_patch_ids:
		if patch_id != &"" and not state.discovered_patch_ids.has(patch_id):
			errors.append(
				"product_loop.equipped_patch_ids: equipped patches must be discovered"
			)
			break
	for slot_index: int in state.equipped_patch_ids.size():
		if (
			slot_index >= state.unlocked_patch_slots
			and state.equipped_patch_ids[slot_index] != &""
		):
			errors.append(
				"product_loop.equipped_patch_ids: locked slots must be empty"
			)
			break
	var income_interval := (
		catalog.balance.day_income_interval_seconds if catalog != null else 1200
	)
	var income_cap := (
		catalog.balance.day_income_cap_bits if catalog != null else 36
	)
	if state.day_income_remainder_seconds >= income_interval:
		errors.append(
			"product_loop.day_income_remainder_seconds: must be below one interval"
		)
	if state.last_day_income_bits > income_cap:
		errors.append(
			"product_loop.last_day_income_bits: exceeds the DAY income cap"
		)
	if catalog != null and (
		state.legacy_cache_level
		> catalog.base_catalog.balance.max_legacy_cache_level
	):
		errors.append(
			"product_loop.legacy_cache_level: exceeds the catalog maximum"
		)
	var first := state.get_shift_record(1)
	var second := state.get_shift_record(2)
	if first == null or second == null:
		return
	_validate_migration_provenance(state, errors)
	var expected_operator_ids: Array[StringName] = [
		&"debugger", &"build_engineer",
	]
	var expected_patch_ids: Array[StringName] = []
	var expected_patch_slots := 0
	if state.version >= 2:
		expected_operator_ids.assign(ProductV2Catalog.STABLE_OPERATOR_IDS)
		expected_patch_ids.assign(ProductV2Catalog.STABLE_PATCH_IDS)
		expected_patch_slots = 3
	else:
		if first.best_stars >= 1:
			expected_operator_ids.append(&"sprite_artist")
			expected_patch_ids.append(&"frame_skip")
			expected_patch_slots = 1
		if first.highest_completed_waves >= 5:
			expected_patch_ids.append(&"unsafe_build")
		if first.best_stars >= 2:
			expected_operator_ids.append(&"qa_imp")
		if first.highest_completed_waves >= 7:
			expected_patch_ids.append(&"reward_bypass")
		if first.highest_completed_waves >= 9:
			expected_patch_ids.append(&"rollback_lock")
		if first.best_stars >= 3:
			expected_patch_slots = 2
		if second.boss_encountered:
			expected_patch_ids.append(&"safe_mode")
		if second.best_stars >= 2:
			expected_patch_slots = 3
	if state.migration_source_schema == 0:
		if not _same_id_set(state.unlocked_operator_ids, expected_operator_ids):
			errors.append(
				"product_loop.unlocked_operator_ids: must exactly match version progress"
			)
		if not _same_id_set(state.discovered_patch_ids, expected_patch_ids):
			errors.append(
				"product_loop.discovered_patch_ids: must exactly match version progress"
			)
		if state.unlocked_patch_slots != expected_patch_slots:
			errors.append(
				"product_loop.unlocked_patch_slots: must exactly match version progress"
			)
	var earned_patch_notes := (
		(state.version - 1) * catalog.balance.version_patch_notes_reward
	)
	var spent_patch_notes := (
		state.legacy_cache_level
		* catalog.base_catalog.balance.legacy_cache_cost
	)
	if state.patch_notes + spent_patch_notes != earned_patch_notes:
		errors.append(
			"product_loop.patch_notes: must match completed version updates and cache spending"
		)
	if first.best_stars >= 1 and (
		not state.unlocked_operator_ids.has(&"sprite_artist")
		or not state.discovered_patch_ids.has(&"frame_skip")
		or state.unlocked_patch_slots < 1
	):
		errors.append(
			"product_loop: Shift 1 one-star unlocks are missing"
		)
	if first.highest_completed_waves >= 5 and not state.discovered_patch_ids.has(
		&"unsafe_build"
	):
		errors.append("product_loop: Shift 1 wave-5 patch is missing")
	if first.best_stars >= 2 and not state.unlocked_operator_ids.has(&"qa_imp"):
		errors.append("product_loop: Shift 1 two-star operator is missing")
	if first.highest_completed_waves >= 7 and not state.discovered_patch_ids.has(
		&"reward_bypass"
	):
		errors.append("product_loop: Shift 1 wave-7 patch is missing")
	if first.highest_completed_waves >= 9 and not state.discovered_patch_ids.has(
		&"rollback_lock"
	):
		errors.append("product_loop: Shift 1 wave-9 patch is missing")
	if first.best_stars >= 3 and state.unlocked_patch_slots < 2:
		errors.append("product_loop: Shift 1 three-star slot is missing")
	if second.boss_encountered and not state.discovered_patch_ids.has(&"safe_mode"):
		errors.append("product_loop: Shift 2 boss patch is missing")
	if second.best_stars >= 2 and state.unlocked_patch_slots < 3:
		errors.append("product_loop: Shift 2 two-star slot is missing")


static func _same_id_set(
	actual: Array[StringName],
	expected: Array[StringName]
) -> bool:
	if actual.size() != expected.size():
		return false
	for value: StringName in expected:
		if not actual.has(value):
			return false
	return true


static func _validate_migration_provenance(
	state: ProductLoopState,
	errors: PackedStringArray
) -> void:
	if state.migration_source_schema == 0:
		if (
			state.migration_source_run_count != 0
			or state.migration_saved_at_unix != 0
		):
			errors.append(
				"product_loop.migration: native state cannot contain migration provenance"
			)
		return
	if state.migration_source_schema not in [1, 2]:
		errors.append(
			"product_loop.migration_source_schema: only legacy schema 1 or 2 is supported"
		)
		return
	if state.version < state.migration_source_run_count + 1:
		errors.append(
			"product_loop.version: cannot precede its migrated legacy run"
		)


static func _validate_salary(
	result: Dictionary,
	catalog: ProductV2Catalog,
	errors: PackedStringArray
) -> void:
	var performance_raw := (
		int(result.get("completion_reward", -1))
		+ int(result.get("boss_reward", -1))
		+ int(result.get("stability_reward", -1))
	)
	if int(result.get("performance_raw", -1)) != performance_raw:
		errors.append(
			"product_loop.last_result.performance_raw: reward components do not add up"
		)
	var expected_performance := floori(
		float(performance_raw) * float(result.get("bit_multiplier", 0.0))
	)
	if int(result.get("performance_reward", -1)) != expected_performance:
		errors.append(
			"product_loop.last_result.performance_reward: multiplier must be floored once"
		)
	var expected_total := (
		int(result.get("base_salary", -1))
		+ expected_performance
		+ int(result.get("first_reward_bits", -1))
	)
	if int(result.get("total_reward", -1)) != expected_total:
		errors.append(
			"product_loop.last_result.total_reward: salary components do not add up"
		)
	if (
		int(result.get("bits_after", -1))
		!= int(result.get("bits_before", -1)) + expected_total
	):
		errors.append(
			"product_loop.last_result.bits_after: must equal bits_before plus total reward"
		)
	if catalog == null:
		return
	var completed_waves := int(result.get("completed_waves", 0))
	var success := bool(result.get("success", false))
	var stability := int(result.get("stability", 0))
	var max_stability := maxi(1, int(result.get("max_stability", 1)))
	var expected_stability_steps := floori(
		float(stability * 100)
		/ float(
			max_stability * catalog.balance.stability_step_percent
		)
	)
	if int(result.get("base_salary", -1)) != catalog.balance.base_salary_bits:
		errors.append("product_loop.last_result.base_salary: catalog mismatch")
	if (
		int(result.get("completion_reward", -1))
		!= completed_waves * catalog.balance.completed_wave_salary_bits
	):
		errors.append("product_loop.last_result.completion_reward: catalog mismatch")
	if int(result.get("boss_reward", -1)) != (
		catalog.balance.boss_defeat_salary_bits if success else 0
	):
		errors.append("product_loop.last_result.boss_reward: catalog mismatch")
	if int(result.get("stability_reward", -1)) != (
		expected_stability_steps * catalog.balance.stability_step_salary_bits
	):
		errors.append("product_loop.last_result.stability_reward: catalog mismatch")


static func _stars_for_waves(completed_waves: int) -> int:
	if completed_waves >= 10:
		return 3
	if completed_waves >= 6:
		return 2
	if completed_waves >= 3:
		return 1
	return 0


static func _validate_keys(
	data: Dictionary,
	expected: PackedStringArray,
	context: String,
	errors: PackedStringArray
) -> void:
	for key: String in expected:
		if not data.has(key):
			errors.append("%s.%s: required field is missing" % [context, key])
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not expected.has(String(raw_key)):
			errors.append("%s.%s: unexpected field" % [context, String(raw_key)])


static func _require_int(
	data: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	errors: PackedStringArray
) -> void:
	_require_int_at(data, key, minimum, maximum, "product_loop", errors)


static func _require_int_at(
	data: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_integer(data[key]):
		errors.append("%s.%s: integer is required" % [context, key])
		return
	var value := int(data[key])
	if value < minimum or value > maximum:
		errors.append(
			"%s.%s: value must be between %d and %d"
			% [context, key, minimum, maximum]
		)


static func _require_bool(
	data: Dictionary,
	key: String,
	errors: PackedStringArray
) -> void:
	_require_bool_at(data, key, "product_loop", errors)


static func _require_bool_at(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or typeof(data[key]) != TYPE_BOOL:
		errors.append("%s.%s: boolean is required" % [context, key])


static func _require_string(
	data: Dictionary,
	key: String,
	allow_empty: bool,
	errors: PackedStringArray
) -> void:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING:
		errors.append("product_loop.%s: string is required" % key)
	elif not allow_empty and String(data[key]).is_empty():
		errors.append("product_loop.%s: non-empty string is required" % key)


static func _require_nonempty_string_at(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if (
		not data.has(key)
		or typeof(data[key]) != TYPE_STRING
		or String(data[key]).is_empty()
	):
		errors.append("%s.%s: non-empty string is required" % [context, key])


static func _require_nonnegative_number_at(
	data: Dictionary,
	key: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if (
		not data.has(key)
		or not _is_number(data[key])
		or float(data[key]) < 0.0
		or not is_finite(float(data[key]))
	):
		errors.append("%s.%s: non-negative finite number is required" % [context, key])


static func _is_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return (
		is_finite(numeric)
		and is_equal_approx(numeric, float(int(numeric)))
	)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
