extends SceneTree

const APP_ROOT_SCENE: PackedScene = preload("res://game/app/app_root.tscn")
const TEST_ROOT := "user://combat_v2_integration_tests"
const STEP := 0.25
const OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]


class FakeClock extends RefCounted:
	var value: int

	func _init(initial_value: int) -> void:
		value = initial_value

	func now_unix() -> int:
		return value


class TrackingProductionRepository extends SaveRepository:
	var load_calls := 0
	var save_calls := 0
	var clear_calls := 0

	func _init(base_dir: String) -> void:
		super(base_dir)

	func load() -> SaveLoadResult:
		load_calls += 1
		return super.load()

	func save(data: Dictionary, saved_at_unix: int, last_gameplay_tab: int) -> Error:
		save_calls += 1
		return super.save(data, saved_at_unix, last_gameplay_tab)

	func clear_records() -> Error:
		clear_calls += 1
		return super.clear_records()


class TrackingV2Repository extends CombatV2TestSaveRepository:
	var load_calls := 0
	var save_calls := 0

	func _init(base_dir: String) -> void:
		super(base_dir)

	func load() -> SaveLoadResult:
		load_calls += 1
		return super.load()

	func save(data: Dictionary, saved_at_unix: int, last_gameplay_tab: int) -> Error:
		save_calls += 1
		return super.save(data, saved_at_unix, last_gameplay_tab)


var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift Combat V2 integration tests")
	print("================================================")
	await _run_test("mode routing, one session/tick, and production save isolation", _test_mode_routing)
	await _run_test("V2 test save schema roundtrip and atomic rejection", _test_v2_save_boundary)
	await _run_test("pointer commands and combat-state UI", _test_commands_and_state_ui)
	await _run_test("production hybrid boss HUD and bounded appeals", _test_production_hybrid_ui)
	await _run_test("stage 10 result, operations return, restart, and default isolation", _test_result_and_default)
	print("================================================")
	print("RESULT: %d passed, %d failed, %d assertion failures" % [_passed, _failed, _assertion_failures])
	quit(0 if _failed == 0 else 1)


func _run_test(test_name: String, callable: Callable) -> void:
	var before := _assertion_failures
	await callable.call()
	if _assertion_failures == before:
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


func _test_mode_routing() -> void:
	var production_dir := _case_dir("routing_production")
	var v2_dir := _case_dir("routing_v2")
	_clean_paths(production_dir, v2_dir)
	var production := TrackingProductionRepository.new(production_dir)
	var v2 := TrackingV2Repository.new(v2_dir)
	var app := await _mount(production, v2, true, FakeClock.new(2_100_000_000))
	_check(app.is_combat_v2_test_mode(), "explicit V2 mode must be active")
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "missing V2 save must route to title")
	_check(production.load_calls == 0 and production.save_calls == 0, "V2 boot must not touch production save")
	_check(v2.load_calls == 1, "V2 boot must load exactly its isolated slot")
	_check(app.active_save_base_dir() == v2.base_dir(), "active save path must be the V2 slot")
	await _click_named(app, "PrimaryActionButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "V2 First Shift must enter Operations Room")
	_check("Combat V2 테스트 진입" in _visible_text(app), "Operations Room must identify the V2 entry action")
	var identity := app.session_instance_id()
	await _click_named(app, "PrimaryActionButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_GAMEPLAY, "Operations Room must enter V2 gameplay")
	_check(bool(app.session_snapshot()["combat_v2_test_mode"]), "active session must expose V2 mode")
	var gameplay := _screen_child(app)
	var before_view := app.session_snapshot()
	if gameplay != null:
		gameplay.call("_process", 3.0)
	_check(app.session_snapshot() == before_view, "presentation must not tick the session")
	app._process(3.0)
	_check(app.session_snapshot() != before_view, "AppRoot must own the single active tick path")
	_check(app.session_instance_id() == identity, "navigation and tick must retain one active session")
	_check(production.load_calls == 0 and production.save_calls == 0, "V2 play must leave production save untouched")
	await _unmount(app)


func _test_v2_save_boundary() -> void:
	var v2_dir := _case_dir("save_boundary_v2")
	_clean_paths(_case_dir("save_boundary_production"), v2_dir)
	var repository := CombatV2TestSaveRepository.new(v2_dir)
	var source := CombatV2IntegrationSession.new()
	source.tick(5.0)
	var exported := source.export_state()
	_check(repository.save(exported, 2000, 1) == OK, "V2 save must write its own schema")
	var loaded := repository.load()
	_check(loaded.status == SaveLoadResult.Status.LOADED, "valid V2 slot must load")
	var restored := CombatV2IntegrationSession.new()
	var loaded_errors := restored.restore_state(loaded.session_data)
	if not loaded_errors.is_empty():
		print("      restore errors: %s" % "; ".join(loaded_errors))
	_check(loaded_errors.is_empty(), "loaded V2 state must restore")
	var roundtrip := restored.export_state()
	_check(repository.save(roundtrip, 2001, 1) == OK, "restored canonical V2 state must save again")
	var second_load := repository.load()
	var second_restore := CombatV2IntegrationSession.new()
	_check(second_restore.restore_state(second_load.session_data).is_empty(), "second V2 load must restore")
	_check(second_restore.export_state() == roundtrip, "V2 canonical roundtrip must be stable")
	var legacy_state := exported.duplicate(true)
	legacy_state.erase("appeals")
	_write_json(repository.primary_path(), _outer_envelope({
		"v2_schema_version": 1,
		"state": legacy_state,
	}))
	var migrated := repository.load()
	_check(migrated.status == SaveLoadResult.Status.LOADED, "V2 schema 1 must migrate explicitly")
	_check(migrated.session_data.has("appeals"), "V2 schema 1 migration must add durable appeal state")
	var migrated_session := CombatV2IntegrationSession.new()
	_check(
		migrated_session.restore_state(migrated.session_data).is_empty(),
		"migrated V2 schema 1 state must pass candidate validation"
	)

	var before := restored.export_state()
	var invalid := before.duplicate(true)
	invalid["combat"]["progression"]["bits"] = NAN
	invalid["combat"]["progression"]["patch_notes"] = "invalid"
	var errors := restored.restore_state(invalid)
	_check(errors.size() >= 2, "V2 restore must collect independent invalid fields")
	_check(restored.export_state() == before, "invalid V2 restore must be atomic")

	_write_json(repository.primary_path(), _outer_envelope({
		"v2_schema_version": CombatV2TestSaveRepository.CURRENT_SCHEMA_VERSION + 1,
		"state": exported,
	}))
	_check(repository.load().status == SaveLoadResult.Status.NEWER_SCHEMA, "newer V2 schema must be explicit")
	_write_json(repository.primary_path(), _outer_envelope({
		"v2_schema_version": CombatV2TestSaveRepository.CURRENT_SCHEMA_VERSION,
	}))
	_check(repository.load().status == SaveLoadResult.Status.CORRUPT, "invalid inner V2 schema must not fall back")
	_check("combat_v2" in repository.base_dir(), "V2 slot must be visibly separate from production")


func _test_commands_and_state_ui() -> void:
	var production_dir := _case_dir("commands_production")
	var v2_dir := _case_dir("commands_v2")
	_clean_paths(production_dir, v2_dir)
	var production := TrackingProductionRepository.new(production_dir)
	var repository := CombatV2TestSaveRepository.new(v2_dir)
	var command_session := _fixture_session(&"active")
	_check(repository.save(command_session.export_state(), 3000, 0) == OK, "command fixture must save")
	var app := await _mount(production, repository, true, FakeClock.new(3000))
	await _continue_saved_to_gameplay(app)
	var before_level := _operator_level(app.session_snapshot(), "debugger")
	await _click_named(app, "UpgradeOperator_debugger")
	_check(_operator_level(app.session_snapshot(), "debugger") == before_level + 1, "pointer upgrade must reach V2 simulator")
	await _click_named(app, "DiagnosisActionButton")
	_check(app.last_gameplay_tab() == 1, "diagnosis action must focus patches without a base-DPS action heuristic")
	var remove_patch := app.find_child("RemovePatchButton", true, false) as Button
	_check(
		remove_patch != null and not remove_patch.visible,
		"empty patch slots must not expose the secondary removal action"
	)
	await _click_named(app, "PatchCandidate_frame_skip")
	await _click_named(app, "EquipPatchButton")
	_check(String(app.session_snapshot()["patch_slots"][0]) == "frame_skip", "pointer patch command must reach V2 forecast/session")
	var equip_patch := app.find_child("EquipPatchButton", true, false) as Button
	_check(
		equip_patch != null
			and remove_patch != null
			and remove_patch.visible
			and not remove_patch.disabled
			and remove_patch.flat
			and remove_patch.custom_minimum_size == Vector2(96.0, 48.0)
			and equip_patch.get_parent() == remove_patch.get_parent()
			and remove_patch.size.x < equip_patch.size.x,
		"occupied slots must expose removal as a compact secondary action beside the primary replacement"
	)
	await _click_named(app, "PatchCandidate_unsafe_build")
	_check(
		equip_patch != null and "교체" in equip_patch.text,
		"occupied slots must present direct patch replacement as the primary action"
	)
	_check("현재/예상 다운" in _visible_text(app), "V2 diagnosis must render structured simulator evidence")
	var appeal_card := app.find_child("OperatorAppealCard0", true, false) as Button
	_check(appeal_card != null and appeal_card.visible and appeal_card.size.y >= 44.0, "appeal pointer target must be visible and at least 44px")
	if appeal_card != null and appeal_card.visible:
		appeal_card.pressed.emit()
		await process_frame
		_check(app.last_gameplay_tab() == 0, "appeal review must focus the operator tab without auto-purchase")
	await _unmount(app)

	for fixture_name: StringName in [&"qa", &"emergency", &"maintenance"]:
		var fixture_dir := _case_dir("ui_%s" % fixture_name)
		_clean_paths(_case_dir("ui_prod_%s" % fixture_name), fixture_dir)
		var fixture_repo := CombatV2TestSaveRepository.new(fixture_dir)
		var fixture := _fixture_session(fixture_name)
		fixture_repo.save(fixture.export_state(), 3100, 0)
		var fixture_app := await _mount(
			TrackingProductionRepository.new(_case_dir("ui_prod_%s" % fixture_name)),
			fixture_repo,
			true,
			FakeClock.new(3100)
		)
		await _continue_saved_to_gameplay(fixture_app)
		var text := _visible_text(fixture_app)
		_check("HP" in text and "PROCESS DOWN" in text, "%s UI must show operator HP and process_down" % fixture_name)
		if fixture_name == &"qa":
			_check("QA" in text and "4.0s" in text, "QA pending recovery must be visible")
		if fixture_name == &"emergency":
			var emergency := fixture_app.find_child("EmergencyRedeploy_build_engineer", true, false) as Button
			_check(emergency != null and emergency.visible and not emergency.disabled, "eligible down target must expose emergency selection")
			var bits_before := float(fixture_app.session_snapshot()["bits"])
			await _click_named(fixture_app, "EmergencyRedeploy_build_engineer")
			var after := fixture_app.session_snapshot()
			_check(float(after["bits"]) < bits_before, "emergency pointer command must charge bits once")
			_check(String(_operator_row(after, "build_engineer")["recovery_source"]) == "emergency", "emergency target must show scheduled recovery")
		if fixture_name == &"maintenance":
			_check("재시도 3.5초" in text and "실패" in text, "failure reason and maintenance countdown must be visible")
			var failures := int(fixture_app.session_snapshot()["failure_count"])
			fixture_app._process(3.6)
			var retried := fixture_app.session_snapshot()
			_check(String(retried["mode"]) != "maintenance", "maintenance must deterministically retry")
			_check(int(retried["failure_count"]) == failures, "retry must preserve failure count")
		await _unmount(fixture_app)


func _test_production_hybrid_ui() -> void:
	var production_dir := _case_dir("production_hybrid_ui")
	var v2_dir := _case_dir("production_hybrid_ui_unused_v2")
	_clean_paths(production_dir, v2_dir)
	var production := TrackingProductionRepository.new(production_dir)
	var session := GameSession.new()
	_check(
		_drive_production_to_process_down(session),
		"production fixture must reach a boss process-down state"
	)
	var fixture_snapshot := session.snapshot()
	_check(String(fixture_snapshot["mode"]) == "boss", "production fixture must remain in boss combat")
	_check(
		production.save(session.export_state(), 3500, 0) == OK,
		"production hybrid fixture must save through schema 2"
	)

	var app := await _mount(
		production,
		TrackingV2Repository.new(v2_dir),
		false,
		FakeClock.new(3500)
	)
	await _continue_saved_to_gameplay(app)
	var snapshot := app.session_snapshot()
	_check(
		String(snapshot["mode"]) == "boss" and bool(snapshot["hybrid_combat_enabled"]),
		"restored production gameplay must retain hybrid boss state"
	)

	var down_operator_id := ""
	for raw_operator: Variant in snapshot["operators"] as Array:
		var operator := raw_operator as Dictionary
		if bool(operator["process_down"]):
			down_operator_id = String(operator["id"])
			break
	_check(not down_operator_id.is_empty(), "boss HUD fixture must retain one process-down operator")
	var down_status := app.find_child("OperatorStatus_%s" % down_operator_id, true, false) as Label
	var down_hp := app.find_child("OperatorHP_%s" % down_operator_id, true, false) as ColorRect
	_check(
		down_status != null and down_status.is_visible_in_tree()
		and "PROCESS DOWN" in down_status.text,
		"boss HUD must expose process-down as text, not color alone"
	)
	_check(
		down_hp != null and down_hp.is_visible_in_tree(),
		"boss HUD must expose operator durability only during hybrid boss combat"
	)

	var alert := app.find_child("BossAlertLabel", true, false) as Label
	_check(
		alert != null and alert.is_visible_in_tree() and "제한" in alert.text
		and alert.size.y >= 30.0 and not alert.clip_text,
		"boss HUD must reserve an unclipped line for the persistent time limit"
	)
	var qa_rescue := snapshot["qa_rescue"] as Dictionary
	if bool(qa_rescue["pending"]):
		_check(
			"\n" in alert.text and "QA" in alert.text,
			"pending automatic QA rescue must use its own boss HUD line"
		)

	var appeals := snapshot["appeals"] as Array
	_check(
		not appeals.is_empty() and appeals.size() <= 2,
		"production boss diagnosis must expose one or two factual appeals"
	)
	var visible_appeals: Array[Button] = []
	for index: int in range(2):
		var card := app.find_child("OperatorAppealCard%d" % index, true, false) as Button
		if card != null and card.is_visible_in_tree():
			visible_appeals.append(card)
	_check(
		visible_appeals.size() == appeals.size(),
		"operator tab must render exactly the bounded production appeal set"
	)
	for card: Button in visible_appeals:
		_check(card.size.y >= 44.0, "each production appeal must keep a 44px pointer target")

	var lane := app.find_child("BattleLaneView", true, false) as Control
	var appeal_panel := app.find_child("OperatorAppealPanel", true, false) as Control
	_check(
		lane != null and appeal_panel != null
		and not lane.get_global_rect().intersects(appeal_panel.get_global_rect()),
		"appeals must stay in the operator scroll area without covering the battle lane"
	)
	if not visible_appeals.is_empty():
		var gameplay := _screen_child(app) as MainView
		_check(gameplay != null and gameplay.set_active_tab(1), "production gameplay must expose patch navigation")
		_check(gameplay.get_active_tab() == 1, "appeal navigation test must start on the patch tab")
		var before_selection := app.session_snapshot()
		visible_appeals[0].pressed.emit()
		await process_frame
		_check(gameplay.get_active_tab() == 0, "appeal review must return focus to the operator tab")
		_check(
			app.session_snapshot() == before_selection,
			"appeal review must not issue a manual combat or upgrade command"
		)
	await _unmount(app)


func _test_result_and_default() -> void:
	var result_dir := _case_dir("result_v2")
	_clean_paths(_case_dir("result_production"), result_dir)
	var result_repo := CombatV2TestSaveRepository.new(result_dir)
	var complete := CombatV2IntegrationSession.new()
	_check(_drive_to_completion(complete), "balanced V2 fixture must complete stage 10")
	_check(result_repo.save(complete.export_state(), 4000, 1) == OK, "completed V2 fixture must save")
	var app := await _mount(
		TrackingProductionRepository.new(_case_dir("result_production")),
		result_repo,
		true,
		FakeClock.new(4000)
	)
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "completed test restore must wait at title")
	await _click_named(app, "PrimaryActionButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "continue must enter Operations Room")
	await _click_named(app, "PrimaryActionButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_COMBAT_V2_RESULT, "completed stage 10 must route to read-only result")
	var result_text := _visible_text(app)
	for required: String in ["COMBAT V2 테스트 결과", "실패", "복구", "비트", "현장 의견 활용", "최종 레벨", "주요 진단 이력", "패치 이력"]:
		_check(required in result_text, "result must show '%s'" % required)
	await _click_named(app, "OperationsRoomButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "result must return to Operations Room")
	await _click_named(app, "PrimaryActionButton")
	await _click_named(app, "RestartV2Button")
	_check(app.current_screen_id() == AppRoot.SCREEN_GAMEPLAY, "result restart must begin a new V2 test")
	_check(int(app.session_snapshot()["stage"]) == 1, "restart must reset only the V2 test progression")
	await _unmount(app)

	var production_dir := _case_dir("default_production")
	var unused_v2_dir := _case_dir("default_unused_v2")
	_clean_paths(production_dir, unused_v2_dir)
	var production := TrackingProductionRepository.new(production_dir)
	var unused_v2 := TrackingV2Repository.new(unused_v2_dir)
	var default_app := await _mount(production, unused_v2, false, FakeClock.new(5000))
	_check(not default_app.is_combat_v2_test_mode(), "default launch must keep V2 disabled")
	_check(production.load_calls == 1 and unused_v2.load_calls == 0, "default launch must use only production save")
	await _click_named(default_app, "PrimaryActionButton")
	_check(default_app.current_screen_id() == AppRoot.SCREEN_PROLOGUE, "default game start must open prologue")
	await _click_named(default_app, "SkipButton")
	var production_snapshot := default_app.session_snapshot()
	_check(not bool(production_snapshot["combat_v2_test_mode"]), "default prologue completion must create production GameSession")
	_check(bool(production_snapshot["hybrid_combat_enabled"]), "default production session must enable hybrid boss combat")
	_check(
		production_snapshot.has("appeals") and int(production_snapshot["appeal_limit"]) == 2,
		"default production snapshot must expose the bounded hybrid appeal contract"
	)
	var content := ContentLoader.load_default()
	_check(
		content.is_valid() and ProgressionRules.is_boss_stage(20)
		and content.catalog.get_patch(&"safe_mode").unlock_stage == 15,
		"default production content must retain its stage-20 progression contract"
	)
	await _unmount(default_app)


func _fixture_session(kind: StringName) -> CombatV2IntegrationSession:
	var prototype := CombatV2PrototypeSession.new()
	_drive_session(prototype, 1800.0, 6)
	var state := prototype.debug_state_copy()
	var loaded := CombatV2Loader.load_default()
	assert(loaded.is_valid(), "fixture requires valid Combat V2 content")
	var catalog: CombatV2Catalog = loaded.catalog
	state.progression.bits = maxf(state.progression.bits, 1000.0)
	state.progression.equipped_patch_ids = [&"", &"", &""]
	state.progression.is_maintenance = false
	state.maintenance_remaining = 0.0
	state.last_failure_reason = &""
	state.qa_rescue_consumed = false
	state.qa_recovery_target_id = &""
	state.emergency_redeploy_used = false
	state.emergency_redeploy_target_id = &""
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		runtime.recovery_source = &""
		runtime.recovery_remaining = 0.0
		if state.progression.is_operator_unlocked(runtime.operator_id):
			runtime.current_hp = CombatV2Simulator.operator_max_hp(state, catalog, runtime.operator_id)
			runtime.attack_remaining = 0.5
	if kind in [&"qa", &"emergency"]:
		var target := state.get_operator(&"build_engineer")
		target.current_hp = 0.0
		target.attack_remaining = INF
		if kind == &"qa":
			target.recovery_source = &"qa"
			target.recovery_remaining = 4.0
			state.qa_rescue_consumed = true
			state.qa_recovery_target_id = &"build_engineer"
		else:
			state.qa_rescue_consumed = true
	elif kind == &"maintenance":
		for runtime: CombatV2State.OperatorRuntime in state.operators:
			if state.progression.is_operator_unlocked(runtime.operator_id):
				runtime.current_hp = 0.0
				runtime.attack_remaining = INF
		state.progression.is_maintenance = true
		state.maintenance_remaining = 3.5
		state.normal_failure_count += 1
		state.last_failure_reason = &"normal_all_down"
		state.enemy_locked_target_id = &""
	var restore_errors := prototype.restore_state(CombatV2StateDto.export_state(state))
	assert(restore_errors.is_empty(), "fixture state must validate: %s" % "; ".join(restore_errors))
	return CombatV2IntegrationSession.new(prototype)


func _drive_session(session: Variant, max_seconds: float, target_stage: int) -> void:
	var next_decision := 0.0
	var elapsed := 0.0
	while elapsed < max_seconds:
		var snapshot: Dictionary = session.snapshot()
		if int(snapshot["stage"]) >= target_stage or bool(snapshot["prestige_available"]):
			return
		if elapsed + 0.000001 >= next_decision:
			_apply_balanced_decision(session, snapshot)
			next_decision += 1.0
		session.tick(STEP)
		elapsed += STEP
	assert(false, "fixture failed to reach stage %d" % target_stage)


func _drive_to_completion(session: CombatV2IntegrationSession) -> bool:
	var next_decision := 0.0
	for step: int in range(int(1800.0 / STEP)):
		var snapshot := session.snapshot()
		if session.is_complete():
			return true
		var elapsed := step * STEP
		if elapsed + 0.000001 >= next_decision:
			_apply_balanced_decision(session, snapshot)
			next_decision += 1.0
		session.tick(STEP)
	return session.is_complete()


func _drive_production_to_process_down(session: GameSession) -> bool:
	for _step: int in range(int(1300.0 / STEP)):
		var snapshot := session.snapshot()
		if String(snapshot["mode"]) == "boss":
			for raw_operator: Variant in snapshot["operators"] as Array:
				if bool((raw_operator as Dictionary)["process_down"]):
					return true
		if int(snapshot["stage"]) > 10:
			return false
		session.tick(STEP)
	return false


func _apply_balanced_decision(session: Variant, snapshot: Dictionary) -> void:
	if int(snapshot["unlocked_patch_slots"]) > 0:
		var desired := &"rollback_lock" if int(snapshot["stage"]) == 10 else &"frame_skip"
		var unlocked := false
		for raw_patch: Variant in snapshot["patches"] as Array:
			var patch := raw_patch as Dictionary
			if StringName(String(patch["id"])) == desired:
				unlocked = bool(patch["unlocked"])
				break
		var slots := snapshot["patch_slots"] as Array
		if unlocked and StringName(String(slots[0])) != desired:
			var preview: Dictionary = session.get_patch_preview(0, desired)
			if bool(preview["can_equip"]):
				session.equip_patch(0, desired)
				snapshot = session.snapshot()
	var chosen := &""
	var lowest_level := 2147483647
	var bits := float(snapshot["bits"])
	for raw_operator: Variant in snapshot["operators"] as Array:
		var operator := raw_operator as Dictionary
		if not bool(operator["unlocked"]) or float(operator["upgrade_cost"]) > bits + 0.000001:
			continue
		var level := int(operator["level"])
		if level < lowest_level:
			chosen = StringName(String(operator["id"]))
			lowest_level = level
	if chosen != &"":
		session.upgrade_operator(chosen)


func _mount(
	production: SaveRepository,
	v2: CombatV2TestSaveRepository,
	v2_mode: bool,
	clock: FakeClock
) -> AppRoot:
	var app := APP_ROOT_SCENE.instantiate() as AppRoot
	_check(app != null, "AppRoot must instantiate")
	if app == null:
		return null
	var settings := SettingsRepository.new(_case_dir("settings_%d" % Time.get_ticks_usec()))
	_check(app.configure_services(production, settings, clock, v2, v2_mode), "AppRoot services must configure")
	root.add_child(app)
	app.set_process(false)
	await _wait_frames(5)
	return app


func _unmount(app: AppRoot) -> void:
	if is_instance_valid(app):
		app.queue_free()
	await _wait_frames(3)


func _continue_saved_to_gameplay(app: AppRoot) -> void:
	_check(app.current_screen_id() == AppRoot.SCREEN_TITLE, "saved fixture must wait at title")
	_check(app.session_instance_id() == 0, "saved fixture must remain inactive before continue")
	await _click_named(app, "PrimaryActionButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_OPERATIONS_ROOM, "continue must activate Operations Room")
	await _click_named(app, "PrimaryActionButton")
	_check(app.current_screen_id() == AppRoot.SCREEN_GAMEPLAY, "Operations Room must enter gameplay")


func _click_named(node: Node, button_name: String) -> void:
	var button := node.find_child(button_name, true, false) as Button
	_check(button != null, "button '%s' must exist" % button_name)
	if button == null:
		return
	_check(button.visible and not button.disabled, "button '%s' must be actionable" % button_name)
	if not button.visible or button.disabled:
		return
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _wait_frames(2)


func _operator_level(snapshot: Dictionary, operator_id: String) -> int:
	return int(_operator_row(snapshot, operator_id)["level"])


func _operator_row(snapshot: Dictionary, operator_id: String) -> Dictionary:
	for raw: Variant in snapshot["operators"] as Array:
		var row := raw as Dictionary
		if String(row["id"]) == operator_id:
			return row
	return {}


func _screen_child(app: AppRoot) -> Node:
	var host := app.find_child("ScreenHost", true, false)
	return host.get_child(0) if host != null and host.get_child_count() > 0 else null


func _visible_text(node: Node) -> String:
	var parts := PackedStringArray()
	_collect_visible_text(node, parts)
	return "\n".join(parts)


func _collect_visible_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		parts.append((node as Label).text)
	if node is Button and (node as Button).is_visible_in_tree():
		parts.append((node as Button).text)
	for child: Node in node.get_children():
		_collect_visible_text(child, parts)


func _outer_envelope(inner: Dictionary) -> Dictionary:
	return {
		"schema_version": SaveRepository.CURRENT_SCHEMA_VERSION,
		"saved_at_unix": 2000,
		"last_gameplay_tab": 0,
		"session": inner,
	}


func _case_dir(name: String) -> String:
	return TEST_ROOT.path_join(name)


func _clean_paths(production_dir: String, v2_dir: String) -> void:
	SaveRepository.new(production_dir).clear_records()
	CombatV2TestSaveRepository.new(v2_dir).clear_records()


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture path must open: %s" % path)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
