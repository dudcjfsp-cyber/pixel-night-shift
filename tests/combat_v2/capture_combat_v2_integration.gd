extends SceneTree

const APP_ROOT_SCENE: PackedScene = preload("res://game/app/app_root.tscn")
const FIXTURE_ROOT := "user://combat_v2_integration_captures"
const STEP := 0.25


class FakeClock extends RefCounted:
	var value: int

	func _init(initial_value: int) -> void:
		value = initial_value

	func now_unix() -> int:
		return value


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	root.size = Vector2i(360, 640)
	var output := _output_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(output)
	if directory_error not in [OK, ERR_ALREADY_EXISTS]:
		push_error("Cannot create Combat V2 capture directory: %d" % directory_error)
		quit(1)
		return
	var errors := 0
	errors += await _capture_operations_entry(output)
	errors += await _capture_fixture(output, &"qa", "02_combat_hp_down.png")
	errors += await _capture_fixture(output, &"emergency", "03_emergency_selection.png")
	errors += await _capture_fixture(output, &"maintenance", "04_maintenance_countdown.png")
	errors += await _capture_result(output)
	print("Combat V2 integration captures: %s" % output)
	quit(0 if errors == 0 else 1)


func _capture_operations_entry(output: String) -> int:
	var app := await _mount_empty("operations")
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(5)
	if app.current_screen_id() != AppRoot.SCREEN_OPERATIONS_ROOM:
		push_error("Operations entry capture did not reach Operations Room.")
		await _unmount(app)
		return 1
	var errors := await _save_capture(output.path_join("01_operations_v2_entry.png"))
	await _unmount(app)
	return errors


func _capture_fixture(output: String, kind: StringName, filename: String) -> int:
	var base := FIXTURE_ROOT.path_join(String(kind))
	var production := SaveRepository.new(base.path_join("production"))
	var v2 := CombatV2TestSaveRepository.new(base.path_join("v2"))
	production.clear_records()
	v2.clear_records()
	var fixture := _fixture_session(kind)
	if v2.save(fixture.export_state(), 2_200_000_000, 0) != OK:
		push_error("Cannot save %s capture fixture." % kind)
		return 1
	var app := await _mount(production, v2, FakeClock.new(2_200_000_000))
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(8)
	if app.current_screen_id() != AppRoot.SCREEN_GAMEPLAY:
		push_error("%s capture did not reach V2 gameplay." % kind)
		await _unmount(app)
		return 1
	var errors := await _save_capture(output.path_join(filename))
	await _unmount(app)
	return errors


func _capture_result(output: String) -> int:
	var base := FIXTURE_ROOT.path_join("result")
	var production := SaveRepository.new(base.path_join("production"))
	var v2 := CombatV2TestSaveRepository.new(base.path_join("v2"))
	production.clear_records()
	v2.clear_records()
	var session := CombatV2IntegrationSession.new()
	if not _drive_to_completion(session):
		push_error("Cannot complete Combat V2 result capture fixture.")
		return 1
	v2.save(session.export_state(), 2_200_001_000, 1)
	var app := await _mount(production, v2, FakeClock.new(2_200_001_000))
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(8)
	if app.current_screen_id() != AppRoot.SCREEN_COMBAT_V2_RESULT:
		push_error("Result capture did not reach the Combat V2 result screen.")
		await _unmount(app)
		return 1
	var errors := await _save_capture(output.path_join("05_stage10_result.png"))
	await _unmount(app)
	return errors


func _mount_empty(name: String) -> AppRoot:
	var base := FIXTURE_ROOT.path_join(name)
	var production := SaveRepository.new(base.path_join("production"))
	var v2 := CombatV2TestSaveRepository.new(base.path_join("v2"))
	production.clear_records()
	v2.clear_records()
	return await _mount(production, v2, FakeClock.new(2_200_000_000))


func _mount(
	production: SaveRepository,
	v2: CombatV2TestSaveRepository,
	clock: FakeClock
) -> AppRoot:
	var app := APP_ROOT_SCENE.instantiate() as AppRoot
	var settings := SettingsRepository.new(v2.base_dir().path_join("settings"))
	assert(app.configure_services(production, settings, clock, v2, true))
	root.add_child(app)
	app.set_process(false)
	await _wait_frames(8)
	return app


func _unmount(app: AppRoot) -> void:
	if is_instance_valid(app):
		app.queue_free()
	await _wait_frames(5)


func _fixture_session(kind: StringName) -> CombatV2IntegrationSession:
	var prototype := CombatV2PrototypeSession.new()
	_drive_to_stage(prototype, 6)
	var state := prototype.debug_state_copy()
	var loaded := CombatV2Loader.load_default()
	assert(loaded.is_valid())
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
		state.qa_rescue_consumed = true
		if kind == &"qa":
			target.recovery_source = &"qa"
			target.recovery_remaining = 4.0
			state.qa_recovery_target_id = &"build_engineer"
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
	assert(restore_errors.is_empty(), "; ".join(restore_errors))
	return CombatV2IntegrationSession.new(prototype)


func _drive_to_stage(session: CombatV2PrototypeSession, target_stage: int) -> void:
	var next_decision := 0.0
	for step: int in range(int(900.0 / STEP)):
		var snapshot := session.snapshot()
		if int(snapshot["stage"]) >= target_stage:
			return
		var elapsed := step * STEP
		if elapsed + 0.000001 >= next_decision:
			_apply_balanced_decision(session, snapshot)
			next_decision += 1.0
		session.tick(STEP)
	assert(false, "Cannot build stage %d capture fixture." % target_stage)


func _drive_to_completion(session: CombatV2IntegrationSession) -> bool:
	var next_decision := 0.0
	for step: int in range(int(1800.0 / STEP)):
		if session.is_complete():
			return true
		var snapshot := session.snapshot()
		var elapsed := step * STEP
		if elapsed + 0.000001 >= next_decision:
			_apply_balanced_decision(session, snapshot)
			next_decision += 1.0
		session.tick(STEP)
	return session.is_complete()


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
	var selected := &""
	var selected_level := 2147483647
	var bits := float(snapshot["bits"])
	for raw_operator: Variant in snapshot["operators"] as Array:
		var operator := raw_operator as Dictionary
		if not bool(operator["unlocked"]) or float(operator["upgrade_cost"]) > bits + 0.000001:
			continue
		if int(operator["level"]) < selected_level:
			selected = StringName(String(operator["id"]))
			selected_level = int(operator["level"])
	if selected != &"":
		session.upgrade_operator(selected)


func _save_capture(path: String) -> int:
	await _wait_frames(2)
	RenderingServer.force_draw(true, 0.0)
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != Vector2i(360, 640):
		push_error("Invalid 360x640 authority capture: %s" % path)
		return 1
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("Cannot save capture '%s': %d" % [path, save_error])
		return 1
	print("CAPTURE %s (360x640)" % path)
	return 0


func _emit_button(node: Node, button_name: String) -> void:
	var button := node.find_child(button_name, true, false) as Button
	assert(button != null and button.visible and not button.disabled, "Capture requires '%s'." % button_name)
	button.pressed.emit()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var requested := argument.trim_prefix("--capture-dir=")
			assert(requested.is_absolute_path(), "--capture-dir must be absolute")
			return requested
	return ProjectSettings.globalize_path("user://combat_v2_integration_authority_captures")
