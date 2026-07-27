extends SceneTree

const DefenseLabSaveRepositoryScript := preload(
	"res://game/persistence/product_v2/defense_lab_save_repository.gd"
)
const DEFENSE_LAB_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/defense_lab_view.tscn"
)
const OUTPUT_PATH := "user://product_v2_defense_lab_capture.png"
const CAPTURE_SIZE := Vector2i(360, 640)


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = CAPTURE_SIZE
	var repository := DefenseLabSaveRepositoryScript.new()
	if repository.clear_records() != OK:
		push_error("Cannot clear the isolated Defense Lab capture state.")
		quit(1)
		return

	var coordinator := DEFENSE_LAB_SCENE.instantiate()
	if coordinator == null:
		push_error("Cannot instantiate the Defense Lab scene.")
		quit(1)
		return
	root.add_child(coordinator)
	coordinator.set_process(false)
	coordinator.call("_process", 3.2)
	await _wait_frames(4)
	RenderingServer.force_draw(true, 0.0)

	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != CAPTURE_SIZE:
		push_error("Defense Lab capture must be a non-empty 360x640 image.")
		coordinator.queue_free()
		await _wait_frames(2)
		quit(1)
		return
	var save_error := image.save_png(OUTPUT_PATH)
	if save_error != OK:
		push_error("Cannot save Defense Lab capture: %d" % save_error)
	else:
		print("CAPTURE %s (360x640)" % ProjectSettings.globalize_path(OUTPUT_PATH))

	coordinator.queue_free()
	await _wait_frames(2)
	repository.clear_records()
	quit(0 if save_error == OK else 1)


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
