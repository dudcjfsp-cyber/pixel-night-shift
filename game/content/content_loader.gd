class_name ContentLoader
extends RefCounted

const OPERATOR_PATH := "res://game/content/operators.json"
const PATCH_PATH := "res://game/content/patches.json"
const BALANCE_PATH := "res://game/content/balance.json"
const PROTOTYPE_MAX_STAGE := 20
const REQUIRED_OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp"
]
const REQUIRED_PATCH_IDS: Array[StringName] = [
	&"frame_skip", &"unsafe_build", &"reward_bypass", &"rollback_lock", &"safe_mode"
]


static func load_default() -> ContentLoadResult:
	var result := ContentLoadResult.new()
	var operator_text := _read_text(OPERATOR_PATH, result)
	var patch_text := _read_text(PATCH_PATH, result)
	var balance_text := _read_text(BALANCE_PATH, result)
	if not result.errors.is_empty():
		return result
	return load_from_json(operator_text, patch_text, balance_text)


static func load_from_json(
	operator_json: String,
	patch_json: String,
	balance_json: String
) -> ContentLoadResult:
	var result := ContentLoadResult.new()
	var raw_operators: Variant = _parse_json(operator_json, "operators", result)
	var raw_patches: Variant = _parse_json(patch_json, "patches", result)
	var raw_balance: Variant = _parse_json(balance_json, "balance", result)
	if not result.errors.is_empty():
		return result
	if typeof(raw_operators) != TYPE_ARRAY:
		result.errors.append("operators: root must be an array")
	if typeof(raw_patches) != TYPE_ARRAY:
		result.errors.append("patches: root must be an array")
	if typeof(raw_balance) != TYPE_DICTIONARY:
		result.errors.append("balance: root must be an object")
	if not result.errors.is_empty():
		return result

	var catalog := ContentCatalog.new()
	catalog.operators = _parse_operators(raw_operators as Array, result)
	catalog.patches = _parse_patches(raw_patches as Array, result)
	catalog.balance = _parse_balance(raw_balance as Dictionary, result)
	_validate_required_ids(catalog, result)
	if not result.errors.is_empty():
		return result
	catalog.build_indexes()
	result.catalog = catalog
	return result


static func _read_text(path: String, result: ContentLoadResult) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Unable to read content file: %s" % path)
		return ""
	return file.get_as_text()


static func _parse_json(text: String, label: String, result: ContentLoadResult) -> Variant:
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		result.errors.append(
			"%s: JSON parse error at line %d: %s"
			% [label, parser.get_error_line(), parser.get_error_message()]
		)
		return null
	return parser.data


static func _parse_operators(raw_items: Array, result: ContentLoadResult) -> Array[OperatorDefinition]:
	var definitions: Array[OperatorDefinition] = []
	var seen_ids: Dictionary = {}
	for index: int in raw_items.size():
		var raw_item: Variant = raw_items[index]
		var context := "operators[%d]" % index
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		var id := _required_string(data, "id", context, result)
		var display_name := _required_string(data, "name", context, result)
		var base_dps := _required_positive_float(data, "base_dps", context, result)
		var base_cost := _required_positive_float(data, "base_cost", context, result)
		var cost_growth := _required_positive_float(data, "cost_growth", context, result)
		var dps_exponent := _required_positive_float(data, "dps_exponent", context, result)
		var unlock_stage := _required_positive_int(data, "unlock_stage", context, result)
		if unlock_stage > PROTOTYPE_MAX_STAGE:
			result.errors.append(
				"%s.unlock_stage: must be within prototype stages 1..%d"
				% [context, PROTOTYPE_MAX_STAGE]
			)
		if cost_growth <= 1.0:
			result.errors.append("%s.cost_growth: must be greater than 1" % context)
		if seen_ids.has(id):
			result.errors.append("%s.id: duplicate id '%s'" % [context, id])
		if result.errors.size() != start_error_count:
			continue
		seen_ids[id] = true
		definitions.append(OperatorDefinition.new(
			StringName(id), display_name, base_dps, base_cost, cost_growth, dps_exponent, unlock_stage
		))
	return definitions


static func _parse_patches(raw_items: Array, result: ContentLoadResult) -> Array[PatchDefinition]:
	var definitions: Array[PatchDefinition] = []
	var seen_ids: Dictionary = {}
	for index: int in raw_items.size():
		var raw_item: Variant = raw_items[index]
		var context := "patches[%d]" % index
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		var id := _required_string(data, "id", context, result)
		var display_name := _required_string(data, "name", context, result)
		var description := _required_string(data, "description", context, result)
		var benefit := _required_string(data, "benefit", context, result)
		var drawback := _required_string(data, "drawback", context, result)
		var unlock_stage := _required_positive_int(data, "unlock_stage", context, result)
		if unlock_stage > PROTOTYPE_MAX_STAGE:
			result.errors.append(
				"%s.unlock_stage: must be within prototype stages 1..%d"
				% [context, PROTOTYPE_MAX_STAGE]
			)
		var damage_multiplier := _required_positive_float(data, "damage_multiplier", context, result)
		var attack_speed_multiplier := _required_positive_float(data, "attack_speed_multiplier", context, result)
		var bit_multiplier := _required_positive_float(data, "bit_multiplier", context, result)
		var enemy_health_multiplier := _required_positive_float(data, "enemy_health_multiplier", context, result)
		var boss_recovery_multiplier := _required_positive_float(data, "boss_recovery_multiplier", context, result)
		var special_interval_multiplier := _required_positive_float(
			data, "boss_special_interval_multiplier", context, result
		)
		if seen_ids.has(id):
			result.errors.append("%s.id: duplicate id '%s'" % [context, id])
		if result.errors.size() != start_error_count:
			continue
		seen_ids[id] = true
		definitions.append(PatchDefinition.new(
			StringName(id), display_name, description, benefit, drawback, unlock_stage,
			damage_multiplier, attack_speed_multiplier, bit_multiplier,
			enemy_health_multiplier, boss_recovery_multiplier, special_interval_multiplier
		))
	return definitions


static func _parse_balance(data: Dictionary, result: ContentLoadResult) -> BalanceDefinition:
	var balance := BalanceDefinition.new()
	balance.normal_enemy_count = _required_positive_int(data, "normal_enemy_count", "balance", result)
	balance.enemy_base_health = _required_positive_float(data, "enemy_base_health", "balance", result)
	balance.enemy_health_growth = _required_positive_float(data, "enemy_health_growth", "balance", result)
	balance.post_stage_10_health_growth = _required_positive_float(
		data, "post_stage_10_health_growth", "balance", result
	)
	balance.enemy_reward_base = _required_positive_float(data, "enemy_reward_base", "balance", result)
	balance.enemy_reward_growth = _required_positive_float(data, "enemy_reward_growth", "balance", result)
	balance.boss_health_multiplier = _required_positive_float(data, "boss_health_multiplier", "balance", result)
	balance.boss_time_limit = _required_positive_float(data, "boss_time_limit", "balance", result)
	balance.stage_10_recovery_interval = _required_positive_float(data, "stage_10_recovery_interval", "balance", result)
	balance.stage_10_recovery_fraction = _required_positive_float(data, "stage_10_recovery_fraction", "balance", result)
	balance.stage_20_recovery_interval = _required_positive_float(data, "stage_20_recovery_interval", "balance", result)
	balance.stage_20_recovery_fraction = _required_positive_float(data, "stage_20_recovery_fraction", "balance", result)
	balance.stage_20_debuff_time = _required_positive_float(data, "stage_20_debuff_time", "balance", result)
	balance.stage_20_debuff_multiplier = _required_positive_float(data, "stage_20_debuff_multiplier", "balance", result)
	balance.maintenance_cycles = _required_positive_int(data, "maintenance_cycles", "balance", result)
	balance.target_normal_ttk = _required_positive_float(data, "target_normal_ttk", "balance", result)
	balance.legacy_cache_bonus = _required_positive_float(data, "legacy_cache_bonus", "balance", result)
	balance.legacy_cache_cost = _required_positive_int(data, "legacy_cache_cost", "balance", result)
	balance.max_legacy_cache_level = _required_positive_int(data, "max_legacy_cache_level", "balance", result)
	balance.patch_slot_unlock_stages = _required_positive_int_array(
		data, "patch_slot_unlock_stages", "balance", result
	)
	if balance.enemy_health_growth <= 1.0:
		result.errors.append("balance.enemy_health_growth: must be greater than 1")
	if balance.post_stage_10_health_growth <= 1.0:
		result.errors.append("balance.post_stage_10_health_growth: must be greater than 1")
	if balance.enemy_reward_growth <= 1.0:
		result.errors.append("balance.enemy_reward_growth: must be greater than 1")
	if balance.patch_slot_unlock_stages.size() != 3:
		result.errors.append("balance.patch_slot_unlock_stages: exactly three entries are required")
	for unlock_stage: int in balance.patch_slot_unlock_stages:
		if unlock_stage > PROTOTYPE_MAX_STAGE:
			result.errors.append(
				"balance.patch_slot_unlock_stages: entries must be within prototype stages 1..%d"
				% PROTOTYPE_MAX_STAGE
			)
	return balance


static func _validate_required_ids(catalog: ContentCatalog, result: ContentLoadResult) -> void:
	var operator_ids: Dictionary = {}
	for definition: OperatorDefinition in catalog.operators:
		operator_ids[definition.id] = true
	for required_id: StringName in REQUIRED_OPERATOR_IDS:
		if not operator_ids.has(required_id):
			result.errors.append("operators: missing required id '%s'" % required_id)
	if catalog.operators.size() != REQUIRED_OPERATOR_IDS.size():
		result.errors.append("operators: prototype requires exactly four definitions")

	var patch_ids: Dictionary = {}
	for definition: PatchDefinition in catalog.patches:
		patch_ids[definition.id] = true
	for required_id: StringName in REQUIRED_PATCH_IDS:
		if not patch_ids.has(required_id):
			result.errors.append("patches: missing required id '%s'" % required_id)
	if catalog.patches.size() != REQUIRED_PATCH_IDS.size():
		result.errors.append("patches: prototype requires exactly five definitions")


static func _required_string(
	data: Dictionary,
	key: String,
	context: String,
	result: ContentLoadResult
) -> String:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING or String(data[key]).strip_edges().is_empty():
		result.errors.append("%s.%s: non-empty string is required" % [context, key])
		return ""
	return String(data[key])


static func _required_positive_float(
	data: Dictionary,
	key: String,
	context: String,
	result: ContentLoadResult
) -> float:
	if not data.has(key) or not _is_number(data[key]):
		result.errors.append("%s.%s: number is required" % [context, key])
		return 0.0
	var value := float(data[key])
	if value <= 0.0 or not is_finite(value):
		result.errors.append("%s.%s: finite value greater than zero is required" % [context, key])
		return 0.0
	return value


static func _required_positive_int(
	data: Dictionary,
	key: String,
	context: String,
	result: ContentLoadResult
) -> int:
	if not data.has(key) or not _is_number(data[key]):
		result.errors.append("%s.%s: integer is required" % [context, key])
		return 0
	var numeric := float(data[key])
	var value := int(numeric)
	if value <= 0 or not is_equal_approx(numeric, float(value)):
		result.errors.append("%s.%s: positive integer is required" % [context, key])
		return 0
	return value


static func _required_positive_int_array(
	data: Dictionary,
	key: String,
	context: String,
	result: ContentLoadResult
) -> PackedInt32Array:
	var values := PackedInt32Array()
	if not data.has(key) or typeof(data[key]) != TYPE_ARRAY:
		result.errors.append("%s.%s: array is required" % [context, key])
		return values
	var raw_values := data[key] as Array
	var previous := 0
	for index: int in raw_values.size():
		var raw_value: Variant = raw_values[index]
		if not _is_number(raw_value):
			result.errors.append("%s.%s[%d]: positive integer is required" % [context, key, index])
			continue
		var numeric := float(raw_value)
		var value := int(numeric)
		if value <= previous or not is_equal_approx(numeric, float(value)):
			result.errors.append("%s.%s: entries must be strictly increasing positive integers" % [context, key])
			continue
		values.append(value)
		previous = value
	return values


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
