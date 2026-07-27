extends SceneTree

const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const NightShiftState := preload(
	"res://game/domain/product_v2/night_shift_state.gd"
)
const PRODUCT_V2_LOADER := preload("res://game/content/product_v2/product_v2_loader.gd")
const NIGHT_SHIFT_SIMULATOR := preload(
	"res://game/domain/product_v2/night_shift_simulator.gd"
)

const PROFILE_PATH := "res://game/content/product_v2/product_v2.json"
const EPSILON := 0.00001
const ALL_OPERATOR_IDS: Array[StringName] = [
	&"debugger",
	&"build_engineer",
	&"sprite_artist",
	&"qa_imp",
]

var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift Product V2 night-shift tests")
	print("================================================")
	var required_scripts: Array[Script] = [
		ProductV2Catalog,
		NightShiftState,
		PRODUCT_V2_LOADER,
		NIGHT_SHIFT_SIMULATOR,
	]
	for required_script: Script in required_scripts:
		if not required_script.can_instantiate():
			print("FAIL  Product V2 scripts did not compile")
			print("================================================")
			print("RESULT: 0 passed, 1 failed, 1 assertion failure")
			quit(1)
			return
	_run_test("default content and strict rejection", _test_content_contract)
	_run_test("tick partition invariance", _test_tick_partition_invariance)
	_run_test(
		"normal deadline ordering and transition boundary",
		_test_normal_deadline_and_transition
	)
	_run_test("leak cap and star boundaries", _test_leak_cap_and_star_boundaries)
	_run_test(
		"boss boundary outcomes and terminal immutability",
		_test_boss_boundaries_and_terminal_immutability
	)
	print("================================================")
	print("RESULT: %d passed, %d failed, %d assertion failures" % [
		_passed,
		_failed,
		_assertion_failures,
	])
	quit(0 if _failed == 0 else 1)


func _run_test(test_name: String, method: Callable) -> void:
	var before := _assertion_failures
	method.call()
	if before == _assertion_failures:
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


func _check_close(actual: float, expected: float, message: String) -> void:
	var both_infinite: bool = (
		is_inf(actual)
		and is_inf(expected)
		and sign(actual) == sign(expected)
	)
	_check(
		both_infinite or absf(actual - expected) <= EPSILON,
		"%s (%.6f vs %.6f)" % [message, actual, expected]
	)


func _test_content_contract() -> void:
	var load_result := PRODUCT_V2_LOADER.load_default()
	_check(load_result.is_valid(), "default Product V2 content must load")
	if not load_result.is_valid():
		return

	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	_check(file != null, "strict rejection fixture must read the Product V2 profile")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY, "Product V2 profile fixture must be an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var invalid := (parsed as Dictionary).duplicate(true)
	(invalid["balance"] as Dictionary)["silent_fallback"] = true
	var rejected := PRODUCT_V2_LOADER.load_from_json(
		JSON.stringify(invalid),
		load_result.catalog.base_catalog
	)
	_check(not rejected.is_valid(), "an unknown content key must be rejected")

	var oversized_wave := (parsed as Dictionary).duplicate(true)
	var first_shift := (oversized_wave["shifts"] as Array)[0] as Dictionary
	var first_wave := (first_shift["waves"] as Array)[0] as Dictionary
	var first_entry := (first_wave["entries"] as Array)[0] as Dictionary
	first_entry["count"] = 7
	var oversized_rejection := PRODUCT_V2_LOADER.load_from_json(
		JSON.stringify(oversized_wave),
		load_result.catalog.base_catalog
	)
	_check(
		not oversized_rejection.is_valid(),
		"more than six enemies in one wave must be rejected"
	)


func _test_tick_partition_invariance() -> void:
	var catalog := _load_catalog()
	if catalog == null:
		return
	var single := _create_state(catalog, 3)
	var partitioned := _create_state(catalog, 3)
	NIGHT_SHIFT_SIMULATOR.advance(single, catalog, 90.0)
	for _step: int in range(360):
		NIGHT_SHIFT_SIMULATOR.advance(partitioned, catalog, 0.25)
	_check(
		_variants_equal(_state_signature(single), _state_signature(partitioned)),
		"one 90-second tick and 360 quarter-second ticks must produce the same state"
	)

	var tiny_single := _create_state(catalog, 3)
	var tiny_partitioned := _create_state(catalog, 3)
	var tiny_total := 0.00001
	NIGHT_SHIFT_SIMULATOR.advance(tiny_single, catalog, tiny_total)
	var tiny_consumed := 0.0
	for _step: int in range(100):
		tiny_consumed += NIGHT_SHIFT_SIMULATOR.advance(
			tiny_partitioned,
			catalog,
			tiny_total / 100.0
		)
	_check_close(tiny_consumed, tiny_total, "positive sub-microsecond ticks must not be discarded")
	_check(
		_variants_equal(_state_signature(tiny_single), _state_signature(tiny_partitioned)),
		"very small tick partitions must preserve the same state"
	)


func _test_normal_deadline_and_transition() -> void:
	var catalog := _load_catalog()
	if catalog == null:
		return
	var state := _create_state(catalog, 1)
	NIGHT_SHIFT_SIMULATOR.advance(state, catalog, catalog.balance.countdown_seconds)
	_check(
		state.phase == NightShiftState.Phase.NORMAL_ACTIVE and state.current_wave == 1,
		"countdown completion must start normal wave 1"
	)
	if state.phase != NightShiftState.Phase.NORMAL_ACTIVE or state.enemies.is_empty():
		return

	state.enemies.resize(1)
	state.enemies[0].current_hp = 0.001
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF
	state.get_operator_combat_state(&"debugger").attack_remaining = (
		catalog.balance.normal_wave_seconds
	)

	NIGHT_SHIFT_SIMULATOR.advance(
		state,
		catalog,
		catalog.balance.normal_wave_seconds
	)
	_check(state.completed_waves == 1, "a kill at exactly five seconds must clear wave 1")
	_check(state.stability == catalog.balance.max_stability, "the deadline kill must not leak")
	_check(
		state.phase == NightShiftState.Phase.INTER_WAVE,
		"the deadline kill must enter the inter-wave transition"
	)
	_check_close(
		state.phase_remaining,
		catalog.balance.transition_seconds,
		"early-clear transition duration"
	)

	NIGHT_SHIFT_SIMULATOR.advance(
		state,
		catalog,
		catalog.balance.transition_seconds - 0.001
	)
	_check(
		state.phase == NightShiftState.Phase.INTER_WAVE and state.current_wave == 1,
		"wave 2 must not start before the full 0.4-second transition"
	)
	NIGHT_SHIFT_SIMULATOR.advance(state, catalog, 0.001)
	_check(
		state.phase == NightShiftState.Phase.NORMAL_ACTIVE and state.current_wave == 2,
		"wave 2 must start exactly at the 0.4-second transition boundary"
	)


func _test_leak_cap_and_star_boundaries() -> void:
	var catalog := _load_catalog()
	if catalog == null:
		return
	var state := _create_state(catalog, 1)
	NIGHT_SHIFT_SIMULATOR.advance(state, catalog, catalog.balance.countdown_seconds)
	_check(
		state.phase == NightShiftState.Phase.NORMAL_ACTIVE,
		"leak fixture must enter normal combat"
	)
	if state.phase != NightShiftState.Phase.NORMAL_ACTIVE:
		return

	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF
	state.enemies.clear()
	for enemy_id: StringName in [&"small", &"standard", &"surge"]:
		var archetype := catalog.get_enemy(enemy_id)
		state.enemies.append(NightShiftState.EnemyRuntime.new(
			state.next_enemy_serial,
			enemy_id,
			1.0,
			archetype.leak_damage
		))
		state.next_enemy_serial += 1
	NIGHT_SHIFT_SIMULATOR.advance(
		state,
		catalog,
		catalog.balance.normal_wave_seconds
	)
	_check(
		state.last_wave_leak_damage == 35,
		"small, standard, and surge enemies must sum their 5/10/20 leak damage"
	)
	_check(
		state.stability == catalog.balance.max_stability - 35,
		"uncapped enemy leak damage must reduce stability exactly once"
	)
	_check(state.completed_waves == 1, "a survived leak must still complete its wave")

	var cap_state := _create_state(catalog, 1)
	NIGHT_SHIFT_SIMULATOR.advance(cap_state, catalog, catalog.balance.countdown_seconds)
	for runtime: OperatorCombatState in cap_state.operator_combat_states:
		runtime.attack_remaining = INF
	cap_state.enemies.clear()
	for enemy_id: StringName in [&"surge", &"surge", &"standard"]:
		var archetype := catalog.get_enemy(enemy_id)
		cap_state.enemies.append(NightShiftState.EnemyRuntime.new(
			cap_state.next_enemy_serial,
			enemy_id,
			1.0,
			archetype.leak_damage
		))
		cap_state.next_enemy_serial += 1
	NIGHT_SHIFT_SIMULATOR.advance(
		cap_state,
		catalog,
		catalog.balance.normal_wave_seconds
	)
	_check(
		cap_state.last_wave_leak_damage == catalog.balance.wave_leak_cap,
		"50 raw leak damage must be capped at 40"
	)
	_check(
		cap_state.stability
		== catalog.balance.max_stability - catalog.balance.wave_leak_cap,
		"the capped leak must reduce stability exactly once"
	)

	var boundaries := {
		2: 0,
		3: 1,
		5: 1,
		6: 2,
		9: 2,
		10: 3,
	}
	for raw_completed: Variant in boundaries.keys():
		var completed := int(raw_completed)
		state.completed_waves = completed
		_check(
			state.star_count(catalog.balance.star_thresholds) == int(boundaries[completed]),
			"%d completed waves must award %d stars"
			% [completed, int(boundaries[completed])]
		)


func _test_boss_boundaries_and_terminal_immutability() -> void:
	var exact_fixture := _new_boss_fixture()
	if exact_fixture.is_empty():
		return
	var exact_catalog: ProductV2Catalog = exact_fixture.catalog
	var exact_state: NightShiftState = exact_fixture.state
	_disable_boss_events(exact_state)
	exact_state.boss_hp = 0.001
	exact_state.get_operator_combat_state(&"debugger").attack_remaining = (
		exact_catalog.balance.boss_seconds
	)
	var exact_consumed := NIGHT_SHIFT_SIMULATOR.advance(
		exact_state,
		exact_catalog,
		exact_catalog.balance.boss_seconds
	)
	_check_close(
		exact_consumed,
		exact_catalog.balance.boss_seconds,
		"exact-boundary boss kill consumed time"
	)
	_check(exact_state.is_success(), "an operator kill at exactly 30 seconds must win")
	_check(exact_state.terminal_reason == &"boss_defeated", "success reason must be factual")

	var frozen_signature := _state_signature(exact_state)
	var ignored := NIGHT_SHIFT_SIMULATOR.advance(exact_state, exact_catalog, 60.0)
	_check_close(ignored, 0.0, "terminal state must consume no additional time")
	_check(
		_variants_equal(frozen_signature, _state_signature(exact_state)),
		"terminal state must be immutable under later ticks"
	)

	var timeout_fixture := _new_boss_fixture()
	if timeout_fixture.is_empty():
		return
	var timeout_catalog: ProductV2Catalog = timeout_fixture.catalog
	var timeout_state: NightShiftState = timeout_fixture.state
	_disable_boss_events(timeout_state)
	NIGHT_SHIFT_SIMULATOR.advance(
		timeout_state,
		timeout_catalog,
		timeout_catalog.balance.boss_seconds
	)
	_check(
		timeout_state.phase == NightShiftState.Phase.FAILURE
		and timeout_state.terminal_reason == &"boss_timeout",
		"a living boss at exactly 30 seconds must fail by timeout"
	)

	var down_fixture := _new_boss_fixture()
	if down_fixture.is_empty():
		return
	var down_catalog: ProductV2Catalog = down_fixture.catalog
	var down_state: NightShiftState = down_fixture.state
	for runtime: OperatorCombatState in down_state.operator_combat_states:
		if down_state.unlocked_operator_ids.has(runtime.operator_id):
			runtime.current_hp = 0.0
			runtime.attack_remaining = INF
	var down_consumed := NIGHT_SHIFT_SIMULATOR.advance(down_state, down_catalog, 0.1)
	_check_close(down_consumed, 0.0, "an already-down team must fail without advancing time")
	_check(
		down_state.phase == NightShiftState.Phase.FAILURE
		and down_state.terminal_reason == &"boss_all_down",
		"all unlocked operators down must fail the boss immediately"
	)

	var qa_success_fixture := _new_boss_fixture()
	if qa_success_fixture.is_empty():
		return
	var qa_success_catalog: ProductV2Catalog = qa_success_fixture.catalog
	var qa_success_state: NightShiftState = qa_success_fixture.state
	_disable_boss_events(qa_success_state)
	qa_success_state.get_operator_combat_state(&"debugger").current_hp = 1.0
	qa_success_state.boss_poll_remaining = 0.0
	NIGHT_SHIFT_SIMULATOR.advance(qa_success_state, qa_success_catalog, 0.001)
	_check(
		qa_success_state.qa_rescue_target_id == &"debugger"
		and qa_success_state.qa_rescue_outcome == &"scheduled",
		"the first ally down while QA is active must schedule rescue"
	)
	_disable_boss_events(qa_success_state)
	NIGHT_SHIFT_SIMULATOR.advance(
		qa_success_state,
		qa_success_catalog,
		qa_success_catalog.balance.qa_rescue_delay
	)
	_check(
		qa_success_state.get_operator_combat_state(&"debugger").is_active()
		and qa_success_state.qa_rescue_outcome == &"succeeded",
		"QA must restore the scheduled ally after five seconds"
	)
	for _event_index: int in range(NightShiftState.MAX_RECENT_EVENTS + 1):
		qa_success_state.record_event(&"display_only_attack")
	_check(
		not qa_success_state.operator_down_records.is_empty()
		and qa_success_state.operator_down_records[0]["operator_id"] == &"debugger",
		"operator down evidence must survive display-event eviction"
	)

	var qa_cancel_fixture := _new_boss_fixture()
	if qa_cancel_fixture.is_empty():
		return
	var qa_cancel_catalog: ProductV2Catalog = qa_cancel_fixture.catalog
	var qa_cancel_state: NightShiftState = qa_cancel_fixture.state
	_disable_boss_events(qa_cancel_state)
	qa_cancel_state.get_operator_combat_state(&"debugger").current_hp = 1.0
	qa_cancel_state.boss_poll_remaining = 0.0
	NIGHT_SHIFT_SIMULATOR.advance(qa_cancel_state, qa_cancel_catalog, 0.001)
	for operator_id: StringName in [&"build_engineer", &"sprite_artist"]:
		qa_cancel_state.get_operator_combat_state(operator_id).current_hp = 0.0
	qa_cancel_state.get_operator_combat_state(&"qa_imp").current_hp = 1.0
	qa_cancel_state.boss_poll_remaining = INF
	qa_cancel_state.boss_special_remaining = 0.0
	qa_cancel_state.boss_rollback_remaining = INF
	NIGHT_SHIFT_SIMULATOR.advance(qa_cancel_state, qa_cancel_catalog, 0.001)
	_check(
		qa_cancel_state.qa_rescue_outcome == &"cancelled"
		and qa_cancel_state.qa_rescue_outcome_reason == &"qa_process_down"
		and qa_cancel_state.qa_rescue_target_id == &"",
		"QA process-down must cancel a pending rescue with a factual reason"
	)


func _load_catalog() -> ProductV2Catalog:
	var load_result := PRODUCT_V2_LOADER.load_default()
	_check(load_result.is_valid(), "Product V2 fixture content must load")
	if not load_result.is_valid():
		return null
	return load_result.catalog


func _create_state(catalog: ProductV2Catalog, level: int) -> NightShiftState:
	var levels: Dictionary = {}
	var unlocked: Array[StringName] = []
	for operator_id: StringName in ALL_OPERATOR_IDS:
		levels[operator_id] = level
		unlocked.append(operator_id)
	return NIGHT_SHIFT_SIMULATOR.create_state(catalog, 1, levels, unlocked)


func _new_boss_fixture() -> Dictionary:
	var catalog := _load_catalog()
	if catalog == null:
		return {}
	for archetype: ProductV2Catalog.EnemyArchetype in catalog.enemy_archetypes:
		archetype.base_hp = 0.001
	var shift := catalog.get_shift(1)
	for wave: ProductV2Catalog.WaveProfile in shift.waves:
		wave.entries.resize(1)
		wave.entries[0].count = 1

	var state := _create_state(catalog, 1)
	NIGHT_SHIFT_SIMULATOR.advance(state, catalog, state.phase_remaining)
	for expected_wave: int in range(1, 10):
		_check(
			state.phase == NightShiftState.Phase.NORMAL_ACTIVE
			and state.current_wave == expected_wave,
			"boss fixture must reach normal wave %d" % expected_wave
		)
		if state.phase != NightShiftState.Phase.NORMAL_ACTIVE or state.enemies.is_empty():
			return {}
		for runtime: OperatorCombatState in state.operator_combat_states:
			runtime.attack_remaining = INF
		state.get_operator_combat_state(&"debugger").attack_remaining = 0.0
		state.enemies[0].current_hp = 0.001
		NIGHT_SHIFT_SIMULATOR.advance(state, catalog, 0.00001)
		_check(
			state.completed_waves == expected_wave,
			"boss fixture must complete wave %d" % expected_wave
		)
		if expected_wave < 9:
			_check(
				state.phase == NightShiftState.Phase.INTER_WAVE,
				"normal wave %d must enter a transition" % expected_wave
			)
			if state.phase != NightShiftState.Phase.INTER_WAVE:
				return {}
			NIGHT_SHIFT_SIMULATOR.advance(state, catalog, state.phase_remaining)

	_check(
		state.phase == NightShiftState.Phase.BOSS_WARNING,
		"wave 9 must enter the boss warning"
	)
	if state.phase != NightShiftState.Phase.BOSS_WARNING:
		return {}
	NIGHT_SHIFT_SIMULATOR.advance(state, catalog, state.phase_remaining)
	_check(
		state.phase == NightShiftState.Phase.BOSS_ACTIVE and state.current_wave == 10,
		"boss warning completion must start wave 10"
	)
	if state.phase != NightShiftState.Phase.BOSS_ACTIVE:
		return {}
	return {"catalog": catalog, "state": state}


func _disable_boss_events(state: NightShiftState) -> void:
	state.boss_poll_remaining = INF
	state.boss_special_remaining = INF
	state.boss_rollback_remaining = INF
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF


func _state_signature(state: NightShiftState) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for enemy: NightShiftState.EnemyRuntime in state.enemies:
		enemies.append({
			"serial": enemy.serial,
			"id": enemy.enemy_id,
			"hp": enemy.current_hp,
			"max_hp": enemy.max_hp,
			"leak": enemy.leak_damage,
		})
	var operators: Array[Dictionary] = []
	for runtime: OperatorCombatState in state.operator_combat_states:
		operators.append({
			"id": runtime.operator_id,
			"hp": runtime.current_hp,
			"attack": runtime.attack_remaining,
			"dealt": runtime.damage_dealt,
			"taken": runtime.damage_taken,
			"downs": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		})
	return {
		"phase": state.phase,
		"shift": state.shift_index,
		"wave": state.current_wave,
		"completed": state.completed_waves,
		"stability": state.stability,
		"phase_remaining": state.phase_remaining,
		"total_elapsed": state.total_elapsed,
		"combat_elapsed": state.combat_elapsed,
		"wave_elapsed": state.wave_elapsed,
		"levels": state.operator_levels.duplicate(true),
		"unlocked": state.unlocked_operator_ids.duplicate(),
		"patches": state.equipped_patch_ids.duplicate(),
		"legacy": state.legacy_cache_level,
		"enemies": enemies,
		"next_enemy_serial": state.next_enemy_serial,
		"operators": operators,
		"boss": {
			"hp": state.boss_hp,
			"max_hp": state.boss_max_hp,
			"elapsed": state.boss_elapsed,
			"poll": state.boss_poll_remaining,
			"special": state.boss_special_remaining,
			"rollback": state.boss_rollback_remaining,
			"debuff": state.boss_debuff_applied,
			"recovery_count": state.boss_recovery_count,
			"recovered_hp": state.boss_recovered_health,
		},
		"qa": {
			"consumed": state.qa_rescue_consumed,
			"target": state.qa_rescue_target_id,
			"remaining": state.qa_rescue_remaining,
			"count": state.qa_rescue_count,
		},
		"metrics": {
			"defeated": state.total_enemies_defeated,
			"leaked": state.total_enemies_leaked,
			"leak_damage": state.total_leak_damage,
			"largest_leak": state.largest_wave_leak_damage,
			"last_leak": state.last_wave_leak_damage,
			"downs": state.total_operator_down_count,
			"down_time": state.total_operator_down_time,
		},
		"down_records": state.operator_down_records.duplicate(true),
		"qa_outcome": {
			"status": state.qa_rescue_outcome,
			"target": state.qa_rescue_outcome_target_id,
			"reason": state.qa_rescue_outcome_reason,
			"time": state.qa_rescue_outcome_time,
		},
		"terminal_reason": state.terminal_reason,
		"event_serial": state.event_serial,
		"events": state.recent_events.duplicate(true),
	}


func _variants_equal(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		var left_number := float(left)
		var right_number := float(right)
		if is_inf(left_number) or is_inf(right_number):
			return (
				is_inf(left_number)
				and is_inf(right_number)
				and sign(left_number) == sign(right_number)
			)
		return absf(left_number - right_number) <= EPSILON
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for key: Variant in left_dictionary.keys():
			if (
				not right_dictionary.has(key)
				or not _variants_equal(left_dictionary[key], right_dictionary[key])
			):
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
