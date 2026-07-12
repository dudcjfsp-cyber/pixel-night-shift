extends SceneTree

## Validates dimensions, hashes, palette shape, and alpha discipline for every
## generated pixel asset declared by the manifest.

const MANIFEST_PATH := "res://game/assets/manifest.json"
const PRESENTATION_ASSETS_SCRIPT: GDScript = preload(
	"res://game/presentation/presentation_assets.gd"
)
const EXPECTED: Dictionary = {
	"res://game/assets/generated/operators/debugger.png": [32, 32],
	"res://game/assets/generated/operators/build_engineer.png": [32, 32],
	"res://game/assets/generated/operators/sprite_artist.png": [32, 32],
	"res://game/assets/generated/operators/qa_imp.png": [32, 32],
	"res://game/assets/generated/enemies/broken_pixel.png": [32, 32],
	"res://game/assets/generated/enemies/infinite_loop.png": [32, 32],
	"res://game/assets/generated/enemies/missing_resource.png": [32, 32],
	"res://game/assets/generated/enemies/maintenance_error.png": [32, 32],
	"res://game/assets/generated/enemies/watchdog_process.png": [48, 48],
	"res://game/assets/generated/patches/frame_skip.png": [24, 24],
	"res://game/assets/generated/patches/unsafe_build.png": [24, 24],
	"res://game/assets/generated/patches/reward_bypass.png": [24, 24],
	"res://game/assets/generated/patches/rollback_lock.png": [24, 24],
	"res://game/assets/generated/patches/safe_mode.png": [24, 24],
	"res://game/assets/generated/ui/bit.png": [16, 16],
	"res://game/assets/generated/ui/patch_note.png": [16, 16],
	"res://game/assets/generated/ui/stage.png": [16, 16],
	"res://game/assets/generated/ui/diagnosis.png": [16, 16],
	"res://game/assets/generated/ui/combat.png": [16, 16],
	"res://game/assets/generated/ui/boss.png": [16, 16],
	"res://game/assets/generated/ui/maintenance.png": [16, 16],
	"res://game/assets/generated/ui/complete.png": [16, 16],
	"res://game/assets/generated/backgrounds/battle_server_room.png": [344, 64],
}


func _init() -> void:
	var failures: Array[String] = _validate()
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		push_error("Pixel asset validation failed with %d issue(s)." % failures.size())
		quit(1)
		return
	print("Validated %d static pixel assets and all active sprite runs." % EXPECTED.size())
	quit(0)


func _validate() -> Array[String]:
	var failures: Array[String] = []
	var manifest_absolute := ProjectSettings.globalize_path(MANIFEST_PATH)
	if not FileAccess.file_exists(manifest_absolute):
		failures.append("Missing manifest: %s" % MANIFEST_PATH)
		return failures
	var manifest_file := FileAccess.open(manifest_absolute, FileAccess.READ)
	if manifest_file == null:
		failures.append("Could not read manifest: %s" % MANIFEST_PATH)
		return failures
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	if not parsed is Dictionary:
		failures.append("Manifest root must be a Dictionary.")
		return failures
	var manifest: Dictionary = parsed
	if manifest.get("schema_version", 0) != 2:
		failures.append("Manifest schema_version must be 2.")
	if manifest.get("generator", "") != "res://tools/generate_pixel_assets.gd":
		failures.append("Manifest generator path is unexpected.")
	if manifest.get("generator_version", 0) != 2:
		failures.append("Manifest generator_version must be 2.")
	if manifest.get("license", "") != "LicenseRef-PixelNightShift-Original":
		failures.append("Manifest license is unexpected.")
	var entries_value: Variant = manifest.get("assets", [])
	if not entries_value is Array:
		failures.append("Manifest assets must be an Array.")
		return failures
	var entries: Array = entries_value
	if entries.size() != EXPECTED.size():
		failures.append("Expected %d manifest entries, got %d." % [EXPECTED.size(), entries.size()])
	var seen: Dictionary = {}
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			failures.append("Manifest asset entry must be a Dictionary.")
			continue
		var entry: Dictionary = entry_value
		var path := String(entry.get("path", ""))
		if not EXPECTED.has(path):
			failures.append("Unexpected asset path: %s" % path)
			continue
		if seen.has(path):
			failures.append("Duplicate asset path: %s" % path)
			continue
		seen[path] = true
		_validate_entry(path, entry, failures)
	for expected_path: String in EXPECTED:
		if not seen.has(expected_path):
			failures.append("Manifest is missing asset: %s" % expected_path)
	_validate_active_sprite_runs(manifest, failures)
	return failures


func _validate_active_sprite_runs(manifest: Dictionary, failures: Array[String]) -> void:
	var catalog_failures: PackedStringArray = PRESENTATION_ASSETS_SCRIPT.validate_catalog(MANIFEST_PATH)
	for failure: String in catalog_failures:
		failures.append(failure)
	var runs_value: Variant = manifest.get("active_sprite_runs", {})
	if not runs_value is Dictionary:
		return
	var runs: Dictionary = runs_value
	for id_value: Variant in runs.keys():
		var asset_id := String(id_value)
		var entry_value: Variant = runs[id_value]
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if String(entry.get("license", "")) != "LicenseRef-PixelNightShift-Original":
			failures.append("Sprite run '%s' has an unexpected license." % asset_id)
		if String(entry.get("sprite_gen_version", "")).is_empty():
			failures.append("Sprite run '%s' is missing sprite_gen_version provenance." % asset_id)
		var run_manifest_path := String(entry.get("manifest_path", ""))
		var run_manifest := _read_json(run_manifest_path, "sprite run '%s' manifest" % asset_id, failures)
		if run_manifest.is_empty():
			continue
		var run_dir := run_manifest_path.get_base_dir()
		_validate_required_file(run_dir.path_join("sprite-request.json"), asset_id, failures)
		_validate_required_file(run_dir.path_join(String(run_manifest.get("base_image", ""))), asset_id, failures)
		_validate_required_file(run_dir.path_join("qa-notes.md"), asset_id, failures)
		_validate_required_file(run_dir.path_join("qa/all-contact.png"), asset_id, failures)
		var frames_report := _read_json(
			run_dir.path_join("frames/frames-manifest.json"),
			"sprite run '%s' frame report" % asset_id,
			failures
		)
		if not frames_report.is_empty() and not bool(frames_report.get("ok", false)):
			failures.append("Sprite run '%s' frame report is not ok." % asset_id)
		var atlas_report_path := run_dir.path_join(
			String(run_manifest.get("sprite_sheet_alpha_report", ""))
		)
		var atlas_report := _read_json(
			atlas_report_path,
			"sprite run '%s' atlas report" % asset_id,
			failures
		)
		if not atlas_report.is_empty() and not bool(atlas_report.get("ok", false)):
			failures.append("Sprite run '%s' atlas report is not ok." % asset_id)
		var animation_value: Variant = run_manifest.get("animation", {})
		if not animation_value is Dictionary:
			continue
		var animation: Dictionary = animation_value
		var rows_value: Variant = animation.get("rows", {})
		if not rows_value is Dictionary:
			continue
		var rows: Dictionary = rows_value
		var cell_value: Variant = run_manifest.get("cell", {})
		if not cell_value is Dictionary:
			failures.append("Sprite run '%s' cell must be a Dictionary." % asset_id)
			continue
		var cell: Dictionary = cell_value
		var cell_width := int(cell.get("width", 0))
		var cell_height := int(cell.get("height", 0))
		var safe_margin_x := int(cell.get("safe_margin_x", cell.get("safe_margin", 0)))
		var safe_margin_y := int(cell.get("safe_margin_y", cell.get("safe_margin", 0)))
		for state_value: Variant in rows.keys():
			var state := String(state_value)
			_validate_required_file(run_dir.path_join("prompts/%s.txt" % state), asset_id, failures)
			_validate_required_file(run_dir.path_join("raw/%s.png" % state), asset_id, failures)
			_validate_required_file(
				run_dir.path_join("references/layout-guides/%s.png" % state),
				asset_id,
				failures
			)
			_validate_required_file(run_dir.path_join("qa/%s-contact.png" % state), asset_id, failures)
			_validate_required_file(run_dir.path_join("qa/%s.gif" % state), asset_id, failures)
			var metadata_value: Variant = rows[state_value]
			if not metadata_value is Dictionary:
				failures.append("Sprite run '%s' state '%s' metadata must be a Dictionary." % [asset_id, state])
				continue
			var metadata: Dictionary = metadata_value
			var frame_count := int(metadata.get("frames", 0))
			if frame_count <= 0:
				failures.append("Sprite run '%s' state '%s' has no declared frames." % [asset_id, state])
				continue
			for frame_index: int in range(frame_count):
				_validate_sprite_frame(
					run_dir.path_join("frames/%s/frame-%d.png" % [state, frame_index]),
					asset_id,
					state,
					frame_index,
					cell_width,
					cell_height,
					safe_margin_x,
					safe_margin_y,
					failures
				)


func _validate_required_file(path: String, asset_id: String, failures: Array[String]) -> void:
	if path.get_file().is_empty() or not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		failures.append("Sprite run '%s' is missing required file: %s" % [asset_id, path])


func _validate_sprite_frame(
	path: String,
	asset_id: String,
	state: String,
	frame_index: int,
	expected_width: int,
	expected_height: int,
	safe_margin_x: int,
	safe_margin_y: int,
	failures: Array[String]
) -> void:
	var context := "Sprite run '%s' state '%s' frame %d" % [asset_id, state, frame_index]
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		failures.append("%s is missing: %s" % [context, path])
		return
	var image := Image.new()
	var load_error := image.load(absolute_path)
	if load_error != OK:
		failures.append("%s could not be loaded (error %d)." % [context, load_error])
		return
	if image.get_width() != expected_width or image.get_height() != expected_height:
		failures.append(
			"%s must be %dx%d, got %dx%d."
			% [context, expected_width, expected_height, image.get_width(), image.get_height()]
		)
		return
	var palette: Dictionary = {}
	var opaque_pixels: Dictionary = {}
	var partial_alpha_pixels := 0
	var min_x := expected_width
	var min_y := expected_height
	var max_x := -1
	var max_y := -1
	var edge_pixels := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			palette[color.to_rgba32()] = true
			if color.a <= 0.0:
				continue
			if color.a < 1.0:
				partial_alpha_pixels += 1
				continue
			var point := Vector2i(x, y)
			opaque_pixels[point] = true
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
			if x == 0 or y == 0 or x == image.get_width() - 1 or y == image.get_height() - 1:
				edge_pixels += 1
	if opaque_pixels.is_empty():
		failures.append("%s has no opaque subject pixels." % context)
		return
	if partial_alpha_pixels > 0:
		failures.append("%s has %d partially transparent pixels." % [context, partial_alpha_pixels])
	if palette.size() > 12:
		failures.append("%s has %d RGBA colors; limit is 12." % [context, palette.size()])
	if edge_pixels > 0:
		failures.append("%s has %d visible edge pixels." % [context, edge_pixels])
	if (
		min_x < safe_margin_x
		or min_y < safe_margin_y
		or max_x > expected_width - safe_margin_x
		or max_y > expected_height - safe_margin_y
	):
		failures.append(
			"%s bbox (%d,%d)-(%d,%d) violates safe margins (%d,%d)."
			% [context, min_x, min_y, max_x, max_y, safe_margin_x, safe_margin_y]
		)
	var component_count := _count_opaque_components(opaque_pixels)
	if component_count != 1:
		failures.append("%s has %d disconnected opaque components; expected 1." % [context, component_count])


func _count_opaque_components(opaque_pixels: Dictionary) -> int:
	var remaining := opaque_pixels.duplicate()
	var component_count := 0
	var offsets: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	while not remaining.is_empty():
		component_count += 1
		var first_point: Vector2i = remaining.keys()[0]
		remaining.erase(first_point)
		var frontier: Array[Vector2i] = [first_point]
		while not frontier.is_empty():
			var point: Vector2i = frontier.pop_back()
			for offset: Vector2i in offsets:
				var neighbor: Vector2i = point + offset
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					frontier.append(neighbor)
	return component_count


func _read_json(path: String, context: String, failures: Array[String]) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		failures.append("Missing %s: %s" % [context, path])
		return {}
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null:
		failures.append("Could not read %s: %s" % [context, path])
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		failures.append("Invalid JSON in %s: %s" % [context, path])
		return {}
	var data: Dictionary = parser.data
	return data


func _validate_entry(path: String, entry: Dictionary, failures: Array[String]) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		failures.append("Missing PNG: %s" % path)
		return
	var image := Image.new()
	var load_error := image.load(absolute_path)
	if load_error != OK:
		failures.append("Could not load PNG %s (error %d)." % [path, load_error])
		return
	var expected_size: Array = EXPECTED[path]
	var expected_width := int(expected_size[0])
	var expected_height := int(expected_size[1])
	if image.get_width() != expected_width or image.get_height() != expected_height:
		failures.append(
			"Wrong dimensions for %s: expected %dx%d, got %dx%d."
			% [path, expected_width, expected_height, image.get_width(), image.get_height()]
		)
	if int(entry.get("width", 0)) != expected_width or int(entry.get("height", 0)) != expected_height:
		failures.append("Manifest dimensions do not match expected dimensions for %s." % path)
	var expected_hash := String(entry.get("sha256", ""))
	var actual_hash := FileAccess.get_sha256(absolute_path)
	if expected_hash.is_empty() or expected_hash != actual_hash:
		failures.append("SHA-256 mismatch for %s." % path)
	_validate_pixels(path, image, failures)


func _validate_pixels(path: String, image: Image, failures: Array[String]) -> void:
	var palette: Dictionary = {}
	var opaque_pixels := 0
	var transparent_pixels := 0
	var partial_alpha_pixels := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			palette[color.to_rgba32()] = true
			if color.a <= 0.0:
				transparent_pixels += 1
			elif color.a >= 1.0:
				opaque_pixels += 1
			else:
				partial_alpha_pixels += 1
	if opaque_pixels == 0:
		failures.append("Asset has no visible pixels: %s" % path)
	if partial_alpha_pixels > 0:
		failures.append("Asset contains %d partially transparent pixels: %s" % [partial_alpha_pixels, path])
	if path.contains("/backgrounds/"):
		if transparent_pixels > 0:
			failures.append("Background must be fully opaque: %s" % path)
	elif transparent_pixels == 0:
		failures.append("Sprite/icon must preserve a transparent background: %s" % path)
	var palette_limit := 16 if path.contains("/backgrounds/") else 12
	if palette.size() > palette_limit:
		failures.append(
			"Palette is too large for %s: %d colors (limit %d)."
			% [path, palette.size(), palette_limit]
		)
