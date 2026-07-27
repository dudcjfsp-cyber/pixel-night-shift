class_name ProductV2Loader
extends RefCounted

const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const PROFILE_PATH := "res://game/content/product_v2/product_v2.json"
const REQUIRED_SHIFT_COUNT := 2
const REQUIRED_NORMAL_WAVE_COUNT := 9
const MAX_ENEMIES_PER_WAVE := 6
const MIN_BOSS_ACTION_SECONDS := 0.05
const MAX_CONTENT_NUMBER := 1_000_000_000.0

const ROOT_KEYS: Array[String] = [
	"balance", "enemy_archetypes", "shifts",
]
const BALANCE_KEYS: Array[String] = [
	"countdown_seconds",
	"normal_wave_seconds",
	"transition_seconds",
	"boss_warning_seconds",
	"boss_seconds",
	"max_stability",
	"wave_leak_cap",
	"danger_stability",
	"star_thresholds",
	"first_star_reward_bits",
	"starting_bits",
	"base_salary_bits",
	"completed_wave_salary_bits",
	"boss_defeat_salary_bits",
	"stability_step_percent",
	"stability_step_salary_bits",
	"patch_equip_cost_bits",
	"day_income_interval_seconds",
	"day_income_cap_seconds",
	"day_income_cap_bits",
	"version_patch_notes_reward",
	"operator_hp_growth",
	"qa_rescue_delay",
	"qa_rescue_hp_fraction",
]
const ENEMY_KEYS: Array[String] = [
	"id", "display_name", "asset_id", "base_hp", "leak_damage",
]
const SHIFT_KEYS: Array[String] = [
	"index", "health_multiplier", "waves", "boss",
]
const WAVE_KEYS: Array[String] = [
	"number", "hp_multiplier", "entries",
]
const WAVE_ENTRY_KEYS: Array[String] = [
	"enemy_id", "count",
]
const BOSS_KEYS: Array[String] = [
	"id",
	"display_name",
	"asset_id",
	"max_hp",
	"poll_interval",
	"poll_damage",
	"special_interval",
	"special_damage",
	"rollback_interval",
	"rollback_fraction",
	"debuff_start_seconds",
	"debuff_multiplier",
]


class LoadResult:
	extends RefCounted

	var catalog: ProductV2Catalog
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
		result.errors.append("product_v2: root must be an object")
		return result

	var root := raw_profile as Dictionary
	_validate_keys(root, ROOT_KEYS, "product_v2", result)
	if not result.errors.is_empty():
		return result
	if typeof(root["balance"]) != TYPE_DICTIONARY:
		result.errors.append("product_v2.balance: object is required")
	if typeof(root["enemy_archetypes"]) != TYPE_ARRAY:
		result.errors.append("product_v2.enemy_archetypes: array is required")
	if typeof(root["shifts"]) != TYPE_ARRAY:
		result.errors.append("product_v2.shifts: array is required")
	if not result.errors.is_empty():
		return result

	var catalog := ProductV2Catalog.new()
	catalog.base_catalog = base_catalog
	catalog.balance = _parse_balance(root["balance"] as Dictionary, result)
	catalog.enemy_archetypes = _parse_enemies(
		root["enemy_archetypes"] as Array, result
	)
	catalog.shifts = _parse_shifts(
		root["shifts"] as Array, catalog.balance, result
	)
	_validate_required_content(catalog, result)
	if not result.errors.is_empty():
		return result
	_canonicalize_content(catalog)
	catalog.build_indexes()
	result.catalog = catalog
	return result


static func _read_text(path: String, result: LoadResult) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Unable to read Product V2 profile: %s" % path)
		return ""
	return file.get_as_text()


static func _parse_json(text: String, result: LoadResult) -> Variant:
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		result.errors.append(
			"product_v2: JSON parse error at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return null
	return parser.data


static func _validate_base_catalog(base_catalog: ContentCatalog, result: LoadResult) -> void:
	if base_catalog == null:
		result.errors.append("base_catalog: valid ContentCatalog is required")
		return
	for operator_id: StringName in ProductV2Catalog.STABLE_OPERATOR_IDS:
		if not base_catalog.has_operator(operator_id):
			result.errors.append("base_catalog: missing operator '%s'" % operator_id)
	for patch_id: StringName in ProductV2Catalog.STABLE_PATCH_IDS:
		if not base_catalog.has_patch(patch_id):
			result.errors.append("base_catalog: missing patch '%s'" % patch_id)


static func _parse_balance(
	data: Dictionary,
	result: LoadResult
) -> ProductV2Catalog.BalanceProfile:
	var profile := ProductV2Catalog.BalanceProfile.new()
	_validate_keys(data, BALANCE_KEYS, "product_v2.balance", result)
	profile.countdown_seconds = _required_positive_float(
		data, "countdown_seconds", "product_v2.balance", result
	)
	profile.normal_wave_seconds = _required_positive_float(
		data, "normal_wave_seconds", "product_v2.balance", result
	)
	profile.transition_seconds = _required_positive_float(
		data, "transition_seconds", "product_v2.balance", result
	)
	profile.boss_warning_seconds = _required_positive_float(
		data, "boss_warning_seconds", "product_v2.balance", result
	)
	profile.boss_seconds = _required_positive_float(
		data, "boss_seconds", "product_v2.balance", result
	)
	profile.max_stability = _required_positive_int(
		data, "max_stability", "product_v2.balance", result
	)
	profile.wave_leak_cap = _required_positive_int(
		data, "wave_leak_cap", "product_v2.balance", result
	)
	profile.danger_stability = _required_positive_int(
		data, "danger_stability", "product_v2.balance", result
	)
	profile.star_thresholds = _required_increasing_positive_int_array(
		data, "star_thresholds", "product_v2.balance", result
	)
	profile.first_star_reward_bits = _required_increasing_positive_int_array(
		data, "first_star_reward_bits", "product_v2.balance", result
	)
	profile.starting_bits = _required_positive_int(
		data, "starting_bits", "product_v2.balance", result
	)
	profile.base_salary_bits = _required_positive_int(
		data, "base_salary_bits", "product_v2.balance", result
	)
	profile.completed_wave_salary_bits = _required_positive_int(
		data, "completed_wave_salary_bits", "product_v2.balance", result
	)
	profile.boss_defeat_salary_bits = _required_positive_int(
		data, "boss_defeat_salary_bits", "product_v2.balance", result
	)
	profile.stability_step_percent = _required_positive_int(
		data, "stability_step_percent", "product_v2.balance", result
	)
	profile.stability_step_salary_bits = _required_positive_int(
		data, "stability_step_salary_bits", "product_v2.balance", result
	)
	profile.patch_equip_cost_bits = _required_positive_int(
		data, "patch_equip_cost_bits", "product_v2.balance", result
	)
	profile.day_income_interval_seconds = _required_positive_int(
		data, "day_income_interval_seconds", "product_v2.balance", result
	)
	profile.day_income_cap_seconds = _required_positive_int(
		data, "day_income_cap_seconds", "product_v2.balance", result
	)
	profile.day_income_cap_bits = _required_positive_int(
		data, "day_income_cap_bits", "product_v2.balance", result
	)
	profile.version_patch_notes_reward = _required_positive_int(
		data, "version_patch_notes_reward", "product_v2.balance", result
	)
	profile.operator_hp_growth = _required_positive_float(
		data, "operator_hp_growth", "product_v2.balance", result
	)
	profile.qa_rescue_delay = _required_positive_float(
		data, "qa_rescue_delay", "product_v2.balance", result
	)
	profile.qa_rescue_hp_fraction = _required_fraction(
		data, "qa_rescue_hp_fraction", "product_v2.balance", result
	)

	_require_fixed_float(
		profile.countdown_seconds, 2.0, "product_v2.balance.countdown_seconds", result
	)
	_require_fixed_float(
		profile.normal_wave_seconds, 5.0, "product_v2.balance.normal_wave_seconds", result
	)
	_require_fixed_float(
		profile.transition_seconds, 0.4, "product_v2.balance.transition_seconds", result
	)
	_require_fixed_float(
		profile.boss_warning_seconds, 1.0, "product_v2.balance.boss_warning_seconds", result
	)
	_require_fixed_float(
		profile.boss_seconds, 30.0, "product_v2.balance.boss_seconds", result
	)
	if profile.max_stability != 100:
		result.errors.append("product_v2.balance.max_stability: must be exactly 100")
	if profile.wave_leak_cap != 40:
		result.errors.append("product_v2.balance.wave_leak_cap: must be exactly 40")
	if profile.danger_stability != 40:
		result.errors.append("product_v2.balance.danger_stability: must be exactly 40")
	if profile.wave_leak_cap > profile.max_stability:
		result.errors.append(
			"product_v2.balance.wave_leak_cap: must not exceed max_stability"
		)
	if profile.danger_stability > profile.max_stability:
		result.errors.append(
			"product_v2.balance.danger_stability: must not exceed max_stability"
		)
	if (
		profile.star_thresholds.size() != 3
		or profile.star_thresholds != PackedInt32Array([3, 6, 10])
	):
		result.errors.append(
			"product_v2.balance.star_thresholds: must be exactly [3, 6, 10]"
		)
	if (
		profile.first_star_reward_bits.size() != 3
		or profile.first_star_reward_bits != PackedInt32Array([12, 18, 30])
	):
		result.errors.append(
			"product_v2.balance.first_star_reward_bits: must be exactly [12, 18, 30]"
		)
	var fixed_integer_values := {
		"starting_bits": 30,
		"base_salary_bits": 12,
		"completed_wave_salary_bits": 3,
		"boss_defeat_salary_bits": 6,
		"stability_step_percent": 20,
		"stability_step_salary_bits": 2,
		"patch_equip_cost_bits": 8,
		"day_income_interval_seconds": 1200,
		"day_income_cap_seconds": 43200,
		"day_income_cap_bits": 36,
		"version_patch_notes_reward": 1,
	}
	for key: String in fixed_integer_values:
		if int(profile.get(key)) != int(fixed_integer_values[key]):
			result.errors.append(
				"product_v2.balance.%s: must be exactly %d"
				% [key, int(fixed_integer_values[key])]
			)
	if (
		profile.day_income_cap_seconds / profile.day_income_interval_seconds
		!= profile.day_income_cap_bits
	):
		result.errors.append(
			"product_v2.balance: day income cap seconds and bits must agree"
		)
	if profile.operator_hp_growth <= 1.0:
		result.errors.append(
			"product_v2.balance.operator_hp_growth: must be greater than 1"
		)
	return profile


static func _parse_enemies(
	raw_items: Array,
	result: LoadResult
) -> Array[ProductV2Catalog.EnemyArchetype]:
	var archetypes: Array[ProductV2Catalog.EnemyArchetype] = []
	var seen_ids: Dictionary = {}
	for index: int in raw_items.size():
		var raw_item: Variant = raw_items[index]
		var context := "product_v2.enemy_archetypes[%d]" % index
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		_validate_keys(data, ENEMY_KEYS, context, result)
		var id := StringName(_required_string(data, "id", context, result))
		var display_name := _required_string(data, "display_name", context, result)
		var asset_id := StringName(_required_string(data, "asset_id", context, result))
		var base_hp := _required_positive_float(data, "base_hp", context, result)
		var leak_damage := _required_positive_int(data, "leak_damage", context, result)
		if not ProductV2Catalog.STABLE_ENEMY_IDS.has(id):
			result.errors.append("%s.id: unknown enemy archetype '%s'" % [context, id])
		if seen_ids.has(id):
			result.errors.append("%s.id: duplicate id '%s'" % [context, id])
		var expected_asset := _expected_enemy_asset(id)
		if expected_asset != &"" and asset_id != expected_asset:
			result.errors.append(
				"%s.asset_id: enemy '%s' requires asset '%s'"
				% [context, id, expected_asset]
			)
		var expected_leak := _expected_leak_damage(id)
		if expected_leak > 0 and leak_damage != expected_leak:
			result.errors.append(
				"%s.leak_damage: enemy '%s' requires exactly %d"
				% [context, id, expected_leak]
			)
		if result.errors.size() != start_error_count:
			continue
		var archetype := ProductV2Catalog.EnemyArchetype.new()
		archetype.id = id
		archetype.display_name = display_name
		archetype.asset_id = asset_id
		archetype.base_hp = base_hp
		archetype.leak_damage = leak_damage
		seen_ids[id] = true
		archetypes.append(archetype)
	return archetypes


static func _parse_shifts(
	raw_items: Array,
	balance: ProductV2Catalog.BalanceProfile,
	result: LoadResult
) -> Array[ProductV2Catalog.ShiftProfile]:
	var profiles: Array[ProductV2Catalog.ShiftProfile] = []
	var seen_indexes: Dictionary = {}
	for array_index: int in raw_items.size():
		var raw_item: Variant = raw_items[array_index]
		var context := "product_v2.shifts[%d]" % array_index
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		_validate_keys(data, SHIFT_KEYS, context, result)
		var shift_index := _required_positive_int(data, "index", context, result)
		var health_multiplier := _required_positive_float(
			data, "health_multiplier", context, result
		)
		if shift_index != array_index + 1:
			result.errors.append(
				"%s.index: shifts must be ordered and numbered 1..%d"
				% [context, REQUIRED_SHIFT_COUNT]
			)
		if seen_indexes.has(shift_index):
			result.errors.append("%s.index: duplicate shift index %d" % [context, shift_index])
		if not data.has("waves") or typeof(data["waves"]) != TYPE_ARRAY:
			result.errors.append("%s.waves: array is required" % context)
		if not data.has("boss") or typeof(data["boss"]) != TYPE_DICTIONARY:
			result.errors.append("%s.boss: object is required" % context)
		if result.errors.size() != start_error_count:
			continue

		var profile := ProductV2Catalog.ShiftProfile.new()
		profile.index = shift_index
		profile.health_multiplier = health_multiplier
		profile.waves = _parse_waves(data["waves"] as Array, context, result)
		profile.boss = _parse_boss(
			data["boss"] as Dictionary, balance, context, result
		)
		seen_indexes[shift_index] = true
		profiles.append(profile)
	return profiles


static func _parse_waves(
	raw_items: Array,
	shift_context: String,
	result: LoadResult
) -> Array[ProductV2Catalog.WaveProfile]:
	var profiles: Array[ProductV2Catalog.WaveProfile] = []
	var seen_numbers: Dictionary = {}
	if raw_items.size() != REQUIRED_NORMAL_WAVE_COUNT:
		result.errors.append(
			"%s.waves: exactly %d normal waves are required"
			% [shift_context, REQUIRED_NORMAL_WAVE_COUNT]
		)
	for array_index: int in raw_items.size():
		var raw_item: Variant = raw_items[array_index]
		var context := "%s.waves[%d]" % [shift_context, array_index]
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		_validate_keys(data, WAVE_KEYS, context, result)
		var wave_number := _required_positive_int(data, "number", context, result)
		var hp_multiplier := _required_positive_float(
			data, "hp_multiplier", context, result
		)
		if wave_number != array_index + 1 or wave_number > REQUIRED_NORMAL_WAVE_COUNT:
			result.errors.append(
				"%s.number: waves must be ordered and numbered 1..%d"
				% [context, REQUIRED_NORMAL_WAVE_COUNT]
			)
		if seen_numbers.has(wave_number):
			result.errors.append("%s.number: duplicate wave number %d" % [context, wave_number])
		if not data.has("entries") or typeof(data["entries"]) != TYPE_ARRAY:
			result.errors.append("%s.entries: array is required" % context)
		if result.errors.size() != start_error_count:
			continue
		var entries := _parse_wave_entries(data["entries"] as Array, context, result)
		if entries.is_empty():
			result.errors.append("%s.entries: at least one enemy entry is required" % context)
			continue
		var total_enemy_count := 0
		for entry: ProductV2Catalog.WaveEntry in entries:
			total_enemy_count += entry.count
		if total_enemy_count > MAX_ENEMIES_PER_WAVE:
			result.errors.append(
				"%s.entries: at most %d enemies are allowed per wave"
				% [context, MAX_ENEMIES_PER_WAVE]
			)
			continue
		var profile := ProductV2Catalog.WaveProfile.new()
		profile.number = wave_number
		profile.hp_multiplier = hp_multiplier
		profile.entries = entries
		seen_numbers[wave_number] = true
		profiles.append(profile)
	return profiles


static func _parse_wave_entries(
	raw_items: Array,
	wave_context: String,
	result: LoadResult
) -> Array[ProductV2Catalog.WaveEntry]:
	var entries: Array[ProductV2Catalog.WaveEntry] = []
	var seen_enemy_ids: Dictionary = {}
	for index: int in raw_items.size():
		var raw_item: Variant = raw_items[index]
		var context := "%s.entries[%d]" % [wave_context, index]
		if typeof(raw_item) != TYPE_DICTIONARY:
			result.errors.append("%s: item must be an object" % context)
			continue
		var data := raw_item as Dictionary
		var start_error_count := result.errors.size()
		_validate_keys(data, WAVE_ENTRY_KEYS, context, result)
		var enemy_id := StringName(_required_string(data, "enemy_id", context, result))
		var count := _required_positive_int(data, "count", context, result)
		if not ProductV2Catalog.STABLE_ENEMY_IDS.has(enemy_id):
			result.errors.append("%s.enemy_id: unknown enemy '%s'" % [context, enemy_id])
		if seen_enemy_ids.has(enemy_id):
			result.errors.append(
				"%s.enemy_id: duplicate enemy '%s' in one wave" % [context, enemy_id]
			)
		if result.errors.size() != start_error_count:
			continue
		var entry := ProductV2Catalog.WaveEntry.new()
		entry.enemy_id = enemy_id
		entry.count = count
		seen_enemy_ids[enemy_id] = true
		entries.append(entry)
	return entries


static func _parse_boss(
	data: Dictionary,
	balance: ProductV2Catalog.BalanceProfile,
	shift_context: String,
	result: LoadResult
) -> ProductV2Catalog.BossProfile:
	var context := "%s.boss" % shift_context
	var profile := ProductV2Catalog.BossProfile.new()
	_validate_keys(data, BOSS_KEYS, context, result)
	profile.id = StringName(_required_string(data, "id", context, result))
	profile.display_name = _required_string(data, "display_name", context, result)
	profile.asset_id = StringName(_required_string(data, "asset_id", context, result))
	profile.max_hp = _required_positive_float(data, "max_hp", context, result)
	profile.poll_interval = _required_positive_float(
		data, "poll_interval", context, result
	)
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
	profile.debuff_start_seconds = _required_positive_float(
		data, "debuff_start_seconds", context, result
	)
	profile.debuff_multiplier = _required_fraction(
		data, "debuff_multiplier", context, result
	)
	if profile.poll_interval < MIN_BOSS_ACTION_SECONDS:
		result.errors.append(
			"%s.poll_interval: must be at least %.2f seconds"
			% [context, MIN_BOSS_ACTION_SECONDS]
		)
	if profile.special_interval < MIN_BOSS_ACTION_SECONDS:
		result.errors.append(
			"%s.special_interval: must be at least %.2f seconds"
			% [context, MIN_BOSS_ACTION_SECONDS]
		)
	if profile.rollback_interval < MIN_BOSS_ACTION_SECONDS:
		result.errors.append(
			"%s.rollback_interval: must be at least %.2f seconds"
			% [context, MIN_BOSS_ACTION_SECONDS]
		)
	if profile.id != ProductV2Catalog.BOSS_ID:
		result.errors.append(
			"%s.id: boss must be '%s'" % [context, ProductV2Catalog.BOSS_ID]
		)
	if profile.asset_id != ProductV2Catalog.BOSS_ASSET_ID:
		result.errors.append(
			"%s.asset_id: boss requires asset '%s'"
			% [context, ProductV2Catalog.BOSS_ASSET_ID]
		)
	if (
		balance != null
		and balance.boss_seconds > 0.0
		and profile.debuff_start_seconds > balance.boss_seconds
	):
		result.errors.append(
			"%s.debuff_start_seconds: must not exceed the boss time limit" % context
		)
	return profile


static func _validate_required_content(
	catalog: ProductV2Catalog,
	result: LoadResult
) -> void:
	var enemy_ids: Dictionary = {}
	for archetype: ProductV2Catalog.EnemyArchetype in catalog.enemy_archetypes:
		enemy_ids[archetype.id] = true
	for required_id: StringName in ProductV2Catalog.STABLE_ENEMY_IDS:
		if not enemy_ids.has(required_id):
			result.errors.append(
				"product_v2.enemy_archetypes: missing required id '%s'" % required_id
			)
	if catalog.enemy_archetypes.size() != ProductV2Catalog.STABLE_ENEMY_IDS.size():
		result.errors.append(
			"product_v2.enemy_archetypes: exactly three archetypes are required"
		)

	if catalog.shifts.size() != REQUIRED_SHIFT_COUNT:
		result.errors.append(
			"product_v2.shifts: exactly %d shifts are required" % REQUIRED_SHIFT_COUNT
		)
	for expected_index: int in range(1, REQUIRED_SHIFT_COUNT + 1):
		var found := false
		for profile: ProductV2Catalog.ShiftProfile in catalog.shifts:
			if profile.index == expected_index:
				found = true
				if profile.waves.size() != REQUIRED_NORMAL_WAVE_COUNT:
					result.errors.append(
						"product_v2.shifts[%d].waves: exactly %d valid waves are required"
						% [expected_index - 1, REQUIRED_NORMAL_WAVE_COUNT]
					)
				break
		if not found:
			result.errors.append("product_v2.shifts: missing shift index %d" % expected_index)


static func _canonicalize_content(catalog: ProductV2Catalog) -> void:
	var enemies_by_id: Dictionary = {}
	for archetype: ProductV2Catalog.EnemyArchetype in catalog.enemy_archetypes:
		enemies_by_id[archetype.id] = archetype
	var ordered_enemies: Array[ProductV2Catalog.EnemyArchetype] = []
	for enemy_id: StringName in ProductV2Catalog.STABLE_ENEMY_IDS:
		assert(enemies_by_id.has(enemy_id), "Validated enemy archetype is missing")
		ordered_enemies.append(
			enemies_by_id[enemy_id] as ProductV2Catalog.EnemyArchetype
		)
	catalog.enemy_archetypes = ordered_enemies

	var shifts_by_index: Dictionary = {}
	for profile: ProductV2Catalog.ShiftProfile in catalog.shifts:
		shifts_by_index[profile.index] = profile
	var ordered_shifts: Array[ProductV2Catalog.ShiftProfile] = []
	for shift_index: int in range(1, REQUIRED_SHIFT_COUNT + 1):
		assert(shifts_by_index.has(shift_index), "Validated shift profile is missing")
		ordered_shifts.append(
			shifts_by_index[shift_index] as ProductV2Catalog.ShiftProfile
		)
	catalog.shifts = ordered_shifts


static func _expected_enemy_asset(enemy_id: StringName) -> StringName:
	match enemy_id:
		&"small":
			return &"broken_pixel"
		&"standard":
			return &"missing_resource"
		&"surge":
			return &"infinite_loop"
		_:
			return &""


static func _expected_leak_damage(enemy_id: StringName) -> int:
	match enemy_id:
		&"small":
			return 5
		&"standard":
			return 10
		&"surge":
			return 20
		_:
			return 0


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
	if value <= 0.0 or value > MAX_CONTENT_NUMBER or not is_finite(value):
		result.errors.append(
			"%s.%s: finite value in (0, %s] is required"
			% [context, key, MAX_CONTENT_NUMBER]
		)
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


static func _required_increasing_positive_int_array(
	data: Dictionary,
	key: String,
	context: String,
	result: LoadResult
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
			result.errors.append(
				"%s.%s[%d]: positive integer is required" % [context, key, index]
			)
			continue
		var numeric := float(raw_value)
		var value := int(numeric)
		if (
			value <= previous
			or not is_finite(numeric)
			or not is_equal_approx(numeric, float(value))
		):
			result.errors.append(
				"%s.%s: entries must be strictly increasing positive integers"
				% [context, key]
			)
			continue
		values.append(value)
		previous = value
	return values


static func _require_fixed_float(
	actual: float,
	expected: float,
	context: String,
	result: LoadResult
) -> void:
	if not is_equal_approx(actual, expected):
		result.errors.append("%s: must be exactly %s" % [context, expected])


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
