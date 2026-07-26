extends SceneTree

const GameSessionScript := preload("res://game/app/game_session.gd")
const ProgressionRules := preload("res://game/domain/progression_rules.gd")
const ContentLoaderScript := preload("res://game/content/content_loader.gd")
const PresentationAssetsScript := preload("res://game/presentation/presentation_assets.gd")
const BattleLaneViewScript := preload("res://game/presentation/battle_lane_view.gd")

const OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]
const PATCH_IDS: Array[StringName] = [
	&"frame_skip", &"unsafe_build", &"reward_bypass", &"rollback_lock", &"safe_mode",
]
const STEP_SECONDS := 0.25

var _passed_tests := 0
var _failed_tests := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift headless tests")
	print("================================")
	_run_test("monotonic progression rules", _test_monotonic_progression_rules)
	_run_test("deterministic GameSession ticks", _test_deterministic_ticks)
	_run_test("tick partition invariance", _test_tick_partition_invariance)
	_run_test("patch benefits have drawbacks", _test_patch_tradeoffs)
	_run_test("patch removal cannot bypass replacement cost", _test_patch_removal_cost)
	_run_test("boss failure recovers without a soft lock", _test_boss_failure_recovery)
	_run_test("prestige resets run state and preserves meta state", _test_prestige_reset_and_preservation)
	_run_test("content availability and validation", _test_content_validation)
	_run_test("animated sprite manifest contract", _test_animated_sprite_manifest_contract)
	_run_test("battle lane animation events and layout", _test_battle_lane_animation_events_and_layout)
	_run_test("presentation assets are complete", _test_presentation_assets)
	await _run_main_scene_smoke_test()

	print("================================")
	print(
		"RESULT: %d passed, %d failed, %d assertion failures"
		% [_passed_tests, _failed_tests, _assertion_failures]
	)
	quit(0 if _failed_tests == 0 else 1)


func _run_test(test_name: String, test_method: Callable) -> void:
	var failures_before := _assertion_failures
	test_method.call()
	_finish_test(test_name, failures_before)


func _finish_test(test_name: String, failures_before: int) -> void:
	if _assertion_failures == failures_before:
		_passed_tests += 1
		print("PASS  %s" % test_name)
		return
	_failed_tests += 1
	print("FAIL  %s" % test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_assertion_failures += 1
	print("      - %s" % message)


func _test_monotonic_progression_rules() -> void:
	var load_result := ContentLoaderScript.load_default()
	_check(load_result.is_valid(), "default content must load before progression checks")
	if not load_result.is_valid():
		return
	var catalog: ContentCatalog = load_result.catalog
	var balance: BalanceDefinition = catalog.balance
	var previous_health := ProgressionRules.enemy_max_hp(1, false, balance)
	for stage: int in range(2, 21):
		var current_health := ProgressionRules.enemy_max_hp(stage, false, balance)
		_check(
			current_health > previous_health,
			"normal enemy health must increase from stage %d to %d" % [stage - 1, stage]
		)
		previous_health = current_health

	_check(
		ProgressionRules.enemy_max_hp(20, true, balance)
			> ProgressionRules.enemy_max_hp(10, true, balance),
		"the stage 20 boss must have more health than the stage 10 boss"
	)

	for definition: OperatorDefinition in catalog.operators:
		var previous_cost := ProgressionRules.operator_upgrade_cost(
			1, definition.base_cost, definition.cost_growth
		)
		for level: int in range(2, 51):
			var current_cost := ProgressionRules.operator_upgrade_cost(
				level, definition.base_cost, definition.cost_growth
			)
			_check(
				current_cost > previous_cost,
				"%s cost must increase from level %d to %d"
				% [definition.id, level - 1, level]
			)
			previous_cost = current_cost


func _test_deterministic_ticks() -> void:
	var first := GameSessionScript.new()
	var second := GameSessionScript.new()
	var deltas: Array[float] = [0.25, 0.5, 0.125, 1.0, 0.75, 0.375]

	for cycle: int in range(80):
		var delta: float = deltas[cycle % deltas.size()]
		first.tick(delta)
		second.tick(delta)
		if cycle % 8 == 0:
			_check(
				first.upgrade_operator(&"debugger") == second.upgrade_operator(&"debugger"),
				"matching upgrade commands must return the same result"
			)
		if cycle == 40:
			_check(
				first.equip_patch(0, &"frame_skip") == second.equip_patch(0, &"frame_skip"),
				"matching patch commands must return the same result"
			)

	_check(
		first.snapshot() == second.snapshot(),
		"same commands and elapsed time must produce identical snapshots"
	)
	_check(
		first.get_diagnosis() == second.get_diagnosis(),
		"diagnosis must be deterministic for identical state"
	)


func _test_tick_partition_invariance() -> void:
	var single_tick := GameSessionScript.new()
	var partitioned_ticks := GameSessionScript.new()
	single_tick.tick(30.0)
	for _step: int in range(120):
		partitioned_ticks.tick(0.25)
	var single_snapshot: Dictionary = single_tick.snapshot()
	var partitioned_snapshot: Dictionary = partitioned_ticks.snapshot()
	var single_enemy: Dictionary = single_snapshot.get("enemy", {}) as Dictionary
	var partitioned_enemy: Dictionary = partitioned_snapshot.get("enemy", {}) as Dictionary
	_check(
		int(single_snapshot.get("stage", 0)) == int(partitioned_snapshot.get("stage", -1))
		and int(single_snapshot.get("stage_enemy_index", 0))
			== int(partitioned_snapshot.get("stage_enemy_index", -1))
		and String(single_snapshot.get("mode", "")) == String(partitioned_snapshot.get("mode", "?"))
		and is_equal_approx(
			float(single_snapshot.get("bits", 0.0)),
			float(partitioned_snapshot.get("bits", -1.0))
		)
		and is_equal_approx(
			float(single_enemy.get("hp", 0.0)), float(partitioned_enemy.get("hp", -1.0))
		),
		"one 30-second tick and 120 quarter-second ticks must produce equivalent progression"
	)

	var before_invalid: Dictionary = single_tick.snapshot()
	single_tick.tick(-1.0)
	var after_invalid: Dictionary = single_tick.snapshot()
	_check(
		int(after_invalid.get("stage", 0)) == int(before_invalid.get("stage", -1))
		and is_equal_approx(
			float(after_invalid.get("bits", 0.0)), float(before_invalid.get("bits", -1.0))
		),
		"negative elapsed time must not advance progression"
	)
	_check(
		not String(after_invalid.get("last_error", "")).is_empty(),
		"negative elapsed time must report an explicit boundary error"
	)


func _test_patch_tradeoffs() -> void:
	var session := GameSessionScript.new()
	var frame_preview: Dictionary = session.get_patch_preview(0, &"frame_skip")
	var reward_preview: Dictionary = session.get_patch_preview(0, &"reward_bypass")

	_check(not frame_preview.is_empty(), "frame_skip must expose a preview even before it can be equipped")
	_check(not reward_preview.is_empty(), "reward_bypass must expose a preview even before it can be equipped")
	if not frame_preview.is_empty():
		_check(
			_float_field(frame_preview, "after_ttk") < _float_field(frame_preview, "before_ttk"),
			"frame_skip must shorten expected time to kill"
		)
		_check(
			_float_field(frame_preview, "after_bits_multiplier")
				< _float_field(frame_preview, "before_bits_multiplier"),
			"frame_skip must reduce bit income"
		)
	if not reward_preview.is_empty():
		_check(
			_float_field(reward_preview, "after_bits_multiplier")
				> _float_field(reward_preview, "before_bits_multiplier"),
			"reward_bypass must increase bit income"
		)
		_check(
			_float_field(reward_preview, "after_ttk") > _float_field(reward_preview, "before_ttk"),
			"reward_bypass must lengthen expected time to kill"
		)

	var boss_session := GameSessionScript.new()
	_check(
		_advance_with_balanced_upgrades(boss_session, 10, 600.0),
		"boss preview test must reach stage 10"
	)
	var rollback_preview: Dictionary = boss_session.get_patch_preview(0, &"rollback_lock")
	_check(bool(rollback_preview.get("can_equip", false)), "rollback_lock must be available at stage 10")
	_check(
		_float_field(rollback_preview, "after_ttk")
			< _float_field(rollback_preview, "before_ttk"),
		"rollback_lock preview must include its reduction of boss recovery"
	)


func _test_patch_removal_cost() -> void:
	var session := GameSessionScript.new()
	while int(session.snapshot().get("stage", 0)) < 3:
		session.tick(STEP_SECONDS)
	_check(
		session.equip_patch(0, &"frame_skip"),
		"first installation into an empty slot must be free"
	)
	var before_remove: Dictionary = session.snapshot()
	var removed: bool = session.remove_patch(0)
	var after_remove: Dictionary = session.snapshot()
	_check(removed, "an equipped patch must be removable when the swap cost is affordable")
	_check(
		float(after_remove.get("bits", 0.0)) < float(before_remove.get("bits", 0.0)),
		"removing a patch must charge the change cost so remove-then-equip cannot bypass it"
	)


func _test_boss_failure_recovery() -> void:
	var session := GameSessionScript.new()
	var reached_boss := _advance_without_upgrades(session, 10, 1200.0)
	_check(reached_boss, "an unupgraded session must eventually reach the first boss")
	if not reached_boss:
		return

	var saw_maintenance := false
	var steps_to_failure := int(45.0 / STEP_SECONDS)
	for _step: int in range(steps_to_failure):
		session.tick(STEP_SECONDS)
		if _mode(session.snapshot()) == "maintenance":
			saw_maintenance = true
			break
	_check(saw_maintenance, "the underpowered first boss attempt must enter maintenance")
	if not saw_maintenance:
		return

	var maintenance_snapshot: Dictionary = session.snapshot()
	var bits_at_maintenance := float(maintenance_snapshot.get("bits", 0.0))
	_check(
		float(maintenance_snapshot.get("maintenance_time_left", 0.0)) > 0.0,
		"maintenance must expose remaining automatic recovery work"
	)

	var earned_bits := false
	var retried_automatically := false
	var recovery_window := maxf(
		120.0,
		float(maintenance_snapshot.get("maintenance_time_left", 0.0)) + 5.0
	)
	var recovery_steps := int(recovery_window / STEP_SECONDS)
	for _step: int in range(recovery_steps):
		session.tick(STEP_SECONDS)
		var current: Dictionary = session.snapshot()
		earned_bits = earned_bits or float(current.get("bits", 0.0)) > bits_at_maintenance
		if _mode(current) == "boss" and int(current.get("stage", 0)) == 10:
			retried_automatically = true
			break
	_check(earned_bits, "maintenance must earn bits so the player can change the failed build")
	_check(retried_automatically, "maintenance must retry the boss without a manual retry command")


func _test_prestige_reset_and_preservation() -> void:
	var session := GameSessionScript.new()
	var reached_prestige := _drive_to_prestige(session, 20000.0)
	_check(reached_prestige, "automated combat plus public upgrades must reach prestige")
	if not reached_prestige:
		return

	var before: Dictionary = session.snapshot()
	var patch_notes_before := int(before.get("patch_notes", 0))
	var run_count_before := int(before.get("run_count", 0))
	var unlocked_slots_before := int(before.get("unlocked_patch_slots", 0))
	var discovered_operators_before := _availability_by_id(before.get("operators", []) as Array)
	var discovered_patches_before := _availability_by_id(before.get("patches", []) as Array)

	_check(bool(before.get("prestige_available", false)), "stage 20 clear must offer prestige")
	_check(session.prestige(), "prestige command must succeed after stage 20 clear")

	var after: Dictionary = session.snapshot()
	_check(int(after.get("stage", 0)) == 1, "prestige must reset the run to stage 1")
	_check(is_zero_approx(float(after.get("bits", -1.0))), "prestige must reset bits")
	_check(
		int(after.get("patch_notes", 0)) == patch_notes_before + 1,
		"prestige must grant exactly one patch note"
	)
	_check(
		int(after.get("run_count", 0)) == run_count_before + 1,
		"prestige must increment run count"
	)
	_check(
		int(after.get("unlocked_patch_slots", 0)) == unlocked_slots_before,
		"prestige must preserve unlocked patch slots"
	)
	_check(_all_slots_empty(after), "prestige must remove equipped run patches")
	_check(
		_availability_by_id(after.get("operators", []) as Array) == discovered_operators_before,
		"prestige must preserve discovered operators"
	)
	_check(
		_availability_by_id(after.get("patches", []) as Array) == discovered_patches_before,
		"prestige must preserve discovered patches"
	)
	for operator_value: Variant in after.get("operators", []) as Array:
		var operator_data: Dictionary = operator_value as Dictionary
		_check(
			bool(operator_data.get("unlocked", false)) and int(operator_data.get("level", 0)) >= 1,
			"all discovered operators must restart at level 1 after prestige"
		)

	var cache_level_before := int(after.get("legacy_cache_level", 0))
	var cache_cost := int(after.get("legacy_cache_cost", 0))
	var notes_before_cache := int(after.get("patch_notes", 0))
	_check(session.buy_legacy_cache(), "the earned patch note must buy the first legacy cache level")
	var cached: Dictionary = session.snapshot()
	_check(
		int(cached.get("legacy_cache_level", 0)) == cache_level_before + 1,
		"legacy cache purchase must increase its persistent level"
	)
	_check(
		int(cached.get("patch_notes", 0)) == notes_before_cache - cache_cost,
		"legacy cache purchase must spend its documented patch-note cost"
	)


func _test_content_validation() -> void:
	var valid_result := ContentLoaderScript.load_default()
	_check(valid_result.is_valid(), "repository content must pass boundary validation")
	if valid_result.is_valid():
		_check(valid_result.catalog.operators.size() == 4, "default content must contain four operators")
		_check(valid_result.catalog.patches.size() == 5, "default content must contain five patches")
		for definition: OperatorDefinition in valid_result.catalog.operators:
			_check(
				not definition.ability_description.is_empty(),
				"default operator '%s' must explain its ability" % definition.id
			)
		for operator_id: StringName in OPERATOR_IDS:
			_check(
				valid_result.catalog.has_operator(operator_id),
				"default content is missing operator '%s'" % operator_id
			)
		for patch_id: StringName in PATCH_IDS:
			_check(
				valid_result.catalog.has_patch(patch_id),
				"default content is missing patch '%s'" % patch_id
			)

	var malformed_result := ContentLoaderScript.load_from_json("{", "[]", "{}")
	_check(not malformed_result.is_valid(), "malformed JSON must be rejected")
	_check(not malformed_result.errors.is_empty(), "invalid content must report actionable errors")

	var operator_json := FileAccess.get_file_as_string("res://game/content/operators.json")
	var patch_json := FileAccess.get_file_as_string("res://game/content/patches.json")
	var balance_json := FileAccess.get_file_as_string("res://game/content/balance.json")
	var out_of_scope_patch_json := patch_json.replace(
		"\"unlock_stage\": 15", "\"unlock_stage\": 21"
	)
	var out_of_scope_result := ContentLoaderScript.load_from_json(
		operator_json, out_of_scope_patch_json, balance_json
	)
	_check(
		not out_of_scope_result.is_valid(),
		"content that unlocks after the 20-stage prototype must be rejected"
	)

	var session := GameSessionScript.new()
	var snapshot: Dictionary = session.snapshot()
	var operator_rows := snapshot.get("operators", []) as Array
	_check(operator_rows.size() == 4, "session snapshot must expose four operators")
	for operator_data: Dictionary in operator_rows:
		_check(
			not String(operator_data.get("ability", "")).is_empty(),
			"session operator '%s' must expose its ability" % operator_data.get("id", "")
		)
	_check((snapshot.get("patches", []) as Array).size() == 5, "session snapshot must expose five patches")
	_check(String(snapshot.get("last_error", "")).is_empty(), "valid default content must not set last_error")


func _test_animated_sprite_manifest_contract() -> void:
	var initialization_errors: PackedStringArray = PresentationAssetsScript.initialize()
	_check(
		initialization_errors.is_empty(),
		"active presentation assets must initialize without errors: %s"
		% "; ".join(initialization_errors)
	)
	var validation_errors: PackedStringArray = PresentationAssetsScript.validate_catalog(
		PresentationAssetsScript.ROOT_MANIFEST_PATH
	)
	_check(
		validation_errors.is_empty(),
		"root asset catalog must pass independent validation: %s"
		% "; ".join(validation_errors)
	)
	_check_active_sprite_byte_contract()
	if not initialization_errors.is_empty() or not validation_errors.is_empty():
		return

	_check(
		PresentationAssetsScript.is_sprite_run_active(&"debugger"),
		"debugger component-row run must be active"
	)
	_check(
		PresentationAssetsScript.is_sprite_run_active(&"broken_pixel"),
		"broken_pixel component-row run must be active"
	)
	_check_invalid_active_sprite_catalog_fails()

	var debugger_first: SpriteFrames = PresentationAssetsScript.make_operator_frames(&"debugger")
	var debugger_second: SpriteFrames = PresentationAssetsScript.make_operator_frames(&"debugger")
	_check(debugger_first != null, "debugger SpriteFrames must load")
	_check(debugger_second != null, "a second debugger SpriteFrames instance must load")
	if debugger_first != null:
		_check_animation_contract(debugger_first, &"debugger", &"idle", 4, 4.0, true)
		_check_animation_contract(debugger_first, &"debugger", &"upgrade", 4, 6.0, false)
	if debugger_first != null and debugger_second != null:
		_check(
			debugger_first != debugger_second,
			"each debugger request must return an independent SpriteFrames instance"
		)
		var first_frame: Texture2D = debugger_first.get_frame_texture(&"idle", 0)
		var second_frame: Texture2D = debugger_second.get_frame_texture(&"idle", 0)
		_check(
			first_frame != second_frame,
			"each debugger SpriteFrames instance must own independent AtlasTexture frames"
		)

	var enemy_first: SpriteFrames = PresentationAssetsScript.make_enemy_frames(1, false, "combat")
	var enemy_second: SpriteFrames = PresentationAssetsScript.make_enemy_frames(1, false, "combat")
	_check(enemy_first != null, "broken_pixel SpriteFrames must load for stage 1 combat")
	_check(enemy_second != null, "a second broken_pixel SpriteFrames instance must load")
	if enemy_first != null:
		_check_animation_contract(enemy_first, &"broken_pixel", &"idle", 4, 4.0, true)
		_check_animation_contract(enemy_first, &"broken_pixel", &"hurt", 4, 8.0, false)
	if enemy_first != null and enemy_second != null:
		_check(
			enemy_first != enemy_second,
			"each broken_pixel request must return an independent SpriteFrames instance"
		)
		var first_frame: Texture2D = enemy_first.get_frame_texture(&"idle", 0)
		var second_frame: Texture2D = enemy_second.get_frame_texture(&"idle", 0)
		_check(
			first_frame != second_frame,
			"each broken_pixel SpriteFrames instance must own independent AtlasTexture frames"
		)


func _check_active_sprite_byte_contract() -> void:
	var root_text := FileAccess.get_file_as_string(PresentationAssetsScript.ROOT_MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(root_text)
	_check(parsed is Dictionary, "root asset catalog must be valid JSON for byte checks")
	if not parsed is Dictionary:
		return
	var root_manifest: Dictionary = parsed
	var runs_value: Variant = root_manifest.get("active_sprite_runs", {})
	_check(runs_value is Dictionary, "root asset catalog must expose active_sprite_runs")
	if not runs_value is Dictionary:
		return
	var runs: Dictionary = runs_value
	var required_ids: Array[StringName] = [
		&"debugger",
		&"build_engineer",
		&"sprite_artist",
		&"qa_imp",
		&"broken_pixel",
	]
	for asset_id: StringName in required_ids:
		var run_key := String(asset_id)
		_check(runs.has(run_key), "%s active sprite entry must exist" % asset_id)
		if not runs.has(run_key):
			continue
		var entry_value: Variant = runs[run_key]
		_check(entry_value is Dictionary, "%s active sprite entry must be a Dictionary" % asset_id)
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if asset_id in [&"build_engineer", &"sprite_artist", &"qa_imp"]:
			_check(
				String(entry.get("delivery_profile", "")) == "final-only",
				"%s active sprite entry must use final-only delivery" % asset_id
			)
		var manifest_path := String(entry.get("manifest_path", ""))
		var manifest_absolute := ProjectSettings.globalize_path(manifest_path)
		var manifest_file := FileAccess.open(manifest_absolute, FileAccess.READ)
		_check(manifest_file != null, "%s active manifest must be readable" % asset_id)
		if manifest_file == null:
			continue
		var manifest_bytes: PackedByteArray = manifest_file.get_buffer(manifest_file.get_length())
		_check(
			manifest_bytes.find(13) == -1,
			"%s active manifest must contain LF-only bytes" % asset_id
		)
		var actual_manifest_hash := FileAccess.get_sha256(manifest_absolute)
		_check(
			String(entry.get("manifest_sha256", "")) == actual_manifest_hash,
			"%s root manifest pin must match the LF manifest bytes" % asset_id
		)
		var atlas_path := manifest_path.get_base_dir().path_join("sprite-sheet-alpha.png")
		var actual_atlas_hash := FileAccess.get_sha256(ProjectSettings.globalize_path(atlas_path))
		_check(
			String(entry.get("atlas_sha256", "")) == actual_atlas_hash,
			"%s root atlas pin must remain byte-exact" % asset_id
		)


func _check_invalid_active_sprite_catalog_fails() -> void:
	var invalid_path := "user://invalid-active-sprite-catalog.json"
	var invalid_catalog := {
		"schema_version": 2,
		"active_sprite_runs": {
			"debugger": {
				"category": "operator",
				"manifest_contract": 1,
				"manifest_path": "res://game/assets/generated/sprites/debugger/missing.json",
				"manifest_sha256": "missing",
				"atlas_sha256": "missing",
			}
		}
	}
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	_check(file != null, "invalid catalog fixture must be writable")
	if file == null:
		return
	file.store_string(JSON.stringify(invalid_catalog))
	file.close()
	var errors: PackedStringArray = PresentationAssetsScript.validate_catalog(invalid_path)
	_check(not errors.is_empty(), "a missing active sprite manifest must fail catalog validation")
	var reported_missing_file := false
	for error_message: String in errors:
		if error_message.contains("missing file"):
			reported_missing_file = true
	_check(
		reported_missing_file,
		"a missing active sprite manifest must report the concrete missing-file error"
	)
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))
	_check(remove_error == OK, "invalid catalog fixture cleanup must succeed")


func _check_animation_contract(
	frames: SpriteFrames,
	asset_id: StringName,
	state: StringName,
	expected_frame_count: int,
	expected_fps: float,
	expected_loop: bool
) -> void:
	_check(frames.has_animation(state), "%s must define '%s'" % [asset_id, state])
	if not frames.has_animation(state):
		return
	_check(
		frames.get_frame_count(state) == expected_frame_count,
		"%s '%s' must contain %d frames" % [asset_id, state, expected_frame_count]
	)
	_check(
		is_equal_approx(frames.get_animation_speed(state), expected_fps),
		"%s '%s' must play at %.1f fps" % [asset_id, state, expected_fps]
	)
	_check(
		frames.get_animation_loop(state) == expected_loop,
		"%s '%s' loop flag must be %s" % [asset_id, state, expected_loop]
	)

	var seen_regions: Array[Rect2] = []
	for frame_index: int in range(frames.get_frame_count(state)):
		var texture: Texture2D = frames.get_frame_texture(state, frame_index)
		_check(
			texture is AtlasTexture,
			"%s '%s' frame %d must be an AtlasTexture" % [asset_id, state, frame_index]
		)
		if not texture is AtlasTexture:
			continue
		var atlas_frame := texture as AtlasTexture
		_check(
			atlas_frame.region.size == Vector2(32.0, 32.0),
			"%s '%s' frame %d rect must be 32x32" % [asset_id, state, frame_index]
		)
		_check(
			atlas_frame.get_size() == Vector2(32.0, 32.0),
			"%s '%s' frame %d must expose only its 32x32 cell" % [asset_id, state, frame_index]
		)
		_check(
			atlas_frame.atlas != null,
			"%s '%s' frame %d must retain its atlas source" % [asset_id, state, frame_index]
		)
		if atlas_frame.atlas != null:
			var atlas_size: Vector2 = atlas_frame.atlas.get_size()
			_check(
				atlas_frame.region.size != atlas_size,
				"%s '%s' frame %d must not expose the full atlas"
				% [asset_id, state, frame_index]
			)
			_check(
				atlas_frame.region.position.x >= 0.0
				and atlas_frame.region.position.y >= 0.0
				and atlas_frame.region.end.x <= atlas_size.x
				and atlas_frame.region.end.y <= atlas_size.y,
				"%s '%s' frame %d rect must remain inside the atlas"
				% [asset_id, state, frame_index]
			)
		_check(
			atlas_frame.filter_clip,
			"%s '%s' frame %d must clip filtering to its atlas cell"
			% [asset_id, state, frame_index]
		)
		_check(
			not seen_regions.has(atlas_frame.region),
			"%s '%s' frame %d must use a distinct manifest rect"
			% [asset_id, state, frame_index]
		)
		seen_regions.append(atlas_frame.region)


func _test_battle_lane_animation_events_and_layout() -> void:
	var initialization_errors: PackedStringArray = PresentationAssetsScript.initialize()
	_check(
		initialization_errors.is_empty(),
		"battle lane animation test requires a valid active sprite catalog"
	)
	if not initialization_errors.is_empty():
		return

	var lane := BattleLaneViewScript.new()
	root.add_child(lane)
	var session := GameSessionScript.new()
	var snapshot: Dictionary = session.snapshot()
	lane.update_from_snapshot(snapshot, {})

	var enemy_slot := lane.find_child("EnemyPortraitSlot", true, false) as Control
	var enemy_portrait := lane.find_child("EnemyPortrait", true, false) as TextureRect
	var debugger_portrait := lane.find_child("OperatorPortrait_debugger", true, false) as TextureRect
	var debugger_hp := lane.find_child("OperatorHP_debugger", true, false) as ColorRect
	_check(enemy_slot != null, "battle lane must expose a fixed enemy portrait slot")
	_check(enemy_portrait != null, "battle lane must expose the active enemy portrait")
	_check(debugger_portrait != null, "battle lane must expose the debugger portrait")
	_check(
		debugger_hp != null and not debugger_hp.visible,
		"production operator durability must stay hidden outside boss combat"
	)
	if (
		enemy_slot == null
		or enemy_portrait == null
		or debugger_portrait == null
		or debugger_hp == null
	):
		lane.queue_free()
		return

	var integer_hp_snapshot := snapshot.duplicate(true)
	var integer_hp_enemy := integer_hp_snapshot["enemy"] as Dictionary
	integer_hp_enemy["hp"] = 190.99
	integer_hp_enemy["max_hp"] = 330.99
	integer_hp_snapshot["enemy"] = integer_hp_enemy
	lane.update_from_snapshot(integer_hp_snapshot, {})
	var enemy_hp_label := lane.find_child("EnemyHPLabel", true, false) as Label
	_check(
		enemy_hp_label != null and enemy_hp_label.text == "HP 190 / 330",
		"enemy HP must discard decimals instead of rounding them"
	)
	_check(
		enemy_hp_label != null
			and enemy_hp_label.custom_minimum_size.y >= 22.0
			and not enemy_hp_label.clip_text,
		"enemy HP text must keep enough vertical room to avoid clipping"
	)

	var durability_snapshot := snapshot.duplicate(true)
	durability_snapshot["combat_v2_test_mode"] = true
	var durability_operators := durability_snapshot["operators"] as Array
	var debugger_data := durability_operators[0] as Dictionary
	debugger_data["hp"] = 111.99
	debugger_data["max_hp"] = 160.0
	debugger_data["process_down"] = false
	durability_operators[0] = debugger_data
	durability_snapshot["operators"] = durability_operators
	lane.update_from_snapshot(durability_snapshot, {})
	var debugger_hp_fill := debugger_hp.get_node("Fill") as ColorRect
	var debugger_status := lane.find_child("OperatorStatus_debugger", true, false) as Label
	_check(
		debugger_hp.size == Vector2(28.0, 4.0)
			and debugger_hp_fill != null
			and debugger_hp_fill.size.y == 2.0,
		"boss operator HP must use a thin fixed-size track"
	)
	_check(
		debugger_status != null
			and debugger_status.text == "111"
			and debugger_status.get_theme_color("font_color") == Color("edf4ff"),
		"boss operator HP numbers must be integer text with high contrast"
	)
	lane.update_from_snapshot(snapshot, {})

	_check(enemy_slot.size == Vector2(48.0, 48.0), "enemy portrait slot must remain 48x48")
	_check(enemy_portrait.size == Vector2(32.0, 32.0), "broken_pixel must display at 32x32")
	_check(
		enemy_portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"broken_pixel portrait must use nearest filtering"
	)
	_check(
		debugger_portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"debugger portrait must use nearest filtering"
	)
	_check(
		enemy_portrait.position == Vector2(8.0, 16.0),
		"32x32 enemies must be bottom-centered in the 48x48 slot"
	)

	var idle_first: Texture2D = enemy_portrait.texture
	lane._process(0.26)
	var idle_advanced: Texture2D = enemy_portrait.texture
	_check(idle_advanced != idle_first, "broken_pixel idle must advance after one frame interval")
	lane.update_from_snapshot(snapshot, snapshot)
	_check(
		enemy_portrait.texture == idle_advanced,
		"same-enemy snapshot refreshes must not reset the current idle frame"
	)

	lane.play_operator_upgrade(&"debugger")
	_check(debugger_portrait.texture is AtlasTexture, "debugger upgrade event must display an atlas cell")
	if debugger_portrait.texture is AtlasTexture:
		var upgrade_frame := debugger_portrait.texture as AtlasTexture
		_check(
			upgrade_frame.region.position.y == 32.0,
			"debugger upgrade event must switch from idle to the upgrade row"
		)
	_check(
		debugger_portrait.pivot_offset
		== Vector2(debugger_portrait.size.x * 0.5, debugger_portrait.size.y),
		"debugger upgrade pulse pivot must stay at bottom center"
	)
	lane._process(0.1)
	_check(
		debugger_portrait.scale.x > 1.0 and debugger_portrait.scale.y > 1.0,
		"debugger upgrade event must preserve the existing pulse effect"
	)

	var damaged_snapshot: Dictionary = snapshot.duplicate(true)
	var damaged_enemy: Dictionary = damaged_snapshot["enemy"]
	damaged_enemy["hp"] = maxf(0.0, float(damaged_enemy["hp"]) - 1.0)
	damaged_snapshot["enemy"] = damaged_enemy
	lane.update_from_snapshot(damaged_snapshot, snapshot)
	_check(enemy_portrait.texture is AtlasTexture, "enemy damage event must display an atlas cell")
	if enemy_portrait.texture is AtlasTexture:
		var hurt_frame := enemy_portrait.texture as AtlasTexture
		_check(
			hurt_frame.region.position.y == 32.0,
			"enemy damage event must switch from idle to the hurt row"
		)
	_check(
		enemy_portrait.modulate == Color("ff9ca6"),
		"enemy damage event must preserve the existing hit tint"
	)
	var projectile := lane.find_child("CombatProjectile*", true, false) as Control
	_check(projectile != null, "actual enemy HP loss must launch a visible team projectile")
	lane._process(0.19)
	var damage_number := lane.find_child("DamageNumber*", true, false) as Label
	_check(damage_number != null, "projectile impact must create an enemy damage number")
	if damage_number != null:
		_check(damage_number.text == "-1", "damage number must equal the observed 1 HP loss")
	lane.queue_free()

	var switched_lane := BattleLaneViewScript.new()
	root.add_child(switched_lane)
	switched_lane.update_from_snapshot(snapshot, {})
	var switched_snapshot: Dictionary = snapshot.duplicate(true)
	switched_snapshot["stage_enemy_index"] = int(snapshot["stage_enemy_index"]) + 1
	var switched_enemy: Dictionary = switched_snapshot["enemy"]
	switched_enemy["hp"] = maxf(0.0, float(switched_enemy["hp"]) - 5.0)
	switched_snapshot["enemy"] = switched_enemy
	switched_lane.update_from_snapshot(switched_snapshot, snapshot)
	switched_lane._process(0.5)
	_check(
		switched_lane.find_child("CombatProjectile*", true, false) == null,
		"a new enemy snapshot must not turn its lower starting HP into a false attack"
	)
	_check(
		switched_lane.find_child("DamageNumber*", true, false) == null,
		"a target change must not create a false damage number"
	)
	switched_lane.queue_free()

	_test_upgrade_damage_feedback()


func _test_upgrade_damage_feedback() -> void:
	var session := GameSessionScript.new()
	var saved_state: Dictionary = session.export_state()
	saved_state["bits"] = 100.0
	var restore_errors: PackedStringArray = session.restore_state(saved_state)
	_check(restore_errors.is_empty(), "damage feedback test state must restore atomically")
	if not restore_errors.is_empty():
		return

	var before_base: Dictionary = session.snapshot()
	session.tick(0.2)
	var after_base: Dictionary = session.snapshot()
	var base_damage := _enemy_hp(before_base) - _enemy_hp(after_base)
	_check(base_damage > 0.0, "unupgraded operators must deal observable combat damage")

	_check(session.upgrade_operator(&"debugger"), "funded debugger upgrade must succeed")
	var before_upgrade: Dictionary = session.snapshot()
	session.tick(0.2)
	var after_upgrade: Dictionary = session.snapshot()
	var upgraded_damage := _enemy_hp(before_upgrade) - _enemy_hp(after_upgrade)
	_check(
		upgraded_damage > base_damage,
		"the next real-time HP delta must increase immediately after an operator upgrade"
	)

	var lane := BattleLaneViewScript.new()
	root.add_child(lane)
	lane.update_from_snapshot(before_base, {})
	lane.update_from_snapshot(after_base, before_base)
	lane._process(0.19)
	var first_number := _latest_damage_number(lane)
	_check(first_number != null, "base damage must reach the damage-number layer")
	if first_number != null:
		_check(
			first_number.text == _expected_damage_text(base_damage),
			"base damage number must use the actual GameSession HP delta"
		)

	lane.update_from_snapshot(before_upgrade, after_base)
	lane.update_from_snapshot(after_upgrade, before_upgrade)
	lane._process(0.40)
	_check(
		_active_projectile_count(lane) == 0,
		"two active operators must not attack faster than the 1.2-second per-operator cadence"
	)
	lane._process(0.02)
	lane._process(0.19)
	var upgraded_number := _latest_damage_number(lane)
	_check(upgraded_number != null, "upgraded damage must reach the damage-number layer")
	if upgraded_number != null:
		var carried_damage := (
			upgraded_damage
			+ base_damage
			- floorf(base_damage)
		)
		_check(
			upgraded_number.text == _expected_damage_text(carried_damage),
			"integer damage feedback must carry the previous fractional remainder"
		)
	lane.queue_free()


func _enemy_hp(snapshot: Dictionary) -> float:
	return float((snapshot["enemy"] as Dictionary)["hp"])


func _latest_damage_number(lane: Node) -> Label:
	var latest: Label = null
	var latest_serial := -1
	for node: Node in lane.find_children("DamageNumber*", "Label", true, false):
		var serial := String(node.name).trim_prefix("DamageNumber").to_int()
		if serial > latest_serial:
			latest = node as Label
			latest_serial = serial
	return latest


func _active_projectile_count(lane: Node) -> int:
	var active_count := 0
	for node: Node in lane.find_children("CombatProjectile*", "Control", true, false):
		if not node.is_queued_for_deletion():
			active_count += 1
	return active_count


func _expected_damage_text(damage: float) -> String:
	return "-%d" % int(floorf(damage))


func _test_presentation_assets() -> void:
	for operator_id: StringName in OPERATOR_IDS:
		var texture: Texture2D = PresentationAssetsScript.operator_texture(operator_id)
		_check(texture != null, "operator texture '%s' must load" % operator_id)
		if texture != null:
			_check(texture.get_size() == Vector2(32.0, 32.0), "operator texture '%s' must be 32x32" % operator_id)

	for patch_id: StringName in PATCH_IDS:
		var texture: Texture2D = PresentationAssetsScript.patch_texture(patch_id)
		_check(texture != null, "patch texture '%s' must load" % patch_id)
		if texture != null:
			_check(texture.get_size() == Vector2(24.0, 24.0), "patch texture '%s' must be 24x24" % patch_id)

	for icon_id: StringName in [&"bit", &"patch_note", &"stage", &"diagnosis", &"combat", &"boss", &"maintenance", &"complete"]:
		var texture: Texture2D = PresentationAssetsScript.ui_texture(icon_id)
		_check(texture != null, "UI texture '%s' must load" % icon_id)
		if texture != null:
			_check(texture.get_size() == Vector2(16.0, 16.0), "UI texture '%s' must be 16x16" % icon_id)

	var audio_paths: PackedStringArray = [
		"res://game/assets/audio/bgm/title_loop.wav",
		"res://game/assets/audio/bgm/night_shift_loop.ogg",
		"res://game/assets/audio/bgm/watchdog_loop.ogg",
		"res://game/assets/audio/bgm/maintenance_loop.wav",
		"res://game/assets/audio/sfx/ui_move.ogg",
		"res://game/assets/audio/sfx/ui_confirm.ogg",
		"res://game/assets/audio/sfx/ui_error.ogg",
		"res://game/assets/audio/sfx/shift_authorized.wav",
		"res://game/assets/audio/sfx/enemy_break.wav",
		"res://game/assets/audio/sfx/combat_hit.wav",
		"res://game/assets/audio/sfx/stage_clear.ogg",
		"res://game/assets/audio/sfx/operator_upgrade.wav",
		"res://game/assets/audio/sfx/patch_apply.ogg",
		"res://game/assets/audio/sfx/patch_remove.ogg",
		"res://game/assets/audio/sfx/boss_warning.wav",
		"res://game/assets/audio/sfx/maintenance_enter.ogg",
		"res://game/assets/audio/sfx/update_ready.ogg",
		"res://game/assets/audio/sfx/version_update.ogg",
	]
	for audio_path: String in audio_paths:
		var stream: Resource = load(audio_path)
		_check(stream is AudioStream, "audio stream '%s' must load" % audio_path)

	_check(AudioServer.get_bus_index("Music") >= 0, "Music audio bus must exist")
	_check(AudioServer.get_bus_index("SFX") >= 0, "SFX audio bus must exist")


func _run_main_scene_smoke_test() -> void:
	var failures_before := _assertion_failures
	var packed: Resource = load("res://game/presentation/main.tscn")
	_check(packed is PackedScene, "main scene must load as a PackedScene")
	if packed is PackedScene:
		var instance := (packed as PackedScene).instantiate()
		_check(instance != null, "main scene must instantiate")
		if instance != null:
			_check(instance.get_script() != null, "main scene root script must load without parser errors")
			root.add_child(instance)
			await process_frame
			_check(instance.is_inside_tree(), "main scene must survive one headless frame")
			instance.queue_free()
			await process_frame
	_finish_test("main scene headless smoke load", failures_before)


func _float_field(values: Dictionary, key: String) -> float:
	_check(values.has(key), "patch preview is missing '%s'" % key)
	return float(values.get(key, 0.0))


func _mode(snapshot: Dictionary) -> String:
	return String(snapshot.get("mode", ""))


func _advance_without_upgrades(session: Variant, target_stage: int, max_seconds: float) -> bool:
	var step_count := int(max_seconds / STEP_SECONDS)
	for _step: int in range(step_count):
		if int(session.snapshot().get("stage", 0)) >= target_stage:
			return true
		session.tick(STEP_SECONDS)
	return int(session.snapshot().get("stage", 0)) >= target_stage


func _advance_with_balanced_upgrades(
	session: Variant,
	target_stage: int,
	max_seconds: float
) -> bool:
	var step_count := int(max_seconds / STEP_SECONDS)
	for step: int in range(step_count):
		var snapshot: Dictionary = session.snapshot()
		if int(snapshot.get("stage", 0)) >= target_stage:
			return true
		if step % 4 == 0:
			var chosen := &""
			var lowest_level := 2147483647
			var bits := float(snapshot.get("bits", 0.0))
			for raw_operator: Variant in snapshot.get("operators", []) as Array:
				var operator := raw_operator as Dictionary
				if (
					not bool(operator.get("unlocked", false))
					or float(operator.get("upgrade_cost", INF)) > bits + 0.000001
				):
					continue
				var level := int(operator.get("level", 0))
				if level < lowest_level:
					chosen = StringName(String(operator.get("id", "")))
					lowest_level = level
			if chosen != &"":
				session.upgrade_operator(chosen)
		session.tick(STEP_SECONDS)
	return int(session.snapshot().get("stage", 0)) >= target_stage


func _drive_to_prestige(session: Variant, max_seconds: float) -> bool:
	var step_count := int(max_seconds / STEP_SECONDS)
	for step: int in range(step_count):
		var snapshot: Dictionary = session.snapshot()
		if bool(snapshot.get("prestige_available", false)):
			return true

		_try_progress_patches(session, snapshot)
		if step % 4 == 0:
			for operator_id: StringName in OPERATOR_IDS:
				session.upgrade_operator(operator_id)
		session.tick(STEP_SECONDS)
	return bool(session.snapshot().get("prestige_available", false))


func _try_progress_patches(session: Variant, snapshot: Dictionary) -> void:
	var unlocked_slots := int(snapshot.get("unlocked_patch_slots", 0))
	var slots: Array = snapshot.get("patch_slots", []) as Array
	var desired: Array[StringName] = [&"frame_skip", &"unsafe_build", &"rollback_lock"]
	for slot_index: int in range(mini(unlocked_slots, desired.size())):
		var current_id := ""
		if slot_index < slots.size():
			current_id = String(slots[slot_index])
		if current_id != String(desired[slot_index]):
			session.equip_patch(slot_index, desired[slot_index])


func _availability_by_id(items: Array) -> Dictionary:
	var availability: Dictionary = {}
	for item_value: Variant in items:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item := item_value as Dictionary
		var item_id := String(item.get("id", ""))
		if item_id.is_empty():
			continue
		availability[item_id] = bool(item.get("unlocked", item.get("discovered", false)))
	return availability


func _all_slots_empty(snapshot: Dictionary) -> bool:
	var slots: Array = snapshot.get("patch_slots", []) as Array
	for slot_value: Variant in slots:
		if not String(slot_value).is_empty():
			return false
	return true
