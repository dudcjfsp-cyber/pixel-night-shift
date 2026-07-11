extends SceneTree

## Validates dimensions, hashes, palette shape, and alpha discipline for every
## generated pixel asset declared by the manifest.

const MANIFEST_PATH := "res://game/assets/manifest.json"
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
	print("Validated %d generated pixel assets." % EXPECTED.size())
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
	if manifest.get("schema_version", 0) != 1:
		failures.append("Manifest schema_version must be 1.")
	if manifest.get("generator", "") != "res://tools/generate_pixel_assets.gd":
		failures.append("Manifest generator path is unexpected.")
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
	return failures


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
