class_name NightShiftStateDto
extends RefCounted

const NightShiftState := preload(
	"res://game/domain/product_v2/night_shift_state.gd"
)
const NightShiftSimulator := preload(
	"res://game/domain/product_v2/night_shift_simulator.gd"
)
const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)

const EPSILON := 0.000001
const STATE_KEYS: PackedStringArray = [
	"shift_index",
	"phase",
	"current_wave",
	"completed_waves",
	"stability",
	"phase_remaining",
	"total_elapsed",
	"combat_elapsed",
	"wave_elapsed",
	"operator_levels",
	"unlocked_operator_ids",
	"equipped_patch_ids",
	"legacy_cache_level",
	"enemies",
	"next_enemy_serial",
	"operators",
	"boss_hp",
	"boss_max_hp",
	"boss_elapsed",
	"boss_poll_remaining",
	"boss_special_remaining",
	"boss_rollback_remaining",
	"boss_debuff_applied",
	"boss_recovery_count",
	"boss_recovered_health",
	"qa_rescue_consumed",
	"qa_rescue_target_id",
	"qa_rescue_remaining",
	"qa_rescue_count",
	"total_enemies_defeated",
	"total_enemies_leaked",
	"total_leak_damage",
	"largest_wave_leak_damage",
	"last_wave_leak_damage",
	"total_operator_down_count",
	"total_operator_down_time",
	"operator_down_records",
	"qa_rescue_outcome",
	"qa_rescue_outcome_target_id",
	"qa_rescue_outcome_reason",
	"qa_rescue_outcome_time",
	"terminal_reason",
	"event_serial",
	"recent_events",
]
const NONNEGATIVE_INT_KEYS: PackedStringArray = [
	"phase",
	"current_wave",
	"completed_waves",
	"stability",
	"legacy_cache_level",
	"boss_recovery_count",
	"qa_rescue_count",
	"total_enemies_defeated",
	"total_enemies_leaked",
	"total_leak_damage",
	"largest_wave_leak_damage",
	"last_wave_leak_damage",
	"total_operator_down_count",
	"event_serial",
]
const NONNEGATIVE_NUMBER_KEYS: PackedStringArray = [
	"phase_remaining",
	"total_elapsed",
	"combat_elapsed",
	"wave_elapsed",
	"boss_hp",
	"boss_max_hp",
	"boss_elapsed",
	"boss_recovered_health",
	"qa_rescue_remaining",
	"total_operator_down_time",
	"qa_rescue_outcome_time",
]
const TIMER_KEYS: PackedStringArray = [
	"boss_poll_remaining", "boss_special_remaining", "boss_rollback_remaining",
]
const STRING_KEYS: PackedStringArray = [
	"qa_rescue_target_id",
	"qa_rescue_outcome",
	"qa_rescue_outcome_target_id",
	"qa_rescue_outcome_reason",
	"terminal_reason",
]
const ENEMY_KEYS: PackedStringArray = [
	"serial", "id", "current_hp", "max_hp", "leak_damage",
]
const OPERATOR_KEYS: PackedStringArray = [
	"id",
	"current_hp",
	"attack_remaining",
	"damage_dealt",
	"damage_taken",
	"down_count",
	"active_time",
	"down_time",
]
const DOWN_RECORD_KEYS: PackedStringArray = ["operator_id", "attack", "boss_time"]
const EVENT_REQUIRED_KEYS: PackedStringArray = [
	"serial", "kind", "time", "combat_time", "shift", "wave", "phase",
]
const EVENT_DETAIL_KEYS: PackedStringArray = [
	"countdown_seconds",
	"enemy_count",
	"duration",
	"operator_id",
	"target_serial",
	"damage",
	"enemy_id",
	"enemy_serial",
	"raw_damage",
	"applied_damage",
	"capped",
	"stability",
	"had_leak",
	"completed_waves",
	"boss_id",
	"max_hp",
	"multiplier",
	"hp",
	"attack",
	"healed",
	"boss_time",
	"delay",
	"reason",
]
const TERMINAL_REASONS: Array[StringName] = [
	&"boss_defeated", &"stability_depleted", &"boss_timeout", &"boss_all_down",
]
const QA_OUTCOMES: Array[StringName] = [
	&"unused", &"scheduled", &"succeeded", &"cancelled",
]


class RestoreResult:
	extends RefCounted

	var state: NightShiftState
	var errors: PackedStringArray = PackedStringArray()


static func export_state(state: NightShiftState) -> Dictionary:
	assert(state != null, "NightShiftStateDto requires a state")
	var levels: Dictionary = {}
	for raw_id: Variant in state.operator_levels.keys():
		levels[String(raw_id)] = int(state.operator_levels[raw_id])
	var enemies: Array[Dictionary] = []
	for enemy: NightShiftState.EnemyRuntime in state.enemies:
		enemies.append({
			"serial": enemy.serial,
			"id": String(enemy.enemy_id),
			"current_hp": enemy.current_hp,
			"max_hp": enemy.max_hp,
			"leak_damage": enemy.leak_damage,
		})
	var operators: Array[Dictionary] = []
	for runtime: OperatorCombatState in state.operator_combat_states:
		operators.append({
			"id": String(runtime.operator_id),
			"current_hp": runtime.current_hp,
			"attack_remaining": _encode_timer(runtime.attack_remaining),
			"damage_dealt": runtime.damage_dealt,
			"damage_taken": runtime.damage_taken,
			"down_count": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		})
	var down_records: Array[Dictionary] = []
	for row: Dictionary in state.operator_down_records:
		down_records.append({
			"operator_id": String(row["operator_id"]),
			"attack": String(row["attack"]),
			"boss_time": float(row["boss_time"]),
		})
	var events: Array[Dictionary] = []
	for event: Dictionary in state.recent_events:
		events.append(_export_event(event))
	return {
		"shift_index": state.shift_index,
		"phase": state.phase,
		"current_wave": state.current_wave,
		"completed_waves": state.completed_waves,
		"stability": state.stability,
		"phase_remaining": state.phase_remaining,
		"total_elapsed": state.total_elapsed,
		"combat_elapsed": state.combat_elapsed,
		"wave_elapsed": state.wave_elapsed,
		"operator_levels": levels,
		"unlocked_operator_ids": _string_array(state.unlocked_operator_ids),
		"equipped_patch_ids": _string_array(state.equipped_patch_ids),
		"legacy_cache_level": state.legacy_cache_level,
		"enemies": enemies,
		"next_enemy_serial": state.next_enemy_serial,
		"operators": operators,
		"boss_hp": state.boss_hp,
		"boss_max_hp": state.boss_max_hp,
		"boss_elapsed": state.boss_elapsed,
		"boss_poll_remaining": _encode_timer(state.boss_poll_remaining),
		"boss_special_remaining": _encode_timer(state.boss_special_remaining),
		"boss_rollback_remaining": _encode_timer(state.boss_rollback_remaining),
		"boss_debuff_applied": state.boss_debuff_applied,
		"boss_recovery_count": state.boss_recovery_count,
		"boss_recovered_health": state.boss_recovered_health,
		"qa_rescue_consumed": state.qa_rescue_consumed,
		"qa_rescue_target_id": String(state.qa_rescue_target_id),
		"qa_rescue_remaining": state.qa_rescue_remaining,
		"qa_rescue_count": state.qa_rescue_count,
		"total_enemies_defeated": state.total_enemies_defeated,
		"total_enemies_leaked": state.total_enemies_leaked,
		"total_leak_damage": state.total_leak_damage,
		"largest_wave_leak_damage": state.largest_wave_leak_damage,
		"last_wave_leak_damage": state.last_wave_leak_damage,
		"total_operator_down_count": state.total_operator_down_count,
		"total_operator_down_time": state.total_operator_down_time,
		"operator_down_records": down_records,
		"qa_rescue_outcome": String(state.qa_rescue_outcome),
		"qa_rescue_outcome_target_id": String(state.qa_rescue_outcome_target_id),
		"qa_rescue_outcome_reason": String(state.qa_rescue_outcome_reason),
		"qa_rescue_outcome_time": state.qa_rescue_outcome_time,
		"terminal_reason": String(state.terminal_reason),
		"event_serial": state.event_serial,
		"recent_events": events,
	}


static func restore_candidate(
	data: Dictionary,
	catalog: ProductV2Catalog
) -> RestoreResult:
	var result := RestoreResult.new()
	if catalog == null or catalog.base_catalog == null or catalog.balance == null:
		result.errors.append("catalog: loaded Product V2 content is required")
		return result
	_validate_shape(data, result.errors)
	if not result.errors.is_empty():
		return result
	var candidate := _build_candidate(data)
	_validate_candidate(candidate, catalog, result.errors)
	if result.errors.is_empty():
		result.state = candidate
	return result


static func _validate_shape(data: Dictionary, errors: PackedStringArray) -> void:
	_require_exact_keys(data, STATE_KEYS, "night_shift", errors)
	if not errors.is_empty():
		return
	_require_positive_int(data, "shift_index", "night_shift", errors)
	_require_positive_int(data, "next_enemy_serial", "night_shift", errors)
	for key: String in NONNEGATIVE_INT_KEYS:
		_require_nonnegative_int(data, key, "night_shift", errors)
	for key: String in NONNEGATIVE_NUMBER_KEYS:
		_require_nonnegative_number(data, key, "night_shift", errors)
	for key: String in TIMER_KEYS:
		_require_timer(data, key, "night_shift", errors)
	for key: String in STRING_KEYS:
		_require_string(data, key, "night_shift", errors)
	_require_bool(data, "boss_debuff_applied", "night_shift", errors)
	_require_bool(data, "qa_rescue_consumed", "night_shift", errors)
	_validate_levels(data["operator_levels"], errors)
	_validate_string_array(data["unlocked_operator_ids"], "unlocked_operator_ids", errors)
	_validate_string_array(data["equipped_patch_ids"], "equipped_patch_ids", errors)
	_validate_enemy_rows(data["enemies"], errors)
	_validate_operator_rows(data["operators"], errors)
	_validate_down_records(data["operator_down_records"], errors)
	_validate_events(data["recent_events"], errors)


static func _validate_levels(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("night_shift.operator_levels must be an object")
		return
	for raw_id: Variant in (value as Dictionary).keys():
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty():
			errors.append("night_shift.operator_levels keys must be non-empty strings")
		elif (
			not _is_integer_number((value as Dictionary)[raw_id])
			or int((value as Dictionary)[raw_id]) <= 0
		):
			errors.append("night_shift.operator_levels.%s must be a positive integer" % raw_id)


static func _validate_enemy_rows(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("night_shift.enemies must be an array")
		return
	var rows := value as Array
	if rows.size() > 6:
		errors.append("night_shift.enemies exceeds the six-enemy wave cap")
	for index: int in range(rows.size()):
		var context := "night_shift.enemies[%d]" % index
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % context)
			continue
		var row := rows[index] as Dictionary
		_require_exact_keys(row, ENEMY_KEYS, context, errors)
		_require_positive_int(row, "serial", context, errors)
		_require_nonempty_string(row, "id", context, errors)
		_require_nonnegative_number(row, "current_hp", context, errors)
		_require_positive_number(row, "max_hp", context, errors)
		_require_positive_int(row, "leak_damage", context, errors)


static func _validate_operator_rows(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("night_shift.operators must be an array")
		return
	var rows := value as Array
	if rows.size() != ProductV2Catalog.STABLE_OPERATOR_IDS.size():
		errors.append("night_shift.operators must contain all four stable operators")
	for index: int in range(rows.size()):
		var context := "night_shift.operators[%d]" % index
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % context)
			continue
		var row := rows[index] as Dictionary
		_require_exact_keys(row, OPERATOR_KEYS, context, errors)
		_require_nonempty_string(row, "id", context, errors)
		_require_nonnegative_number(row, "current_hp", context, errors)
		_require_timer(row, "attack_remaining", context, errors)
		for key: String in ["damage_dealt", "damage_taken", "active_time", "down_time"]:
			_require_nonnegative_number(row, key, context, errors)
		_require_nonnegative_int(row, "down_count", context, errors)


static func _validate_down_records(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("night_shift.operator_down_records must be an array")
		return
	var rows := value as Array
	if rows.size() > NightShiftState.MAX_OPERATOR_DOWN_RECORDS:
		errors.append("night_shift.operator_down_records exceeds its bounded history")
	for index: int in range(rows.size()):
		var context := "night_shift.operator_down_records[%d]" % index
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % context)
			continue
		var row := rows[index] as Dictionary
		_require_exact_keys(row, DOWN_RECORD_KEYS, context, errors)
		_require_nonempty_string(row, "operator_id", context, errors)
		_require_nonempty_string(row, "attack", context, errors)
		_require_nonnegative_number(row, "boss_time", context, errors)


static func _validate_events(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("night_shift.recent_events must be an array")
		return
	var rows := value as Array
	if rows.size() > NightShiftState.MAX_RECENT_EVENTS:
		errors.append("night_shift.recent_events exceeds its bounded history")
	for index: int in range(rows.size()):
		var context := "night_shift.recent_events[%d]" % index
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % context)
			continue
		var row := rows[index] as Dictionary
		var missing_required := false
		for key: String in EVENT_REQUIRED_KEYS:
			if not row.has(key):
				errors.append("%s.%s is required" % [context, key])
				missing_required = true
		for raw_key: Variant in row.keys():
			var key := String(raw_key)
			if (
				typeof(raw_key) != TYPE_STRING
				or (not EVENT_REQUIRED_KEYS.has(key) and not EVENT_DETAIL_KEYS.has(key))
			):
				errors.append("%s.%s is unexpected" % [context, key])
		if missing_required:
			continue
		_require_positive_int(row, "serial", context, errors)
		_require_nonempty_string(row, "kind", context, errors)
		_require_nonnegative_number(row, "time", context, errors)
		_require_nonnegative_number(row, "combat_time", context, errors)
		_require_positive_int(row, "shift", context, errors)
		_require_nonnegative_int(row, "wave", context, errors)
		_require_nonnegative_int(row, "phase", context, errors)
		for raw_key: Variant in row.keys():
			var key := String(raw_key)
			if EVENT_REQUIRED_KEYS.has(key):
				continue
			var detail: Variant = row[raw_key]
			if typeof(detail) in [TYPE_INT, TYPE_FLOAT] and not is_finite(float(detail)):
				errors.append("%s.%s must be finite" % [context, key])
			elif typeof(detail) not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL]:
				errors.append("%s.%s must be a JSON scalar" % [context, key])


static func _build_candidate(data: Dictionary) -> NightShiftState:
	var state := NightShiftState.new()
	state.shift_index = int(data["shift_index"])
	state.phase = int(data["phase"])
	state.current_wave = int(data["current_wave"])
	state.completed_waves = int(data["completed_waves"])
	state.stability = int(data["stability"])
	state.phase_remaining = float(data["phase_remaining"])
	state.total_elapsed = float(data["total_elapsed"])
	state.combat_elapsed = float(data["combat_elapsed"])
	state.wave_elapsed = float(data["wave_elapsed"])
	for raw_id: Variant in (data["operator_levels"] as Dictionary).keys():
		state.operator_levels[StringName(String(raw_id))] = int(data["operator_levels"][raw_id])
	state.unlocked_operator_ids = _string_name_array(data["unlocked_operator_ids"] as Array)
	state.equipped_patch_ids = _string_name_array(data["equipped_patch_ids"] as Array)
	state.legacy_cache_level = int(data["legacy_cache_level"])
	for raw_row: Variant in data["enemies"] as Array:
		var row := raw_row as Dictionary
		var enemy := NightShiftState.EnemyRuntime.new(
			int(row["serial"]),
			StringName(String(row["id"])),
			float(row["max_hp"]),
			int(row["leak_damage"])
		)
		enemy.current_hp = float(row["current_hp"])
		state.enemies.append(enemy)
	state.next_enemy_serial = int(data["next_enemy_serial"])
	for raw_row: Variant in data["operators"] as Array:
		var row := raw_row as Dictionary
		var runtime := OperatorCombatState.new(StringName(String(row["id"])))
		runtime.current_hp = float(row["current_hp"])
		runtime.attack_remaining = _decode_timer(float(row["attack_remaining"]))
		runtime.damage_dealt = float(row["damage_dealt"])
		runtime.damage_taken = float(row["damage_taken"])
		runtime.down_count = int(row["down_count"])
		runtime.active_time = float(row["active_time"])
		runtime.down_time = float(row["down_time"])
		state.operator_combat_states.append(runtime)
	state.boss_hp = float(data["boss_hp"])
	state.boss_max_hp = float(data["boss_max_hp"])
	state.boss_elapsed = float(data["boss_elapsed"])
	state.boss_poll_remaining = _decode_timer(float(data["boss_poll_remaining"]))
	state.boss_special_remaining = _decode_timer(float(data["boss_special_remaining"]))
	state.boss_rollback_remaining = _decode_timer(float(data["boss_rollback_remaining"]))
	state.boss_debuff_applied = bool(data["boss_debuff_applied"])
	state.boss_recovery_count = int(data["boss_recovery_count"])
	state.boss_recovered_health = float(data["boss_recovered_health"])
	state.qa_rescue_consumed = bool(data["qa_rescue_consumed"])
	state.qa_rescue_target_id = StringName(String(data["qa_rescue_target_id"]))
	state.qa_rescue_remaining = float(data["qa_rescue_remaining"])
	state.qa_rescue_count = int(data["qa_rescue_count"])
	state.total_enemies_defeated = int(data["total_enemies_defeated"])
	state.total_enemies_leaked = int(data["total_enemies_leaked"])
	state.total_leak_damage = int(data["total_leak_damage"])
	state.largest_wave_leak_damage = int(data["largest_wave_leak_damage"])
	state.last_wave_leak_damage = int(data["last_wave_leak_damage"])
	state.total_operator_down_count = int(data["total_operator_down_count"])
	state.total_operator_down_time = float(data["total_operator_down_time"])
	for raw_row: Variant in data["operator_down_records"] as Array:
		var row := raw_row as Dictionary
		state.operator_down_records.append({
			"operator_id": StringName(String(row["operator_id"])),
			"attack": StringName(String(row["attack"])),
			"boss_time": float(row["boss_time"]),
		})
	state.qa_rescue_outcome = StringName(String(data["qa_rescue_outcome"]))
	state.qa_rescue_outcome_target_id = StringName(String(data["qa_rescue_outcome_target_id"]))
	state.qa_rescue_outcome_reason = StringName(String(data["qa_rescue_outcome_reason"]))
	state.qa_rescue_outcome_time = float(data["qa_rescue_outcome_time"])
	state.terminal_reason = StringName(String(data["terminal_reason"]))
	state.event_serial = int(data["event_serial"])
	for raw_event: Variant in data["recent_events"] as Array:
		state.recent_events.append((raw_event as Dictionary).duplicate(true))
	return state


static func _validate_candidate(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	errors: PackedStringArray
) -> void:
	if not catalog.has_shift(state.shift_index):
		errors.append("shift_index refers to unknown Product V2 content")
	if state.phase < NightShiftState.Phase.COUNTDOWN or state.phase > NightShiftState.Phase.FAILURE:
		errors.append("phase is outside the Product V2 phase enum")
	if state.current_wave < 0 or state.current_wave > 10:
		errors.append("current_wave must stay in 0..10")
	if state.completed_waves < 0 or state.completed_waves > 10:
		errors.append("completed_waves must stay in 0..10")
	if state.stability > catalog.balance.max_stability:
		errors.append("stability exceeds max_stability")
	if state.combat_elapsed > state.total_elapsed + EPSILON:
		errors.append("combat_elapsed cannot exceed total_elapsed")
	_validate_phase_counters(state, errors)
	_validate_loadout_and_runtimes(state, catalog, errors)
	_validate_terminal_and_evidence(state, catalog, errors)


static func _validate_phase_counters(
	state: NightShiftState,
	errors: PackedStringArray
) -> void:
	match state.phase:
		NightShiftState.Phase.COUNTDOWN:
			if state.current_wave != 0 or state.completed_waves != 0:
				errors.append("countdown counters are inconsistent")
		NightShiftState.Phase.NORMAL_ACTIVE:
			if state.current_wave < 1 or state.current_wave > 9:
				errors.append("normal phase requires wave 1..9")
			elif state.completed_waves != state.current_wave - 1:
				errors.append("normal phase completed_waves is inconsistent")
		NightShiftState.Phase.INTER_WAVE:
			if (
				state.current_wave != state.completed_waves
				or state.completed_waves < 1
				or state.completed_waves > 8
			):
				errors.append("inter-wave counters are inconsistent")
		NightShiftState.Phase.BOSS_WARNING:
			if state.current_wave != 9 or state.completed_waves != 9:
				errors.append("boss warning requires nine completed waves")
		NightShiftState.Phase.BOSS_ACTIVE:
			if state.current_wave != 10 or state.completed_waves != 9:
				errors.append("boss phase counters are inconsistent")
		NightShiftState.Phase.SUCCESS:
			if state.current_wave != 10 or state.completed_waves != 10:
				errors.append("success counters are inconsistent")
		NightShiftState.Phase.FAILURE:
			match state.terminal_reason:
				&"stability_depleted":
					if (
						state.current_wave < 1
						or state.current_wave > 9
						or state.completed_waves != state.current_wave - 1
						or state.stability != 0
					):
						errors.append(
							"stability failure counters or stability are inconsistent"
						)
				&"boss_timeout", &"boss_all_down":
					if state.current_wave != 10 or state.completed_waves != 9:
						errors.append("boss failure counters are inconsistent")
				_:
					errors.append("failure requires a factual failure reason")


static func _validate_loadout_and_runtimes(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	errors: PackedStringArray
) -> void:
	var unlocked: Dictionary = {}
	for operator_id: StringName in state.unlocked_operator_ids:
		if unlocked.has(operator_id):
			errors.append("duplicate unlocked operator '%s'" % operator_id)
		unlocked[operator_id] = true
		if not catalog.base_catalog.has_operator(operator_id):
			errors.append("unknown unlocked operator '%s'" % operator_id)
		elif int(state.operator_levels.get(operator_id, 0)) <= 0:
			errors.append("unlocked operator '%s' requires a positive level" % operator_id)
	for raw_id: Variant in state.operator_levels.keys():
		var operator_id := StringName(String(raw_id))
		if not unlocked.has(operator_id):
			errors.append("leveled operator '%s' must be unlocked" % operator_id)
	var patches: Dictionary = {}
	for patch_id: StringName in state.equipped_patch_ids:
		if not catalog.base_catalog.has_patch(patch_id):
			errors.append("unknown equipped patch '%s'" % patch_id)
		elif patches.has(patch_id):
			errors.append("duplicate equipped patch '%s'" % patch_id)
		patches[patch_id] = true

	var runtime_ids: Dictionary = {}
	for runtime: OperatorCombatState in state.operator_combat_states:
		if runtime_ids.has(runtime.operator_id):
			errors.append("duplicate operator runtime '%s'" % runtime.operator_id)
			continue
		runtime_ids[runtime.operator_id] = true
		if not catalog.base_catalog.has_operator(runtime.operator_id):
			errors.append("unknown operator runtime '%s'" % runtime.operator_id)
			continue
		var max_hp := (
			NightShiftSimulator.operator_max_hp(state, catalog, runtime.operator_id)
			if unlocked.has(runtime.operator_id) else 0.0
		)
		if runtime.current_hp > max_hp + EPSILON:
			errors.append("operator '%s' HP exceeds max HP" % runtime.operator_id)
		if runtime.current_hp <= EPSILON and not is_inf(runtime.attack_remaining):
			errors.append("down operator '%s' must have a stopped attack timer" % runtime.operator_id)
	for operator_id: StringName in ProductV2Catalog.STABLE_OPERATOR_IDS:
		if not runtime_ids.has(operator_id):
			errors.append("missing operator runtime '%s'" % operator_id)

	var enemy_serials: Dictionary = {}
	var maximum_serial := 0
	for enemy: NightShiftState.EnemyRuntime in state.enemies:
		if enemy_serials.has(enemy.serial):
			errors.append("duplicate enemy serial %d" % enemy.serial)
		enemy_serials[enemy.serial] = true
		maximum_serial = maxi(maximum_serial, enemy.serial)
		if not catalog.has_enemy(enemy.enemy_id):
			errors.append("unknown enemy runtime '%s'" % enemy.enemy_id)
		elif enemy.leak_damage != catalog.get_enemy(enemy.enemy_id).leak_damage:
			errors.append("enemy '%s' leak damage disagrees with content" % enemy.enemy_id)
		if enemy.current_hp > enemy.max_hp + EPSILON:
			errors.append("enemy serial %d HP exceeds max HP" % enemy.serial)
	if state.next_enemy_serial <= maximum_serial:
		errors.append("next_enemy_serial must exceed every enemy serial")
	if state.phase == NightShiftState.Phase.NORMAL_ACTIVE and state.enemies.is_empty():
		errors.append("active normal wave requires enemies")
	if state.phase != NightShiftState.Phase.NORMAL_ACTIVE and not state.enemies.is_empty():
		errors.append("enemy runtimes are only valid during a normal wave")


static func _validate_terminal_and_evidence(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	errors: PackedStringArray
) -> void:
	if state.is_terminal():
		if not TERMINAL_REASONS.has(state.terminal_reason):
			errors.append("unsupported terminal_reason")
		if state.phase_remaining > EPSILON:
			errors.append("terminal state must have zero phase_remaining")
	elif state.terminal_reason != &"":
		errors.append("non-terminal state cannot have terminal_reason")
	if state.phase == NightShiftState.Phase.SUCCESS:
		if state.terminal_reason != &"boss_defeated" or state.boss_hp > EPSILON:
			errors.append("success requires a defeated boss")
	if state.boss_hp > state.boss_max_hp + EPSILON:
		errors.append("boss_hp exceeds boss_max_hp")
	if state.boss_elapsed > catalog.balance.boss_seconds + EPSILON:
		errors.append("boss_elapsed exceeds the boss time limit")
	if not QA_OUTCOMES.has(state.qa_rescue_outcome):
		errors.append("unsupported qa_rescue_outcome")
	if state.qa_rescue_target_id != &"":
		var target := state.get_operator_combat_state(state.qa_rescue_target_id)
		if (
			state.phase != NightShiftState.Phase.BOSS_ACTIVE
			or not state.qa_rescue_consumed
			or target == null
			or target.is_active()
		):
			errors.append("pending QA rescue state is inconsistent")
	elif state.qa_rescue_remaining > EPSILON:
		errors.append("QA rescue timer requires a target")
	if state.total_operator_down_count != state.operator_down_records.size():
		errors.append("operator down count and evidence rows disagree")
	if state.largest_wave_leak_damage > catalog.balance.wave_leak_cap:
		errors.append("largest wave leak exceeds the cap")
	var previous_serial := 0
	for event: Dictionary in state.recent_events:
		var serial := int(event["serial"])
		if serial <= previous_serial:
			errors.append("recent event serials must increase")
			break
		previous_serial = serial
		if int(event["shift"]) != state.shift_index:
			errors.append("recent event shift disagrees with state")
	if not state.recent_events.is_empty() and previous_serial != state.event_serial:
		errors.append("event_serial must match the latest retained event")


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


static func _require_positive_int(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_integer_number(data[key]) or int(data[key]) <= 0:
		errors.append("%s.%s must be a positive integer" % [context, key])


static func _require_nonnegative_int(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_integer_number(data[key]) or int(data[key]) < 0:
		errors.append("%s.%s must be a non-negative integer" % [context, key])


static func _require_positive_number(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_finite_number(data[key]) or float(data[key]) <= 0.0:
		errors.append("%s.%s must be a positive finite number" % [context, key])


static func _require_nonnegative_number(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_finite_number(data[key]) or float(data[key]) < 0.0:
		errors.append("%s.%s must be a non-negative finite number" % [context, key])


static func _require_timer(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or not _is_finite_number(data[key]):
		errors.append("%s.%s must be a finite encoded timer" % [context, key])
	elif float(data[key]) < 0.0 and not is_equal_approx(float(data[key]), -1.0):
		errors.append("%s.%s must be -1 or non-negative" % [context, key])


static func _require_bool(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or typeof(data[key]) != TYPE_BOOL:
		errors.append("%s.%s must be boolean" % [context, key])


static func _require_string(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING:
		errors.append("%s.%s must be a string" % [context, key])


static func _require_nonempty_string(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> void:
	_require_string(data, key, context, errors)
	if data.has(key) and typeof(data[key]) == TYPE_STRING and String(data[key]).is_empty():
		errors.append("%s.%s must not be empty" % [context, key])


static func _validate_string_array(
	value: Variant, context: String, errors: PackedStringArray
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("night_shift.%s must be an array" % context)
		return
	for index: int in range((value as Array).size()):
		if typeof((value as Array)[index]) != TYPE_STRING:
			errors.append("night_shift.%s[%d] must be a string" % [context, index])


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
