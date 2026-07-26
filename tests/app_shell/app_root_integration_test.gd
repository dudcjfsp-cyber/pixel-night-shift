extends SceneTree

const APP_ROOT_SCENE: PackedScene = preload("res://game/app/app_root.tscn")
const PRESENTATION_ASSETS: GDScript = preload("res://game/presentation/presentation_assets.gd")
const TEST_ROOT := "user://app_root_integration_tests"
const STEP_SECONDS := 0.25

class FakeClock extends RefCounted:
	var value: int

	func _init(initial_value: int) -> void:
		value = initial_value

	func now_unix() -> int:
		return value


class FailNextSaveRepository extends SaveRepository:
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


var _passed_tests := 0
var _failed_tests := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift AppRoot integration tests")
	print("==============================================")
	await _run_test("main scene and first-shift boot routing", _test_main_and_first_shift)
	await _run_test("same session and gameplay tab survive navigation", _test_same_session_navigation)
	await _run_test("GameSession durable roundtrip and atomic rejection", _test_session_roundtrip)
	await _run_test("schema 1 migration saves before session activation", _test_schema_1_migration)
	await _run_test("save repository backup and recovery statuses", _test_repository_recovery)
	await _run_test("boot recovery matrix is explicit", _test_boot_recovery_matrix)
	await _run_test("offline progress is capped and applied once", _test_offline_once_and_cap)
	await _run_test("version update rolls back on save failure", _test_version_update_atomicity)
	await _run_test("settings, reset, Back, and safe area contracts", _test_settings_back_and_safe_area)
	print("==============================================")
	print(
		"RESULT: %d passed, %d failed, %d assertion failures"
		% [_passed_tests, _failed_tests, _assertion_failures]
	)
	quit(0 if _failed_tests == 0 else 1)


func _run_test(test_name: String, test_method: Callable) -> void:
	var failures_before := _assertion_failures
	await test_method.call()
	if _assertion_failures == failures_before:
		_passed_tests += 1
		print("PASS  %s" % test_name)
	else:
		_failed_tests += 1
		print("FAIL  %s" % test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_assertion_failures += 1
	print("      - %s" % message)


func _test_main_and_first_shift() -> void:
	_check(PRESENTATION_ASSETS.initialize().is_empty(), "active presentation assets must initialize")
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene"))
			== "res://game/app/app_root.tscn",
		"project main scene must be AppRoot"
	)
	var base_dir := _case_dir("first_shift")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var clock := FakeClock.new(2_000_000_000)
	var app := await _mount_app(repository, clock)
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "missing save must route to title")
	_check(app.current_overlay_id() == AppRoot.OVERLAY_NONE, "title must not invent an overlay")
	_check(app.session_instance_id() == 0, "title must not activate a session")
	var status_label := app.find_child("StatusLabel", true, false) as Label
	_check(status_label != null, "title must expose its localized status text")
	if status_label != null:
		var ui_font := status_label.get_theme_font("font")
		var ui_font_variation := ui_font as FontVariation
		_check(
			ui_font_variation != null
			and ui_font_variation.fallbacks.size() == 1
			and ui_font_variation.fallbacks[0].resource_path
				== "res://game/assets/fonts/Galmuri11-Bold.ttf",
			"default UI font must bundle the Korean fallback"
		)
		_check(
			ui_font != null and ui_font.has_char("한".unicode_at(0)),
			"default UI font must include Korean glyphs"
		)
	_check_touch_targets(app, "title")
	_check(_host_child_count(app, "ScreenHost") == 1, "AppRoot must own one top-level screen")
	_check(_host_child_count(app, "OverlayHost") == 0, "AppRoot overlay host must start empty")

	var first_button := app.find_child("PrimaryActionButton", true, false) as Button
	_check(first_button != null and first_button.text == "게임 시작", "new title must expose game start")
	if first_button != null:
		await _click_button(first_button)
		await _wait_frames(3)
	_check(app.current_screen_id() == AppRoot.SCREEN_PROLOGUE, "game start must open the prologue")
	_check(app.session_instance_id() == 0, "prologue must not create a session before completion")
	_check(repository.load().status == SaveLoadResult.Status.NOT_FOUND, "prologue must not save early")
	_check("야간 인수인계 1 / 5" in _visible_text(app), "prologue must begin at its first story beat")
	var prologue_skip := app.find_child("SkipButton", true, false) as Button
	_check(prologue_skip != null, "prologue must expose a skip action")
	if prologue_skip != null:
		await _click_button(prologue_skip)
		await _wait_frames(3)
	_check(app.current_screen_id() == AppRoot.SCREEN_GAMEPLAY, "first save success must enter gameplay")
	_check(app.current_overlay_id() == AppRoot.OVERLAY_ONBOARDING, "first gameplay must open onboarding")
	_check(app.find_child("OperationsRoomButton", true, false) is Button, "configured gameplay UI must finish building")
	var debugger_ability := app.find_child("OperatorAbility_debugger", true, false) as Label
	_check(
		debugger_ability != null and "공격 우선 대상" in debugger_ability.text,
		"operator cards must expose their boss ability"
	)
	_check_touch_targets(app, "onboarding")
	var saved := repository.load()
	_check(saved.status == SaveLoadResult.Status.LOADED, "first shift must save before gameplay")
	_check(saved.last_gameplay_tab == 0, "first shift must explicitly save gameplay tab 0")
	var onboarding_skip := app.find_child("SkipButton", true, false) as Button
	_check(onboarding_skip != null, "onboarding must expose its skip action")
	if onboarding_skip != null:
		await _click_button(onboarding_skip)
		await _wait_frames(2)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_NONE, "overlay controls must accept real pointer clicks")
	await _unmount(app)

	var fail_dir := _case_dir("first_shift_failure")
	_clean_case(fail_dir)
	var failing := FailNextSaveRepository.new(fail_dir)
	var failed_app := await _mount_app(failing, FakeClock.new(clock.value))
	failing.fail_next = true
	var failed_button := failed_app.find_child("PrimaryActionButton", true, false) as Button
	if failed_button != null:
		failed_button.pressed.emit()
		await _wait_frames(2)
	_emit_button(failed_app, "SkipButton")
	await _wait_frames(2)
	_check(
		failed_app.current_screen_id() == AppRoot.SCREEN_TITLE,
		"failed first save must return the player to title"
	)
	_check(failed_app.session_instance_id() == 0, "failed first save must not retain an active session")
	_check("최초 저장에 실패" in _visible_text(failed_app), "failed first save must explain the error")
	await _unmount(failed_app)


func _test_same_session_navigation() -> void:
	var base_dir := _case_dir("same_session")
	_clean_case(base_dir)
	var app := await _mount_app(SaveRepository.new(base_dir), FakeClock.new(2_000_000_100))
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(2)
	_emit_button(app, "SkipButton")
	await _wait_frames(1)
	_emit_button(app, "SkipButton")
	await _wait_frames(1)
	var identity := app.session_instance_id()
	var gameplay := _host_child(app, "ScreenHost")
	if gameplay != null:
		var before_view_process := app.session_snapshot()
		gameplay.call("_process", 10.0)
		_check(app.session_snapshot() == before_view_process, "MainView must not tick the GameSession")
		app._process(10.0)
		_check(app.session_snapshot() != before_view_process, "AppRoot must own real-time GameSession ticks")
		var patches_tab := gameplay.find_child("GameplayTabButton1", true, false) as Button
		_check(patches_tab != null, "gameplay must expose its patch tab button")
		if patches_tab != null:
			patches_tab.pressed.emit()
		await _wait_frames(1)
	_check(app.last_gameplay_tab() == 1, "gameplay tab selection must be retained by AppRoot")
	if gameplay != null:
		var operations_button := gameplay.find_child("OperationsRoomButton", true, false) as Button
		_check(operations_button != null, "gameplay must expose its operations button")
		if operations_button != null:
			operations_button.pressed.emit()
	await _wait_frames(2)
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "gameplay must return to operations")
	_check(app.session_instance_id() == identity, "operations navigation must keep the same GameSession")
	var before_operations_tick := app.session_snapshot()
	app._process(10.0)
	_check(app.session_snapshot() != before_operations_tick, "operations room must keep automatic simulation running")
	_emit_button(app, "SettingsButton")
	await _wait_frames(1)
	var before_settings_tick := app.session_snapshot()
	app._process(10.0)
	_check(app.session_snapshot() != before_settings_tick, "settings overlay must keep automatic simulation running")
	app.handle_back_request()
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(2)
	_check(app.current_screen_id() == AppRoot.SCREEN_GAMEPLAY, "operations primary action must return to gameplay")
	_check(app.session_instance_id() == identity, "gameplay return must keep the same GameSession")
	_check(app.last_gameplay_tab() == 1, "gameplay return must restore the selected tab")
	_emit_button(app, "SettingsButton")
	await _wait_frames(1)
	var replay_manual := app.find_child("ManualButton", true, false) as Button
	_check(replay_manual != null and not replay_manual.disabled, "manual replay must enable with an active session")
	if replay_manual != null:
		replay_manual.pressed.emit()
	await _wait_frames(1)
	_check("운영 매뉴얼 1 / 3" in _visible_text(app), "manual replay must start at step one")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(1)
	_check("운영 매뉴얼 2 / 3" in _visible_text(app), "onboarding must advance to diagnosis")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(1)
	_check("운영 매뉴얼 3 / 3" in _visible_text(app), "diagnosis action must advance to judgment")
	_check(app.last_gameplay_tab() == 1, "diagnosis onboarding action must focus and save the patch tab")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(1)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_NONE, "third onboarding action must close the manual")
	_check(
		SettingsRepository.new(base_dir).load().settings.onboarding_completed,
		"onboarding completion must persist in the separate settings file"
	)
	await _unmount(app)


func _test_session_roundtrip() -> void:
	var source := GameSession.new()
	for _step: int in range(120):
		source.tick(STEP_SECONDS)
	var exported := source.export_state()
	var restored := GameSession.new()
	var errors := restored.restore_state(exported)
	_check(errors.is_empty(), "exported GameSession state must restore without errors")
	_check(restored.export_state() == exported, "durable roundtrip must preserve the complete state")
	var before := restored.export_state()
	var broken := exported.duplicate(true)
	broken.erase("enemy_health")
	broken["stage"] = 99
	broken["equipped_patch_ids"] = ["unknown_patch", "", ""]
	var rejection := restored.restore_state(broken)
	_check(rejection.size() >= 3, "restore must collect independent validation errors")
	_check(restored.export_state() == before, "failed restore must leave the active session unchanged")
	var non_finite := exported.duplicate(true)
	non_finite["bits"] = NAN
	non_finite["enemy_health"] = INF
	_check(not restored.restore_state(non_finite).is_empty(), "restore must reject NaN and INF")
	_check(restored.export_state() == before, "non-finite rejection must remain atomic")
	var wrong_types := exported.duplicate(true)
	wrong_types["is_maintenance"] = 0
	wrong_types["run_count"] = "1"
	_check(not restored.restore_state(wrong_types).is_empty(), "restore must reject bool and integer type confusion")
	_check(restored.export_state() == before, "wrong-type rejection must remain atomic")
	var unknown_ids := exported.duplicate(true)
	unknown_ids["operator_levels"]["unknown_operator"] = 1
	unknown_ids["discovered_patch_ids"].append("unknown_patch")
	_check(not restored.restore_state(unknown_ids).is_empty(), "restore must reject unknown content IDs")
	_check(restored.export_state() == before, "unknown-ID rejection must remain atomic")
	exported["bits"] = 999999.0
	_check(restored.export_state() == before, "restored state must not alias caller dictionaries")
	var detached := restored.export_state()
	detached["bits"] = 777.0
	_check(restored.export_state() == before, "exported dictionaries must not alias session state")


func _test_schema_1_migration() -> void:
	var saved_at := 2_000_005_000
	var legacy_state := _schema_1_state(GameSession.new().export_state())

	var success_dir := _case_dir("schema_1_migration")
	_clean_case(success_dir)
	var success_repo := SaveRepository.new(success_dir)
	_write_json(success_repo.primary_path(), {
		"schema_version": SaveRepository.LEGACY_SCHEMA_VERSION,
		"saved_at_unix": saved_at,
		"last_gameplay_tab": 2,
		"session": legacy_state,
	})
	var migrated_app := await _mount_app(success_repo, FakeClock.new(saved_at))
	_check(migrated_app.current_screen_id() == AppRoot.SCREEN_TITLE, "migrated save must wait at title")
	_check(migrated_app.session_instance_id() == 0, "migrated candidate must stay inactive before continue")
	_check(
		success_repo.load().schema_version == SaveRepository.CURRENT_SCHEMA_VERSION,
		"successful migration must persist schema 2 before title"
	)
	await _continue_saved_shift(migrated_app)
	_check(migrated_app.session_instance_id() != 0, "valid schema 1 data must activate after migration")
	_check(migrated_app.last_gameplay_tab() == 2, "migration must preserve the selected gameplay tab")
	_check(
		bool(migrated_app.session_snapshot().get("hybrid_combat_enabled", false)),
		"migrated production sessions must enable hybrid boss combat"
	)
	await _unmount(migrated_app)

	var failure_dir := _case_dir("schema_1_migration_failure")
	_clean_case(failure_dir)
	var failure_repo := FailNextSaveRepository.new(failure_dir)
	_write_json(failure_repo.primary_path(), {
		"schema_version": SaveRepository.LEGACY_SCHEMA_VERSION,
		"saved_at_unix": saved_at,
		"last_gameplay_tab": 1,
		"session": legacy_state,
	})
	failure_repo.fail_next = true
	var failed_app := await _mount_app(failure_repo, FakeClock.new(saved_at))
	_check(
		failed_app.current_screen_id() == AppRoot.SCREEN_SAVE_RECOVERY,
		"failed migration save must route to explicit recovery"
	)
	_check(failed_app.session_instance_id() == 0, "failed migration must not activate its candidate")
	_check(
		failure_repo.load().schema_version == SaveRepository.LEGACY_SCHEMA_VERSION,
		"failed migration must leave the legacy primary intact"
	)
	_check("저장 전환 실패" in _visible_text(failed_app), "migration failure must explain the next action")
	await _unmount(failed_app)


func _test_repository_recovery() -> void:
	var base_dir := _case_dir("repository")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var session_a := GameSession.new()
	var session_b := GameSession.new()
	session_b.tick(20.0)
	_check(repository.save(session_a.export_state(), 1000, 0) == OK, "first repository save must succeed")
	_check(repository.save(session_b.export_state(), 2000, 2) == OK, "second repository save must rotate backup")
	var loaded := repository.load()
	_check(loaded.status == SaveLoadResult.Status.LOADED, "valid primary must load")
	_check(loaded.saved_at_unix == 2000 and loaded.last_gameplay_tab == 2, "envelope metadata must roundtrip")
	_write_text(repository.primary_path(), "{broken")
	var recovered := repository.load()
	_check(recovered.status == SaveLoadResult.Status.RECOVERED_BACKUP, "corrupt primary must expose backup candidate")
	_check(recovered.saved_at_unix == 1000, "backup candidate must retain the older timestamp")
	_check(repository.save(session_b.export_state(), 3000, 1) != OK, "normal save must not overwrite a corrupt primary")
	_check(repository.promote_backup() == OK, "explicit backup promotion must succeed")
	_check(repository.load().status == SaveLoadResult.Status.LOADED, "promoted backup must become a valid primary")

	var newer_dir := _case_dir("repository_newer")
	_clean_case(newer_dir)
	var newer_repo := SaveRepository.new(newer_dir)
	_check(newer_repo.save(session_a.export_state(), 1000, 0) == OK, "newer-schema fixture base save must succeed")
	_write_json(newer_repo.primary_path(), {
		"schema_version": 99,
		"saved_at_unix": 1000,
		"last_gameplay_tab": 0,
		"session": session_a.export_state(),
	})
	_check(newer_repo.load().status == SaveLoadResult.Status.NEWER_SCHEMA, "newer schema must not be called corrupt")

	var invalid_dir := _case_dir("repository_invalid_envelopes")
	_clean_case(invalid_dir)
	var invalid_repo := SaveRepository.new(invalid_dir)
	var valid_envelope := {
		"schema_version": 1,
		"saved_at_unix": 1000,
		"last_gameplay_tab": 0,
		"session": session_a.export_state(),
	}
	var invalid_cases: Array[Dictionary] = []
	var missing_tab := valid_envelope.duplicate(true)
	missing_tab.erase("last_gameplay_tab")
	invalid_cases.append(missing_tab)
	var extra_key := valid_envelope.duplicate(true)
	extra_key["unexpected"] = true
	invalid_cases.append(extra_key)
	var bad_tab := valid_envelope.duplicate(true)
	bad_tab["last_gameplay_tab"] = 3
	invalid_cases.append(bad_tab)
	var wrong_time := valid_envelope.duplicate(true)
	wrong_time["saved_at_unix"] = "1000"
	invalid_cases.append(wrong_time)
	for invalid_envelope: Dictionary in invalid_cases:
		invalid_repo.clear_records()
		_write_json(invalid_repo.primary_path(), invalid_envelope)
		_check(invalid_repo.load().status == SaveLoadResult.Status.CORRUPT, "invalid envelope must be explicit corruption")
	invalid_repo.clear_records()
	_write_text(invalid_repo.primary_path(), "broken")
	_write_text(invalid_repo.backup_path(), "also-broken")
	_check(invalid_repo.load().status == SaveLoadResult.Status.CORRUPT, "two corrupt records must not create a new game")
	invalid_repo.clear_records()
	_check(invalid_repo.load_backup().status == SaveLoadResult.Status.NOT_FOUND, "missing backup must remain distinguishable")


func _test_boot_recovery_matrix() -> void:
	var backup_dir := _case_dir("boot_backup")
	_clean_case(backup_dir)
	var backup_repo := SaveRepository.new(backup_dir)
	var session := GameSession.new()
	backup_repo.save(session.export_state(), 1000, 0)
	session.tick(20.0)
	backup_repo.save(session.export_state(), 1100, 1)
	_write_text(backup_repo.primary_path(), "not-json")
	var backup_app := await _mount_app(backup_repo, FakeClock.new(1200))
	_check(backup_app.current_screen_id() == AppRoot.SCREEN_SAVE_RECOVERY, "backup candidate must route to recovery")
	_check("백업은 사용할 수 있습니다" in _visible_text(backup_app), "recovery must explain backup availability")
	_check_touch_targets(backup_app, "save recovery")
	_emit_button(backup_app, "RestoreBackupButton")
	await _wait_frames(2)
	_check(backup_app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "explicit backup action must restore operations")
	await _unmount(backup_app)

	var newer_dir := _case_dir("boot_newer")
	_clean_case(newer_dir)
	var newer_repo := SaveRepository.new(newer_dir)
	newer_repo.save(GameSession.new().export_state(), 1000, 0)
	_write_json(newer_repo.primary_path(), {
		"schema_version": 9,
		"saved_at_unix": 1000,
		"last_gameplay_tab": 0,
		"session": {},
	})
	var newer_app := await _mount_app(newer_repo, FakeClock.new(1000))
	_check(newer_app.current_screen_id() == AppRoot.SCREEN_SAVE_RECOVERY, "newer save must route to recovery")
	_check("게임 업데이트가 필요" in _visible_text(newer_app), "newer save must request a game update")
	_check(newer_app.find_child("RestoreBackupButton", true, false) == null or not (newer_app.find_child("RestoreBackupButton", true, false) as Button).visible, "newer save must not offer silent backup downgrade")
	await _unmount(newer_app)

	var session_invalid_dir := _case_dir("boot_session_invalid")
	_clean_case(session_invalid_dir)
	var session_invalid_repo := SaveRepository.new(session_invalid_dir)
	var backup_session := GameSession.new()
	session_invalid_repo.save(backup_session.export_state(), 1000, 0)
	var newer_session := GameSession.new()
	newer_session.tick(20.0)
	session_invalid_repo.save(newer_session.export_state(), 1100, 1)
	_write_json(session_invalid_repo.primary_path(), {
		"schema_version": 1,
		"saved_at_unix": 1100,
		"last_gameplay_tab": 1,
		"session": {},
	})
	var invalid_session_app := await _mount_app(session_invalid_repo, FakeClock.new(1100))
	_check(invalid_session_app.current_screen_id() == AppRoot.SCREEN_SAVE_RECOVERY, "invalid primary session must route to recovery")
	_check("백업은 사용할 수 있습니다" in _visible_text(invalid_session_app), "valid backup session must be offered explicitly")
	await _unmount(invalid_session_app)

	_write_json(session_invalid_repo.backup_path(), {
		"schema_version": 99,
		"saved_at_unix": 1000,
		"last_gameplay_tab": 0,
		"session": backup_session.export_state(),
	})
	var newer_backup_app := await _mount_app(session_invalid_repo, FakeClock.new(1100))
	_check("게임 업데이트가 필요" in _visible_text(newer_backup_app), "newer backup must not be mislabeled as corruption")
	await _unmount(newer_backup_app)


func _test_offline_once_and_cap() -> void:
	var base_dir := _case_dir("offline_cap")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var seed := GameSession.new()
	var baseline := 2_000_010_000
	var now := baseline + (10 * 60 * 60)
	repository.save(seed.export_state(), baseline, 0)
	var reference := GameSession.new()
	var restore_errors := reference.restore_state(seed.export_state())
	_check(restore_errors.is_empty(), "offline reference session must restore")
	_check(AppPolicy.OFFLINE_CAP_SECONDS == 28_800, "offline policy cap must remain exactly 8 hours")
	for _chunk: int in range(480):
		reference.tick(60.0)

	var app := await _mount_app(repository, FakeClock.new(now))
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "valid save must wait at title")
	_check(app.session_instance_id() == 0, "saved session must remain inactive before continue")
	var saved_before_continue := repository.load().saved_at_unix
	app._process(60.0)
	_check(repository.load().saved_at_unix == saved_before_continue, "title wait must not overwrite offline baseline")
	await _continue_saved_shift(app)
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "valid save must boot to operations")
	_check(app.current_overlay_id() == AppRoot.OVERLAY_OFFLINE_REPORT, "capped visible progress must show report")
	_check("8시간 이후" in _visible_text(app), "capped report must explain the 8-hour limit")
	_check_touch_targets(app, "offline report")
	_check(app.session_snapshot() == reference.snapshot(), "offline simulation must equal deterministic 8-hour reference")
	var first_result := repository.load()
	_check(first_result.saved_at_unix == now, "offline result must be saved at application time")
	await _unmount(app)

	var second := await _mount_app(repository, FakeClock.new(now))
	await _continue_saved_shift(second)
	_check(second.current_overlay_id() == AppRoot.OVERLAY_NONE, "same saved timestamp must not grant or report twice")
	var second_snapshot := second.session_snapshot()
	_check(
		_variants_match_approximately(second_snapshot, reference.snapshot()),
		"second launch at same time must not advance state"
	)
	await _unmount(second)

	var failure_dir := _case_dir("offline_save_failure")
	_clean_case(failure_dir)
	var failing := FailNextSaveRepository.new(failure_dir)
	var failure_baseline := 2_000_015_000
	var failure_clock := FakeClock.new(failure_baseline + 180)
	failing.save(GameSession.new().export_state(), failure_baseline, 0)
	failing.fail_next = true
	var failed_app := await _mount_app(failing, failure_clock)
	await _continue_saved_shift(failed_app)
	var applied_snapshot := failed_app.session_snapshot()
	_check(failed_app.current_overlay_id() == AppRoot.OVERLAY_NONE, "offline report must stay hidden before save succeeds")
	_check(failed_app.save_has_error(), "offline save failure must remain visibly retryable")
	failing.fail_next = true
	failed_app.handle_application_paused()
	failure_clock.value += 180
	failed_app.handle_application_resumed()
	await _wait_frames(2)
	_check(failed_app.current_overlay_id() == AppRoot.OVERLAY_OFFLINE_REPORT, "foreground resume must reveal the saved pending report")
	_check(failed_app.session_snapshot() != applied_snapshot, "resume must add only its new elapsed interval")
	_check("6분 0초" in _visible_text(failed_app), "pending and resumed absence intervals must be merged")
	await _unmount(failed_app)

	var backward_dir := _case_dir("offline_backward_clock")
	_clean_case(backward_dir)
	var backward_repo := SaveRepository.new(backward_dir)
	var future_saved_at := 2_000_100_000
	var backward_seed := GameSession.new()
	backward_repo.save(backward_seed.export_state(), future_saved_at, 0)
	var backward_app := await _mount_app(backward_repo, FakeClock.new(future_saved_at - 1000))
	await _continue_saved_shift(backward_app)
	_check(backward_app.session_snapshot() == backward_seed.snapshot(), "backward clock must apply zero offline progress")
	_check(backward_repo.load().saved_at_unix == future_saved_at, "backward clock must not move the save timestamp backward")
	await _unmount(backward_app)


func _test_version_update_atomicity() -> void:
	var base_dir := _case_dir("version_update")
	_clean_case(base_dir)
	var repository := FailNextSaveRepository.new(base_dir)
	var ready := GameSession.new()
	_check(_drive_to_prestige(ready, 900.0), "version-update fixture must reach prestige")
	var clock := FakeClock.new(2_000_020_000)
	repository.save(ready.export_state(), clock.value, 2)
	var app := await _mount_app(repository, clock)
	await _continue_saved_shift(app)
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(2)
	var gameplay := _host_child(app, "ScreenHost")
	var before := app.session_snapshot()
	var update_button := gameplay.find_child("VersionUpdateButton", true, false) as Button
	_check(update_button != null and not update_button.disabled, "ready gameplay must enable version update")
	if update_button != null:
		update_button.pressed.emit()
	await _wait_frames(1)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_VERSION_UPDATE_CONFIRM, "prestige request must open confirmation")
	_check_touch_targets(app, "version update confirmation")
	_emit_button(app, "CancelButton")
	await _wait_frames(1)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_NONE, "update cancel must return to gameplay")
	_check(app.session_snapshot() == before, "update cancel must not change the session")
	if update_button != null:
		update_button.pressed.emit()
	await _wait_frames(1)
	repository.fail_next = true
	_emit_button(app, "ConfirmButton")
	await _wait_frames(2)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_VERSION_UPDATE_CONFIRM, "failed update save must keep confirmation")
	_check(app.session_snapshot() == before, "failed update save must atomically restore the prior run")
	_check("저장에 실패" in _visible_text(app), "failed update must explain rollback")
	_check(_loaded_snapshot_matches(repository, before), "failed update must keep the prior durable record")
	_emit_button(app, "ConfirmButton")
	await _wait_frames(2)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_RUN_SUMMARY, "successful update save must show summary")
	_check_touch_targets(app, "run summary")
	_check(("STAGE %02d" % int(before["stage"])) in _visible_text(app), "run summary must use the pre-update snapshot")
	var after := app.session_snapshot()
	_check(int(after["run_count"]) == int(before["run_count"]) + 1, "successful update must increment run count once")
	_check(int(after["patch_notes"]) == int(before["patch_notes"]) + 1, "successful update must grant one patch note")
	_check(_saved_update_matches(app, repository), "saved update must match the active durable session")
	await _unmount(app)


func _test_settings_back_and_safe_area() -> void:
	var base_dir := _case_dir("settings_back")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var settings_repository := SettingsRepository.new(base_dir)
	var clock := FakeClock.new(2_000_030_000)
	var app := await _mount_app(repository, clock, settings_repository)
	_emit_button(app, "SettingsButton")
	await _wait_frames(1)
	_check(app.current_overlay_id() == AppRoot.OVERLAY_SETTINGS, "settings entry must open one overlay")
	_check_touch_targets(app, "settings")
	var manual_button := app.find_child("ManualButton", true, false) as Button
	_check(manual_button != null and manual_button.disabled, "manual replay must explain that a session is required")
	var music_slider := app.find_child("MusicVolumePercentSlider", true, false) as HSlider
	_check(music_slider != null, "settings must expose music volume")
	if music_slider != null:
		music_slider.value = 25.0
		await _wait_frames(1)
	var audio := app.find_child("AudioDirector", true, false) as AudioDirector
	_check(audio != null and audio.get_music_volume_percent() == 25, "music volume must apply immediately")
	var saved_settings := settings_repository.load()
	_check(saved_settings.is_loaded() and is_equal_approx(saved_settings.settings.music_volume, 0.25), "music volume must persist separately")
	_emit_button(app, "ReducedMotionButton")
	await _wait_frames(1)
	_check(settings_repository.load().settings.reduced_motion, "reduced motion must persist immediately")
	_check(not app.handle_back_request(), "Back on overlay must be handled in-app")
	_check(app.current_overlay_id() == AppRoot.OVERLAY_NONE, "Back must close the active overlay first")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(2)
	_emit_button(app, "SkipButton")
	await _wait_frames(1)
	_emit_button(app, "SkipButton")
	await _wait_frames(1)
	var lane := app.find_child("BattleLaneView", true, false) as BattleLaneView
	var portrait := app.find_child("OperatorPortrait_debugger", true, false) as TextureRect
	_check(lane != null and portrait != null and portrait.texture is AtlasTexture, "gameplay must expose animated sprite playback")
	if lane != null and portrait != null and portrait.texture is AtlasTexture:
		var before_region := (portrait.texture as AtlasTexture).region
		lane._process(1.0)
		var after_region := (portrait.texture as AtlasTexture).region
		_check(after_region == before_region, "reduced motion must freeze repeated sprite playback")
	_check(not app.handle_back_request(), "Back from gameplay must return to operations")
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "gameplay Back must show operations")
	_check(app.handle_back_request(), "Back from operations must request system exit")
	var before_pause := app.session_snapshot()
	clock.value += 180
	app.handle_application_paused()
	clock.value += 180
	app.handle_application_resumed()
	var after_resume := app.session_snapshot()
	_check(after_resume != before_pause, "resume must apply elapsed background progress")
	app.handle_application_resumed()
	_check(app.session_snapshot() == after_resume, "duplicate resume notification must not apply progress twice")

	app.apply_safe_area(Rect2i(20, 40, 320, 580), Vector2i(360, 640))
	var safe_area := app.find_child("SafeArea", true, false) as MarginContainer
	_check(safe_area != null, "AppRoot must expose a single safe-area owner")
	if safe_area != null:
		_check(safe_area.get_theme_constant("margin_left") == 20, "safe-area left inset must map to logical pixels")
		_check(safe_area.get_theme_constant("margin_right") == 20, "safe-area right inset must map to logical pixels")
		_check(safe_area.get_theme_constant("margin_top") == 40, "safe-area top inset must map to logical pixels")
		_check(safe_area.get_theme_constant("margin_bottom") == 20, "safe-area bottom inset must map to logical pixels")
	app.apply_safe_area(Rect2i(40, 80, 640, 1160), Vector2i(720, 1280))
	if safe_area != null:
		_check(safe_area.get_theme_constant("margin_left") == 20, "scaled safe-area inset must preserve logical size")
	app.apply_safe_area(Rect2i(0, 80, 720, 1480), Vector2i(720, 1600))
	if safe_area != null:
		_check(safe_area.get_theme_constant("margin_top") == 40, "tall safe-area top inset must use the uniform content scale")
		_check(safe_area.get_theme_constant("margin_bottom") == 20, "tall safe-area bottom inset must use the uniform content scale")
	app.apply_safe_area(Rect2i(0, 0, 960, 1280), Vector2i(960, 1280))
	if safe_area != null:
		_check(safe_area.get_theme_constant("margin_left") == 60, "wide screens must center the fixed-width game stage")
		_check(safe_area.get_theme_constant("margin_right") == 60, "wide screens must center the fixed-width game stage")
	_check(app.find_child("ScreenScroll", true, false) != null, "operations room must scroll inside short safe areas")

	_emit_button(app, "SettingsButton")
	await _wait_frames(1)
	_emit_button(app, "ResetRecordsButton")
	await _wait_frames(1)
	_check_touch_targets(app, "reset confirmation")
	_check(repository.load().status == SaveLoadResult.Status.LOADED, "reset prompt must not delete before confirmation")
	_emit_button(app, "ConfirmResetButton")
	await _wait_frames(2)
	_check(repository.load().status == SaveLoadResult.Status.NOT_FOUND, "confirmed reset must clear progress records")
	_check(settings_repository.load().status == SettingsRepository.LoadStatus.LOADED, "progress reset must preserve settings")
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "confirmed reset must return to title")
	await _unmount(app)

	var atomic_dir := _case_dir("settings_atomic_recovery")
	_clean_case(atomic_dir)
	var atomic_repo := SettingsRepository.new(atomic_dir)
	var custom_settings := AppSettings.new()
	custom_settings.music_volume = 0.35
	_check(atomic_repo.save(custom_settings) == OK, "settings fixture must save")
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(atomic_repo.settings_path()),
		ProjectSettings.globalize_path(atomic_repo.rollback_path())
	)
	_check(copy_error == OK, "settings rollback fixture must copy")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(atomic_repo.settings_path()))
	var recovered_settings := atomic_repo.load()
	_check(recovered_settings.is_loaded(), "interrupted settings replace must recover the previous file")
	_check(is_equal_approx(recovered_settings.settings.music_volume, 0.35), "settings recovery must preserve user choices")
	_check(FileAccess.file_exists(atomic_repo.settings_path()), "settings recovery must restore the primary file")
	_check(
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(atomic_repo.settings_path()),
			ProjectSettings.globalize_path(atomic_repo.rollback_path())
		) == OK,
		"settings rollback fixture must be recreated"
	)
	_write_text(atomic_repo.settings_path(), "{\"schema_version\": 1")
	var recovered_corrupt_primary := atomic_repo.load()
	_check(recovered_corrupt_primary.is_loaded(), "valid rollback must recover a partial primary")
	_check(
		is_equal_approx(recovered_corrupt_primary.settings.music_volume, 0.35),
		"partial-primary recovery must preserve rollback settings"
	)
	_check(not FileAccess.file_exists(atomic_repo.rollback_path()), "successful recovery must clean the rollback artifact")
	_check(atomic_repo.load().is_loaded(), "restored settings primary must load again")

	var newer_primary_dir := _case_dir("settings_newer_primary")
	_clean_case(newer_primary_dir)
	var newer_primary_repo := SettingsRepository.new(newer_primary_dir)
	_check(newer_primary_repo.save(custom_settings) == OK, "newer-primary fixture must save")
	_check(
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(newer_primary_repo.settings_path()),
			ProjectSettings.globalize_path(newer_primary_repo.rollback_path())
		) == OK,
		"newer-primary rollback fixture must copy"
	)
	_write_json(newer_primary_repo.settings_path(), {
		"schema_version": SettingsRepository.CURRENT_SCHEMA_VERSION + 1,
		"settings": custom_settings.to_dictionary(),
	})
	_check(
		newer_primary_repo.load().status == SettingsRepository.LoadStatus.NEWER_SCHEMA,
		"newer primary settings must not auto-downgrade to an older rollback"
	)

	var double_corrupt_dir := _case_dir("settings_double_corrupt")
	_clean_case(double_corrupt_dir)
	var double_corrupt_repo := SettingsRepository.new(double_corrupt_dir)
	_check(double_corrupt_repo.save(custom_settings) == OK, "double-corrupt fixture must save")
	_write_text(double_corrupt_repo.settings_path(), "broken-primary")
	_write_text(double_corrupt_repo.rollback_path(), "broken-rollback")
	var double_corrupt := double_corrupt_repo.load()
	var combined_errors := "\n".join(double_corrupt.errors)
	_check(double_corrupt.status == SettingsRepository.LoadStatus.CORRUPT, "two corrupt settings files must stay corrupt")
	_check("primary:" in combined_errors, "corrupt settings must retain the primary error")
	_check("rollback:" in combined_errors, "corrupt settings must retain the rollback error")


func _mount_app(
	repository: SaveRepository,
	clock: FakeClock,
	settings_repository: SettingsRepository = null
) -> AppRoot:
	var app := APP_ROOT_SCENE.instantiate() as AppRoot
	_check(app != null, "AppRoot scene must instantiate")
	if app == null:
		return null
	var settings_repo := settings_repository
	if settings_repo == null:
		settings_repo = SettingsRepository.new(repository.base_dir())
	_check(app.configure_services(repository, settings_repo, clock), "AppRoot test services must configure")
	root.add_child(app)
	app.set_process(false)
	await _wait_frames(4)
	return app


func _continue_saved_shift(app: AppRoot) -> void:
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "saved shift must wait at title")
	_check(app.session_instance_id() == 0, "saved shift must stay inactive before continue")
	var continue_button := app.find_child("PrimaryActionButton", true, false) as Button
	_check(
		continue_button != null and continue_button.text == "이어하기",
		"saved title must expose continue"
	)
	if continue_button != null:
		await _click_button(continue_button)
		await _wait_frames(2)


func _unmount(app: AppRoot) -> void:
	if is_instance_valid(app):
		app.queue_free()
	await _wait_frames(2)


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _click_button(button: Button) -> void:
	var click_position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click_position
	root.push_input(motion, true)
	await process_frame
	for is_pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = click_position
		event.pressed = is_pressed
		root.push_input(event, true)
		await process_frame


func _case_dir(case_name: String) -> String:
	return TEST_ROOT.path_join(case_name)


func _clean_case(base_dir: String) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	_check(directory_error in [OK, ERR_ALREADY_EXISTS], "test case directory must exist")
	var repository := SaveRepository.new(base_dir)
	repository.clear_records()
	var settings_repository := SettingsRepository.new(base_dir)
	for path: String in [
		settings_repository.settings_path(),
		settings_repository.temporary_path(),
		settings_repository.rollback_path(),
	]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "test fixture file '%s' must open" % path)
	if file != null:
		file.store_string(content)
		file.close()


func _write_json(path: String, data: Dictionary) -> void:
	_write_text(path, JSON.stringify(data))


func _schema_1_state(schema_2_state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in GameSession.SCHEMA_1_STATE_KEYS:
		var value: Variant = schema_2_state[key]
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		result[key] = value
	return result


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


func _visible_text(node: Node) -> String:
	var parts := PackedStringArray()
	_collect_visible_text(node, parts)
	return "\n".join(parts)


func _variants_match_approximately(actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return (
			is_finite(float(actual))
			and is_finite(float(expected))
			and is_equal_approx(float(actual), float(expected))
		)
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size():
			return false
		for key: Variant in actual.keys():
			if not expected.has(key) or not _variants_match_approximately(actual[key], expected[key]):
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


func _collect_visible_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		parts.append((node as Label).text)
	if node is Button and (node as Button).is_visible_in_tree():
		parts.append((node as Button).text)
	for child: Node in node.get_children():
		_collect_visible_text(child, parts)


func _check_touch_targets(node: Node, context: String) -> void:
	if node is BaseButton and (node as BaseButton).is_visible_in_tree():
		var button := node as BaseButton
		_check(
			button.size.x + 0.01 >= 48.0 and button.size.y + 0.01 >= 48.0,
			"%s target '%s' must be at least 48x48, got %s" % [context, button.name, button.size]
		)
		if button.name == &"PrimaryActionButton":
			_check(button.size.y + 0.01 >= 52.0, "%s primary target must be at least 52px high" % context)
	if node is HSlider and (node as HSlider).is_visible_in_tree():
		var slider := node as HSlider
		_check(slider.size.y + 0.01 >= 48.0, "%s slider '%s' must be at least 48px high" % [context, slider.name])
	for child: Node in node.get_children():
		_check_touch_targets(child, context)


func _drive_to_prestige(session: GameSession, max_seconds: float) -> bool:
	var operator_ids: Array[StringName] = [
		&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
	]
	var step_count := int(max_seconds / STEP_SECONDS)
	for step: int in range(step_count):
		var snapshot := session.snapshot()
		if bool(snapshot.get("prestige_available", false)):
			return true
		if step % 4 == 0:
			for operator_id: StringName in operator_ids:
				session.upgrade_operator(operator_id)
		session.tick(STEP_SECONDS)
	return bool(session.snapshot().get("prestige_available", false))


func _saved_update_matches(app: AppRoot, repository: SaveRepository) -> bool:
	var loaded_session := GameSession.new()
	var loaded := repository.load()
	var errors := loaded_session.restore_state(loaded.session_data)
	_check(errors.is_empty(), "saved version-update session must restore")
	if not errors.is_empty():
		return false
	var saved_snapshot := loaded_session.snapshot()
	var active_snapshot := app.session_snapshot()
	for key: String in ["stage", "bits", "patch_notes", "run_count", "patch_slots", "unlocked_patch_slots"]:
		if saved_snapshot.get(key) != active_snapshot.get(key):
			return false
	return true


func _loaded_snapshot_matches(repository: SaveRepository, expected: Dictionary) -> bool:
	var load_result := repository.load()
	if not load_result.has_session_candidate():
		return false
	var restored := GameSession.new()
	if not restored.restore_state(load_result.session_data).is_empty():
		return false
	var actual := restored.snapshot()
	for key: String in ["stage", "bits", "patch_notes", "run_count", "patch_slots", "unlocked_patch_slots"]:
		if actual.get(key) != expected.get(key):
			return false
	return true
