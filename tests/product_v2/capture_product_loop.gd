extends SceneTree

const DefenseLabSaveRepositoryScript := preload(
	"res://game/persistence/product_v2/defense_lab_save_repository.gd"
)
const PRODUCT_LOOP_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/product_loop.tscn"
)
const SAVE_BASE_DIR := "user://product_v2_product_loop_lab"
const CAPTURE_SIZE := Vector2i(360, 640)


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = CAPTURE_SIZE
	var repository := DefenseLabSaveRepositoryScript.new(SAVE_BASE_DIR)
	if repository.clear_records() != OK:
		push_error("Cannot clear Product V2 loop capture records.")
		quit(1)
		return

	var coordinator := PRODUCT_LOOP_SCENE.instantiate()
	if coordinator == null:
		push_error("Cannot instantiate the Product V2 loop scene.")
		quit(1)
		return
	root.add_child(coordinator)
	coordinator.set_process(false)
	await _wait_frames(3)

	var failures := await _save_capture(
		"user://product_v2_day_prep_capture.png"
	)
	var start_button := coordinator.find_child("StartShift1Button", true, false) as Button
	if start_button == null or start_button.disabled:
		push_error("Product V2 capture requires the first-night start button.")
		failures += 1
	else:
		start_button.pressed.emit()
		coordinator.call("_process", 300.0)
		await _wait_frames(3)
		failures += await _save_capture(
			"user://product_v2_shift_result_capture.png"
		)

	coordinator.queue_free()
	await _wait_frames(2)
	repository.clear_records()
	quit(0 if failures == 0 else 1)


func _save_capture(path: String) -> int:
	RenderingServer.force_draw(true, 0.0)
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != CAPTURE_SIZE:
		push_error("Invalid 360x640 Product V2 capture: %s" % path)
		return 1
	var error := image.save_png(path)
	if error != OK:
		push_error("Cannot save Product V2 capture '%s': %d" % [path, error])
		return 1
	print("CAPTURE %s (360x640)" % ProjectSettings.globalize_path(path))
	return 0


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
