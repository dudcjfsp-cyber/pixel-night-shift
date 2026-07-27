extends SceneTree

const ProductLoopSessionScript := preload(
	"res://game/app/product_v2/product_loop_session.gd"
)
const ProductV2LoaderScript := preload(
	"res://game/content/product_v2/product_v2_loader.gd"
)
const DefenseLabSaveRepositoryScript := preload(
	"res://game/persistence/product_v2/defense_lab_save_repository.gd"
)
const PRODUCT_LOOP_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/product_loop.tscn"
)
const LOOP_SAVE_BASE_DIR := "user://product_v2_product_loop_lab"
const LARGE_TICK_SECONDS := 300.0

var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift Product V2 product-loop tests")
	print("================================================")
	_run_test(
		"DAY to NIGHT to RESULT to DAY and invalid commands",
		_test_phase_flow_and_invalid_commands
	)
	_run_test(
		"shift unlocks and version-update availability",
		_test_shift_and_update_unlocks
	)
	_run_test(
		"first-star rewards are cumulative and idempotent",
		_test_first_star_reward_contract
	)
	_run_test(
		"failure report is factual, read-only, and retry is fresh",
		_test_failure_report_and_retry
	)
	await _run_async_test(
		"DAY NIGHT RESULT atomic restore and scene smoke",
		_test_restore_contract_and_scene_smoke
	)
	print("================================================")
	print("RESULT: %d passed, %d failed, %d assertion failures" % [
		_passed,
		_failed,
		_assertion_failures,
	])
	quit(0 if _failed == 0 else 1)


func _run_test(test_name: String, method: Callable) -> void:
	var failures_before := _assertion_failures
	method.call()
	_finish_test(test_name, failures_before)


func _run_async_test(test_name: String, method: Callable) -> void:
	var failures_before := _assertion_failures
	await method.call()
	_finish_test(test_name, failures_before)


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


func _test_phase_flow_and_invalid_commands() -> void:
	var session := ProductLoopSessionScript.new(_easy_catalog(), &"full_team")
	_check(_phase_name(session) == "day_prep", "a new loop must begin in DAY")
	_check(
		not session.continue_to_day(),
		"DAY must reject the RESULT-only continue command"
	)
	_check(session.start_shift(1), "DAY must start the first night")
	_check(_phase_name(session) == "night_active", "start must enter NIGHT")
	_check(
		not session.start_shift(1),
		"NIGHT must reject a second start command"
	)
	_check(
		not session.continue_to_day(),
		"NIGHT must reject the RESULT-only continue command"
	)
	_check(session.tick(LARGE_TICK_SECONDS), "NIGHT must accept elapsed time")
	_check(_phase_name(session) == "shift_result", "terminal NIGHT must enter RESULT")
	_check(
		not session.start_shift(1),
		"RESULT must not bypass DAY with a direct retry"
	)
	_check(session.continue_to_day(), "RESULT must continue to DAY exactly once")
	_check(_phase_name(session) == "day_prep", "continue must return to DAY")
	_check(
		not session.continue_to_day(),
		"DAY must reject repeated RESULT acknowledgement"
	)


func _test_shift_and_update_unlocks() -> void:
	var session := ProductLoopSessionScript.new(_easy_catalog(), &"full_team")
	var initial := session.snapshot()
	_check(
		not _shift_2_unlocked(initial),
		"the second night must begin locked"
	)
	_check(
		not session.start_shift(2),
		"the locked second night must reject start"
	)

	_check(session.start_shift(1), "the first night must start")
	_check(session.tick(LARGE_TICK_SECONDS), "the first night must finish")
	var first_result := _result(session.snapshot())
	_check(int(first_result.get("stars", -1)) == 3, "easy first night must earn 3 stars")
	_check(session.continue_to_day(), "first result must return to DAY")
	var after_first := session.snapshot()
	_check(_shift_2_unlocked(after_first), "first-night 3 stars must unlock night two")
	_check(
		not _version_update_available(after_first),
		"night one must not unlock version update"
	)

	_check(session.start_shift(2), "unlocked second night must start")
	_check(session.tick(LARGE_TICK_SECONDS), "the second night must finish")
	var second_result := _result(session.snapshot())
	_check(int(second_result.get("stars", -1)) == 3, "easy second night must earn 3 stars")
	_check(
		_version_update_available(session.snapshot()),
		"second-night 3 stars must expose version-update availability"
	)


func _test_first_star_reward_contract() -> void:
	var catalog: Variant = _one_star_then_failure_catalog()
	var session := ProductLoopSessionScript.new(catalog, &"full_team")
	_check(session.start_shift(1), "one-star fixture must start")
	_check(session.tick(LARGE_TICK_SECONDS), "one-star fixture must settle")
	var first_snapshot := session.snapshot()
	var first_result := _result(first_snapshot)
	_check(int(first_result.get("stars", -1)) == 1, "fixture must stop at 1 star")
	_check(
		int(first_result.get("first_reward_bits", -1)) == 12,
		"first 1-star result must grant 12 bits"
	)
	var first_bits := int(first_snapshot.get("bits", -1))
	_check(
		first_bits == int(first_result.get("bits_after", -2))
		and first_bits
			== int(first_result.get("bits_before", -3))
				+ int(first_result.get("total_reward", -4)),
		"wallet must receive salary and the first-star reward once"
	)

	var settled_state: Dictionary = session.export_state()
	_check(session.tick(LARGE_TICK_SECONDS), "RESULT tick must be accepted as a no-op")
	_check(
		session.export_state() == settled_state,
		"extra RESULT ticks must not recreate results or rewards"
	)

	_check(session.continue_to_day(), "one-star result must return to DAY")
	_make_catalog_easy(catalog)
	_check(session.start_shift(1), "improved retry must start")
	_check(session.tick(LARGE_TICK_SECONDS), "improved retry must settle")
	var improved_snapshot := session.snapshot()
	var improved_result := _result(improved_snapshot)
	_check(int(improved_result.get("stars", -1)) == 3, "retry must reach 3 stars")
	_check(
		int(improved_result.get("first_reward_bits", -1)) == 48,
		"jumping from 1 to 3 stars must grant skipped rewards 18 + 30"
	)
	_check(
		int(improved_snapshot.get("bits", -1))
			== int(improved_result.get("bits_after", -2))
		and int(improved_result.get("bits_after", -2))
			== int(improved_result.get("bits_before", -3))
				+ int(improved_result.get("total_reward", -4)),
		"improved retry must add one salary and the newly earned star rewards"
	)

	_check(session.continue_to_day(), "improved result must return to DAY")
	var bits_before_repeat := int(improved_snapshot.get("bits", -1))
	_check(session.start_shift(1), "completed night must remain retryable")
	_check(session.tick(LARGE_TICK_SECONDS), "completed retry must settle")
	var repeated_snapshot := session.snapshot()
	var repeated_result := _result(repeated_snapshot)
	_check(
		int(repeated_result.get("first_reward_bits", -1)) == 0,
		"repeating the same best result must not pay a first reward"
	)
	_check(
		int(repeated_snapshot.get("bits", -1))
			== int(repeated_result.get("bits_after", -2))
		and int(repeated_result.get("bits_before", -3)) == bits_before_repeat
		and int(repeated_result.get("bits_after", -2))
			== bits_before_repeat + int(repeated_result.get("total_reward", -4)),
		"repeat completion must add salary without duplicating first rewards"
	)


func _test_failure_report_and_retry() -> void:
	var session := ProductLoopSessionScript.new(_leak_failure_catalog(), &"first_two")
	_check(session.start_shift(1), "failure fixture must start")
	_check(session.tick(LARGE_TICK_SECONDS), "failure fixture must settle")
	var failed := session.snapshot()
	var failed_result := _result(failed)
	_check(not bool(failed_result.get("success", true)), "fixture must fail")
	_check(
		String(failed_result.get("terminal_reason", "")) == "stability_depleted",
		"fixture must preserve the factual stability failure reason"
	)
	var report := _report(failed)
	var report_key := String(report.get("key", ""))
	var report_rows := report.get("rows", []) as Array
	_check(not report_key.is_empty(), "failure must create a stable report key")
	_check(not report_rows.is_empty(), "failure must create factual operator rows")
	_check(not bool(report.get("read", true)), "a new failure report must be unread")
	for raw_row: Variant in report_rows:
		var row := raw_row as Dictionary
		_check(
			row.has("operator_id")
			and row.has("kind")
			and row.has("primary_value")
			and row.has("primary_max")
			and row.has("count")
			and row.has("seconds"),
			"report rows must expose structured facts captured at settlement"
		)
	if not report_rows.is_empty():
		var primary_row := report_rows[0] as Dictionary
		var metrics := failed_result.get("combat_metrics", {}) as Dictionary
		_check(
			String(primary_row.get("kind", "")) == "stability_depleted"
			and int(primary_row.get("primary_value", -1)) == int(
				failed_result.get("stability", -2)
			)
			and int(primary_row.get("primary_max", -1)) == int(
				failed_result.get("max_stability", -2)
			)
			and int(primary_row.get("count", -1)) == int(
				metrics.get("enemies_leaked", -2)
			),
			"failure report values must match the frozen terminal evidence"
		)

	var result_before := failed_result.duplicate(true)
	var bits_before := int(failed.get("bits", -1))
	_check(
		not session.mark_report_read("unknown-report"),
		"an unknown report key must not be acknowledged"
	)
	_check(session.mark_report_read(report_key), "the current report must be acknowledged")
	var read_snapshot := session.snapshot()
	_check(bool(_report(read_snapshot).get("read", false)), "report must become read")
	_check(
		_result(read_snapshot) == result_before
		and int(read_snapshot.get("bits", -1)) == bits_before,
		"reading a report must not mutate its result or rewards"
	)

	_check(session.continue_to_day(), "failed result must return to DAY")
	_check(session.start_shift(1), "the failed night must be retryable")
	var retry := session.snapshot()
	var night := _night(retry)
	_check(
		_phase_name(session) == "night_active"
		and int(night.get("stability", -1)) == int(night.get("max_stability", -2))
		and int(night.get("completed_waves", -1)) == 0
		and not bool(night.get("terminal", true)),
		"retry must create a fresh fully recovered combat state"
	)


func _test_restore_contract_and_scene_smoke() -> void:
	var catalog: Variant = _easy_catalog()

	var day := ProductLoopSessionScript.new(catalog, &"first_two")
	var day_data: Dictionary = day.export_state()
	var restored_day := ProductLoopSessionScript.new(catalog, &"first_two")
	_check(
		restored_day.restore_state(day_data).is_empty(),
		"valid DAY state must restore"
	)
	_check(restored_day.export_state() == day_data, "DAY restore must round-trip")

	_check(day.start_shift(1), "NIGHT restore fixture must start")
	_check(day.tick(2.1), "NIGHT restore fixture must advance mid-wave")
	var night_data: Dictionary = day.export_state()
	var restored_night := ProductLoopSessionScript.new(catalog, &"first_two")
	_check(
		restored_night.restore_state(night_data).is_empty(),
		"valid mid-NIGHT state must restore"
	)
	_check(
		restored_night.export_state() == night_data,
		"NIGHT restore must preserve the exact combat DTO"
	)

	_check(day.tick(LARGE_TICK_SECONDS), "RESULT restore fixture must settle")
	var result_data: Dictionary = day.export_state()
	var restored_result := ProductLoopSessionScript.new(catalog, &"first_two")
	var result_restore_errors: PackedStringArray = restored_result.restore_state(result_data)
	if not result_restore_errors.is_empty():
		print("      result restore errors: %s" % "; ".join(result_restore_errors))
	_check(
		result_restore_errors.is_empty(),
		"valid RESULT state must restore"
	)
	_check(
		restored_result.export_state() == result_data,
		"RESULT restore must preserve the read-only result DTO"
	)

	var canonical: Dictionary = restored_result.export_state()
	var corrupt := canonical.duplicate(true)
	var loop_data := corrupt.get("product_loop", {}) as Dictionary
	loop_data["phase"] = 999
	var errors: PackedStringArray = restored_result.restore_state(corrupt)
	_check(not errors.is_empty(), "unknown product phase must be rejected")
	_check(
		restored_result.export_state() == canonical,
		"rejected Product V2 restore must not partially mutate the session"
	)

	var repository := DefenseLabSaveRepositoryScript.new(LOOP_SAVE_BASE_DIR)
	_check(repository.clear_records() == OK, "scene smoke must clear only loop-lab records")
	root.size = Vector2i(360, 640)
	var coordinator := PRODUCT_LOOP_SCENE.instantiate()
	_check(coordinator != null, "Product V2 loop scene must instantiate")
	if coordinator != null:
		root.add_child(coordinator)
		await _wait_frames(3)
		_check(
			coordinator.has_method("snapshot_for_test")
			and coordinator.has_method("session_instance_id_for_test")
			and coordinator.has_method("active_surface_for_test"),
			"loop coordinator must expose read-only smoke seams"
		)
		if (
			coordinator.has_method("snapshot_for_test")
			and coordinator.has_method("session_instance_id_for_test")
			and coordinator.has_method("active_surface_for_test")
		):
			var scene_snapshot := coordinator.call("snapshot_for_test") as Dictionary
			_check(
				String(scene_snapshot.get("phase_name", "")) == "day_prep",
				"fresh loop scene must show DAY"
			)
			_check(
				int(coordinator.call("session_instance_id_for_test")) != 0,
				"loop coordinator must own exactly one active session"
			)
			_check(
				StringName(coordinator.call("active_surface_for_test")) == &"day_prep",
				"fresh loop scene must select only the DAY surface"
			)
		coordinator.queue_free()
		await _wait_frames(2)
	_check(repository.clear_records() == OK, "scene smoke must clean loop-lab records")


func _easy_catalog() -> Variant:
	var catalog: Variant = _load_catalog()
	_make_catalog_easy(catalog)
	return catalog


func _one_star_then_failure_catalog() -> Variant:
	var catalog: Variant = _load_catalog()
	for archetype: Variant in catalog.enemy_archetypes:
		archetype.base_hp = 1.0
	for shift: Variant in catalog.shifts:
		shift.health_multiplier = 1.0
		shift.boss.max_hp = 1.0
		shift.boss.poll_damage = 1.0
		shift.boss.special_damage = 1.0
	for wave_index: int in range(catalog.shifts[0].waves.size()):
		catalog.shifts[0].waves[wave_index].hp_multiplier = (
			1.0 if wave_index < 3 else 1_000_000.0
		)
	return catalog


func _leak_failure_catalog() -> Variant:
	var catalog: Variant = _load_catalog()
	for archetype: Variant in catalog.enemy_archetypes:
		archetype.base_hp = 1_000_000.0
	return catalog


func _make_catalog_easy(catalog: Variant) -> void:
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


func _load_catalog() -> Variant:
	var load_result: Variant = ProductV2LoaderScript.load_default()
	_check(load_result.is_valid(), "Product V2 fixture content must load")
	assert(load_result.is_valid(), "Product V2 tests require valid default content")
	return load_result.catalog


func _phase_name(session: Variant) -> String:
	return String((session.snapshot() as Dictionary).get("phase_name", ""))


func _result(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("result", {}) as Dictionary


func _report(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("report", {}) as Dictionary


func _night(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("night", {}) as Dictionary


func _shift_2_unlocked(snapshot: Dictionary) -> bool:
	var unlocks := snapshot.get("unlocks", {}) as Dictionary
	return bool(unlocks.get("shift_2_unlocked", false))


func _version_update_available(snapshot: Dictionary) -> bool:
	var unlocks := snapshot.get("unlocks", {}) as Dictionary
	return bool(unlocks.get("version_update_available", false))


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
