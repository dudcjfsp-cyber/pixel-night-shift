extends SceneTree

## Deterministic, dependency-free pixel asset generator for Pixel Night Shift.
## Run with:
##   godot --headless --path . --script res://tools/generate_pixel_assets.gd

const OUTPUT_ROOT := "res://game/assets/generated"
const MANIFEST_PATH := "res://game/assets/manifest.json"
const GENERATOR_VERSION := 1
const GENERATION_SEED := "pns-midnight-terminal-v1"
const ASSET_LICENSE := "LicenseRef-PixelNightShift-Original"

const CLEAR := Color("00000000")
const VOID := Color("050914")
const INK := Color("0a1220")
const PANEL := Color("101e2f")
const PANEL_LIGHT := Color("183247")
const STEEL := Color("315166")
const MUTED := Color("658297")
const PALE := Color("d7edf0")
const WHITE := Color("f6fbf5")
const CYAN := Color("31d2c9")
const CYAN_DARK := Color("177f88")
const GREEN := Color("6ee7a2")
const GREEN_DARK := Color("27875c")
const AMBER := Color("ffb34d")
const ORANGE := Color("f4784d")
const RED := Color("df4d67")
const RED_DARK := Color("812f4a")
const MAGENTA := Color("d96bd8")
const PURPLE := Color("8a78e6")
const BLUE := Color("5599e9")

var _manifest_entries: Array[Dictionary] = []


func _init() -> void:
	var error: Error = _generate_all()
	if error != OK:
		push_error("Pixel asset generation failed with error %d." % error)
		quit(1)
		return
	print("Generated %d deterministic pixel assets." % _manifest_entries.size())
	quit(0)


func _generate_all() -> Error:
	_manifest_entries.clear()
	var assets: Array[Dictionary] = [
		_entry("debugger", "operator", "operators/debugger.png", _operator_debugger()),
		_entry("build_engineer", "operator", "operators/build_engineer.png", _operator_build_engineer()),
		_entry("sprite_artist", "operator", "operators/sprite_artist.png", _operator_sprite_artist()),
		_entry("qa_imp", "operator", "operators/qa_imp.png", _operator_qa_imp()),
		_entry("broken_pixel", "enemy", "enemies/broken_pixel.png", _enemy_broken_pixel()),
		_entry("infinite_loop", "enemy", "enemies/infinite_loop.png", _enemy_infinite_loop()),
		_entry("missing_resource", "enemy", "enemies/missing_resource.png", _enemy_missing_resource()),
		_entry("maintenance_error", "enemy", "enemies/maintenance_error.png", _enemy_maintenance_error()),
		_entry("watchdog_process", "boss", "enemies/watchdog_process.png", _boss_watchdog()),
		_entry("frame_skip", "patch", "patches/frame_skip.png", _patch_frame_skip()),
		_entry("unsafe_build", "patch", "patches/unsafe_build.png", _patch_unsafe_build()),
		_entry("reward_bypass", "patch", "patches/reward_bypass.png", _patch_reward_bypass()),
		_entry("rollback_lock", "patch", "patches/rollback_lock.png", _patch_rollback_lock()),
		_entry("safe_mode", "patch", "patches/safe_mode.png", _patch_safe_mode()),
		_entry("bit", "ui", "ui/bit.png", _ui_bit()),
		_entry("patch_note", "ui", "ui/patch_note.png", _ui_patch_note()),
		_entry("stage", "ui", "ui/stage.png", _ui_stage()),
		_entry("diagnosis", "ui", "ui/diagnosis.png", _ui_diagnosis()),
		_entry("combat", "ui", "ui/combat.png", _ui_combat()),
		_entry("boss", "ui", "ui/boss.png", _ui_boss()),
		_entry("maintenance", "ui", "ui/maintenance.png", _ui_maintenance()),
		_entry("complete", "ui", "ui/complete.png", _ui_complete()),
		_entry("battle_server_room", "background", "backgrounds/battle_server_room.png", _battle_background()),
	]

	for asset: Dictionary in assets:
		var save_error: Error = _save_asset(asset)
		if save_error != OK:
			return save_error
	return _write_manifest()


func _entry(id: String, category: String, relative_path: String, image: Image) -> Dictionary:
	return {
		"id": id,
		"category": category,
		"relative_path": relative_path,
		"image": image,
	}


func _save_asset(asset: Dictionary) -> Error:
	var image: Image = asset["image"] as Image
	var relative_path: String = asset["relative_path"]
	var resource_path := "%s/%s" % [OUTPUT_ROOT, relative_path]
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		push_error("Could not create asset directory: %s" % absolute_path.get_base_dir())
		return directory_error
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("Could not save PNG: %s" % resource_path)
		return save_error
	_manifest_entries.append({
		"id": asset["id"],
		"category": asset["category"],
		"path": resource_path,
		"width": image.get_width(),
		"height": image.get_height(),
		"sha256": FileAccess.get_sha256(absolute_path),
	})
	return OK


func _write_manifest() -> Error:
	var absolute_path := ProjectSettings.globalize_path(MANIFEST_PATH)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var manifest := {
		"schema_version": 1,
		"generator": "res://tools/generate_pixel_assets.gd",
		"generator_version": GENERATOR_VERSION,
		"generation_seed": GENERATION_SEED,
		"license": ASSET_LICENSE,
		"style": "original midnight operations-terminal pixel art",
		"assets": _manifest_entries,
	}
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open manifest for writing: %s" % MANIFEST_PATH)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	return OK


func _canvas(width: int, height: int, color: Color = CLEAR) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, color)


func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	image.fill_rect(Rect2i(x, y, width, height), color)


func _outline(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	_rect(image, x, y, width, 1, color)
	_rect(image, x, y + height - 1, width, 1, color)
	_rect(image, x, y, 1, height, color)
	_rect(image, x + width - 1, y, 1, height, color)


func _line(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var x := x0
	var y := y0
	var delta_x := absi(x1 - x0)
	var step_x := 1 if x0 < x1 else -1
	var delta_y := -absi(y1 - y0)
	var step_y := 1 if y0 < y1 else -1
	var error := delta_x + delta_y
	while true:
		_px(image, x, y, color)
		if x == x1 and y == y1:
			break
		var doubled_error := 2 * error
		if doubled_error >= delta_y:
			error += delta_y
			x += step_x
		if doubled_error <= delta_x:
			error += delta_x
			y += step_y


func _disc(image: Image, center_x: int, center_y: int, radius: int, color: Color) -> void:
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				_px(image, center_x + x, center_y + y, color)


func _operator_base() -> Image:
	var image := _canvas(32, 32)
	_rect(image, 7, 29, 18, 2, VOID)
	return image


func _operator_debugger() -> Image:
	var image := _operator_base()
	_rect(image, 10, 13, 12, 14, INK)
	_rect(image, 8, 16, 3, 9, PANEL_LIGHT)
	_rect(image, 22, 15, 3, 9, PANEL_LIGHT)
	_rect(image, 11, 6, 10, 8, MUTED)
	_rect(image, 10, 8, 12, 4, INK)
	_rect(image, 12, 9, 8, 2, CYAN)
	_px(image, 19, 9, WHITE)
	_rect(image, 12, 14, 8, 10, PANEL)
	_rect(image, 14, 16, 4, 6, CYAN_DARK)
	_rect(image, 14, 17, 4, 2, CYAN)
	_rect(image, 10, 25, 5, 4, STEEL)
	_rect(image, 18, 25, 5, 4, STEEL)
	_line(image, 24, 15, 27, 10, GREEN)
	_px(image, 27, 9, GREEN)
	_px(image, 28, 10, GREEN)
	return image


func _operator_build_engineer() -> Image:
	var image := _operator_base()
	_rect(image, 8, 15, 16, 11, INK)
	_rect(image, 6, 17, 4, 8, ORANGE)
	_rect(image, 22, 17, 4, 8, ORANGE)
	_rect(image, 11, 7, 10, 8, MUTED)
	_rect(image, 10, 6, 12, 4, AMBER)
	_rect(image, 9, 9, 14, 2, AMBER)
	_rect(image, 12, 11, 8, 3, PALE)
	_rect(image, 9, 15, 14, 3, ORANGE)
	_rect(image, 11, 18, 10, 7, PANEL)
	_rect(image, 12, 20, 8, 2, AMBER)
	_rect(image, 10, 25, 5, 4, STEEL)
	_rect(image, 18, 25, 5, 4, STEEL)
	_rect(image, 25, 12, 2, 9, MUTED)
	_rect(image, 24, 11, 4, 3, PALE)
	return image


func _operator_sprite_artist() -> Image:
	var image := _operator_base()
	_rect(image, 9, 14, 14, 13, INK)
	_rect(image, 11, 7, 10, 7, MUTED)
	_rect(image, 10, 6, 9, 3, MAGENTA)
	_rect(image, 17, 5, 5, 2, MAGENTA)
	_rect(image, 12, 10, 8, 3, PALE)
	_px(image, 13, 10, PANEL)
	_px(image, 18, 10, PANEL)
	_rect(image, 11, 15, 10, 10, PURPLE)
	_rect(image, 13, 16, 6, 8, PANEL)
	_rect(image, 7, 16, 4, 7, MAGENTA)
	_rect(image, 21, 16, 3, 7, MAGENTA)
	_line(image, 24, 17, 28, 12, CYAN)
	_px(image, 28, 11, WHITE)
	_rect(image, 10, 25, 5, 4, STEEL)
	_rect(image, 18, 25, 5, 4, STEEL)
	return image


func _operator_qa_imp() -> Image:
	var image := _operator_base()
	_rect(image, 10, 12, 12, 14, INK)
	_rect(image, 11, 8, 10, 7, PURPLE)
	_line(image, 11, 9, 8, 5, PURPLE)
	_line(image, 20, 9, 23, 5, PURPLE)
	_px(image, 8, 5, MAGENTA)
	_px(image, 23, 5, MAGENTA)
	_rect(image, 12, 11, 8, 2, PALE)
	_px(image, 13, 11, RED)
	_px(image, 18, 11, RED)
	_rect(image, 12, 15, 8, 9, PURPLE)
	_rect(image, 7, 16, 4, 7, PURPLE)
	_rect(image, 21, 16, 4, 7, PURPLE)
	_rect(image, 19, 16, 6, 8, PALE)
	_outline(image, 19, 16, 6, 8, STEEL)
	_line(image, 20, 20, 21, 21, GREEN_DARK)
	_line(image, 21, 21, 24, 18, GREEN)
	_rect(image, 10, 25, 5, 4, STEEL)
	_rect(image, 18, 25, 5, 4, STEEL)
	return image


func _enemy_broken_pixel() -> Image:
	var image := _canvas(32, 32)
	_rect(image, 7, 10, 18, 15, RED_DARK)
	_rect(image, 5, 14, 4, 8, RED)
	_rect(image, 23, 12, 4, 11, RED)
	_rect(image, 9, 8, 7, 4, RED)
	_rect(image, 18, 9, 7, 5, ORANGE)
	_rect(image, 9, 15, 5, 3, PALE)
	_rect(image, 19, 15, 4, 3, PALE)
	_px(image, 12, 16, VOID)
	_px(image, 20, 16, VOID)
	_line(image, 15, 11, 17, 15, PALE)
	_line(image, 17, 15, 15, 20, PALE)
	_line(image, 15, 20, 18, 24, ORANGE)
	_rect(image, 10, 25, 4, 3, RED)
	_rect(image, 20, 25, 4, 3, RED)
	_px(image, 6, 9, RED)
	_px(image, 25, 7, ORANGE)
	_px(image, 27, 10, RED)
	return image


func _enemy_infinite_loop() -> Image:
	var image := _canvas(32, 32)
	_disc(image, 16, 16, 10, INK)
	_line(image, 7, 14, 10, 10, AMBER)
	_line(image, 10, 10, 15, 10, AMBER)
	_line(image, 15, 10, 22, 20, AMBER)
	_line(image, 22, 20, 26, 16, AMBER)
	_line(image, 25, 15, 26, 16, AMBER)
	_line(image, 26, 16, 26, 13, AMBER)
	_line(image, 25, 18, 22, 22, RED)
	_line(image, 22, 22, 17, 22, RED)
	_line(image, 17, 22, 10, 12, RED)
	_line(image, 10, 12, 6, 16, RED)
	_line(image, 6, 16, 6, 13, RED)
	_line(image, 6, 16, 9, 16, RED)
	_rect(image, 14, 14, 4, 4, PALE)
	_px(image, 15, 15, VOID)
	return image


func _enemy_missing_resource() -> Image:
	var image := _canvas(32, 32)
	_rect(image, 7, 8, 18, 18, INK)
	_outline(image, 7, 8, 18, 18, PURPLE)
	_rect(image, 9, 10, 6, 6, STEEL)
	_rect(image, 17, 10, 6, 6, PANEL_LIGHT)
	_rect(image, 9, 18, 6, 6, PANEL_LIGHT)
	_rect(image, 17, 18, 6, 6, STEEL)
	_rect(image, 13, 13, 6, 6, CLEAR)
	_rect(image, 14, 13, 4, 2, RED)
	_rect(image, 17, 15, 2, 3, RED)
	_rect(image, 15, 18, 2, 2, RED)
	_px(image, 15, 22, RED)
	_px(image, 5, 11, PURPLE)
	_px(image, 26, 20, PURPLE)
	return image


func _enemy_maintenance_error() -> Image:
	var image := _canvas(32, 32)
	_rect(image, 7, 12, 18, 13, INK)
	_outline(image, 7, 12, 18, 13, ORANGE)
	_rect(image, 9, 9, 14, 5, AMBER)
	_rect(image, 11, 7, 10, 4, AMBER)
	_rect(image, 10, 15, 12, 7, PANEL_LIGHT)
	_rect(image, 11, 16, 3, 3, RED)
	_rect(image, 18, 16, 3, 3, RED)
	_rect(image, 14, 21, 4, 2, PALE)
	_rect(image, 5, 15, 3, 7, STEEL)
	_rect(image, 24, 15, 3, 7, STEEL)
	_line(image, 8, 24, 11, 20, AMBER)
	_line(image, 12, 24, 15, 20, AMBER)
	_line(image, 16, 24, 19, 20, AMBER)
	_line(image, 20, 24, 23, 20, AMBER)
	_rect(image, 9, 25, 5, 3, ORANGE)
	_rect(image, 19, 25, 5, 3, ORANGE)
	return image


func _boss_watchdog() -> Image:
	var image := _canvas(48, 48)
	_rect(image, 8, 15, 32, 25, INK)
	_outline(image, 8, 15, 32, 25, RED_DARK)
	_rect(image, 5, 19, 5, 15, RED_DARK)
	_rect(image, 38, 19, 5, 15, RED_DARK)
	_rect(image, 12, 10, 24, 8, PANEL_LIGHT)
	_line(image, 13, 11, 9, 5, RED)
	_line(image, 34, 11, 38, 5, RED)
	_px(image, 8, 4, RED)
	_px(image, 39, 4, RED)
	_rect(image, 12, 19, 24, 15, PANEL)
	_rect(image, 15, 21, 18, 10, VOID)
	_rect(image, 18, 23, 12, 6, CYAN_DARK)
	_rect(image, 20, 24, 8, 4, CYAN)
	_rect(image, 23, 24, 3, 4, WHITE)
	_rect(image, 13, 35, 22, 3, RED_DARK)
	_rect(image, 12, 40, 8, 5, STEEL)
	_rect(image, 28, 40, 8, 5, STEEL)
	_rect(image, 2, 23, 5, 4, MUTED)
	_rect(image, 41, 23, 5, 4, MUTED)
	_px(image, 4, 22, RED)
	_px(image, 43, 22, RED)
	return image


func _patch_base(accent: Color) -> Image:
	var image := _canvas(24, 24)
	_rect(image, 2, 2, 20, 20, INK)
	_outline(image, 2, 2, 20, 20, accent)
	_px(image, 3, 3, PALE)
	return image


func _patch_frame_skip() -> Image:
	var image := _patch_base(CYAN)
	_outline(image, 5, 6, 8, 10, STEEL)
	_outline(image, 8, 8, 8, 10, CYAN_DARK)
	_line(image, 16, 9, 19, 12, CYAN)
	_line(image, 19, 12, 16, 15, CYAN)
	_line(image, 18, 9, 21, 12, PALE)
	_line(image, 21, 12, 18, 15, PALE)
	return image


func _patch_unsafe_build() -> Image:
	var image := _patch_base(ORANGE)
	for row: int in range(0, 8):
		_rect(image, 12 - row, 5 + row, row * 2 + 1, 1, AMBER)
	_line(image, 12, 7, 12, 12, INK)
	_rect(image, 11, 14, 3, 3, INK)
	_rect(image, 6, 18, 12, 2, RED)
	return image


func _patch_reward_bypass() -> Image:
	var image := _patch_base(GREEN)
	_disc(image, 8, 8, 4, AMBER)
	_disc(image, 8, 8, 2, PANEL)
	_line(image, 5, 16, 9, 16, GREEN)
	_line(image, 9, 16, 12, 12, GREEN)
	_line(image, 12, 12, 16, 12, GREEN)
	_line(image, 16, 12, 19, 8, GREEN)
	_line(image, 17, 8, 19, 8, PALE)
	_line(image, 19, 8, 19, 10, PALE)
	return image


func _patch_rollback_lock() -> Image:
	var image := _patch_base(PURPLE)
	_line(image, 5, 11, 8, 7, PURPLE)
	_line(image, 8, 7, 14, 6, PURPLE)
	_line(image, 14, 6, 18, 9, PURPLE)
	_line(image, 5, 11, 5, 7, PURPLE)
	_line(image, 5, 11, 9, 11, PURPLE)
	_rect(image, 9, 12, 10, 8, STEEL)
	_outline(image, 9, 12, 10, 8, PALE)
	_outline(image, 11, 9, 6, 6, PALE)
	_px(image, 14, 16, VOID)
	return image


func _patch_safe_mode() -> Image:
	var image := _patch_base(BLUE)
	_line(image, 12, 5, 18, 8, BLUE)
	_line(image, 18, 8, 17, 15, BLUE)
	_line(image, 17, 15, 12, 19, BLUE)
	_line(image, 12, 19, 7, 15, BLUE)
	_line(image, 7, 15, 6, 8, BLUE)
	_line(image, 6, 8, 12, 5, BLUE)
	_line(image, 9, 12, 11, 14, PALE)
	_line(image, 11, 14, 15, 9, GREEN)
	return image


func _ui_canvas() -> Image:
	return _canvas(16, 16)


func _ui_bit() -> Image:
	var image := _ui_canvas()
	_line(image, 8, 1, 13, 5, CYAN)
	_line(image, 13, 5, 11, 13, CYAN)
	_line(image, 11, 13, 5, 13, CYAN_DARK)
	_line(image, 5, 13, 3, 5, CYAN_DARK)
	_line(image, 3, 5, 8, 1, CYAN)
	_rect(image, 6, 5, 4, 5, PALE)
	return image


func _ui_patch_note() -> Image:
	var image := _ui_canvas()
	_rect(image, 3, 2, 10, 12, PANEL_LIGHT)
	_outline(image, 3, 2, 10, 12, PALE)
	_rect(image, 5, 5, 6, 1, CYAN)
	_rect(image, 5, 8, 6, 1, MUTED)
	_rect(image, 5, 11, 4, 1, MUTED)
	return image


func _ui_stage() -> Image:
	var image := _ui_canvas()
	_rect(image, 2, 11, 4, 3, STEEL)
	_rect(image, 6, 8, 4, 6, BLUE)
	_rect(image, 10, 5, 4, 9, CYAN)
	_line(image, 11, 4, 13, 2, PALE)
	_line(image, 13, 2, 13, 5, PALE)
	return image


func _ui_diagnosis() -> Image:
	var image := _ui_canvas()
	_outline(image, 2, 3, 10, 8, CYAN_DARK)
	_line(image, 3, 8, 5, 8, CYAN)
	_line(image, 5, 8, 7, 5, CYAN)
	_line(image, 7, 5, 9, 9, CYAN)
	_line(image, 9, 9, 11, 6, CYAN)
	_line(image, 10, 11, 14, 15, PALE)
	return image


func _ui_combat() -> Image:
	var image := _ui_canvas()
	_outline(image, 3, 3, 10, 10, RED)
	_rect(image, 7, 1, 2, 5, PALE)
	_rect(image, 7, 10, 2, 5, PALE)
	_rect(image, 1, 7, 5, 2, PALE)
	_rect(image, 10, 7, 5, 2, PALE)
	_px(image, 7, 7, RED)
	_px(image, 8, 8, RED)
	return image


func _ui_boss() -> Image:
	var image := _ui_canvas()
	_rect(image, 3, 5, 10, 8, RED_DARK)
	_line(image, 3, 5, 2, 1, RED)
	_line(image, 12, 5, 13, 1, RED)
	_rect(image, 5, 7, 2, 2, PALE)
	_rect(image, 9, 7, 2, 2, PALE)
	_rect(image, 6, 11, 4, 2, INK)
	return image


func _ui_maintenance() -> Image:
	var image := _ui_canvas()
	_line(image, 3, 2, 13, 12, AMBER)
	_line(image, 2, 3, 12, 13, ORANGE)
	_rect(image, 1, 1, 5, 3, STEEL)
	_rect(image, 10, 12, 5, 3, STEEL)
	_rect(image, 10, 2, 4, 2, MUTED)
	_rect(image, 12, 1, 2, 5, MUTED)
	return image


func _ui_complete() -> Image:
	var image := _ui_canvas()
	_disc(image, 8, 8, 7, GREEN_DARK)
	_line(image, 3, 8, 7, 12, PALE)
	_line(image, 7, 12, 13, 4, GREEN)
	return image


func _battle_background() -> Image:
	var image := _canvas(344, 64, VOID)
	_rect(image, 0, 0, 344, 8, INK)
	_rect(image, 0, 8, 344, 43, PANEL)
	_rect(image, 0, 51, 344, 13, INK)
	for bay: int in range(8):
		var x := bay * 43
		_rect(image, x + 3, 11, 35, 36, Color("0a1624"))
		_outline(image, x + 3, 11, 35, 36, PANEL_LIGHT)
		_rect(image, x + 7, 15, 27, 8, STEEL)
		_rect(image, x + 7, 26, 27, 8, STEEL)
		_rect(image, x + 7, 37, 27, 6, STEEL)
		for light_index: int in range(4):
			var light_color := CYAN_DARK if (bay + light_index) % 3 != 0 else AMBER
			_rect(image, x + 9 + light_index * 5, 17, 2, 2, light_color)
		_rect(image, x + 29, 17, 3, 4, PANEL)
		_rect(image, x + 9, 28, 18, 2, PANEL_LIGHT)
		_rect(image, x + 29, 28, 3, 3, GREEN_DARK)
		_rect(image, x + 9, 39, 10, 2, PANEL_LIGHT)
		_rect(image, x + 29, 39, 3, 2, RED_DARK if bay % 4 == 3 else CYAN_DARK)
	for x: int in range(0, 344, 16):
		_line(image, x, 63, x + 8, 51, PANEL_LIGHT)
	_rect(image, 0, 51, 344, 1, STEEL)
	_rect(image, 0, 62, 344, 2, VOID)
	_line(image, 0, 7, 344, 7, CYAN_DARK)
	return image
