class_name CombatV2Loader
extends RefCounted

const PROFILE_PATH := "res://game/content/combat_v2/combat_v2.json"
const REQUIRED_PATCH_IDS: Array[StringName] = [
	&"frame_skip", &"unsafe_build", &"reward_bypass", &"rollback_lock", &"safe_mode"
]
const ROOT_KEYS: Array[String] = ["balance", "diagnosis", "operators", "enemies"]
const BALANCE_KEYS: Array[String] = [
	"max_stage", "normal_enemy_count", "hp_per_level", "revive_fraction", "damage_growth"
]
const DIAGNOSIS_KEYS: Array[String] = [
	"ttk_regression_fraction",
	"team_hp_loss_fraction",
	"recovery_delay_seconds",
	"minimum_uptime_fraction",
	"patch_bits_regression_fraction",
	"boss_heal_regression_fraction",
]
const OPERATOR_KEYS: Array[String] = [
	"id",
	"role_name",
	"base_hp",
	"attack_interval",
	"recovery_duration",
	"threat_weight",
	"outgoing_multiplier",
	"damage_exponent_multiplier",
	"incoming_multiplier",
	"boss_multiplier",
	"team_interval_multiplier",
]
const QA_OPERATOR_KEYS: Array[String] = [
	"id",
	"role_name",
	"base_hp",
	"attack_interval",
	"recovery_duration",
	"threat_weight",
	"outgoing_multiplier",
	"damage_exponent_multiplier",
	"incoming_multiplier",
	"boss_multiplier",
	"team_interval_multiplier",
	"repair_interval",
	"repair_reduction",
]
const STANDARD_ENEMY_KEYS: Array[String] = [
	"id", "display_name", "pattern", "attack_interval", "attack_damage"
]
const BURST_ENEMY_KEYS: Array[String] = [
	"id", "display_name", "pattern", "attack_interval", "attack_damage", "burst_count", "burst_gap"
]
const WATCHDOG_ENEMY_KEYS: Array[String] = [
	"id",
	"display_name",
	"pattern",
	"poll_interval",
	"poll_damage",
	"special_interval",
	"special_damage",
	"rollback_interval",
	"rollback_fraction",
]


class LoadResult:
	extends RefCounted

	var catalog: CombatV2Catalog
	var errors: PackedStringArray = PackedStringArray()


	func is_valid() -> bool:
		return catalog != null and errors.is_empty()


static func load_default() -> LoadResult:
	var result := LoadResult.new()
	var base_result := ContentLoader.load_default()
	if not base_result.is_valid():
		for error: String in base_result.errors:
			result.errors.append("base content: %s" % error)
		return result
	var profile_text := _read_text(PROFILE_PATH, result)
	if not result.errors.is_empty():
		return result
	return load_from_json(profile_text, base_result.catalog)


static func load_from_json(profile_json: String, base_catalog: ContentCatalog) -> LoadResult:
	var result := LoadResult.new()
	_validate_base_catalog(base_catalog, result)
	var raw_profile: Variant = _parse_json(profile_json, result)
	if not result.errors.is_empty():
		return result
	if typeof(raw_profile) != TYPE_DICTIONARY:
		result.errors.append("combat_v2: root must be an object")
		return result

	var root := raw_profile as Dictionary
	_validate_keys(root, ROOT_KEYS, "combat_v2", result)
	if not result.errors.is_empty():
		return result
	if typeof(root["balance"]) != TYPE_DICTIONARY:
		result.errors.append("combat_v2.balance: object is required")
	if typeof(root["diagnosis"]) != TYPE_DICTIONARY:
		result.errors.append("combat_v2.diagnosis: object is required")
	if typeof(root["operators"]) != TYPE_ARRAY:
		result.errors.append("combat_v2.operators: array is required")
	if typeof(root["enemies"]) != TYPE_ARRAY:
		result.errors.append("combat_v2.enemies: array is required")
	if not result.errors.is_empty():
		return result

	var catalog := CombatV2Catalog.new()
	catalog.base_catalog = base_catalog
	catalog.balance = _parse_balance(root["balance"] as Dictionary, result)
	catalog.diagnosis = _parse_diagnosis(root["diagnosis"] as Dictionary, result)
	catalog.operators = _parse_operators(root["operators"] as Array, base_catalog, result)
	catalog.enemies = _parse_enemies(root["enemies"] as Array, result)
	_validate_required_profiles(catalog, result)
	if not result.errors.is_empty():
		return result
	_canonicalize_profile_order(catalog)
	catalog.build_indexes()
	result.catalog = catalog
	return result


static func _read_text(path: String, result: LoadResult) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Unable to read combat V2 profile: %s" % path)
		return ""
	return file.get_as_text()


static func _parse_json(text: String, result: LoadResult) -> Variant:
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		result.errors.append(
			"combat_v2: JSON parse error at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return null
	return parser.data


static func _validate_base_catalog(base_catalog: ContentCatalog, result: LoadResult) -> void:
	if base_catalog == null:
		result.errors.append("base_catalog: valid ContentCatalog is required")
		return
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		if not base_catalog.has_operator(operator_id):
			result.errors.append("base_catalog: missing operator '%s'" % operator_id)
	for patch_id: StringName in REQUIRED_PATCH_IDS:
		if not base_catalog.has_patch(patch_id):
			result.errors.append("base_catalog: missing patch '%s'" % patch_id)


static func _parse_balance(data: Dictionary, result: LoadResult) -> CombatV2Catalog.BalanceProfile:
	_validate_keys(data, BALANCE_KEYS, "combat_v2.balance", result)
	var profile := CombatV2Catalog.BalanceProfile.new()
	profile.max_stage = _required_positive_int(data, "max_stage", "combat_v2.balance", result)
	profile.normal_enemy_count = _required_positive_int(
		data, "normal_enemy_count", "combat_v2.balance", result
	)
	profile.hp_per_level = _required_fraction(data, "hp_per_level", "combat_v2.balance", result)
	profile.revive_fraction = _required_fraction(
		data, "revive_fraction", "combat_v2.balance", result
	)
	profile.damage_growth = _required_positive_float(
		data, "damage_growth", "combat_v2.balance", result
	)
	if profile.max_stage != 10:
		result.errors.append("combat_v2.balance.max_stage: prototype requires exactly 10")
	if profile.normal_enemy_count != 3:
		result.errors.append("combat_v2.balance.normal_enemy_count: exactly 3 is required")
	if profile.damage_growth <= 1.0:
		result.errors.append("combat_v2.balance.damage_growth: must be greater than 1")
	return profile


static func _parse_diagnosis(
	data: Dictionary,
	result: LoadResult
) -> CombatV2Catalog.DiagnosisThresholds:
	_validate_keys(data, DIAGNOSIS_KEYS, "combat_v2.diagnosis", result)
	var thresholds := CombatV2Catalog.DiagnosisThresholds.new()
	thresholds.ttk_regression_fraction = _required_fraction(
		data, "ttk_regression_fraction", "combat_v2.diagnosis", result
	)
	thresholds.team_hp_loss_fraction = _required_fraction(
		data, "team_hp_loss_fraction", "combat_v2.diagnosis", result
	)
	thresholds.recovery_delay_seconds = _required_positive_float(
		data, "recovery_delay_seconds", "combat_v2.diagnosis", result
	)
	thresholds.minimum_uptime_fraction = _required_fraction(
		data, "minimum_uptime_fraction", "combat_v2.diagnosis", result
	)
	thresholds.patch_bits_regression_fraction = _required_fraction(
		data, "patch_bits_regression_fraction", "combat_v2.diagnosis", result
	)
	thresholds.boss_heal_regression_fraction = _required_fraction(
		data, "boss_heal_regression_fraction", "combat_v2.diagnosis", result
	)
	return thresholds


static func _parse_operators(
	raw_items: Array,
	base_catalog: ContentCatalog,
	result: LoadResult
) -> Array[CombatV2Catalog.OperatorProfile]:
	var profiles: Array[CombatV2Catalog.OperatorProfile] = []
	var seen_ids: Dictionary = {}
	for index: int in raw_items.size():
		var raw_item: Variant = raw_items[index]
		var context := "combat_v2.operators[%d]" % index
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		var id_text := _required_string(data, "id", context, result)
		var role_name := _required_string(data, "role_name", context, result)
		var operator_id := StringName(id_text)
		if operator_id == &"qa_imp":
			_validate_keys(data, QA_OPERATOR_KEYS, context, result)
		else:
			_validate_keys(data, OPERATOR_KEYS, context, result)
		if not CombatV2Catalog.STABLE_OPERATOR_IDS.has(operator_id):
			result.errors.append("%s.id: unknown operator '%s'" % [context, id_text])
		if seen_ids.has(operator_id):
			result.errors.append("%s.id: duplicate id '%s'" % [context, id_text])
		if not base_catalog.has_operator(operator_id):
			result.errors.append("%s.id: operator is absent from base catalog" % context)

		var base_hp := _required_positive_float(data, "base_hp", context, result)
		var attack_interval := _required_positive_float(data, "attack_interval", context, result)
		var recovery_duration := _required_positive_float(
			data, "recovery_duration", context, result
		)
		var threat_weight := _required_positive_float(data, "threat_weight", context, result)
		var outgoing_multiplier := _required_positive_float(
			data, "outgoing_multiplier", context, result
		)
		var damage_exponent_multiplier := _required_positive_float(
			data, "damage_exponent_multiplier", context, result
		)
		if damage_exponent_multiplier > 1.0:
			result.errors.append(
				"%s.damage_exponent_multiplier: must not exceed 1" % context
			)
		var incoming_multiplier := _required_positive_float(
			data, "incoming_multiplier", context, result
		)
		var boss_multiplier := _required_positive_float(data, "boss_multiplier", context, result)
		var team_interval_multiplier := _required_positive_float(
			data, "team_interval_multiplier", context, result
		)
		if team_interval_multiplier > 1.0:
			result.errors.append("%s.team_interval_multiplier: must not exceed 1" % context)

		var repair_interval := 0.0
		var repair_reduction := 0.0
		if operator_id == &"qa_imp":
			repair_interval = _required_positive_float(data, "repair_interval", context, result)
			repair_reduction = _required_positive_float(data, "repair_reduction", context, result)
			if repair_reduction >= repair_interval:
				result.errors.append("%s.repair_reduction: must be less than repair_interval" % context)
		if result.errors.size() != start_error_count:
			continue
		seen_ids[operator_id] = true
		profiles.append(CombatV2Catalog.OperatorProfile.new(
			operator_id,
			role_name,
			base_hp,
			attack_interval,
			recovery_duration,
			threat_weight,
			outgoing_multiplier,
			damage_exponent_multiplier,
			incoming_multiplier,
			boss_multiplier,
			team_interval_multiplier,
			repair_interval,
			repair_reduction
		))
	return profiles


static func _parse_enemies(
	raw_items: Array,
	result: LoadResult
) -> Array[CombatV2Catalog.EnemyProfile]:
	var profiles: Array[CombatV2Catalog.EnemyProfile] = []
	var seen_ids: Dictionary = {}
	for index: int in raw_items.size():
		var raw_item: Variant = raw_items[index]
		var context := "combat_v2.enemies[%d]" % index
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		var id_text := _required_string(data, "id", context, result)
		var enemy_id := StringName(id_text)
		var display_name := _required_string(data, "display_name", context, result)
		var pattern_text := _required_string(data, "pattern", context, result)
		var pattern := StringName(pattern_text)
		_validate_enemy_keys(data, enemy_id, context, result)
		_validate_enemy_identity(enemy_id, pattern, context, result)
		if seen_ids.has(enemy_id):
			result.errors.append("%s.id: duplicate id '%s'" % [context, id_text])

		var profile := CombatV2Catalog.EnemyProfile.new(enemy_id, display_name, pattern)
		if enemy_id == &"watchdog_process":
			profile.poll_interval = _required_positive_float(data, "poll_interval", context, result)
			profile.poll_damage = _required_positive_float(data, "poll_damage", context, result)
			profile.special_interval = _required_positive_float(
				data, "special_interval", context, result
			)
			profile.special_damage = _required_positive_float(
				data, "special_damage", context, result
			)
			profile.rollback_interval = _required_positive_float(
				data, "rollback_interval", context, result
			)
			profile.rollback_fraction = _required_fraction(
				data, "rollback_fraction", context, result
			)
		else:
			profile.attack_interval = _required_positive_float(
				data, "attack_interval", context, result
			)
			profile.attack_damage = _required_positive_float(
				data, "attack_damage", context, result
			)
			if enemy_id == &"infinite_loop":
				profile.burst_count = _required_positive_int(data, "burst_count", context, result)
				profile.burst_gap = _required_positive_float(data, "burst_gap", context, result)
				if profile.burst_count < 2:
					result.errors.append("%s.burst_count: at least 2 is required" % context)
				if profile.burst_gap >= profile.attack_interval:
					result.errors.append("%s.burst_gap: must be less than attack_interval" % context)
		if result.errors.size() != start_error_count:
			continue
		seen_ids[enemy_id] = true
		profiles.append(profile)
	return profiles


static func _validate_enemy_keys(
	data: Dictionary,
	enemy_id: StringName,
	context: String,
	result: LoadResult
) -> void:
	if enemy_id == &"infinite_loop":
		_validate_keys(data, BURST_ENEMY_KEYS, context, result)
	elif enemy_id == &"watchdog_process":
		_validate_keys(data, WATCHDOG_ENEMY_KEYS, context, result)
	else:
		_validate_keys(data, STANDARD_ENEMY_KEYS, context, result)


static func _validate_enemy_identity(
	enemy_id: StringName,
	pattern: StringName,
	context: String,
	result: LoadResult
) -> void:
	var expected_pattern := &""
	match enemy_id:
		&"broken_pixel":
			expected_pattern = &"focused"
		&"infinite_loop":
			expected_pattern = &"burst"
		&"missing_resource":
			expected_pattern = &"aoe"
		&"watchdog_process":
			expected_pattern = &"watchdog"
		_:
			result.errors.append("%s.id: unknown enemy '%s'" % [context, enemy_id])
			return
	if pattern != expected_pattern:
		result.errors.append(
			"%s.pattern: enemy '%s' requires pattern '%s'"
			% [context, enemy_id, expected_pattern]
		)


static func _validate_required_profiles(catalog: CombatV2Catalog, result: LoadResult) -> void:
	var operator_ids: Dictionary = {}
	for profile: CombatV2Catalog.OperatorProfile in catalog.operators:
		operator_ids[profile.id] = true
	for required_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		if not operator_ids.has(required_id):
			result.errors.append("combat_v2.operators: missing required id '%s'" % required_id)
	if catalog.operators.size() != CombatV2Catalog.STABLE_OPERATOR_IDS.size():
		result.errors.append("combat_v2.operators: exactly four profiles are required")

	var enemy_ids: Dictionary = {}
	for profile: CombatV2Catalog.EnemyProfile in catalog.enemies:
		enemy_ids[profile.id] = true
	for required_id: StringName in CombatV2Catalog.STABLE_ENEMY_IDS:
		if not enemy_ids.has(required_id):
			result.errors.append("combat_v2.enemies: missing required id '%s'" % required_id)
	if catalog.enemies.size() != CombatV2Catalog.STABLE_ENEMY_IDS.size():
		result.errors.append("combat_v2.enemies: exactly four profiles are required")


static func _canonicalize_profile_order(catalog: CombatV2Catalog) -> void:
	var operators_by_id: Dictionary = {}
	for profile: CombatV2Catalog.OperatorProfile in catalog.operators:
		operators_by_id[profile.id] = profile
	var ordered_operators: Array[CombatV2Catalog.OperatorProfile] = []
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		assert(operators_by_id.has(operator_id), "Validated operator profile is missing")
		ordered_operators.append(
			operators_by_id[operator_id] as CombatV2Catalog.OperatorProfile
		)
	catalog.operators = ordered_operators

	var enemies_by_id: Dictionary = {}
	for profile: CombatV2Catalog.EnemyProfile in catalog.enemies:
		enemies_by_id[profile.id] = profile
	var ordered_enemies: Array[CombatV2Catalog.EnemyProfile] = []
	for enemy_id: StringName in CombatV2Catalog.STABLE_ENEMY_IDS:
		assert(enemies_by_id.has(enemy_id), "Validated enemy profile is missing")
		ordered_enemies.append(enemies_by_id[enemy_id] as CombatV2Catalog.EnemyProfile)
	catalog.enemies = ordered_enemies


static func _validate_keys(
	data: Dictionary,
	expected_keys: Array[String],
	context: String,
	result: LoadResult
) -> void:
	for expected_key: String in expected_keys:
		if not data.has(expected_key):
			result.errors.append("%s.%s: required field is missing" % [context, expected_key])
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not expected_keys.has(String(raw_key)):
			result.errors.append("%s.%s: unknown field" % [context, String(raw_key)])


static func _required_string(
	data: Dictionary,
	key: String,
	context: String,
	result: LoadResult
) -> String:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING:
		result.errors.append("%s.%s: non-empty string is required" % [context, key])
		return ""
	var value := String(data[key]).strip_edges()
	if value.is_empty():
		result.errors.append("%s.%s: non-empty string is required" % [context, key])
	return value


static func _required_positive_float(
	data: Dictionary,
	key: String,
	context: String,
	result: LoadResult
) -> float:
	if not data.has(key) or not _is_number(data[key]):
		result.errors.append("%s.%s: number is required" % [context, key])
		return 0.0
	var value := float(data[key])
	if value <= 0.0 or not is_finite(value):
		result.errors.append("%s.%s: finite value greater than zero is required" % [context, key])
		return 0.0
	return value


static func _required_fraction(
	data: Dictionary,
	key: String,
	context: String,
	result: LoadResult
) -> float:
	var value := _required_positive_float(data, key, context, result)
	if value > 1.0:
		result.errors.append("%s.%s: value must not exceed 1" % [context, key])
	return value


static func _required_positive_int(
	data: Dictionary,
	key: String,
	context: String,
	result: LoadResult
) -> int:
	if not data.has(key) or not _is_number(data[key]):
		result.errors.append("%s.%s: positive integer is required" % [context, key])
		return 0
	var numeric := float(data[key])
	var value := int(numeric)
	if value <= 0 or not is_finite(numeric) or not is_equal_approx(numeric, float(value)):
		result.errors.append("%s.%s: positive integer is required" % [context, key])
		return 0
	return value


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
