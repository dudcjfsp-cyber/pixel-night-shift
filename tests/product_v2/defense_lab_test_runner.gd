extends SceneTree

const DefenseLabSessionScript := preload(
	"res://game/app/product_v2/defense_lab_session.gd"
)
const DefenseLabSaveRepositoryScript := preload(
	"res://game/persistence/product_v2/defense_lab_save_repository.gd"
)
const DEFENSE_LAB_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/defense_lab_view.tscn"
)
const FIXTURE_BASE_DIR := "user://product_v2_defense_lab_tests"
const EPSILON := 0.00001

var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift Product V2 Defense Lab tests")
	print("================================================")
	_run_test(
		"session snapshot and atomic mid-wave restore",
		_test_session_restore_contract
	)
	_run_test(
		"isolated Defense Lab save boundary",
		_test_isolated_save_repository
	)
	await _run_async_test(
		"Defense Lab coordinator and view smoke",
		_test_scene_boundary_smoke
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
	_finish_test(test_name, before)


func _run_async_test(test_name: String, method: Callable) -> void:
	var before := _assertion_failures
	await method.call()
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


func _test_session_restore_contract() -> void:
	var original := DefenseLabSessionScript.new()
	var initial := original.snapshot()
	for key: String in [
		"prototype",
		"phase_name",
		"stability",
		"timers",
		"enemies",
		"operators",
		"boss",
		"terminal",
		"terminal_reason",
	]:
		_check(initial.has(key), "session snapshot must expose '%s'" % key)

	_check(original.tick(2.1), "session must accept a positive mid-wave tick")
	var mid_wave := original.snapshot()
	_check(
		String(mid_wave.get("phase_name", "")) == "normal_active",
		"2.1 seconds must place the default fixture inside a normal wave"
	)
	var exported := original.export_state()
	var restored := DefenseLabSessionScript.new()
	var restore_errors: PackedStringArray = restored.restore_state(exported)
	_check(restore_errors.is_empty(), "valid mid-wave state must restore")
	if not restore_errors.is_empty():
		return
	_check(
		restored.snapshot() == mid_wave,
		"restored session must expose the same mid-wave snapshot"
	)

	_check(original.tick(1.75), "original session must accept the comparison tick")
	_check(restored.tick(1.75), "restored session must accept the comparison tick")
	_check(
		restored.export_state() == original.export_state(),
		"restored and original sessions must produce the same result after the same tick"
	)

	var canonical := restored.export_state()
	var corrupt := canonical.duplicate(true)
	(corrupt["night_shift"] as Dictionary)["stability"] = 999
	var corrupt_errors: PackedStringArray = restored.restore_state(corrupt)
	_check(not corrupt_errors.is_empty(), "invalid stability must be rejected")
	_check(
		restored.export_state() == canonical,
		"rejected restore must not partially mutate the active session"
	)

	var failed := DefenseLabSessionScript.new(null, &"first_two", 2)
	_check(failed.tick(300.0), "hard preset must accept a terminal comparison tick")
	var failed_snapshot := failed.snapshot()
	_check(
		bool(failed_snapshot.get("terminal", false))
		and not bool(failed_snapshot.get("success", true)),
		"hard preset must provide a factual failure fixture"
	)
	if (
		bool(failed_snapshot.get("terminal", false))
		and not bool(failed_snapshot.get("success", true))
	):
		var impossible_failure := failed.export_state()
		(impossible_failure["night_shift"] as Dictionary)["completed_waves"] = 10
		_check(
			not failed.restore_state(impossible_failure).is_empty(),
			"a failed shift cannot restore with ten completed waves"
		)


func _test_isolated_save_repository() -> void:
	var repository := DefenseLabSaveRepositoryScript.new(FIXTURE_BASE_DIR)
	_check(repository.clear_records() == OK, "Defense Lab fixture records must clear")
	_check(
		repository.base_dir() == FIXTURE_BASE_DIR,
		"Defense Lab repository must retain its dedicated base directory"
	)
	var production := SaveRepository.new()
	_check(
		repository.primary_path() != production.primary_path(),
		"Defense Lab primary save must be separate from the production save"
	)

	var first := DefenseLabSessionScript.new()
	first.tick(2.1)
	var first_state := first.export_state()
	_check(
		repository.save(first_state, 2_300_000_000) == OK,
		"Defense Lab state must save"
	)
	var loaded := repository.load()
	_check(loaded.has_session_candidate(), "saved Defense Lab state must load")
	if loaded.has_session_candidate():
		var expected_loaded := DefenseLabSessionScript.new()
		var expected_errors: PackedStringArray = expected_loaded.restore_state(first_state)
		var loaded_session := DefenseLabSessionScript.new()
		var loaded_errors: PackedStringArray = loaded_session.restore_state(
			loaded.session_data
		)
		_check(
			expected_errors.is_empty() and loaded_errors.is_empty(),
			"saved and loaded Defense Lab candidates must restore"
		)
		if expected_errors.is_empty() and loaded_errors.is_empty():
			_check_sessions_equivalent(
				loaded_session,
				expected_loaded,
				"loaded Defense Lab state"
			)
			expected_loaded.tick(0.25)
			loaded_session.tick(0.25)
			_check_sessions_equivalent(
				loaded_session,
				expected_loaded,
				"loaded Defense Lab state after the same tick"
			)

	first.tick(0.5)
	var second_state := first.export_state()
	_check(
		repository.save(second_state, 2_300_000_001) == OK,
		"a second save must succeed and rotate the previous record"
	)
	var backup := repository.load_backup()
	_check(backup.has_session_candidate(), "the previous Defense Lab save must be a backup")
	if backup.has_session_candidate():
		var expected_backup := DefenseLabSessionScript.new()
		var expected_backup_errors: PackedStringArray = expected_backup.restore_state(
			first_state
		)
		var backup_session := DefenseLabSessionScript.new()
		var backup_errors: PackedStringArray = backup_session.restore_state(
			backup.session_data
		)
		_check(
			expected_backup_errors.is_empty() and backup_errors.is_empty(),
			"previous and backup Defense Lab candidates must restore"
		)
		if expected_backup_errors.is_empty() and backup_errors.is_empty():
			_check_sessions_equivalent(
				backup_session,
				expected_backup,
				"Defense Lab backup"
			)
			expected_backup.tick(0.25)
			backup_session.tick(0.25)
			_check_sessions_equivalent(
				backup_session,
				expected_backup,
				"Defense Lab backup after the same tick"
			)

	_check(repository.clear_records() == OK, "Defense Lab fixture cleanup must succeed")
	_check(
		not repository.load().has_session_candidate(),
		"cleared Defense Lab records must not expose a load candidate"
	)


func _test_scene_boundary_smoke() -> void:
	var default_repository := DefenseLabSaveRepositoryScript.new()
	_check(
		default_repository.clear_records() == OK,
		"scene smoke must start without a previous isolated Lab record"
	)
	root.size = Vector2i(360, 640)
	var coordinator := DEFENSE_LAB_SCENE.instantiate()
	_check(coordinator != null, "Defense Lab scene must instantiate")
	if coordinator == null:
		return
	root.add_child(coordinator)
	await _wait_frames(3)

	_check(
		coordinator.has_method("snapshot_for_test"),
		"coordinator must expose a read-only smoke snapshot"
	)
	var first_snapshot: Dictionary = {}
	if coordinator.has_method("snapshot_for_test"):
		first_snapshot = coordinator.call("snapshot_for_test") as Dictionary
	_check(
		not first_snapshot.is_empty(),
		"coordinator must expose its active session through a snapshot"
	)
	await _wait_frames(3)
	var second_snapshot: Dictionary = {}
	if coordinator.has_method("snapshot_for_test"):
		second_snapshot = coordinator.call("snapshot_for_test") as Dictionary
	_check(
		not second_snapshot.is_empty(),
		"coordinator must retain an active session while processing frames"
	)
	if not first_snapshot.is_empty() and not second_snapshot.is_empty():
		_check(
			String(second_snapshot.get("prototype", ""))
			== String(first_snapshot.get("prototype", "")),
			"coordinator snapshots must remain on the same Defense Lab boundary"
		)
		_check(
			int(second_snapshot.get("shift_index", 0))
			== int(first_snapshot.get("shift_index", 0)),
			"coordinator must retain the active shift across frames"
		)
		var first_timers := first_snapshot.get("timers", {}) as Dictionary
		var second_timers := second_snapshot.get("timers", {}) as Dictionary
		_check(
			float(second_timers.get("total_elapsed", -1.0))
			>= float(first_timers.get("total_elapsed", 0.0)),
			"coordinator must maintain or advance its sole session state"
		)

	var view := coordinator.get_node_or_null("DefenseLabView")
	_check(view != null, "Defense Lab scene must contain its view")
	if view != null:
		_check(not view.has_method("tick"), "view must not own the simulation tick")
		_check(
			not _has_property(view, "_session") and not _has_property(view, "session"),
			"view must not own the application session"
		)
		_check(view.has_method("refresh"), "view must accept coordinator snapshots")

	coordinator.queue_free()
	await _wait_frames(2)
	_check(
		default_repository.clear_records() == OK,
		"scene smoke must clean its isolated Lab record"
	)


func _has_property(node: Object, property_name: String) -> bool:
	for raw_property: Variant in node.get_property_list():
		var property := raw_property as Dictionary
		if String(property.get("name", "")) == property_name:
			return true
	return false


func _check_sessions_equivalent(
	actual: RefCounted,
	expected: RefCounted,
	context: String
) -> void:
	_check(
		_variants_close(actual.call("snapshot"), expected.call("snapshot")),
		"%s must preserve the same observable session state" % context
	)


func _variants_close(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		return absf(float(left) - float(right)) <= EPSILON
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for raw_key: Variant in left_dictionary.keys():
			if (
				not right_dictionary.has(raw_key)
				or not _variants_close(
					left_dictionary[raw_key],
					right_dictionary[raw_key]
				)
			):
				return false
		return true
	if left is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index: int in range(left_array.size()):
			if not _variants_close(left_array[index], right_array[index]):
				return false
		return true
	return left == right


func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
