extends SceneTree

const APP_ROOT_SCENE: PackedScene = preload("res://game/app/app_root.tscn")
const PRODUCT_SESSION_SCRIPT: GDScript = preload(
	"res://game/app/product_v2/product_loop_session.gd"
)
const LEGACY_SESSION_SCRIPT: GDScript = preload(
	"res://game/app/game_session.gd"
)
const TEST_ROOT := "user://app_root_integration_tests"


class FakeClock:
	extends RefCounted

	var value: int


	func _init(initial_value: int) -> void:
		value = initial_value


	func now_unix() -> int:
		return value


class FailNextSaveRepository:
	extends SaveRepository

	var fail_next := false


	func _init(base_dir: String) -> void:
		super(base_dir)


	func save(
		session_data: Dictionary,
		saved_at_unix: int,
		last_gameplay_tab: int
	) -> Error:
		if fail_next:
			fail_next = false
			return ERR_CANT_CREATE
		return super.save(session_data, saved_at_unix, last_gameplay_tab)


var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift AppRoot Product V2 integration tests")
	print("======================================================")
	await _run_test(
		"first run saves before entering DAY",
		_test_first_run
	)
	await _run_test(
		"saved DAY NIGHT RESULT resume exactly",
		_test_exact_phase_resume
	)
	await _run_test(
		"commands and terminal transition are atomic",
		_test_atomic_commands_and_terminal
	)
	await _run_test(
		"offline income applies once in DAY and freezes NIGHT",
		_test_offline_contract
	)
	await _run_test(
		"legacy migration persists before activation",
		_test_migration_activation_order
	)
	await _run_test(
		"settings safe area Back recovery and speed boundary",
		_test_shell_contracts
	)
	print("======================================================")
	print(
		"RESULT: %d passed, %d failed, %d assertion failures"
		% [_passed, _failed, _assertion_failures]
	)
	quit(0 if _failed == 0 else 1)


func _run_test(test_name: String, test_method: Callable) -> void:
	var failures_before := _assertion_failures
	await test_method.call()
	if _assertion_failures == failures_before:
		_passed += 1
		print("PASS  %s" % test_name)
	else:
		_failed += 1
		print("FAIL  %s" % test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_assertion_failures += 1
	print("      - %s" % message)


func _test_first_run() -> void:
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene"))
			== "res://game/app/app_root.tscn",
		"AppRoot must remain the project main scene"
	)
	var base_dir := _case_dir("first_run")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var app := await _mount_app(repository, FakeClock.new(2_000_000_000))
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "missing save must open title")
	_check(app.session_instance_id() == 0, "title must not activate a session")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(2)
	_check(app.current_screen_id() == AppRoot.SCREEN_PROLOGUE, "start must open prologue")
	_check(repository.load().status == SaveLoadResult.Status.NOT_FOUND, "prologue must not save")
	_emit_button(app, "SkipButton")
	await _wait_frames(3)
	_check(app.current_screen_id() == AppRoot.SCREEN_DAY_PREP, "prologue must enter DAY")
	_check(
		String(app.session_snapshot().get("prototype", ""))
			== "product_v2_product_loop",
		"production AppRoot must own ProductLoopSession"
	)
	var loaded := repository.load()
	_check(loaded.status == SaveLoadResult.Status.LOADED, "DAY must appear only after first save")
	var restored: Variant = PRODUCT_SESSION_SCRIPT.new()
	_check(
		restored.restore_state(loaded.session_data).is_empty(),
		"first Product V2 save must restore"
	)
	_check(
		String(restored.snapshot().get("phase_name", "")) == "day_prep",
		"first save must contain DAY"
	)
	_check(_host_child_count(app, "ScreenHost") == 1, "AppRoot must own one screen")
	_check(_host_child_count(app, "OverlayHost") == 0, "DAY must not invent an overlay")
	_check_settings_target(app, "DAY")
	await _unmount(app)

	var fail_dir := _case_dir("first_run_failure")
	_clean_case(fail_dir)
	var failing := FailNextSaveRepository.new(fail_dir)
	var failed_app := await _mount_app(failing, FakeClock.new(2_000_000_010))
	_emit_button(failed_app, "PrimaryActionButton")
	await _wait_frames(1)
	failing.fail_next = true
	_emit_button(failed_app, "SkipButton")
	await _wait_frames(3)
	_check(
		failed_app.current_screen_id() == AppRoot.SCREEN_TITLE,
		"failed first save must return to title"
	)
	_check(failed_app.session_instance_id() == 0, "failed first save must discard candidate")
	await _unmount(failed_app)


func _test_exact_phase_resume() -> void:
	var saved_at := 2_000_001_000

	var day_session: Variant = PRODUCT_SESSION_SCRIPT.new()
	day_session.account_day_income(saved_at)
	var day_app := await _mount_saved_session(
		"resume_day", day_session, saved_at, saved_at
	)
	_check(day_app.current_screen_id() == AppRoot.SCREEN_DAY_PREP, "DAY save must resume DAY")
	_check(
		_variants_match_approximately(day_app.session_snapshot(), day_session.snapshot()),
		"DAY snapshot must resume exactly"
	)
	_check_settings_target(day_app, "DAY resume")
	await _unmount(day_app)

	var night_session: Variant = PRODUCT_SESSION_SCRIPT.new()
	night_session.account_day_income(saved_at)
	_check(night_session.start_shift(1), "NIGHT fixture must start")
	_check(night_session.tick(7.25), "NIGHT fixture must advance")
	var night_expected: Dictionary = night_session.snapshot()
	var night_app := await _mount_saved_session(
		"resume_night", night_session, saved_at, saved_at + 20_000
	)
	_check(
		night_app.current_screen_id() == AppRoot.SCREEN_NIGHT_ACTIVE,
		"NIGHT save must resume NIGHT"
	)
	_check(
		_variants_match_approximately(night_app.session_snapshot(), night_expected),
		"NIGHT must not gain offline progress"
	)
	_check_settings_target(night_app, "NIGHT resume")
	await _unmount(night_app)

	var result_session: Variant = PRODUCT_SESSION_SCRIPT.new()
	result_session.account_day_income(saved_at)
	_check(result_session.start_shift(1), "RESULT fixture must start")
	_check(_drive_session_to_result(result_session), "RESULT fixture must terminate")
	var result_validator: Variant = PRODUCT_SESSION_SCRIPT.new()
	var result_fixture_errors: PackedStringArray = result_validator.restore_state(
		result_session.export_state()
	)
	if not result_fixture_errors.is_empty():
		print("      RESULT fixture restore errors: %s" % "; ".join(result_fixture_errors))
	_check(result_fixture_errors.is_empty(), "RESULT fixture export must restore")
	var result_expected: Dictionary = result_session.snapshot()
	var result_app := await _mount_saved_session(
		"resume_result", result_session, saved_at, saved_at + 20_000
	)
	_check(
		result_app.current_screen_id() == AppRoot.SCREEN_SHIFT_RESULT,
		"RESULT save must resume RESULT"
	)
	_check(
		_variants_match_approximately(result_app.session_snapshot(), result_expected),
		"RESULT must remain frozen"
	)
	_check_settings_target(result_app, "RESULT resume")
	await _unmount(result_app)


func _test_atomic_commands_and_terminal() -> void:
	var base_dir := _case_dir("atomic_commands")
	_clean_case(base_dir)
	var repository := FailNextSaveRepository.new(base_dir)
	var app := await _start_new_game(repository, FakeClock.new(2_000_002_000))
	var day_view := _host_child(app, "ScreenHost")
	var before_upgrade: Dictionary = app.session_snapshot()
	app.call("_on_product_upgrade_operator", &"debugger")
	await _wait_frames(2)
	_check(
		_host_child(app, "ScreenHost") == day_view,
		"same-phase command must preserve the active DAY view"
	)
	_check(
		int(app.session_snapshot().get("bits", 0)) < int(before_upgrade.get("bits", 0)),
		"successful upgrade must spend bits"
	)

	var before_failure: Dictionary = app.session_snapshot()
	repository.fail_next = true
	app.call("_on_product_upgrade_operator", &"debugger")
	await _wait_frames(2)
	_check(
		app.session_snapshot() == before_failure,
		"failed command save must roll back the complete session"
	)
	_check(
		_host_child(app, "ScreenHost") == day_view,
		"failed same-phase command must preserve DAY selection state"
	)

	app.call("_on_product_start_shift", 1)
	await _wait_frames(2)
	_check(
		app.current_screen_id() == AppRoot.SCREEN_NIGHT_ACTIVE,
		"phase-changing command must replace DAY with NIGHT"
	)
	app.set("_save_elapsed", -10_000.0)
	repository.fail_next = true
	var terminal_save_failed := false
	for _step: int in range(160):
		app.call("_process", 1.0)
		if app.save_has_error():
			terminal_save_failed = true
			break
	_check(terminal_save_failed, "terminal transition fixture must reach its forced save failure")
	_check(
		app.current_screen_id() == AppRoot.SCREEN_NIGHT_ACTIVE,
		"RESULT must not become visible before terminal save succeeds"
	)
	_check(
		String(app.session_snapshot().get("phase_name", "")) == "night_active",
		"terminal save failure must restore NIGHT state"
	)

	app.call("_on_product_pause")
	for _step: int in range(5):
		app.call("_process", 1.0)
		if app.current_screen_id() == AppRoot.SCREEN_SHIFT_RESULT:
			break
	_check(
		app.current_screen_id() == AppRoot.SCREEN_SHIFT_RESULT,
		"successful retry must enter RESULT"
	)
	var loaded := repository.load()
	var restored: Variant = PRODUCT_SESSION_SCRIPT.new()
	var restore_errors: PackedStringArray = restored.restore_state(loaded.session_data)
	if not restore_errors.is_empty():
		print("      terminal restore errors: %s" % "; ".join(restore_errors))
	_check(restore_errors.is_empty(), "terminal save must restore")
	_check(
		String(restored.snapshot().get("phase_name", "")) == "shift_result",
		"persisted terminal state must already be RESULT"
	)
	await _unmount(app)


func _test_offline_contract() -> void:
	var saved_at := 2_000_003_000
	var base_dir := _case_dir("offline_day")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var source: Variant = PRODUCT_SESSION_SCRIPT.new()
	source.account_day_income(saved_at)
	var bits_before := int(source.snapshot().get("bits", 0))
	_check(repository.save(source.export_state(), saved_at, 0) == OK, "DAY fixture must save")
	var clock := FakeClock.new(saved_at + 2_400)
	var app := await _mount_app(repository, clock)
	await _continue_saved(app)
	var bits_after := int(app.session_snapshot().get("bits", 0))
	_check(bits_after > bits_before, "DAY resume must award elapsed day income")
	var handoff := app.find_child("OfflineHandoffPanel", true, false) as Control
	_check(
		handoff != null and handoff.visible,
		"saved DAY award must be shown only after persistence"
	)
	await _unmount(app)

	var second_app := await _mount_app(repository, clock)
	await _continue_saved(second_app)
	_check(
		int(second_app.session_snapshot().get("bits", 0)) == bits_after,
		"same DAY interval must never apply twice"
	)
	await _unmount(second_app)

	var night_dir := _case_dir("offline_night")
	_clean_case(night_dir)
	var night_repository := SaveRepository.new(night_dir)
	var night_source: Variant = PRODUCT_SESSION_SCRIPT.new()
	night_source.account_day_income(saved_at)
	_check(night_source.start_shift(1), "offline NIGHT fixture must start")
	_check(night_source.tick(4.0), "offline NIGHT fixture must advance")
	var expected: Dictionary = night_source.snapshot()
	_check(
		night_repository.save(night_source.export_state(), saved_at, 0) == OK,
		"offline NIGHT fixture must save"
	)
	var night_app := await _mount_app(
		night_repository,
		FakeClock.new(saved_at + 100_000)
	)
	await _continue_saved(night_app)
	_check(
		_variants_match_approximately(night_app.session_snapshot(), expected),
		"NIGHT must freeze while offline"
	)
	await _unmount(night_app)


func _test_migration_activation_order() -> void:
	var saved_at := 2_000_004_000
	var legacy: Variant = LEGACY_SESSION_SCRIPT.new()
	var legacy_data: Dictionary = legacy.export_state()

	var base_dir := _case_dir("migration_success")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	_write_json(repository.primary_path(), {
		"schema_version": SaveRepository.PREVIOUS_SCHEMA_VERSION,
		"saved_at_unix": saved_at,
		"last_gameplay_tab": 2,
		"session": legacy_data,
	})
	var app := await _mount_app(repository, FakeClock.new(saved_at))
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "migration must finish at title")
	_check(app.session_instance_id() == 0, "migrated candidate must remain pending")
	_check(
		repository.load().schema_version == SaveRepository.CURRENT_SCHEMA_VERSION,
		"legacy save must be rewritten before activation"
	)
	await _continue_saved(app)
	_check(app.current_screen_id() == AppRoot.SCREEN_DAY_PREP, "migrated save must enter DAY")
	await _unmount(app)

	var fail_dir := _case_dir("migration_failure")
	_clean_case(fail_dir)
	var failing := FailNextSaveRepository.new(fail_dir)
	_write_json(failing.primary_path(), {
		"schema_version": SaveRepository.PREVIOUS_SCHEMA_VERSION,
		"saved_at_unix": saved_at,
		"last_gameplay_tab": 0,
		"session": legacy_data,
	})
	failing.fail_next = true
	var failed_app := await _mount_app(failing, FakeClock.new(saved_at))
	_check(
		failed_app.current_screen_id() == AppRoot.SCREEN_SAVE_RECOVERY,
		"migration save failure must route to recovery"
	)
	_check(
		failed_app.session_instance_id() == 0,
		"migration save failure must never activate the candidate"
	)
	_check(
		failing.load().schema_version == SaveRepository.PREVIOUS_SCHEMA_VERSION,
		"failed migration must preserve the legacy primary"
	)
	await _unmount(failed_app)


func _test_shell_contracts() -> void:
	var base_dir := _case_dir("shell_contracts")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var app := await _start_new_game(repository, FakeClock.new(2_000_005_000))
	_emit_button(app, "SettingsButton")
	await _wait_frames(2)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_SETTINGS, "DAY settings must open")
	var manual := app.find_child("ManualButton", true, false) as Button
	_check(manual != null and manual.disabled, "legacy manual must stay disabled in Product V2")
	_check(not app.handle_back_request(), "Back must close the settings overlay first")
	_check(app.current_overlay_id() == AppRoot.OVERLAY_NONE, "Back must close settings")

	app.apply_safe_area(Rect2i(0, 40, 360, 580), Vector2i(360, 640))
	var safe_area := app.find_child("SafeArea", true, false) as MarginContainer
	_check(
		safe_area != null
		and safe_area.get_theme_constant("margin_top") == 40
		and safe_area.get_theme_constant("margin_bottom") == 20,
		"safe-area margins must protect portrait controls"
	)
	var countdown_delta := float(app.call(
		"_product_tick_delta",
		{"playback_speed": 2, "night": {"phase_name": "countdown"}},
		1.0
	))
	var active_delta := float(app.call(
		"_product_tick_delta",
		{"playback_speed": 2, "night": {"phase_name": "normal_active"}},
		1.0
	))
	_check(
		is_equal_approx(countdown_delta, 1.0)
		and is_equal_approx(active_delta, 2.0),
		"2x must affect active combat but not countdown"
	)
	_check(app.handle_back_request(), "Back from a Product V2 surface must request exit")
	_check(repository.load().status == SaveLoadResult.Status.LOADED, "Back must save before exit")
	await _unmount(app)

	var corrupt_dir := _case_dir("shell_recovery")
	_clean_case(corrupt_dir)
	var corrupt_repository := SaveRepository.new(corrupt_dir)
	_write_text(corrupt_repository.primary_path(), "{broken")
	var corrupt_app := await _mount_app(
		corrupt_repository,
		FakeClock.new(2_000_005_100)
	)
	_check(
		corrupt_app.current_screen_id() == AppRoot.SCREEN_SAVE_RECOVERY,
		"corrupt production save must preserve explicit recovery"
	)
	await _unmount(corrupt_app)


func _mount_saved_session(
	case_name: String,
	session: Variant,
	saved_at: int,
	now_unix: int
) -> AppRoot:
	var base_dir := _case_dir(case_name)
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	_check(
		repository.save(session.export_state(), saved_at, 0) == OK,
		"%s fixture must save" % case_name
	)
	var app := await _mount_app(repository, FakeClock.new(now_unix))
	await _continue_saved(app)
	return app


func _start_new_game(repository: SaveRepository, clock: FakeClock) -> AppRoot:
	var app := await _mount_app(repository, clock)
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(1)
	_emit_button(app, "SkipButton")
	await _wait_frames(3)
	_check(app.current_screen_id() == AppRoot.SCREEN_DAY_PREP, "fixture must reach DAY")
	return app


func _mount_app(repository: SaveRepository, clock: FakeClock) -> AppRoot:
	var app := APP_ROOT_SCENE.instantiate() as AppRoot
	_check(app != null, "AppRoot scene must instantiate")
	if app == null:
		return null
	var settings_repository := SettingsRepository.new(repository.base_dir())
	_check(
		app.configure_services(repository, settings_repository, clock),
		"AppRoot test services must configure"
	)
	root.add_child(app)
	app.set_process(false)
	await _wait_frames(4)
	return app


func _continue_saved(app: AppRoot) -> void:
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "saved session must wait at title")
	_check(app.session_instance_id() == 0, "saved session must remain pending")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(3)


func _drive_session_to_result(session: Variant) -> bool:
	for _step: int in range(160):
		if String(session.snapshot().get("phase_name", "")) == "shift_result":
			return true
		if not session.tick(1.0):
			return false
	return String(session.snapshot().get("phase_name", "")) == "shift_result"


func _check_settings_target(app: AppRoot, context: String) -> void:
	var button := app.find_child("SettingsButton", true, false) as Button
	_check(button != null, "%s must expose settings" % context)
	if button == null:
		return
	_check(button.is_visible_in_tree(), "%s settings must be visible" % context)
	_check(
		button.size.x + 0.01 >= 48.0 and button.size.y + 0.01 >= 48.0,
		"%s settings target must be at least 48x48" % context
	)


func _unmount(app: AppRoot) -> void:
	if is_instance_valid(app):
		app.queue_free()
	await _wait_frames(2)


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _emit_button(node: Node, button_name: String) -> void:
	var button := node.find_child(button_name, true, false) as Button
	_check(button != null, "button '%s' must exist" % button_name)
	if button != null:
		button.pressed.emit()


func _host_child(app: AppRoot, host_name: String) -> Node:
	var host := app.find_child(host_name, true, false)
	return host.get_child(0) if host != null and host.get_child_count() > 0 else null


func _host_child_count(app: AppRoot, host_name: String) -> int:
	var host := app.find_child(host_name, true, false)
	return 0 if host == null else host.get_child_count()


func _variants_match_approximately(actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	if (
		typeof(actual) in [TYPE_INT, TYPE_FLOAT]
		and typeof(expected) in [TYPE_INT, TYPE_FLOAT]
	):
		return (
			is_finite(float(actual))
			and is_finite(float(expected))
			and is_equal_approx(float(actual), float(expected))
		)
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size():
			return false
		for key: Variant in actual.keys():
			if (
				not expected.has(key)
				or not _variants_match_approximately(actual[key], expected[key])
			):
				return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return false
		for index: int in actual.size():
			if not _variants_match_approximately(actual[index], expected[index]):
				return false
		return true
	return false


func _case_dir(case_name: String) -> String:
	return TEST_ROOT.path_join(case_name)


func _clean_case(base_dir: String) -> void:
	var absolute := ProjectSettings.globalize_path(base_dir)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute)
	_check(directory_error in [OK, ERR_ALREADY_EXISTS], "test directory must exist")
	SaveRepository.new(base_dir).clear_records()
	var settings_repository := SettingsRepository.new(base_dir)
	for path: String in [
		settings_repository.settings_path(),
		settings_repository.temporary_path(),
		settings_repository.rollback_path(),
	]:
		var settings_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(settings_path):
			DirAccess.remove_absolute(settings_path)


func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture '%s' must open" % path)
	if file != null:
		file.store_string(content)
		file.close()


func _write_json(path: String, data: Dictionary) -> void:
	_write_text(path, JSON.stringify(data))
