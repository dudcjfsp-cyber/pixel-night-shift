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
	_run_test("linear HP, process-down persistence, and stage full heal", _test_hp_down_recovery)
	_run_test("QA one-shot rescue, cancellation, and stable recovery ordering", _test_qa_limited_recovery)
	_run_test("emergency redeploy command validation and atomic spend", _test_emergency_redeploy)
	_run_test("operator roles and patch tradeoffs", _test_roles_and_patch_tradeoffs)
	_run_test("stable tie ordering and kill-at-timeout", _test_tie_ordering)
	_run_test("tick partition invariance", _test_tick_partition_invariance)
	_run_test("offline-style chunk equivalence", _test_chunk_equivalence)
	_run_test("forecast uses the actual simulator", _test_forecast_matches_actual)
	_run_test("all-down and timeout failures enter six-second maintenance", _test_maintenance_retry)
	_run_test("failed attempts retry deterministically without a soft lock", _test_all_down_no_softlock)
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
	var invalid_redeploy_fraction := (parsed as Dictionary).duplicate(true)
	(invalid_redeploy_fraction["balance"] as Dictionary)["emergency_cost_fraction"] = 0.0
	_check(
		not V2_LOADER.load_from_json(
			JSON.stringify(invalid_redeploy_fraction), base_catalog
		).is_valid(),
		"zero emergency cost fraction must be rejected"
	)
	var missing_maintenance := (parsed as Dictionary).duplicate(true)
	(missing_maintenance["balance"] as Dictionary).erase("maintenance_seconds")
	_check(
		not V2_LOADER.load_from_json(JSON.stringify(missing_maintenance), base_catalog).is_valid(),
		"missing maintenance duration must be rejected"
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
	state = _stage_fixture(catalog, 4)
	state.qa_rescue_consumed = true
	var debugger := state.get_operator(&"debugger")
	debugger.current_hp = 1.0
	debugger.attack_remaining = 10.0
	state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	_check(not debugger.is_active(), "focused damage must down the debugger")
	_check(debugger.recovery_source == &"", "base process-down must not schedule recovery")
	V2_SIMULATOR.advance(state, catalog, 4.0)
	_check(not debugger.is_active(), "time alone must never recover a process-down operator")
	_check(
		String(V2_DIAGNOSIS.evaluate(state, catalog).kind) == "recovery_delay",
		"one unscheduled process-down operator must never be diagnosed as stable"
	)

	state.progression.enemy_health = 0.01
	state.get_operator(&"build_engineer").attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001, true)
	_check(state.progression.enemy_index == 2, "normal enemy transition must stay in the stage")
	_check(not debugger.is_active(), "process-down must persist between the three normal enemies")

	state.progression.enemy_index = catalog.balance.normal_enemy_count
	state.progression.enemy_health = 0.01
	state.get_operator(&"build_engineer").attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001, true)
	_check(state.progression.stage == 5, "third enemy defeat must clear the stage")
	_check(V2_SIMULATOR.all_active(state), "stage clear must restore the entire unlocked team")
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if state.progression.is_operator_unlocked(runtime.operator_id):
			_check_close(
				runtime.current_hp,
				V2_SIMULATOR.operator_max_hp(state, catalog, runtime.operator_id),
				"stage clear full heal for %s" % runtime.operator_id
			)


func _test_qa_limited_recovery() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog
	var state := _stage_fixture(catalog, 6)
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		runtime.attack_remaining = 100.0
	state.get_operator(&"debugger").current_hp = 1.0
	state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	var debugger := state.get_operator(&"debugger")
	_check(debugger.recovery_source == &"qa", "first ally down must reserve QA recovery")
	_check_close(debugger.recovery_remaining, catalog.balance.qa_recovery_delay - 0.001, "QA delay")
	_check(state.qa_rescue_consumed, "QA rescue must be consumed once scheduled")
	state.enemy_attack_remaining = 100.0
	var rescue_forecast := V2_FORECAST.estimate(state, catalog)
	_check(
		int(rescue_forecast.ending_down_count) == 0,
		"forecast expected-down count must reflect the pending QA rescue"
	)
	V2_SIMULATOR.advance(state, catalog, debugger.recovery_remaining)
	_check(debugger.is_active(), "QA reservation must restore the first downed ally")
	_check_close(
		debugger.current_hp,
		V2_SIMULATOR.operator_max_hp(state, catalog, &"debugger") * 0.4,
		"QA rescue must restore 40 percent max HP"
	)
	_check(state.qa_rescue_count == 1, "QA rescue count must increment once")
	var build := state.get_operator(&"build_engineer")
	build.current_hp = 1.0
	state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	_check(not build.is_active() and build.recovery_source == &"", "second stage down must stay down")

	var cancelled := _stage_fixture(catalog, 6)
	for runtime: CombatV2State.OperatorRuntime in cancelled.operators:
		runtime.attack_remaining = 100.0
	var cancel_target := cancelled.get_operator(&"debugger")
	cancel_target.current_hp = 1.0
	cancelled.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(cancelled, catalog, 0.001)
	_check(cancel_target.recovery_source == &"qa", "cancellation fixture must reserve QA recovery")
	cancelled.get_operator(&"qa_imp").current_hp = 1.0
	cancelled.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(cancelled, catalog, 0.001)
	_check(not cancelled.get_operator(&"qa_imp").is_active(), "QA must be downed in cancellation fixture")
	_check(
		cancel_target.recovery_source == &"" and is_zero_approx(cancel_target.recovery_remaining),
		"QA down before completion must cancel the pending free recovery"
	)
	V2_SIMULATOR.advance(cancelled, catalog, catalog.balance.qa_recovery_delay + 0.1)
	_check(not cancel_target.is_active(), "cancelled QA recovery must never fire later")

	var qa_first := _stage_fixture(catalog, 6)
	for runtime: CombatV2State.OperatorRuntime in qa_first.operators:
		runtime.attack_remaining = 100.0
	qa_first.get_operator(&"qa_imp").current_hp = 1.0
	qa_first.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(qa_first, catalog, 0.001)
	_check(qa_first.qa_rescue_consumed, "QA first-down must consume the stage rescue opportunity")
	qa_first.get_operator(&"debugger").current_hp = 1.0
	qa_first.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(qa_first, catalog, 0.001)
	_check(
		qa_first.get_operator(&"debugger").recovery_source == &"",
		"an ally down after QA must not receive a free recovery"
	)


func _test_emergency_redeploy() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog
	var state := _stage_fixture(catalog, 6)
	state.qa_rescue_consumed = true
	var target := state.get_operator(&"debugger")
	target.current_hp = 0.0
	target.attack_remaining = INF
	var expected_cheapest := INF
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		if not state.progression.is_operator_unlocked(definition.id):
			continue
		var level := int(state.progression.operator_levels.get(definition.id, 0))
		expected_cheapest = minf(expected_cheapest, ProgressionRules.operator_upgrade_cost(
			level, definition.base_cost, definition.cost_growth
		))
	var expected_cost := maxf(1.0, ceilf(expected_cheapest * 0.80))
	var cost := V2_SIMULATOR.emergency_redeploy_cost(state, catalog)
	_check_close(cost, expected_cost, "emergency cost must use 80 percent of cheapest next upgrade")

	state.progression.bits = cost - 1.0
	var insufficient_before := _state_signature(state)
	var insufficient := V2_SIMULATOR.request_emergency_redeploy(state, catalog, &"debugger")
	_check(not bool(insufficient.succeeded), "insufficient bits must reject emergency redeploy")
	_check(String(insufficient.error) != "", "insufficient bits rejection must explain the failure")
	_check(
		_variants_equal(insufficient_before, _state_signature(state)),
		"rejected emergency redeploy must leave the complete state unchanged"
	)

	state.progression.bits = cost + 10.0
	var accepted := V2_SIMULATOR.request_emergency_redeploy(state, catalog, &"debugger")
	_check(bool(accepted.succeeded), "valid emergency redeploy must be accepted")
	_check_close(state.progression.bits, 10.0, "accepted command must deduct bits exactly once")
	_check_close(state.emergency_spent_bits, cost, "spent-bit metric must record the one charge")
	_check(state.paid_redeploy_count == 1, "paid redeploy count must increment at approval")
	_check(target.recovery_source == &"emergency", "accepted target must own an emergency reservation")
	_check_close(target.recovery_remaining, 2.0, "emergency redeploy delay must be two seconds")
	var duplicate_before := _state_signature(state)
	var duplicate := V2_SIMULATOR.request_emergency_redeploy(state, catalog, &"debugger")
	_check(not bool(duplicate.succeeded), "attempt must reject a second emergency redeploy")
	_check(
		_variants_equal(duplicate_before, _state_signature(state)),
		"duplicate rejection must not charge bits or alter the reservation"
	)
	state.enemy_attack_remaining = 100.0
	V2_SIMULATOR.advance(state, catalog, 2.0)
	_check(target.is_active(), "paid redeploy must restore its selected target after two seconds")
	_check_close(
		target.current_hp,
		V2_SIMULATOR.operator_max_hp(state, catalog, &"debugger") * 0.4,
		"paid redeploy must restore 40 percent max HP"
	)

	var active_state := _stage_fixture(catalog, 6)
	var active_before := _state_signature(active_state)
	var invalid_target := V2_SIMULATOR.request_emergency_redeploy(
		active_state, catalog, &"debugger"
	)
	_check(not bool(invalid_target.succeeded), "active operator must be an invalid target")
	_check(
		_variants_equal(active_before, _state_signature(active_state)),
		"invalid target rejection must be atomic"
	)
	var unknown_before := _state_signature(active_state)
	var unknown_target := V2_SIMULATOR.request_emergency_redeploy(
		active_state, catalog, &"not_an_operator"
	)
	_check(not bool(unknown_target.succeeded), "unknown operator must be rejected")
	_check(
		_variants_equal(unknown_before, _state_signature(active_state)),
		"unknown target rejection must be atomic"
	)
	var locked_state := _stage_fixture(catalog, 1)
	var locked_before := _state_signature(locked_state)
	var locked_target := V2_SIMULATOR.request_emergency_redeploy(
		locked_state, catalog, &"qa_imp"
	)
	_check(not bool(locked_target.succeeded), "locked operator must be rejected")
	_check(
		_variants_equal(locked_before, _state_signature(locked_state)),
		"locked target rejection must be atomic"
	)
	var session := V2_SESSION.new()
	var session_before := session.snapshot()
	_check(not session.emergency_redeploy(&"debugger"), "session command must reject an active target")
	var session_after := session.snapshot()
	_check(String(session_after.last_error) != "", "session rejection must expose last_error")
	_check_close(float(session_after.bits), float(session_before.bits), "session rejection must not charge")


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

	var recovery_state := _stage_fixture(catalog, 6)
	for runtime: CombatV2State.OperatorRuntime in recovery_state.operators:
		runtime.attack_remaining = 100.0
	var recovery_debugger := recovery_state.get_operator(&"debugger")
	var recovery_build := recovery_state.get_operator(&"build_engineer")
	recovery_debugger.current_hp = 1.0
	recovery_state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(recovery_state, catalog, 0.001)
	_check(recovery_debugger.recovery_source == &"qa", "tie fixture must schedule QA recovery")
	var duplicate_before := _state_signature(recovery_state)
	var same_target := V2_SIMULATOR.request_emergency_redeploy(
		recovery_state, catalog, &"debugger"
	)
	_check(not bool(same_target.succeeded), "QA target must reject duplicate paid recovery")
	_check(
		_variants_equal(duplicate_before, _state_signature(recovery_state)),
		"duplicate QA/paid target rejection must be a complete no-op"
	)
	recovery_build.current_hp = 1.0
	var command_delay := recovery_debugger.recovery_remaining - 2.0
	recovery_state.enemy_attack_remaining = command_delay
	V2_SIMULATOR.advance(recovery_state, catalog, command_delay)
	recovery_state.progression.bits = 1000.0
	var paid := V2_SIMULATOR.request_emergency_redeploy(
		recovery_state, catalog, &"build_engineer"
	)
	_check(bool(paid.succeeded), "tie fixture must schedule paid recovery for a second target")
	recovery_state.enemy_attack_remaining = 100.0
	var event_start := recovery_state.recent_events.size()
	V2_SIMULATOR.advance(recovery_state, catalog, 2.0)
	var recovered_ids: Array[StringName] = []
	for event_index: int in range(event_start, recovery_state.recent_events.size()):
		var event := recovery_state.recent_events[event_index]
		if StringName(event.kind) == &"operator_recovered":
			recovered_ids.append(StringName(event.operator_id))
	_check(
		recovered_ids == [&"debugger", &"build_engineer"],
		"same-time recoveries must resolve by stable operator ID before source priority"
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
	var wipe_state := _stage_fixture(catalog, 6)
	wipe_state.progression.enemy_index = 2
	for runtime: CombatV2State.OperatorRuntime in wipe_state.operators:
		if wipe_state.progression.is_operator_unlocked(runtime.operator_id):
			runtime.current_hp = 1.0
			runtime.attack_remaining = 100.0
	wipe_state.enemy_attack_remaining = 0.0
	var wipe_before := _state_signature(wipe_state)
	var wipe_forecast := V2_FORECAST.estimate(wipe_state, catalog)
	_check(not bool(wipe_forecast.resolved), "enemy-two wipe must not be forecast as a kill")
	_check(bool(wipe_forecast.maintenance), "wipe forecast must expose maintenance")
	_check(int(wipe_forecast.failures) == 1, "wipe forecast must expose one failure")
	_check(
		int(wipe_forecast.ending_down_count) == V2_SIMULATOR.unlocked_operator_count(wipe_state),
		"wipe forecast expected-down count must expose the full team"
	)
	_check(
		_variants_equal(wipe_before, _state_signature(wipe_state)),
		"wipe forecast must not mutate its source state"
	)
	var actual := source.deep_clone()
	var before_elapsed := actual.total_elapsed
	var before_downs := actual.total_down_count
	var before_damage := actual.total_damage_taken
	var before_serial := actual.encounter_serial
	var before_bits := actual.progression.bits
	var before_boss_healed := actual.total_boss_healed
	var before_failures := actual.total_failure_count()
	var before_normal_failures := actual.normal_failure_count
	var before_boss_failures := actual.progression.boss_failure_count
	var before_qa_rescues := actual.qa_rescue_count
	var before_paid_redeploys := actual.paid_redeploy_count
	var before_emergency_spent := actual.emergency_spent_bits
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
	_check(
		int(forecast.failures) == actual.total_failure_count() - before_failures,
		"forecast failures"
	)
	_check(
		int(forecast.normal_failures) == actual.normal_failure_count - before_normal_failures,
		"forecast normal failures"
	)
	_check(
		int(forecast.boss_failures) == actual.progression.boss_failure_count - before_boss_failures,
		"forecast boss failures"
	)
	_check(int(forecast.qa_rescues) == actual.qa_rescue_count - before_qa_rescues, "forecast QA rescues")
	_check(
		int(forecast.paid_redeploys) == actual.paid_redeploy_count - before_paid_redeploys,
		"forecast must not inject paid redeploys"
	)
	_check_close(
		float(forecast.emergency_spent_bits),
		actual.emergency_spent_bits - before_emergency_spent,
		"forecast emergency spend"
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
	var normal := _stage_fixture(catalog, 6)
	for runtime: CombatV2State.OperatorRuntime in normal.operators:
		if normal.progression.is_operator_unlocked(runtime.operator_id):
			runtime.current_hp = 1.0
			runtime.attack_remaining = 100.0
	var normal_bits := normal.progression.bits
	var normal_attempt := normal.attempt_serial
	normal.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(normal, catalog, 0.001)
	_check(normal.progression.is_maintenance, "normal all-down must fail immediately")
	_check(
		normal.total_failure_count() == 1 and normal.normal_failure_count == 1,
		"normal failure counters"
	)
	_check(normal.last_failure_reason == &"normal_all_down", "normal failure reason must be explicit")
	_check_close(
		normal.maintenance_remaining,
		catalog.balance.maintenance_seconds - 0.001,
		"normal failure maintenance duration"
	)
	_check_close(normal.progression.bits, normal_bits, "failure must preserve bits")
	var maintenance_diagnosis := V2_DIAGNOSIS.evaluate(normal, catalog)
	_check(String(maintenance_diagnosis.kind) == "maintenance", "maintenance diagnosis kind")
	var maintenance_evidence := maintenance_diagnosis.evidence_data as Dictionary
	for key: String in [
		"recovery_cost", "current_downs", "forecast_downs", "estimated_wipe_risk",
		"wipe_risk_basis", "failure_count", "maintenance", "maintenance_remaining",
		"maintenance_reason", "emergency_available",
	]:
		_check(maintenance_evidence.has(key), "diagnosis evidence must expose %s" % key)
	_check(bool(maintenance_evidence.maintenance), "diagnosis must mark maintenance active")
	var maintenance_command_before := _state_signature(normal)
	var maintenance_command := V2_SIMULATOR.request_emergency_redeploy(
		normal, catalog, &"debugger"
	)
	_check(not bool(maintenance_command.succeeded), "ended attempt must reject emergency command")
	_check(
		_variants_equal(maintenance_command_before, _state_signature(normal)),
		"maintenance command rejection must leave state unchanged"
	)
	var failed_enemy_hp := normal.progression.enemy_health
	V2_SIMULATOR.advance(normal, catalog, 5.499)
	_check(normal.progression.is_maintenance, "retry must wait the full six seconds")
	_check_close(normal.progression.enemy_health, failed_enemy_hp, "maintenance must not attack the enemy")
	V2_SIMULATOR.advance(normal, catalog, 0.5)
	_check(not normal.progression.is_maintenance, "six seconds must start the automatic retry")
	_check(normal.progression.stage == 6 and normal.progression.enemy_index == 1, "retry same stage from enemy one")
	_check(normal.attempt_serial == normal_attempt + 1, "retry must create a new attempt serial")
	_check(V2_SIMULATOR.all_active(normal), "normal retry must start with full team health")
	_check(normal.qa_rescue_consumed, "QA stage rescue usage must persist across same-stage retry")
	_check(not normal.emergency_redeploy_used, "paid redeploy allowance must reset for the new attempt")

	var boss_down := _stage_fixture(catalog, 10)
	for runtime: CombatV2State.OperatorRuntime in boss_down.operators:
		runtime.current_hp = 0.0
		runtime.attack_remaining = INF
	var last_active := boss_down.get_operator(&"debugger")
	last_active.current_hp = 1.0
	last_active.attack_remaining = 100.0
	boss_down.enemy_attack_remaining = 0.0
	boss_down.boss_special_remaining = 100.0
	boss_down.boss_rollback_remaining = 100.0
	V2_SIMULATOR.advance(boss_down, catalog, 0.001)
	_check(boss_down.progression.is_maintenance, "boss all-down must fail immediately")
	_check(boss_down.last_failure_reason == &"boss_all_down", "boss all-down reason")
	_check(boss_down.progression.boss_failure_count == 1, "boss all-down failure counter")

	var timeout := _stage_fixture(catalog, 10)
	timeout.progression.boss_elapsed = catalog.base_catalog.balance.boss_time_limit
	timeout.progression.enemy_health = V2_FORECAST.enemy_max_hp(timeout, catalog)
	timeout.enemy_attack_remaining = 100.0
	timeout.boss_special_remaining = 100.0
	timeout.boss_rollback_remaining = 100.0
	for runtime: CombatV2State.OperatorRuntime in timeout.operators:
		runtime.attack_remaining = 100.0
	V2_SIMULATOR.advance(timeout, catalog, 0.001)
	_check(timeout.progression.is_maintenance, "boss timeout must enter maintenance")
	_check(timeout.last_failure_reason == &"boss_timeout", "boss timeout reason must be explicit")
	_check(timeout.progression.boss_failure_count == 1, "boss timeout failure counter")
	_check(timeout.progression.free_patch_swaps == 1, "first boss failure keeps the existing free swap")

	var natural_boss := _stage_fixture(catalog, 10)
	V2_SIMULATOR.advance(
		natural_boss,
		catalog,
		catalog.base_catalog.balance.boss_time_limit + 1.0,
		true
	)
	_check(
		natural_boss.progression.is_maintenance
		and natural_boss.progression.boss_failure_count == 1,
		"untuned level-one product rules must make a real boss failure reachable"
	)


func _test_all_down_no_softlock() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var catalog: CombatV2Catalog = fixture.catalog
	var state := _stage_fixture(catalog, 6)
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if state.progression.is_operator_unlocked(runtime.operator_id):
			runtime.current_hp = 1.0
			runtime.attack_remaining = 100.0
	state.enemy_attack_remaining = 0.0
	V2_SIMULATOR.advance(state, catalog, 0.001)
	_check(state.progression.is_maintenance, "fixture must enter maintenance after wipe")
	V2_SIMULATOR.advance(state, catalog, 6.0)
	_check(not state.progression.is_maintenance, "maintenance must always leave a deterministic retry")
	var retry_hp := state.progression.enemy_health
	var retry_serial := state.encounter_serial
	V2_SIMULATOR.advance(state, catalog, 30.0)
	_check(
		state.progression.enemy_health < retry_hp or state.encounter_serial > retry_serial,
		"automatic combat must resume after retry without player input"
	)
	_check(state.total_elapsed >= 36.001 - EPSILON, "no-softlock path must consume elapsed time")


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
			and int(focus.total_failures) <= int(candidate.total_failures)
			and float(focus.total_value) + EPSILON >= float(candidate.total_value)
		)
		margin_pass = margin_pass or (
			float(candidate.clear_time) <= float(focus.clear_time) * 0.90 + EPSILON
			or int(candidate.total_failures) <= int(focus.total_failures) - 1
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
		var redeploy_button := instance.find_child("Redeploy_debugger", true, false) as Button
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
		_check(
			redeploy_button != null
			and "EMERGENCY REDEPLOY" in redeploy_button.text
			and "bits" in redeploy_button.text
			and "left" in redeploy_button.text,
			"greybox must expose selected-target redeploy cost and remaining use"
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
			"recovery_source": runtime.recovery_source,
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
		},
		"metrics": {
			"encounter_serial": state.encounter_serial,
			"attempt_serial": state.attempt_serial,
			"maintenance_remaining": state.maintenance_remaining,
			"failure_count": state.total_failure_count(),
			"normal_failure_count": state.normal_failure_count,
			"last_failure_reason": state.last_failure_reason,
			"qa_rescue_consumed": state.qa_rescue_consumed,
			"qa_recovery_target_id": state.qa_recovery_target_id,
			"qa_rescue_count": state.qa_rescue_count,
			"emergency_redeploy_used": state.emergency_redeploy_used,
			"emergency_redeploy_target_id": state.emergency_redeploy_target_id,
			"paid_redeploy_count": state.paid_redeploy_count,
			"emergency_spent_bits": state.emergency_spent_bits,
			"total_bits_earned": state.total_bits_earned,
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
