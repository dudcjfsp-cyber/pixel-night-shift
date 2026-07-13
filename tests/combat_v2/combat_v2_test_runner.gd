extends SceneTree

const V2_LOADER := preload("res://game/content/combat_v2/combat_v2_loader.gd")
const V2_STATE := preload("res://game/domain/combat_v2/combat_v2_state.gd")
const V2_SIMULATOR := preload("res://game/domain/combat_v2/combat_v2_simulator.gd")
const V2_FORECAST := preload("res://game/domain/combat_v2/combat_v2_forecast.gd")
const V2_DIAGNOSIS := preload("res://game/domain/combat_v2/combat_v2_diagnosis_rules.gd")
const V2_SESSION := preload("res://game/app/combat_v2_prototype_session.gd")
const COMPARISON_REPORT := preload("res://tests/combat_v2/combat_v2_comparison_report.gd")

const PROFILE_PATH := "res://game/content/combat_v2/combat_v2.json"
const GREYBOX_PATH := "res://game/presentation/combat_v2/combat_v2_greybox_view.tscn"
const EPSILON := 0.00001

var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift Combat V2 headless tests")
	print("================================================")
	_run_test("strict Combat V2 content rejection", _test_content_rejection)
	_run_test("linear HP, down, recovery, and recovery-wait diagnosis", _test_hp_down_recovery)
	_run_test("operator roles and patch tradeoffs", _test_roles_and_patch_tradeoffs)
	_run_test("stable tie ordering and kill-at-timeout", _test_tie_ordering)
	_run_test("tick partition invariance", _test_tick_partition_invariance)
	_run_test("offline-style chunk equivalence", _test_chunk_equivalence)
	_run_test("forecast uses the actual simulator", _test_forecast_matches_actual)
	_run_test("maintenance farming retries automatically", _test_maintenance_retry)
	_run_test("all-down normal combat has no soft lock", _test_all_down_no_softlock)
	_run_test("anti-debugger policy matrix", _test_anti_debugger_matrix)
	await _run_greybox_headless_load()
	print("================================================")
	print("RESULT: %d passed, %d failed, %d assertion failures" % [
		_passed, _failed, _assertion_failures,
	])
	quit(0 if _failed == 0 else 1)


func _run_test(test_name: String, method: Callable) -> void:
	var before := _assertion_failures
	method.call()
	_finish_test(test_name, before)


func _finish_test(test_name: String, failures_before: int) -> void:
	if failures_before == _assertion_failures:
		_passed += 1
		print("PASS  %s" % test_name)
		return
	_failed += 1
	print("FAIL  %s" % test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_assertion_failures += 1
	print("      - %s" % message)


func _test_content_rejection() -> void:
	var load_result := V2_LOADER.load_default()
	_check(load_result.is_valid(), "default Combat V2 content must load")
	if not load_result.is_valid():
		return
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	_check(file != null, "test must read the Combat V2 profile")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY, "Combat V2 profile fixture must be an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var base_catalog: ContentCatalog = load_result.catalog.base_catalog

	var invalid_hp := (parsed as Dictionary).duplicate(true)
	(invalid_hp["balance"] as Dictionary)["hp_per_level"] = 0.0
	_check(
		not V2_LOADER.load_from_json(JSON.stringify(invalid_hp), base_catalog).is_valid(),
		"zero HP growth must be rejected"
	)
	var extra_key := (parsed as Dictionary).duplicate(true)
	(extra_key["operators"] as Array)[0]["hidden_fallback"] = true
	_check(
		not V2_LOADER.load_from_json(JSON.stringify(extra_key), base_catalog).is_valid(),
		"unknown operator keys must be rejected"
	)
	var duplicate_id := (parsed as Dictionary).duplicate(true)
	(duplicate_id["enemies"] as Array)[1]["id"] = "broken_pixel"
	_check(
		not V2_LOADER.load_from_json(JSON.stringify(duplicate_id), base_catalog).is_valid(),
		"duplicate and missing enemy IDs must be rejected"
	)
	var invalid_exponent := (parsed as Dictionary).duplicate(true)
	(invalid_exponent["operators"] as Array)[0]["damage_exponent_multiplier"] = 1.5
	_check(
		not V2_LOADER.load_from_json(JSON.stringify(invalid_exponent), base_catalog).is_valid(),
		"role damage exponent multipliers above one must be rejected"
	)
	var reordered := (parsed as Dictionary).duplicate(true)
	(reordered["operators"] as Array).reverse()
	(reordered["enemies"] as Array).reverse()
	var reordered_result := V2_LOADER.load_from_json(JSON.stringify(reordered), base_catalog)
	_check(reordered_result.is_valid(), "content array order must not be a hidden contract")
	if reordered_result.is_valid():
		_check(
			reordered_result.catalog.operators[0].id == &"debugger"
			and reordered_result.catalog.operators[3].id == &"qa_imp",
			"operator profiles must canonicalize to stable ID tie-break order"
		)
		_check(
			reordered_result.catalog.enemies[0].id == &"broken_pixel"
			and reordered_result.catalog.enemies[3].id == &"watchdog_process",
			"enemy stage cycle must be independent from JSON array order"
		)


func _test_hp_down_recovery() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var state: CombatV2State = fixture.state
	var catalog: CombatV2Catalog = fixture.catalog
	state.progression.operator_levels[&"debugger"] = 3
	_check_close(
		V2_SIMULATOR.operator_max_hp(state, catalog, &"debugger"),
		200.0 * (1.0 + 0.12 * 2.0),
		"max HP must use the approved linear formula"
	)
	state.progression.operator_levels[&"debugger"] = 1
	V2_SIMULATOR.reset_team_full(state, catalog)
	var debugger := state.get_operator(&"debugger")
	debugger.current_hp = 1.0
	debugger.attack_remaining = 10.0
	state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	_check(not debugger.is_active(), "focused damage must down the debugger")
	_check(
		debugger.recovery_remaining > 7.99 and debugger.recovery_remaining <= 8.0,
		"debugger recovery must start at eight seconds"
	)
	V2_SIMULATOR.advance(state, catalog, debugger.recovery_remaining)
	_check(debugger.is_active(), "downed debugger must recover automatically")
	_check_close(
		debugger.current_hp,
		V2_SIMULATOR.operator_max_hp(state, catalog, &"debugger") * 0.5,
		"automatic recovery must restore 50% HP"
	)

	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if state.progression.is_operator_unlocked(runtime.operator_id):
			runtime.current_hp = 0.0
			runtime.attack_remaining = INF
			runtime.recovery_remaining = 2.0
	var diagnosis := V2_DIAGNOSIS.evaluate(state, catalog)
	_check(String(diagnosis.kind) == "recovery_wait", "all-down normal combat needs recovery_wait")
	_check(String(diagnosis.title) == "자동 복구 대기", "recovery wait must be explicit in UI language")


func _test_roles_and_patch_tradeoffs() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog

	var damage_state: CombatV2State = fixture.state
	var debugger := damage_state.get_operator(&"debugger")
	var before_hp := debugger.current_hp
	debugger.attack_remaining = 10.0
	damage_state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(damage_state, catalog, 0.001)
	_check_close(before_hp - debugger.current_hp, 15.0 * 0.70, "debugger must reduce incoming damage")

	var stage_three := _stage_fixture(catalog, 3)
	_check_close(
		V2_SIMULATOR.operator_attack_interval(stage_three, catalog, &"debugger"),
		1.0 * 0.90,
		"active Sprite Artist must accelerate the whole living team"
	)
	_check_close(
		V2_SIMULATOR.operator_attack_interval(stage_three, catalog, &"sprite_artist"),
		0.75 * 0.90,
		"Sprite Artist must include itself in the speed aura"
	)
	var scheduled_before := stage_three.get_operator(&"debugger").attack_remaining
	stage_three.get_operator(&"sprite_artist").current_hp = 0.0
	stage_three.get_operator(&"sprite_artist").recovery_remaining = 6.0
	_check_close(
		stage_three.get_operator(&"debugger").attack_remaining,
		scheduled_before,
		"a role change must not reschedule an already pending attack"
	)

	var stage_six := _stage_fixture(catalog, 6)
	var repair_target := stage_six.get_operator(&"debugger")
	repair_target.current_hp = 0.0
	repair_target.attack_remaining = INF
	repair_target.recovery_remaining = 5.0
	stage_six.qa_pulse_remaining = 0.0
	stage_six.enemy_attack_remaining = 10.0
	for runtime: CombatV2State.OperatorRuntime in stage_six.operators:
		if runtime.is_active():
			runtime.attack_remaining = 10.0
	V2_SIMULATOR.advance(stage_six, catalog, 0.001)
	_check_close(repair_target.recovery_remaining, 3.749, "QA pulse must reduce the longest recovery")

	var base_patch_state := _stage_fixture(catalog, 9)
	var base_interval := V2_SIMULATOR.operator_attack_interval(
		base_patch_state, catalog, &"build_engineer"
	)
	base_patch_state.progression.equipped_patch_ids[0] = &"frame_skip"
	_check_close(
		V2_SIMULATOR.operator_attack_interval(base_patch_state, catalog, &"build_engineer"),
		base_interval / 1.35,
		"frame_skip must accelerate only future operator scheduling"
	)
	base_patch_state.progression.equipped_patch_ids[0] = &""
	var base_damage := V2_SIMULATOR.operator_attack_damage(
		base_patch_state, catalog, &"build_engineer"
	)
	base_patch_state.progression.equipped_patch_ids[0] = &"unsafe_build"
	_check_close(
		V2_SIMULATOR.operator_attack_damage(base_patch_state, catalog, &"build_engineer"),
		base_damage * 1.45,
		"unsafe_build must increase outgoing damage"
	)
	base_patch_state.progression.equipped_patch_ids[0] = &""
	var base_enemy_hp := V2_FORECAST.enemy_max_hp(base_patch_state, catalog)
	base_patch_state.progression.equipped_patch_ids[0] = &"reward_bypass"
	_check_close(
		V2_FORECAST.enemy_max_hp(base_patch_state, catalog),
		base_enemy_hp * 1.20,
		"reward_bypass must increase enemy HP without changing operator HP"
	)

	var normal_build := _stage_fixture(catalog, 9)
	var boss_build := _stage_fixture(catalog, 10)
	_check_close(
		V2_SIMULATOR.operator_attack_damage(boss_build, catalog, &"build_engineer"),
		V2_SIMULATOR.operator_attack_damage(normal_build, catalog, &"build_engineer") * 1.35,
		"Build Engineer must receive its boss damage role multiplier"
	)

	var base_heal := _trigger_rollback(_stage_fixture(catalog, 10), catalog, &"")
	var unsafe_heal := _trigger_rollback(_stage_fixture(catalog, 10), catalog, &"unsafe_build")
	var locked_heal := _trigger_rollback(_stage_fixture(catalog, 10), catalog, &"rollback_lock")
	_check_close(unsafe_heal, base_heal * 1.25, "unsafe_build must amplify watchdog rollback")
	_check_close(locked_heal, base_heal * 0.30, "rollback_lock must reduce watchdog rollback")

	var safe_state := _stage_fixture(catalog, 10)
	safe_state.progression.equipped_patch_ids[0] = &"safe_mode"
	safe_state.enemy_attack_remaining = 10.0
	safe_state.boss_special_remaining = 0.0
	safe_state.boss_rollback_remaining = 10.0
	for runtime: CombatV2State.OperatorRuntime in safe_state.operators:
		runtime.attack_remaining = 10.0
	V2_SIMULATOR.advance(safe_state, catalog, 0.001)
	_check_close(
		safe_state.boss_special_remaining,
		6.0 * 1.4 - 0.001,
		"safe_mode must delay future specials"
	)
	_check_close(safe_state.enemy_attack_remaining, 9.999, "safe_mode must not delay watchdog poll")


func _test_tie_ordering() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog
	var burst_state := _stage_fixture(catalog, 2)
	var debugger_profile := catalog.get_operator(&"debugger")
	debugger_profile.outgoing_multiplier = 3.8 / 5.2
	var debugger_runtime := burst_state.get_operator(&"debugger")
	var build_runtime := burst_state.get_operator(&"build_engineer")
	burst_state.operators.reverse()
	debugger_runtime.current_hp = 100.0
	build_runtime.current_hp = 100.0
	for runtime: CombatV2State.OperatorRuntime in burst_state.operators:
		runtime.attack_remaining = 10.0
	burst_state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(burst_state, catalog, 0.001)
	_check(
		debugger_runtime.current_hp < 100.0 and is_equal_approx(build_runtime.current_hp, 100.0),
		"equal-DPS burst targeting must choose the stable debugger ID first"
	)

	var state := _stage_fixture(catalog, 10)
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		runtime.attack_remaining = 10.0
	var debugger := state.get_operator(&"debugger")
	debugger.attack_remaining = 0.0
	state.progression.enemy_health = V2_SIMULATOR.operator_attack_damage(
		state, catalog, &"debugger"
	) * 0.5
	state.progression.boss_elapsed = catalog.base_catalog.balance.boss_time_limit
	state.enemy_attack_remaining = 0.0
	state.boss_special_remaining = 0.0
	state.boss_rollback_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	_check(state.progression.can_prestige, "operator kill must win a tie with attacks, rollback, and timeout")
	_check(state.progression.boss_failure_count == 0, "kill-at-timeout must not enter maintenance")
	_check(
		String(V2_DIAGNOSIS.evaluate(state, catalog).kind) == "complete",
		"completed stage 10 must never be diagnosed as firepower shortage"
	)


func _test_tick_partition_invariance() -> void:
	var single := V2_SESSION.new()
	var partitioned := V2_SESSION.new()
	var mixed := V2_SESSION.new()
	single.tick(120.0)
	for _step: int in range(480):
		partitioned.tick(0.25)
	var mixed_deltas: Array[float] = [0.125, 0.375, 0.5, 1.0, 2.0]
	for _cycle: int in range(30):
		for delta: float in mixed_deltas:
			mixed.tick(delta)
	_check_state_equal(
		single.debug_state_copy(),
		partitioned.debug_state_copy(),
		"120 seconds single vs 480 x 0.25"
	)
	_check_state_equal(
		single.debug_state_copy(),
		mixed.debug_state_copy(),
		"120 seconds single vs mixed partitions"
	)


func _test_chunk_equivalence() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog
	var single: CombatV2State = fixture.state
	var chunked := single.deep_clone()
	V2_SIMULATOR.advance(single, catalog, 8.0 * 60.0 * 60.0)
	for _chunk: int in range(480):
		V2_SIMULATOR.advance(chunked, catalog, 60.0)
	_check_close(single.total_elapsed, 8.0 * 60.0 * 60.0, "single offline simulation must consume 8h")
	_check_close(chunked.total_elapsed, 8.0 * 60.0 * 60.0, "chunked offline simulation must consume 8h")
	_check(not single.progression.can_prestige, "baseline offline fixture must exercise retries, not stop early")
	_check_state_equal(single, chunked, "8 hours vs 480 x 60 seconds")


func _test_forecast_matches_actual() -> void:
	var session := V2_SESSION.new()
	session.tick(7.25)
	var source := session.debug_state_copy()
	var load_result := V2_LOADER.load_default()
	_check(load_result.is_valid(), "forecast test requires content")
	if not load_result.is_valid():
		return
	var catalog: CombatV2Catalog = load_result.catalog
	var source_before := _state_signature(source)
	var forecast := V2_FORECAST.estimate(source, catalog)
	_check(
		_variants_equal(source_before, _state_signature(source)),
		"forecast must not mutate its source state"
	)
	var override_forecast := V2_FORECAST.estimate(
		source,
		catalog,
		[&"reward_bypass", &"", &""]
	)
	_check(
		_variants_equal(source_before, _state_signature(source)),
		"patch counterfactual must not mutate source HP, patches, or timers"
	)
	_check(
		float(override_forecast.seconds) >= float(forecast.seconds),
		"reward_bypass counterfactual must expose its enemy-HP drawback"
	)
	var actual := source.deep_clone()
	var before_elapsed := actual.total_elapsed
	var before_downs := actual.total_down_count
	var before_damage := actual.total_damage_taken
	var before_serial := actual.encounter_serial
	var before_bits := actual.progression.bits
	var before_boss_healed := actual.total_boss_healed
	var before_active_time := _total_active_time(actual)
	var unlocked_count := V2_SIMULATOR.unlocked_operator_count(actual)
	V2_SIMULATOR.advance(actual, catalog, 30.0, true)
	var actual_seconds := actual.total_elapsed - before_elapsed
	_check_close(float(forecast.seconds), actual.total_elapsed - before_elapsed, "forecast elapsed")
	_check(int(forecast.downs) == actual.total_down_count - before_downs, "forecast downs must match")
	_check_close(
		float(forecast.damage_taken),
		actual.total_damage_taken - before_damage,
		"forecast incoming damage"
	)
	_check(
		bool(forecast.encounter_changed) == (actual.encounter_serial != before_serial),
		"forecast encounter result must match actual simulator"
	)
	_check(bool(forecast.resolved), "stage-one forecast must resolve the current enemy")
	_check_close(float(forecast.bits_earned), actual.progression.bits - before_bits, "forecast bits")
	_check_close(
		float(forecast.boss_healed),
		actual.total_boss_healed - before_boss_healed,
		"forecast boss healing"
	)
	var expected_uptime := 0.0
	if actual_seconds > EPSILON and unlocked_count > 0:
		expected_uptime = (
			(_total_active_time(actual) - before_active_time)
			/ (actual_seconds * float(unlocked_count))
		)
	_check_close(float(forecast.uptime), expected_uptime, "forecast operator uptime")


func _test_maintenance_retry() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog
	var state := _stage_fixture(catalog, 10)
	state.progression.boss_elapsed = catalog.base_catalog.balance.boss_time_limit
	state.progression.enemy_health = V2_FORECAST.enemy_max_hp(state, catalog)
	state.enemy_attack_remaining = 10.0
	state.boss_special_remaining = 10.0
	state.boss_rollback_remaining = 10.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		runtime.attack_remaining = 10.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	_check(state.progression.is_maintenance, "boss timeout must enter maintenance")
	_check(state.progression.maintenance_cycles_remaining == 2, "maintenance must use two cycles")
	_check(state.progression.free_patch_swaps == 1, "first boss failure must grant one free swap")
	for _enemy: int in range(6):
		V2_SIMULATOR.advance(state, catalog, 120.0, true)
	_check(not state.progression.is_maintenance, "six safe maintenance enemies must retry the boss")
	_check(state.progression.stage == 10, "automatic retry must return to stage 10")
	_check(V2_SIMULATOR.all_active(state), "boss retry must start with a fully recovered team")
	_check_close(state.progression.boss_elapsed, 0.0, "boss retry timer must reset")


func _test_all_down_no_softlock() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var state: CombatV2State = fixture.state
	var catalog: CombatV2Catalog = fixture.catalog
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if state.progression.is_operator_unlocked(runtime.operator_id):
			runtime.current_hp = 0.0
			runtime.attack_remaining = INF
			runtime.recovery_remaining = 1.0
	var enemy_hp_before := state.progression.enemy_health
	_check(V2_SIMULATOR.all_down(state), "fixture must begin with every unlocked operator down")
	V2_SIMULATOR.advance(state, catalog, 5.0)
	_check(V2_SIMULATOR.active_operator_count(state) > 0, "time alone must recover operators")
	_check(
		state.progression.enemy_health < enemy_hp_before,
		"recovered operators must resume automatic attacks without player input"
	)


func _test_anti_debugger_matrix() -> void:
	var results: Array[Dictionary] = []
	for policy: String in ["debugger_focus", "cheapest", "balanced", "diagnosis_follow"]:
		var result: Dictionary = COMPARISON_REPORT.simulate_v2_policy(policy)
		results.append(result)
		_check(bool(result.valid), "%s policy must complete: %s" % [policy, String(result.error)])
	if results.size() != 4:
		return
	var focus := results[0]
	var dominates_all := true
	var margin_pass := false
	for index: int in range(1, results.size()):
		var candidate := results[index]
		dominates_all = dominates_all and (
			float(focus.clear_time) <= float(candidate.clear_time) + EPSILON
			and int(focus.maintenance_entries) <= int(candidate.maintenance_entries)
			and float(focus.total_value) + EPSILON >= float(candidate.total_value)
		)
		margin_pass = margin_pass or (
			float(candidate.clear_time) <= float(focus.clear_time) * 0.90 + EPSILON
			or int(candidate.maintenance_entries) <= int(focus.maintenance_entries) - 1
		)
	_check(not dominates_all, "debugger_focus must not Pareto-dominate every comparison policy")
	_check(margin_pass, "a non-debugger policy must be 10% faster or fail one fewer time")


func _run_greybox_headless_load() -> void:
	var failures_before := _assertion_failures
	var packed := load(GREYBOX_PATH) as PackedScene
	_check(packed != null, "independent greybox scene must load")
	if packed != null:
		var instance := packed.instantiate()
		root.add_child(instance)
		await process_frame
		await process_frame
		_check(instance.is_inside_tree(), "independent greybox must survive two headless frames")
		var enemy_label := instance.find_child("EnemyLabel", true, false) as Label
		var next_action_label := instance.find_child("NextActionLabel", true, false) as Label
		var diagnosis_label := instance.find_child("DiagnosisLabel", true, false) as Label
		var debugger_label := instance.find_child("Operator_debugger", true, false) as Label
		_check(enemy_label != null and "ST 1" in enemy_label.text, "greybox must render stage and enemy")
		_check(
			next_action_label != null and "다음 적 행동" in next_action_label.text,
			"greybox must render the next enemy action"
		)
		_check(
			diagnosis_label != null and not diagnosis_label.text.strip_edges().is_empty(),
			"greybox must render a diagnosis"
		)
		_check(
			debugger_label != null and "HP" in debugger_label.text and "전열 안정화" in debugger_label.text,
			"greybox must render operator role and HP"
		)
		root.remove_child(instance)
		instance.queue_free()
		await process_frame
	_finish_test("independent greybox headless load", failures_before)


func _new_fixture() -> Dictionary:
	var load_result := V2_LOADER.load_default()
	_check(load_result.is_valid(), "Combat V2 fixture content must load")
	if not load_result.is_valid():
		return {}
	var state := V2_STATE.new()
	V2_SIMULATOR.initialize_new_run(state, load_result.catalog)
	return {"state": state, "catalog": load_result.catalog}


func _stage_fixture(catalog: CombatV2Catalog, stage: int) -> CombatV2State:
	var state := V2_STATE.new()
	V2_SIMULATOR.initialize_new_run(state, catalog)
	state.progression.stage = stage
	state.progression.highest_stage = stage
	state.progression.enemy_index = 1
	state.progression.is_maintenance = false
	state.progression.can_prestige = false
	state.progression.boss_elapsed = 0.0
	state.progression.boss_failure_count = 0
	ProgressionRules.refresh_unlocks(state.progression, catalog.base_catalog)
	V2_SIMULATOR.reset_team_full(state, catalog)
	state.progression.enemy_health = V2_FORECAST.enemy_max_hp(state, catalog)
	var profile := V2_SIMULATOR.current_enemy_profile(state, catalog)
	if stage == catalog.balance.max_stage:
		state.enemy_attack_remaining = profile.poll_interval
		state.boss_special_remaining = profile.special_interval
		state.boss_rollback_remaining = profile.rollback_interval
	else:
		state.enemy_attack_remaining = profile.attack_interval
		state.boss_special_remaining = INF
		state.boss_rollback_remaining = INF
	state.enemy_pattern_step = 0
	state.enemy_locked_target_id = &""
	return state


func _trigger_rollback(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	patch_id: StringName
) -> float:
	state.progression.equipped_patch_ids[0] = patch_id
	var max_hp := V2_FORECAST.enemy_max_hp(state, catalog)
	state.progression.enemy_health = max_hp * 0.5
	state.enemy_attack_remaining = 10.0
	state.boss_special_remaining = 10.0
	state.boss_rollback_remaining = 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		runtime.attack_remaining = 10.0
	var before := state.progression.enemy_health
	V2_SIMULATOR.advance(state, catalog, 0.001)
	return state.progression.enemy_health - before


func _check_state_equal(first: CombatV2State, second: CombatV2State, context: String) -> void:
	_check(
		_variants_equal(_state_signature(first), _state_signature(second)),
		"%s: complete observable state" % context
	)
	_check(first.progression.stage == second.progression.stage, "%s: stage" % context)
	_check(first.progression.enemy_index == second.progression.enemy_index, "%s: enemy index" % context)
	_check(first.progression.is_maintenance == second.progression.is_maintenance, "%s: mode" % context)
	_check(first.progression.can_prestige == second.progression.can_prestige, "%s: complete" % context)
	_check_close(first.progression.bits, second.progression.bits, "%s: bits" % context)
	_check_close(first.progression.enemy_health, second.progression.enemy_health, "%s: enemy HP" % context)
	_check_close(first.progression.boss_elapsed, second.progression.boss_elapsed, "%s: boss time" % context)
	_check_close(first.enemy_attack_remaining, second.enemy_attack_remaining, "%s: enemy timer" % context)
	_check_close(first.boss_special_remaining, second.boss_special_remaining, "%s: special timer" % context)
	_check_close(first.boss_rollback_remaining, second.boss_rollback_remaining, "%s: rollback timer" % context)
	_check(first.enemy_pattern_step == second.enemy_pattern_step, "%s: enemy phase" % context)
	_check(first.enemy_locked_target_id == second.enemy_locked_target_id, "%s: target lock" % context)
	_check(first.encounter_serial == second.encounter_serial, "%s: encounter serial" % context)
	_check(first.operators.size() == second.operators.size(), "%s: operator count" % context)
	for index: int in range(mini(first.operators.size(), second.operators.size())):
		var left := first.operators[index]
		var right := second.operators[index]
		_check(left.operator_id == right.operator_id, "%s: operator order" % context)
		_check_close(left.current_hp, right.current_hp, "%s: %s HP" % [context, left.operator_id])
		_check_close(
			left.attack_remaining, right.attack_remaining,
			"%s: %s attack timer" % [context, left.operator_id]
		)
		_check_close(
			left.recovery_remaining, right.recovery_remaining,
			"%s: %s recovery" % [context, left.operator_id]
		)
		_check(left.down_count == right.down_count, "%s: %s downs" % [context, left.operator_id])


func _state_signature(state: CombatV2State) -> Dictionary:
	var progression := state.progression
	var operator_rows: Array[Dictionary] = []
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		var runtime := state.get_operator(operator_id)
		assert(runtime != null, "Combat V2 state signature requires every operator")
		operator_rows.append({
			"id": runtime.operator_id,
			"hp": runtime.current_hp,
			"attack": runtime.attack_remaining,
			"recovery": runtime.recovery_remaining,
			"dealt": runtime.damage_dealt,
			"taken": runtime.damage_taken,
			"downs": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		})
	return {
		"progression": {
			"stage": progression.stage,
			"highest_stage": progression.highest_stage,
			"bits": progression.bits,
			"patch_notes": progression.patch_notes,
			"run_count": progression.run_count,
			"legacy_cache_level": progression.legacy_cache_level,
			"operator_levels": progression.operator_levels.duplicate(true),
			"unlocked_operator_ids": progression.unlocked_operator_ids.duplicate(),
			"discovered_patch_ids": progression.discovered_patch_ids.duplicate(),
			"equipped_patch_ids": progression.equipped_patch_ids.duplicate(),
			"unlocked_patch_slots": progression.unlocked_patch_slots,
			"enemy_index": progression.enemy_index,
			"enemy_health": progression.enemy_health,
			"boss_elapsed": progression.boss_elapsed,
			"boss_recovery_count": progression.boss_recovery_count,
			"boss_recovered_health": progression.boss_recovered_health,
			"boss_debuff_applied": progression.boss_debuff_applied,
			"boss_failure_count": progression.boss_failure_count,
			"is_maintenance": progression.is_maintenance,
			"maintenance_cycles_remaining": progression.maintenance_cycles_remaining,
			"can_prestige": progression.can_prestige,
			"free_patch_swaps": progression.free_patch_swaps,
			"status_message": progression.status_message,
		},
		"operators": operator_rows,
		"timers": {
			"enemy": state.enemy_attack_remaining,
			"pattern_step": state.enemy_pattern_step,
			"locked_target": state.enemy_locked_target_id,
			"boss_special": state.boss_special_remaining,
			"boss_rollback": state.boss_rollback_remaining,
			"qa_pulse": state.qa_pulse_remaining,
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
			"stage_damage_taken": state.stage_damage_taken,
			"stage_down_count": state.stage_down_count,
			"stage_down_time": state.stage_down_time,
			"stage_boss_healed": state.stage_boss_healed,
		},
		"recent_events": state.recent_events.duplicate(true),
	}


func _total_active_time(state: CombatV2State) -> float:
	var total := 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		total += runtime.active_time
	return total


func _variants_equal(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		var left_number := float(left)
		var right_number := float(right)
		if is_inf(left_number) or is_inf(right_number):
			return is_inf(left_number) and is_inf(right_number) and sign(left_number) == sign(right_number)
		return absf(left_number - right_number) <= EPSILON
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for key: Variant in left_dictionary.keys():
			if not right_dictionary.has(key):
				return false
			if not _variants_equal(left_dictionary[key], right_dictionary[key]):
				return false
		return true
	if left is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index: int in range(left_array.size()):
			if not _variants_equal(left_array[index], right_array[index]):
				return false
		return true
	return left == right


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _check_close(actual: float, expected: float, message: String) -> void:
	var both_infinite: bool = (
		is_inf(actual) and is_inf(expected) and sign(actual) == sign(expected)
	)
	_check(both_infinite or absf(actual - expected) <= EPSILON, "%s (%.6f vs %.6f)" % [
		message, actual, expected,
	])
