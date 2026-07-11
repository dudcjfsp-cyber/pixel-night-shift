extends SceneTree

const PREVIEW_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/app_shell_preview.tscn"
)
const PREVIEW_CONTROLLER_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/preview/app_shell_preview_controller.gd"
)


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(360, 640)
	var output_directory := _output_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error(
			"Cannot create app-shell capture directory '%s': error %d"
			% [output_directory, directory_error]
		)
		quit(1)
		return

	var dev_preview := _instantiate_preview()
	if dev_preview == null:
		push_error("App-shell preview scene did not instantiate with its controller script.")
		quit(1)
		return
	root.add_child(dev_preview)
	await _wait_frames(6)

	var error_count := 0
	error_count += await _save_capture(output_directory.path_join("00_dev_preview.png"))
	var state_count := dev_preview.preview_state_count()
	dev_preview.queue_free()
	await _wait_frames(4)

	for state_index: int in range(state_count):
		var preview := _instantiate_preview()
		if preview == null:
			push_error("Cannot instantiate preview for state %d." % state_index)
			error_count += 1
			continue
		root.add_child(preview)
		await _wait_frames(4)
		preview.show_preview_state(state_index)
		preview.set_dev_chrome_visible(false)
		await _wait_frames(8)
		var file_name := "%02d_%s.png" % [
			state_index + 1,
			String(preview.current_state_id()),
		]
		error_count += await _save_capture(output_directory.path_join(file_name))
		preview.queue_free()
		await _wait_frames(4)

	print("App-shell captures: %s" % output_directory)
	quit(0 if error_count == 0 else 1)


func _save_capture(output_path: String) -> int:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Viewport returned an empty image for '%s'." % output_path)
		return 1
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Cannot save app-shell capture '%s': error %d" % [output_path, save_error])
		return 1
	print("CAPTURE %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	return 0


func _instantiate_preview() -> PREVIEW_CONTROLLER_SCRIPT:
	return PREVIEW_SCENE.instantiate() as PREVIEW_CONTROLLER_SCRIPT


func _wait_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var requested := argument.trim_prefix("--capture-dir=")
			assert(not requested.is_empty(), "--capture-dir requires an absolute path.")
			return requested
	return ProjectSettings.globalize_path("user://app_shell_captures")
