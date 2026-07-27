extends SceneTree

const ProductV2SaveMigrator := preload(
	"res://game/app/product_v2/product_v2_save_migrator.gd"
)
const ProductLoopSession := preload(
	"res://game/app/product_v2/product_loop_session.gd"
)
const ProductV2Loader := preload(
	"res://game/content/product_v2/product_v2_loader.gd"
)
const GameSession := preload(
	"res://game/app/game_session.gd"
)
const TEST_ROOT := "user://product_v2_migration_test"
const SAVED_AT := 2_100_000_000

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Pixel Night Shift Product V2 migration tests")
	print("================================================")
	_test_schema_1_preservation()
	_test_schema_2_preservation()
	_test_invalid_is_atomic()
	_test_schema_3_roundtrip()
	print("================================================")
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _test_schema_1_preservation() -> void:
	var schema_2 := _legacy_schema_2_fixture()
	var schema_1: Dictionary = {}
	for key: String in GameSession.SCHEMA_1_STATE_KEYS:
		schema_1[key] = _copy_value(schema_2[key])
	var result := ProductV2SaveMigrator.migrate(1, schema_1, SAVED_AT)
	_check_preserved(result, 1, "schema 1")


func _test_schema_2_preservation() -> void:
	var result := ProductV2SaveMigrator.migrate(
		2, _legacy_schema_2_fixture(), SAVED_AT
	)
	_check_preserved(result, 2, "schema 2")


func _test_invalid_is_atomic() -> void:
	var invalid := _legacy_schema_2_fixture()
	invalid["bits"] = -1.0
	var invalid_before := invalid.duplicate(true)
	var rejected := ProductV2SaveMigrator.migrate(2, invalid, SAVED_AT)
	_check(not rejected.is_valid(), "invalid legacy data must be rejected")
	_check(not rejected.errors.is_empty(), "invalid migration must return explicit errors")
	_check(rejected.candidate == null, "invalid migration must expose no candidate")
	_check(rejected.session_data.is_empty(), "invalid migration must expose no session data")
	_check(invalid == invalid_before, "migration must not mutate the legacy payload")

	var valid := ProductV2SaveMigrator.migrate(
		2, _legacy_schema_2_fixture(), SAVED_AT
	)
	_check(valid.is_valid(), "atomic fixture migration must be valid")
	if not valid.is_valid():
		return
	var active := ProductLoopSession.new()
	var active_before := active.export_state()
	var corrupt_loop := (
		(valid.session_data["product_loop"] as Dictionary).duplicate(true)
	)
	corrupt_loop["bits"] = -1
	_check(
		not active.restore_migrated_day_state(corrupt_loop).is_empty(),
		"invalid Product V2 migration candidate must be rejected"
	)
	_check(
		active.export_state() == active_before,
		"rejected candidate must not partially mutate an active session"
	)
	var invalid_speed := valid.session_data.duplicate(true)
	(invalid_speed["product_loop"] as Dictionary)["playback_speed"] = 2
	var speed_target := ProductLoopSession.new()
	var speed_before := speed_target.export_state()
	_check(
		not speed_target.restore_state(invalid_speed).is_empty(),
		"DTO must reject DAY_PREP 2x playback"
	)
	_check(
		speed_target.export_state() == speed_before,
		"rejected playback authority must remain atomic"
	)


func _test_schema_3_roundtrip() -> void:
	var migrated := ProductV2SaveMigrator.migrate(
		2, _legacy_schema_2_fixture(), SAVED_AT
	)
	_check(migrated.is_valid(), "schema 3 roundtrip fixture must migrate")
	if not migrated.is_valid():
		return
	_check(
		not migrated.candidate.set_playback_speed(2),
		"DAY_PREP must reject 2x playback"
	)
	var expected := migrated.candidate.export_state()
	var repository := SaveRepository.new(TEST_ROOT)
	_check(repository.clear_records() == OK, "roundtrip fixture cleanup must succeed")
	_check(
		repository.save(expected, SAVED_AT, 0) == OK,
		"migrated state must save in a schema 3 envelope"
	)
	var loaded := repository.load()
	_check(loaded.schema_version == 3, "new Product V2 save must use schema 3")
	var restored := ProductV2SaveMigrator.migrate(
		loaded.schema_version,
		loaded.session_data,
		loaded.saved_at_unix
	)
	_check(restored.is_valid(), "valid schema 3 session must restore")
	if restored.is_valid():
		var canonical := restored.session_data
		var restored_again := ProductV2SaveMigrator.migrate(
			3, canonical, loaded.saved_at_unix
		)
		_check(
			restored_again.is_valid(),
			"canonical schema 3 session must restore repeatedly"
		)
		var repeated_data := (
			restored_again.session_data if restored_again.is_valid() else {}
		)
		var difference := _first_difference(
			canonical, repeated_data
		)
		_check(
			difference.is_empty(),
			"schema 3 durable Product V2 DTO must roundtrip exactly%s"
			% (" (%s)" % difference if not difference.is_empty() else "")
		)
		_check(
			int(restored.candidate.snapshot().get("playback_speed", 0)) == 1,
			"schema 3 restore must preserve 1x DAY playback exactly"
		)
	_check(repository.clear_records() == OK, "roundtrip records must be removed")
	_check_result_json_roundtrip()
	_check_playback_authority()
	_check_fresh_day_meta_roundtrip()


func _check_preserved(result: Variant, source_schema: int, label: String) -> void:
	_check(result.is_valid(), "%s migration must succeed: %s" % [
		label, "; ".join(result.errors),
	])
	if not result.is_valid():
		return
	_check(result.migrated, "%s must be marked as migrated" % label)
	var snapshot := result.candidate.snapshot() as Dictionary
	var loop := result.session_data["product_loop"] as Dictionary
	_check(
		String(snapshot.get("phase_name", "")) == "day_prep",
		"%s migration must enter DAY_PREP" % label
	)
	_check(
		int(snapshot.get("bits", -1)) == 47,
		"%s bits must use a non-negative floor integer" % label
	)
	_check(
		int(snapshot.get("version", -1)) == 3,
		"%s run_count 2 must map to Product V2 version 3" % label
	)
	_check(
		int(snapshot.get("patch_notes", -1)) == 1
		and int(snapshot.get("legacy_cache_level", -1)) == 1,
		"%s patch notes and legacy cache must be preserved" % label
	)
	_check(
		(loop["operator_levels"] as Dictionary) == {
			"debugger": 4,
			"build_engineer": 3,
			"sprite_artist": 2,
			"qa_imp": 1,
		},
		"%s operator levels must be preserved" % label
	)
	_check(
		(loop["unlocked_operator_ids"] as Array).size() == 4
		and (loop["discovered_patch_ids"] as Array).size() == 5
		and int(loop["unlocked_patch_slots"]) == 3,
		"%s unlocks, discoveries, and slots must be preserved" % label
	)
	_check(
		_all_empty(loop["equipped_patch_ids"] as Array),
		"%s equipped patches must be cleared" % label
	)
	_check(
		int(loop["day_income_anchor_unix"]) == SAVED_AT
		and int(loop["migration_source_schema"]) == source_schema
		and int(loop["migration_source_run_count"]) == 2
		and int(loop["migration_saved_at_unix"]) == SAVED_AT,
		"%s DAY anchor and migration provenance must be exact" % label
	)
	_check(
		int(loop["playback_speed"]) == 1,
		"%s migration must begin at 1x playback" % label
	)


func _legacy_schema_2_fixture() -> Dictionary:
	var state := GameSession.new().export_state()
	state["stage"] = 1
	state["highest_stage"] = 20
	state["bits"] = 47.9
	state["patch_notes"] = 1
	state["run_count"] = 2
	state["legacy_cache_level"] = 1
	state["operator_levels"] = {
		"debugger": 4,
		"build_engineer": 3,
		"sprite_artist": 2,
		"qa_imp": 1,
	}
	state["unlocked_operator_ids"] = [
		"debugger", "build_engineer", "sprite_artist", "qa_imp",
	]
	state["discovered_patch_ids"] = [
		"frame_skip",
		"unsafe_build",
		"reward_bypass",
		"rollback_lock",
		"safe_mode",
	]
	state["equipped_patch_ids"] = ["frame_skip", "", ""]
	state["unlocked_patch_slots"] = 3
	return state


func _check_playback_authority() -> void:
	var catalog: Variant = _easy_catalog()
	var session := ProductLoopSession.new(catalog, &"full_team")
	_check(not session.set_playback_speed(2), "fresh DAY must reject 2x playback")
	_check(session.start_shift(1), "playback fixture first NIGHT must start")
	_check(
		int(session.snapshot().get("playback_speed", 0)) == 1
		and not session.set_playback_speed(2),
		"first NIGHT must start at 1x and reject locked 2x"
	)
	_check(session.tick(300.0), "playback fixture first NIGHT must settle")
	_check(
		int(session.snapshot().get("playback_speed", 0)) == 1,
		"terminal settlement must reset playback to 1x"
	)
	_check(session.continue_to_day(SAVED_AT), "playback fixture must return to DAY")
	_check(
		int(session.snapshot().get("playback_speed", 0)) == 1,
		"DAY transition must retain 1x playback"
	)
	_check(session.start_shift(1), "three-star NIGHT retry must start")
	_check(
		int(session.snapshot().get("playback_speed", 0)) == 1,
		"every NIGHT retry must begin at 1x"
	)
	_check(
		session.set_playback_speed(2),
		"three-star active NIGHT retry must allow 2x playback"
	)
	var active_retry := session.export_state()
	var restored_retry := ProductLoopSession.new(catalog, &"full_team")
	_check(
		restored_retry.restore_state(active_retry).is_empty()
		and int(restored_retry.snapshot().get("playback_speed", 0)) == 2,
		"DTO must restore authorized active NIGHT 2x exactly"
	)
	_check(session.tick(300.0), "2x-authorized retry must settle")
	_check(
		int(session.snapshot().get("playback_speed", 0)) == 1,
		"terminal settlement after 2x must reset to 1x"
	)


func _check_fresh_day_meta_roundtrip() -> void:
	var legacy := _legacy_schema_2_fixture()
	legacy["patch_notes"] = 2
	legacy["legacy_cache_level"] = 0
	var migrated := ProductV2SaveMigrator.migrate(2, legacy, SAVED_AT)
	_check(migrated.is_valid(), "fresh DAY meta fixture must migrate")
	if not migrated.is_valid():
		return
	var session: Variant = migrated.candidate
	_check(
		session.upgrade_operator(&"debugger"),
		"fresh DAY operator upgrade must succeed"
	)
	_check(
		session.equip_patch(0, &"frame_skip"),
		"fresh DAY patch equip must succeed"
	)
	_check(
		session.buy_legacy_cache(),
		"fresh DAY legacy-cache purchase must succeed"
	)
	var exported := session.export_state() as Dictionary
	var restored := ProductLoopSession.new()
	var errors: PackedStringArray = restored.restore_state(exported)
	_check(
		errors.is_empty() and restored.export_state() == exported,
		"fresh DAY meta mutations must keep the exported Lab loadout self-restorable"
	)


func _check_result_json_roundtrip() -> void:
	var catalog: Variant = _one_star_result_catalog()
	var session := ProductLoopSession.new(catalog, &"first_two")
	_check(session.start_shift(1), "RESULT JSON fixture NIGHT must start")
	_check(session.tick(300.0), "RESULT JSON fixture NIGHT must settle")
	var source_result := (
		session.snapshot().get("result", {}) as Dictionary
	)
	_check(
		source_result.get("new_reward_stars", []) == [1],
		"RESULT JSON fixture must earn exactly the first star tier"
	)

	var repository := SaveRepository.new(TEST_ROOT)
	_check(repository.clear_records() == OK, "RESULT JSON fixture cleanup must succeed")
	_check(
		repository.save(session.export_state(), SAVED_AT, 0) == OK,
		"RESULT session must save through schema 3 JSON"
	)
	var loaded := repository.load()
	var restored := ProductV2SaveMigrator.migrate(
		loaded.schema_version,
		loaded.session_data,
		loaded.saved_at_unix,
		catalog
	)
	_check(
		restored.is_valid(),
		"JSON-loaded RESULT session must restore: %s"
		% "; ".join(restored.errors)
	)
	if restored.is_valid():
		var restored_result := (
			restored.candidate.snapshot().get("result", {}) as Dictionary
		)
		var reward_stars := (
			restored_result.get("new_reward_stars", []) as Array
		)
		var unlock_slots := (
			(restored_result.get("new_unlocks", {}) as Dictionary).get(
				"patch_slots", []
			) as Array
		)
		_check(
			reward_stars == [1]
			and typeof(reward_stars[0]) == TYPE_INT
			and not unlock_slots.is_empty()
			and typeof(unlock_slots[0]) == TYPE_INT,
			"RESULT numeric arrays must canonicalize JSON numbers to integers"
		)
	_check(repository.clear_records() == OK, "RESULT JSON records must be removed")


func _easy_catalog() -> Variant:
	var load_result: Variant = ProductV2Loader.load_default()
	_check(load_result.is_valid(), "playback fixture content must load")
	assert(load_result.is_valid(), "playback fixture requires valid content")
	var catalog: Variant = load_result.catalog
	for archetype: Variant in catalog.enemy_archetypes:
		archetype.base_hp = 1.0
	for shift: Variant in catalog.shifts:
		shift.health_multiplier = 1.0
		for wave: Variant in shift.waves:
			wave.hp_multiplier = 1.0
		shift.boss.max_hp = 1.0
		shift.boss.poll_damage = 1.0
		shift.boss.special_damage = 1.0
		shift.boss.rollback_fraction = 0.01
		shift.boss.debuff_start_seconds = 30.0
		shift.boss.debuff_multiplier = 1.0
	return catalog


func _one_star_result_catalog() -> Variant:
	var catalog: Variant = _easy_catalog()
	for shift: Variant in catalog.shifts:
		for wave_index: int in range(shift.waves.size()):
			shift.waves[wave_index].hp_multiplier = (
				1.0 if wave_index < 3 else 1_000_000.0
			)
	return catalog


func _all_empty(values: Array) -> bool:
	for value: Variant in values:
		if not String(value).is_empty():
			return false
	return values.size() == 3


func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


func _first_difference(
	expected: Variant,
	actual: Variant,
	path: String = "session"
) -> String:
	if typeof(expected) != typeof(actual):
		return "%s type %d != %d" % [path, typeof(expected), typeof(actual)]
	if expected is Dictionary:
		var expected_dict := expected as Dictionary
		var actual_dict := actual as Dictionary
		if expected_dict.keys().size() != actual_dict.keys().size():
			return "%s key count differs" % path
		for raw_key: Variant in expected_dict.keys():
			if not actual_dict.has(raw_key):
				return "%s.%s missing" % [path, raw_key]
			var nested := _first_difference(
				expected_dict[raw_key],
				actual_dict[raw_key],
				"%s.%s" % [path, raw_key]
			)
			if not nested.is_empty():
				return nested
		return ""
	if expected is Array:
		var expected_array := expected as Array
		var actual_array := actual as Array
		if expected_array.size() != actual_array.size():
			return "%s size %d != %d" % [
				path, expected_array.size(), actual_array.size(),
			]
		for index: int in expected_array.size():
			var nested := _first_difference(
				expected_array[index],
				actual_array[index],
				"%s[%d]" % [path, index]
			)
			if not nested.is_empty():
				return nested
		return ""
	if expected != actual:
		return "%s value %s != %s" % [path, expected, actual]
	return ""


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("  - %s" % message)
