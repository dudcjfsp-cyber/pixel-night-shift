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
	print("Pixel Night Shift Product V2 day-meta tests")
	print("=============================================")
	_run_test(
		"salary formula, one-floor multiplier, first reward, and no duplicate",
		_test_salary_contract
	)
	_run_test(
		"DAY offline income boundaries and idempotency",
		_test_offline_income_contract
	)
	_run_test(
		"integer operator upgrades and fresh retry loadout",
		_test_operator_upgrade_and_fresh_retry
	)
	_run_test(
		"complete unlock table, patch slots, direct replacement, and forecast",
		_test_unlocks_and_patch_board
	)
	await _run_async_test(
		"version reset-preserve, atomic DTO restore, and DAY UI smoke",
		_test_version_update_restore_and_ui
	)
	print("=============================================")
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


func _test_salary_contract() -> void:
	var session := ProductLoopSessionScript.new(_easy_catalog(), &"first_two")
	_check(int(session.snapshot().get("bits", -1)) == 30, "new DAY must start with 30 bits")
	_check(_complete_shift(session, 1), "easy first shift must complete")
	var first := session.snapshot()
	var first_result := _result(first)
	_check(int(first_result.get("base_salary", -1)) == 12, "base salary must be 12")
	_check(int(first_result.get("completion_reward", -1)) == 30, "ten waves must pay 30")
	_check(int(first_result.get("boss_reward", -1)) == 6, "boss clear must pay 6")
	_check(
		int(first_result.get("stability_reward", -1)) == 10,
		"full stability must pay the maximum 10 integrity bits"
	)
	_check(
		is_equal_approx(float(first_result.get("bit_multiplier", -1.0)), 1.0),
		"an empty patch board must use a 1.0 bit multiplier"
	)
	_check(
		int(first_result.get("performance_reward", -1)) == 46,
		"unmodified performance salary must be 30 + 6 + 10"
	)
	_check(int(first_result.get("first_reward_bits", -1)) == 60, "first 3 stars must pay 60")
	_check(
		int(first_result.get("total_reward", -1)) == 118
		and int(first.get("bits", -1)) == 148,
		"first perfect result must pay 12 + 46 + 60 exactly once"
	)

	var settled: Dictionary = session.export_state()
	_check(session.tick(LARGE_TICK_SECONDS), "RESULT tick may be a no-op")
	_check(session.export_state() == settled, "extra ticks must not settle salary twice")

	_check(session.continue_to_day(), "first result must return to DAY")
	_check(_complete_shift(session, 2), "easy second shift must complete")
	_check(session.continue_to_day(), "second result must return to DAY")
	_check(
		session.equip_patch(0, &"safe_mode"),
		"the safe-mode patch must equip after its second-shift discovery"
	)
	_check(_complete_shift(session, 2), "safe-mode retry must complete")
	var scaled_result := _result(session.snapshot())
	_check(
		is_equal_approx(float(scaled_result.get("bit_multiplier", -1.0)), 0.75),
		"safe mode must apply its 0.75 bit multiplier"
	)
	_check(
		int(scaled_result.get("performance_reward", -1)) == 34,
		"floor((30 + 6 + 10) × 0.75) must be 34 with one final floor"
	)
	_check(
		int(scaled_result.get("first_reward_bits", -1)) == 0
		and int(scaled_result.get("total_reward", -1)) == 46,
		"retry salary must be base 12 + scaled 34 without first reward"
	)

	var no_abandon := ProductLoopSessionScript.new(_easy_catalog(), &"first_two")
	var before_abandon := int(no_abandon.snapshot().get("bits", -1))
	_check(no_abandon.start_shift(1), "no-abandon fixture must start")
	_check(
		not no_abandon.continue_to_day(),
		"an unfinished night must not be converted into a paid result"
	)
	_check(
		int(no_abandon.snapshot().get("bits", -1)) == before_abandon,
		"an invalid abandon attempt must pay no salary"
	)


func _test_offline_income_contract() -> void:
	var session := ProductLoopSessionScript.new(_easy_catalog(), &"first_two")
	var anchor := 2_000_000_000
	var initialized := session.account_day_income(anchor)
	_check(_offline_bits(initialized) == 0, "first DAY timestamp must initialize without income")

	var short := session.account_day_income(anchor + 1199)
	_check(_offline_bits(short) == 0, "1199 seconds must not pay a bit")
	var first_bit := session.account_day_income(anchor + 1200)
	_check(_offline_bits(first_bit) == 1, "1200 accumulated DAY seconds must pay 1 bit")
	var after_first := int(session.snapshot().get("bits", -1))
	var duplicate := session.account_day_income(anchor + 1200)
	_check(
		_offline_bits(duplicate) == 0
		and int(session.snapshot().get("bits", -1)) == after_first,
		"the same DAY timestamp must be idempotent"
	)

	var capped_at := anchor + 1200 + 13 * 60 * 60
	var capped := session.account_day_income(capped_at)
	_check(_offline_bits(capped) == 36, "a 13-hour absence must cap at 36 bits")

	_check(session.start_shift(1), "offline phase fixture must enter NIGHT")
	var night_bits := int(session.snapshot().get("bits", -1))
	var night_income := session.account_day_income(capped_at + 3600)
	_check(
		_offline_bits(night_income) == 0
		and int(session.snapshot().get("bits", -1)) == night_bits,
		"NIGHT must generate no offline income"
	)
	_check(session.tick(LARGE_TICK_SECONDS), "offline fixture night must settle")
	var result_bits := int(session.snapshot().get("bits", -1))
	var result_income := session.account_day_income(capped_at + 7200)
	_check(
		_offline_bits(result_income) == 0
		and int(session.snapshot().get("bits", -1)) == result_bits,
		"RESULT must generate no offline income"
	)


func _test_operator_upgrade_and_fresh_retry() -> void:
	var session := ProductLoopSessionScript.new(_easy_catalog(), &"first_two")
	var initial := session.snapshot()
	var debugger := _row_by_id(initial.get("operators", []) as Array, "debugger")
	var builder := _row_by_id(initial.get("operators", []) as Array, "build_engineer")
	var sprite := _row_by_id(initial.get("operators", []) as Array, "sprite_artist")
	var qa := _row_by_id(initial.get("operators", []) as Array, "qa_imp")
	_check(
		int(debugger.get("level", -1)) == 1
		and int(debugger.get("upgrade_cost", -1)) == 12
		and typeof(debugger.get("upgrade_cost")) == TYPE_INT,
		"debugger must expose integer level-1 cost 12"
	)
	_check(
		int(builder.get("level", -1)) == 1
		and int(builder.get("upgrade_cost", -1)) == 15
		and typeof(builder.get("upgrade_cost")) == TYPE_INT,
		"build engineer must expose integer level-1 cost 15"
	)
	_check(
		not bool(sprite.get("unlocked", true))
		and not bool(qa.get("unlocked", true)),
		"the other two operators must begin locked"
	)

	_check(session.upgrade_operator(&"debugger"), "debugger upgrade must succeed in DAY")
	_check(session.upgrade_operator(&"build_engineer"), "builder upgrade must succeed in DAY")
	_check(int(session.snapshot().get("bits", -1)) == 3, "12 + 15 upgrades must leave 3 bits")
	_check(
		not session.upgrade_operator(&"sprite_artist"),
		"a locked operator must reject upgrade"
	)

	_check(session.start_shift(1), "upgraded loadout must start NIGHT")
	var active := _night(session.snapshot())
	_check(
		int(_row_by_id(active.get("operators", []) as Array, "debugger").get("level", -1)) == 2
		and int(
			_row_by_id(active.get("operators", []) as Array, "build_engineer").get("level", -1)
		) == 2,
		"NIGHT must use the upgraded DAY levels"
	)
	var bits_during_night := int(session.snapshot().get("bits", -1))
	_check(
		not session.upgrade_operator(&"debugger")
		and int(session.snapshot().get("bits", -1)) == bits_during_night,
		"NIGHT must reject upgrades without spending bits"
	)

	_check(session.tick(LARGE_TICK_SECONDS), "upgraded night must settle")
	_check(session.continue_to_day(), "upgraded result must return to DAY")
	_check(session.start_shift(1), "completed shift must allow a fresh retry")
	var retry := _night(session.snapshot())
	var retry_debugger := _row_by_id(retry.get("operators", []) as Array, "debugger")
	var retry_builder := _row_by_id(retry.get("operators", []) as Array, "build_engineer")
	_check(
		int(retry.get("stability", -1)) == int(retry.get("max_stability", -2))
		and int(retry.get("completed_waves", -1)) == 0
		and not bool(retry.get("terminal", true)),
		"retry must start with fresh server state"
	)
	_check(
		int(retry_debugger.get("level", -1)) == 2
		and int(retry_builder.get("level", -1)) == 2
		and float(retry_debugger.get("hp", -1.0)) == float(
			retry_debugger.get("max_hp", -2.0)
		)
		and float(retry_builder.get("hp", -1.0)) == float(
			retry_builder.get("max_hp", -2.0)
		),
		"retry must preserve levels while fully restoring operator HP"
	)


func _test_unlocks_and_patch_board() -> void:
	var session := ProductLoopSessionScript.new(_easy_catalog(), &"first_two")
	_check(_complete_shift(session, 1), "first unlock fixture must complete")
	_check(session.continue_to_day(), "first unlock result must return to DAY")
	var after_first := session.snapshot()
	_check(
		_unlocked_ids(after_first.get("operators", []) as Array).size() == 4,
		"first-shift milestones must expose all four operators"
	)
	var first_patch_ids := _discovered_ids(after_first.get("patches", []) as Array)
	for patch_id: String in [
		"frame_skip", "unsafe_build", "reward_bypass", "rollback_lock",
	]:
		_check(first_patch_ids.has(patch_id), "first shift must discover %s" % patch_id)
	_check(
		int(after_first.get("unlocked_patch_slots", -1)) == 2,
		"first-shift 3 stars must unlock two patch slots"
	)
	_check(
		bool((after_first.get("unlocks", {}) as Dictionary).get(
			"shift_2_unlocked", false
		)),
		"first-shift 3 stars must unlock the second shift"
	)

	_check(_complete_shift(session, 2), "second unlock fixture must complete")
	_check(session.continue_to_day(), "second unlock result must return to DAY")
	var after_second := session.snapshot()
	var all_patch_ids := _discovered_ids(after_second.get("patches", []) as Array)
	_check(all_patch_ids.size() == 5 and all_patch_ids.has("safe_mode"), "all five patches must be found")
	_check(
		int(after_second.get("unlocked_patch_slots", -1)) == 3,
		"second-shift 2 stars or better must unlock slot three"
	)

	_check(session.equip_patch(0, &"frame_skip"), "an unlocked patch must fill slot one")
	_check(
		session.equip_patch(0, &"unsafe_build"),
		"an occupied slot must support direct replacement"
	)
	var replaced := session.snapshot()
	var slots := replaced.get("patch_slots", []) as Array
	_check(
		slots.size() == 3 and String(slots[0]) == "unsafe_build",
		"direct replacement must leave the new patch in the same slot"
	)

	var preview := session.get_patch_preview(1, &"reward_bypass")
	_check(bool(preview.get("can_equip", false)), "discovered patch preview must be actionable")
	_check(
		preview.has("before")
		and preview.has("after")
		and preview.has("benefit")
		and preview.has("drawback"),
		"patch preview must expose before, after, benefit, and drawback together"
	)
	if preview.has("before") and preview.has("after"):
		var before := preview["before"] as Dictionary
		var after := preview["after"] as Dictionary
		_check(
			before.has("expected_clear_seconds")
			and before.has("expected_leaks")
			and before.has("boss_risk")
			and before.has("repeat_salary")
			and after.has("expected_clear_seconds")
			and after.has("expected_leaks")
			and after.has("boss_risk")
			and after.has("repeat_salary"),
			"patch comparison must cover time, leaks, boss risk, and salary"
		)


func _test_version_update_restore_and_ui() -> void:
	var catalog: Variant = _easy_catalog()
	var session := ProductLoopSessionScript.new(catalog, &"first_two")
	_check(_complete_both_shifts(session), "version-one fixture must clear both shifts")
	_check(session.equip_patch(0, &"frame_skip"), "version fixture must equip a patch")
	_check(session.upgrade_operator(&"debugger"), "version fixture must upgrade an operator")

	var canonical: Dictionary = session.export_state()
	var restored := ProductLoopSessionScript.new(catalog, &"first_two")
	var restore_errors: PackedStringArray = restored.restore_state(canonical)
	if not restore_errors.is_empty():
		print("      restore errors: %s" % "; ".join(restore_errors))
	_check(restore_errors.is_empty(), "valid Stage5 DTO must restore")
	_check(restored.export_state() == canonical, "valid Stage5 DTO must round-trip exactly")
	var corrupt := canonical.duplicate(true)
	var corrupt_loop := corrupt["product_loop"] as Dictionary
	corrupt_loop["bits"] = -1
	var errors: PackedStringArray = restored.restore_state(corrupt)
	_check(not errors.is_empty(), "negative Stage5 bits must be rejected")
	_check(
		restored.export_state() == canonical,
		"rejected Stage5 DTO must not partially mutate the active session"
	)
	var fresh_data: Dictionary = ProductLoopSessionScript.new(
		catalog, &"first_two"
	).export_state()
	var early_unlocks := fresh_data.duplicate(true)
	var early_loop := early_unlocks["product_loop"] as Dictionary
	early_loop["unlocked_patch_slots"] = 3
	early_loop["discovered_patch_ids"] = ["safe_mode"]
	_check(
		not restored.restore_state(early_unlocks).is_empty(),
		"DTO must reject unlocks that current version progress did not earn"
	)
	var impossible_version := fresh_data.duplicate(true)
	var impossible_loop := impossible_version["product_loop"] as Dictionary
	impossible_loop["version"] = 2
	impossible_loop["patch_notes"] = 1
	_check(
		not restored.restore_state(impossible_version).is_empty(),
		"DTO must reject a later version that is missing preserved unlocks"
	)
	_check(
		restored.export_state() == canonical,
		"all rejected meta candidates must leave the active session unchanged"
	)

	_check(session.version_update(2_100_000_000), "eligible DAY must execute version update")
	var version_two := session.snapshot()
	_check(
		int(version_two.get("version", -1)) == 2
		and int(version_two.get("bits", -1)) == 30
		and int(version_two.get("patch_notes", -1)) == 1,
		"version update must advance version, set bits to 30, and grant one patch note"
	)
	_check(
		_all_shift_records_reset(version_two.get("shift_records", []) as Array)
		and _all_slots_empty(version_two.get("patch_slots", []) as Array)
		and _result(version_two).is_empty()
		and not bool(_report(version_two).get("available", true)),
		"version update must clear per-version progress, loadout, result, and report"
	)
	_check(
		_unlocked_ids(version_two.get("operators", []) as Array).size() == 4
		and _discovered_ids(version_two.get("patches", []) as Array).size() == 5
		and int(version_two.get("unlocked_patch_slots", -1)) == 3,
		"version update must preserve discoveries and opened slots"
	)
	for raw_operator: Variant in version_two.get("operators", []) as Array:
		var row := raw_operator as Dictionary
		if bool(row.get("unlocked", false)):
			_check(int(row.get("level", -1)) == 1, "discovered operator levels must reset to 1")

	_check(session.buy_legacy_cache(), "one patch note must buy legacy cache level one")
	_check(
		int(session.snapshot().get("patch_notes", -1)) == 0
		and int(session.snapshot().get("legacy_cache_level", -1)) == 1,
		"legacy purchase must spend one note and grant one persistent level"
	)
	_check(_complete_both_shifts(session), "version-two fixture must clear both shifts")
	_check(session.version_update(2_200_000_000), "second eligible update must execute")
	var version_three := session.snapshot()
	_check(
		int(version_three.get("version", -1)) == 3
		and int(version_three.get("bits", -1)) == 30
		and int(version_three.get("patch_notes", -1)) == 1
		and int(version_three.get("legacy_cache_level", -1)) == 1,
		"later update must preserve cache while granting the next patch note"
	)

	var repository := DefenseLabSaveRepositoryScript.new(LOOP_SAVE_BASE_DIR)
	_check(repository.clear_records() == OK, "DAY UI smoke must clear only loop-lab records")
	root.size = Vector2i(360, 640)
	var coordinator := PRODUCT_LOOP_SCENE.instantiate()
	_check(coordinator != null, "Product loop scene must instantiate")
	if coordinator != null:
		root.add_child(coordinator)
		await _wait_frames(3)
		_check(
			StringName(coordinator.call("active_surface_for_test")) == &"day_prep",
			"fresh Stage5 scene must show DAY"
		)
		var scene_snapshot := coordinator.call("snapshot_for_test") as Dictionary
		_check(
			int(scene_snapshot.get("bits", -1)) == 30
			and (scene_snapshot.get("operators", []) as Array).size() == 4
			and (scene_snapshot.get("patches", []) as Array).size() == 5,
			"DAY UI snapshot must expose the initial wallet, four operators, and five patches"
		)
		var day_view := coordinator.get_node_or_null("DayPrepView")
		_check(day_view != null and day_view.visible, "DAY view must be the visible surface")
		if day_view != null:
			_check(
				day_view.has_method("active_tab_for_test")
				and StringName(day_view.call("active_tab_for_test")) == &"operators",
				"DAY view must begin on the operator-maintenance tab"
			)
			for node_name: String in [
				"OperatorTabButton",
				"PatchTabButton",
				"DutyTabButton",
				"UpgradeButton",
				"VersionUpdateButton",
			]:
				_check(
					day_view.find_child(node_name, true, false) != null,
					"DAY UI must expose %s" % node_name
				)
		coordinator.queue_free()
		await _wait_frames(2)
	_check(repository.clear_records() == OK, "DAY UI smoke must clean loop-lab records")


func _complete_shift(session: Variant, shift_index: int) -> bool:
	if not session.start_shift(shift_index):
		_check(false, "shift %d must start" % shift_index)
		return false
	if not session.tick(LARGE_TICK_SECONDS):
		_check(false, "shift %d must accept its completion tick" % shift_index)
		return false
	var snapshot := session.snapshot() as Dictionary
	_check(
		String(snapshot.get("phase_name", "")) == "shift_result",
		"shift %d must create a result" % shift_index
	)
	return (
		String(snapshot.get("phase_name", "")) == "shift_result"
		and int(_result(snapshot).get("stars", -1)) == 3
	)


func _complete_both_shifts(session: Variant) -> bool:
	if not _complete_shift(session, 1):
		return false
	if not session.continue_to_day():
		return false
	if not _complete_shift(session, 2):
		return false
	return session.continue_to_day()


func _easy_catalog() -> Variant:
	var load_result: Variant = ProductV2LoaderScript.load_default()
	_check(load_result.is_valid(), "Product V2 fixture content must load")
	assert(load_result.is_valid(), "Stage5 tests require valid Product V2 content")
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


func _offline_bits(result: Dictionary) -> int:
	for key: String in ["awarded_bits", "granted_bits", "applied_bits", "bits"]:
		if result.has(key):
			return int(result[key])
	return -1


func _row_by_id(rows: Array, expected_id: String) -> Dictionary:
	for raw_row: Variant in rows:
		var row := raw_row as Dictionary
		if String(row.get("id", "")) == expected_id:
			return row
	return {}


func _unlocked_ids(rows: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_row: Variant in rows:
		var row := raw_row as Dictionary
		if bool(row.get("unlocked", false)):
			result.append(String(row.get("id", "")))
	return result


func _discovered_ids(rows: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_row: Variant in rows:
		var row := raw_row as Dictionary
		if bool(row.get("discovered", false)):
			result.append(String(row.get("id", "")))
	return result


func _all_shift_records_reset(records: Array) -> bool:
	if records.size() != 2:
		return false
	for raw_record: Variant in records:
		var record := raw_record as Dictionary
		if (
			int(record.get("attempts", -1)) != 0
			or int(record.get("highest_completed_waves", -1)) != 0
			or int(record.get("best_stars", -1)) != 0
			or int(record.get("claimed_reward_stars", -1)) != 0
			or bool(record.get("boss_encountered", true))
		):
			return false
	return true


func _all_slots_empty(slots: Array) -> bool:
	if slots.size() != 3:
		return false
	for raw_slot: Variant in slots:
		if raw_slot is Dictionary:
			if not String((raw_slot as Dictionary).get("patch_id", "")).is_empty():
				return false
		elif not String(raw_slot).is_empty():
			return false
	return true


func _result(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("result", {}) as Dictionary


func _report(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("report", {}) as Dictionary


func _night(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("night", {}) as Dictionary


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
