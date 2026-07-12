extends SceneTree

const APP_ROOT_SCENE: PackedScene = preload("res://game/app/app_root.tscn")
const CAPTURE_BASE := "user://app_root_capture_fixtures"
const STEP_SECONDS := 0.25

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
	var output_directory := _output_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error not in [OK, ERR_ALREADY_EXISTS]:
		push_error("Cannot create AppRoot capture directory: error %d" % directory_error)
		quit(1)
		return

	var error_count := 0
	error_count += await _capture_first_start_and_settings(output_directory)
	error_count += await _capture_operations_and_offline(output_directory)
	error_count += await _capture_gameplay_and_onboarding(output_directory)
	error_count += await _capture_recovery_states(output_directory)
	error_count += await _capture_version_update(output_directory)
	print("AppRoot captures: %s" % output_directory)
	quit(0 if error_count == 0 else 1)


func _capture_first_start_and_settings(output_directory: String) -> int:
	var base_dir := CAPTURE_BASE.path_join("first")
	_clean_case(base_dir)
	var app := await _mount_app(SaveRepository.new(base_dir), FakeClock.new(2_000_100_000))
	var errors := await _save_capture(output_directory.path_join("01_first_start.png"))
	_emit_button(app, "SettingsButton")
	await _wait_frames(4)
	errors += await _save_capture(output_directory.path_join("02_settings.png"))
	await _unmount(app)
	return errors


func _capture_operations_and_offline(output_directory: String) -> int:
	var operations_dir := CAPTURE_BASE.path_join("operations")
	_clean_case(operations_dir)
	var operations_repo := SaveRepository.new(operations_dir)
	var operations_session := GameSession.new()
	operations_session.tick(180.0)
	var now := 2_000_110_000
	operations_repo.save(operations_session.export_state(), now, 1)
	var operations_app := await _mount_app(operations_repo, FakeClock.new(now))
	var errors := await _save_capture(output_directory.path_join("03_operations_room.png"))
	await _unmount(operations_app)

	var offline_dir := CAPTURE_BASE.path_join("offline")
	_clean_case(offline_dir)
	var offline_repo := SaveRepository.new(offline_dir)
	var offline_session := GameSession.new()
	offline_session.tick(120.0)
	offline_repo.save(offline_session.export_state(), now - 7200, 0)
	var offline_app := await _mount_app(offline_repo, FakeClock.new(now))
	errors += await _save_capture(output_directory.path_join("04_offline_report.png"))
	await _unmount(offline_app)
	return errors


func _capture_gameplay_and_onboarding(output_directory: String) -> int:
	var base_dir := CAPTURE_BASE.path_join("gameplay")
	_clean_case(base_dir)
	var app := await _mount_app(SaveRepository.new(base_dir), FakeClock.new(2_000_120_000))
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(8)
	var errors := await _save_capture(output_directory.path_join("05_gameplay_onboarding.png"))
	_emit_button(app, "SkipButton")
	await _wait_frames(8)
	errors += await _save_capture(output_directory.path_join("06_gameplay_sprites.png"))
	await _unmount(app)
	return errors


func _capture_recovery_states(output_directory: String) -> int:
	var backup_dir := CAPTURE_BASE.path_join("backup_recovery")
	_clean_case(backup_dir)
	var backup_repo := SaveRepository.new(backup_dir)
	var session := GameSession.new()
	backup_repo.save(session.export_state(), 2_000_130_000, 0)
	session.tick(60.0)
	backup_repo.save(session.export_state(), 2_000_130_100, 1)
	_write_text(backup_repo.primary_path(), "{broken")
	var backup_app := await _mount_app(backup_repo, FakeClock.new(2_000_130_200))
	var errors := await _save_capture(output_directory.path_join("07_backup_recovery.png"))
	await _unmount(backup_app)

	var newer_dir := CAPTURE_BASE.path_join("newer_recovery")
	_clean_case(newer_dir)
	var newer_repo := SaveRepository.new(newer_dir)
	newer_repo.save(GameSession.new().export_state(), 2_000_130_000, 0)
	_write_text(newer_repo.primary_path(), JSON.stringify({
		"schema_version": 99,
		"saved_at_unix": 2_000_130_000,
		"last_gameplay_tab": 0,
		"session": {},
	}))
	var newer_app := await _mount_app(newer_repo, FakeClock.new(2_000_130_000))
	errors += await _save_capture(output_directory.path_join("08_newer_schema_recovery.png"))
	await _unmount(newer_app)
	return errors


func _capture_version_update(output_directory: String) -> int:
	var base_dir := CAPTURE_BASE.path_join("version_update")
	_clean_case(base_dir)
	var repository := SaveRepository.new(base_dir)
	var session := GameSession.new()
	if not _drive_to_prestige(session, 900.0):
		push_error("Cannot build version-update capture fixture.")
		return 1
	var clock := FakeClock.new(2_000_140_000)
	repository.save(session.export_state(), clock.value, 2)
	var app := await _mount_app(repository, clock)
	_emit_button(app, "PrimaryActionButton")
	await _wait_frames(6)
	_emit_button(app, "VersionUpdateButton")
	await _wait_frames(4)
	var errors := await _save_capture(output_directory.path_join("09_version_confirm.png"))
	_emit_button(app, "ConfirmButton")
	await _wait_frames(4)
	errors += await _save_capture(output_directory.path_join("10_run_summary.png"))
	await _unmount(app)
	return errors


func _mount_app(repository: SaveRepository, clock: FakeClock) -> AppRoot:
	var app := APP_ROOT_SCENE.instantiate() as AppRoot
	var settings_repository := SettingsRepository.new(repository.base_dir())
	assert(app.configure_services(repository, settings_repository, clock))
	root.add_child(app)
	app.set_process(false)
	await _wait_frames(6)
	return app


func _unmount(app: AppRoot) -> void:
	if is_instance_valid(app):
		app.queue_free()
	await _wait_frames(4)


func _save_capture(output_path: String) -> int:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Viewport returned an empty image for '%s'." % output_path)
		return 1
	if image.get_width() != 360 or image.get_height() != 640:
		push_error("Capture '%s' is not 360x640." % output_path)
		return 1
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Cannot save AppRoot capture '%s': error %d" % [output_path, save_error])
		return 1
	print("CAPTURE %s (360x640)" % output_path)
	return 0


func _emit_button(node: Node, button_name: String) -> void:
	var button := node.find_child(button_name, true, false) as Button
	assert(button != null, "Capture requires button '%s'." % button_name)
	button.pressed.emit()


func _clean_case(base_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	SaveRepository.new(base_dir).clear_records()
	var settings_repository := SettingsRepository.new(base_dir)
	for path: String in [
		settings_repository.settings_path(),
		settings_repository.temporary_path(),
		settings_repository.rollback_path(),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Capture fixture path must open: %s" % path)
	file.store_string(content)
	file.close()


func _drive_to_prestige(session: GameSession, max_seconds: float) -> bool:
	var operator_ids: Array[StringName] = [
		&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
	]
	for step: int in range(int(max_seconds / STEP_SECONDS)):
		var snapshot := session.snapshot()
		if bool(snapshot.get("prestige_available", false)):
			return true
		if step % 4 == 0:
			for operator_id: StringName in operator_ids:
				session.upgrade_operator(operator_id)
		session.tick(STEP_SECONDS)
	return bool(session.snapshot().get("prestige_available", false))


func _wait_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var requested := argument.trim_prefix("--capture-dir=")
			assert(not requested.is_empty(), "--capture-dir requires an absolute path.")
			return requested
	return ProjectSettings.globalize_path("user://app_root_captures")
