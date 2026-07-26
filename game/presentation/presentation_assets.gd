class_name PresentationAssets
extends RefCounted

const ROOT_MANIFEST_PATH := "res://game/assets/manifest.json"
const SUPPORTED_ROOT_SCHEMA := 2
const SUPPORTED_SPRITE_MANIFEST_CONTRACT := 1

const OPERATOR_TEXTURES: Dictionary = {
	&"debugger": preload("res://game/assets/generated/operators/debugger.png"),
	&"build_engineer": preload("res://game/assets/generated/operators/build_engineer.png"),
	&"sprite_artist": preload("res://game/assets/generated/operators/sprite_artist.png"),
	&"qa_imp": preload("res://game/assets/generated/operators/qa_imp.png"),
}

const ACTIVE_SPRITE_TEXTURES: Dictionary = {
	&"broken_pixel": preload(
		"res://game/assets/generated/sprites/broken_pixel/sprite-sheet-alpha.png"
	),
	&"build_engineer": preload(
		"res://game/assets/generated/sprites/build_engineer/sprite-sheet-alpha.png"
	),
	&"debugger": preload(
		"res://game/assets/generated/sprites/debugger/sprite-sheet-alpha.png"
	),
	&"qa_imp": preload(
		"res://game/assets/generated/sprites/qa_imp/sprite-sheet-alpha.png"
	),
	&"sprite_artist": preload(
		"res://game/assets/generated/sprites/sprite_artist/sprite-sheet-alpha.png"
	),
}

const PATCH_TEXTURES: Dictionary = {
	&"frame_skip": preload("res://game/assets/generated/patches/frame_skip.png"),
	&"unsafe_build": preload("res://game/assets/generated/patches/unsafe_build.png"),
	&"reward_bypass": preload("res://game/assets/generated/patches/reward_bypass.png"),
	&"rollback_lock": preload("res://game/assets/generated/patches/rollback_lock.png"),
	&"safe_mode": preload("res://game/assets/generated/patches/safe_mode.png"),
}

const ENEMY_TEXTURES: Dictionary = {
	&"broken_pixel": preload("res://game/assets/generated/enemies/broken_pixel.png"),
	&"infinite_loop": preload("res://game/assets/generated/enemies/infinite_loop.png"),
	&"missing_resource": preload("res://game/assets/generated/enemies/missing_resource.png"),
	&"maintenance_error": preload("res://game/assets/generated/enemies/maintenance_error.png"),
	&"watchdog_process": preload("res://game/assets/generated/enemies/watchdog_process.png"),
}

const UI_TEXTURES: Dictionary = {
	&"bit": preload("res://game/assets/generated/ui/bit.png"),
	&"patch_note": preload("res://game/assets/generated/ui/patch_note.png"),
	&"stage": preload("res://game/assets/generated/ui/stage.png"),
	&"diagnosis": preload("res://game/assets/generated/ui/diagnosis.png"),
	&"combat": preload("res://game/assets/generated/ui/combat.png"),
	&"boss": preload("res://game/assets/generated/ui/boss.png"),
	&"maintenance": preload("res://game/assets/generated/ui/maintenance.png"),
	&"complete": preload("res://game/assets/generated/ui/complete.png"),
}

const BATTLE_BACKGROUND: Texture2D = preload(
	"res://game/assets/generated/backgrounds/battle_server_room.png"
)
const TITLE_BACKGROUND: Texture2D = preload(
	"res://game/assets/opening/title_background.png"
)
const CITY_NETWORK_BACKGROUND: Texture2D = preload(
	"res://game/assets/opening/city_network.png"
)

static var _initialized := false
static var _initialization_errors := PackedStringArray()
static var _sprite_runs: Dictionary = {}


static func initialize() -> PackedStringArray:
	if _initialized:
		return _initialization_errors.duplicate()
	_initialized = true
	_sprite_runs.clear()
	_initialization_errors = PackedStringArray(_load_catalog(ROOT_MANIFEST_PATH, _sprite_runs))
	return _initialization_errors.duplicate()


static func validate_catalog(manifest_path: String) -> PackedStringArray:
	var validated_runs: Dictionary = {}
	return PackedStringArray(_load_catalog(manifest_path, validated_runs))


static func is_sprite_run_active(asset_id: StringName) -> bool:
	return _is_ready() and _sprite_runs.has(asset_id)


static func make_operator_frames(operator_id: StringName) -> SpriteFrames:
	if not _is_ready():
		return null
	if _sprite_runs.has(operator_id):
		return _make_sprite_frames(operator_id)
	if not OPERATOR_TEXTURES.has(operator_id):
		push_error("Unknown operator asset id: %s" % operator_id)
		return null
	return _make_static_frames(OPERATOR_TEXTURES[operator_id] as Texture2D)


static func operator_idle_texture(operator_id: StringName) -> Texture2D:
	var frames := make_operator_frames(operator_id)
	if frames == null or not frames.has_animation(&"idle"):
		return null
	return frames.get_frame_texture(&"idle", 0)


static func operator_texture(operator_id: StringName) -> Texture2D:
	if not _is_ready():
		return null
	if _sprite_runs.has(operator_id):
		return operator_idle_texture(operator_id)
	if not OPERATOR_TEXTURES.has(operator_id):
		push_error("Unknown operator asset id: %s" % operator_id)
		return null
	return OPERATOR_TEXTURES[operator_id] as Texture2D


static func patch_texture(patch_id: StringName) -> Texture2D:
	if not PATCH_TEXTURES.has(patch_id):
		push_error("Unknown patch asset id: %s" % patch_id)
		return null
	return PATCH_TEXTURES[patch_id] as Texture2D


static func ui_texture(icon_id: StringName) -> Texture2D:
	if not UI_TEXTURES.has(icon_id):
		push_error("Unknown UI asset id: %s" % icon_id)
		return null
	return UI_TEXTURES[icon_id] as Texture2D


static func enemy_id(stage: int, is_boss: bool, mode: String) -> StringName:
	if is_boss:
		return &"watchdog_process"
	if mode == "maintenance":
		return &"maintenance_error"
	var normal_ids: Array[StringName] = [
		&"broken_pixel",
		&"infinite_loop",
		&"missing_resource",
	]
	return normal_ids[posmod(stage - 1, normal_ids.size())]


static func make_enemy_frames(stage: int, is_boss: bool, mode: String) -> SpriteFrames:
	if not _is_ready():
		return null
	var asset_id := enemy_id(stage, is_boss, mode)
	if _sprite_runs.has(asset_id):
		return _make_sprite_frames(asset_id)
	if not ENEMY_TEXTURES.has(asset_id):
		push_error("Unknown enemy asset id: %s" % asset_id)
		return null
	return _make_static_frames(ENEMY_TEXTURES[asset_id] as Texture2D)


static func enemy_texture(stage: int, is_boss: bool, mode: String) -> Texture2D:
	var frames := make_enemy_frames(stage, is_boss, mode)
	if frames == null:
		return null
	return frames.get_frame_texture(&"idle", 0)


static func sprite_cell_size(asset_id: StringName) -> Vector2i:
	if not _is_ready():
		return Vector2i.ZERO
	if _sprite_runs.has(asset_id):
		var run: Dictionary = _sprite_runs[asset_id]
		var manifest: Dictionary = run["manifest"]
		var cell: Dictionary = manifest["cell"]
		return Vector2i(int(cell["width"]), int(cell["height"]))
	return Vector2i(48, 48) if asset_id == &"watchdog_process" else Vector2i(32, 32)


static func mode_texture(mode: String) -> Texture2D:
	var mode_id: StringName = StringName(mode)
	if not UI_TEXTURES.has(mode_id):
		push_error("Unknown presentation mode: %s" % mode)
		return null
	return UI_TEXTURES[mode_id] as Texture2D


static func _is_ready() -> bool:
	if not _initialized:
		initialize()
	if _initialization_errors.is_empty():
		return true
	push_error("Presentation assets are unavailable:\n%s" % "\n".join(_initialization_errors))
	return false


static func _load_catalog(manifest_path: String, out_runs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var root_manifest := _load_json_dictionary(manifest_path, "asset catalog", errors)
	if root_manifest.is_empty():
		return errors
	var schema := int(root_manifest.get("schema_version", 0))
	if schema > SUPPORTED_ROOT_SCHEMA:
		errors.append(
			"Asset catalog %s uses newer schema %d; supported schema is %d."
			% [manifest_path, schema, SUPPORTED_ROOT_SCHEMA]
		)
		return errors
	if schema != SUPPORTED_ROOT_SCHEMA:
		errors.append(
			"Asset catalog %s must use schema %d, got %d."
			% [manifest_path, SUPPORTED_ROOT_SCHEMA, schema]
		)
		return errors
	var runs_value: Variant = root_manifest.get("active_sprite_runs", {})
	if not runs_value is Dictionary:
		errors.append("Asset catalog %s active_sprite_runs must be a Dictionary." % manifest_path)
		return errors
	var runs: Dictionary = runs_value
	for id_value: Variant in runs.keys():
		var asset_id := StringName(String(id_value))
		var entry_value: Variant = runs[id_value]
		if not entry_value is Dictionary:
			errors.append("Active sprite '%s' catalog entry must be a Dictionary." % asset_id)
			continue
		_validate_run(asset_id, entry_value, out_runs, errors)
	return errors


static func _validate_run(
	asset_id: StringName,
	entry: Dictionary,
	out_runs: Dictionary,
	errors: Array[String]
) -> void:
	var context := "Active sprite '%s'" % asset_id
	var initial_error_count := errors.size()
	var contract := int(entry.get("manifest_contract", 0))
	if contract > SUPPORTED_SPRITE_MANIFEST_CONTRACT:
		errors.append(
			"%s uses newer manifest contract %d; supported contract is %d."
			% [context, contract, SUPPORTED_SPRITE_MANIFEST_CONTRACT]
		)
		return
	if contract != SUPPORTED_SPRITE_MANIFEST_CONTRACT:
		errors.append("%s manifest_contract must be 1." % context)
		return
	var category := String(entry.get("category", ""))
	if category not in ["operator", "enemy", "boss"]:
		errors.append("%s has unsupported category '%s'." % [context, category])
		return
	if category == "operator" and not OPERATOR_TEXTURES.has(asset_id):
		errors.append("%s does not match a known operator id." % context)
		return
	if category in ["enemy", "boss"] and not ENEMY_TEXTURES.has(asset_id):
		errors.append("%s does not match a known enemy id." % context)
		return
	if asset_id == &"watchdog_process" and category != "boss":
		errors.append("%s must use category 'boss'." % context)
		return
	if asset_id != &"watchdog_process" and category == "boss":
		errors.append("%s is not the supported boss id." % context)
		return
	var manifest_path := String(entry.get("manifest_path", ""))
	var expected_prefix := "res://game/assets/generated/sprites/%s/" % asset_id
	if (
		manifest_path.is_empty()
		or not manifest_path.begins_with(expected_prefix)
		or manifest_path.contains("..")
		or manifest_path.get_extension().to_lower() != "json"
	):
		errors.append("%s has unsafe manifest_path '%s'." % [context, manifest_path])
		return
	if not _validate_hash(manifest_path, String(entry.get("manifest_sha256", "")), context, errors):
		return
	var manifest := _load_json_dictionary(manifest_path, context + " manifest", errors)
	if manifest.is_empty():
		return
	if String(manifest.get("characterId", "")) != String(asset_id):
		errors.append("%s manifest characterId does not match its catalog id." % context)
	if String(manifest.get("engine", "")) != "component-row":
		errors.append("%s manifest engine must be component-row." % context)
	if bool(manifest.get("degraded_static_fallback", true)):
		errors.append("%s manifest must not be a degraded static fallback." % context)
	if String(manifest.get("frame_variant", "")) != "pixel":
		errors.append("%s must use the canonical pixel frame variant." % context)
	var game_input := String(manifest.get("game_input", ""))
	if game_input.is_empty() or game_input.get_file() != game_input or game_input.contains(".."):
		errors.append("%s has unsafe game_input '%s'." % [context, game_input])
		return
	var atlas_path := manifest_path.get_base_dir().path_join(game_input)
	if not _validate_imported_resource_hash(
		atlas_path,
		String(entry.get("atlas_sha256", "")),
		context,
		errors
	):
		return
	var cell_value: Variant = manifest.get("cell", {})
	var animation_value: Variant = manifest.get("animation", {})
	var layout_value: Variant = manifest.get("frame_layout", {})
	if not cell_value is Dictionary or not animation_value is Dictionary or not layout_value is Dictionary:
		errors.append("%s manifest cell, animation, and frame_layout must be Dictionaries." % context)
		return
	var cell: Dictionary = cell_value
	var animation: Dictionary = animation_value
	var layout: Dictionary = layout_value
	var expected_cell := 48 if category == "boss" else 32
	var cell_width := _positive_int(cell.get("width"), context + " cell.width", errors)
	var cell_height := _positive_int(cell.get("height"), context + " cell.height", errors)
	var sheet_width := _positive_int(layout.get("sheetWidth"), context + " sheetWidth", errors)
	var sheet_height := _positive_int(layout.get("sheetHeight"), context + " sheetHeight", errors)
	if cell_width != expected_cell or cell_height != expected_cell:
		errors.append(
			"%s cell must be %dx%d, got %dx%d."
			% [context, expected_cell, expected_cell, cell_width, cell_height]
		)
	if int(layout.get("cellWidth", 0)) != cell_width or int(layout.get("cellHeight", 0)) != cell_height:
		errors.append("%s frame_layout cell dimensions do not match cell." % context)
	if int(animation.get("cellWidth", 0)) != cell_width or int(animation.get("cellHeight", 0)) != cell_height:
		errors.append("%s animation cell dimensions do not match cell." % context)
	var animation_rows_value: Variant = animation.get("rows", {})
	var layout_rows_value: Variant = layout.get("rows", {})
	if not animation_rows_value is Dictionary or not layout_rows_value is Dictionary:
		errors.append("%s animation.rows and frame_layout.rows must be Dictionaries." % context)
		return
	var animation_rows: Dictionary = animation_rows_value
	var layout_rows: Dictionary = layout_rows_value
	var required_states: Array[StringName] = []
	required_states.append(&"idle")
	required_states.append(&"upgrade" if category == "operator" else &"hurt")
	if animation_rows.size() != required_states.size() or layout_rows.size() != required_states.size():
		errors.append("%s must define exactly the required states: %s." % [context, required_states])
	for state_name: StringName in required_states:
		_validate_state(
			context,
			state_name,
			animation_rows,
			layout_rows,
			sheet_width,
			sheet_height,
			cell_width,
			cell_height,
			errors
		)
	if not ACTIVE_SPRITE_TEXTURES.has(asset_id):
		errors.append("%s has no packaged active atlas." % context)
		return
	var atlas_resource: Resource = ACTIVE_SPRITE_TEXTURES[asset_id]
	if not atlas_resource is Texture2D or atlas_resource.resource_path != atlas_path:
		errors.append("%s atlas is not a Texture2D: %s" % [context, atlas_path])
		return
	var atlas := atlas_resource as Texture2D
	if atlas.get_size() != Vector2(sheet_width, sheet_height):
		errors.append(
			"%s atlas dimensions must be %dx%d, got %s."
			% [context, sheet_width, sheet_height, atlas.get_size()]
		)
	if errors.size() > initial_error_count:
		return
	out_runs[asset_id] = {
		"category": category,
		"manifest_path": manifest_path,
		"manifest": manifest,
		"atlas": atlas,
	}


static func _validate_state(
	context: String,
	state_name: StringName,
	animation_rows: Dictionary,
	layout_rows: Dictionary,
	sheet_width: int,
	sheet_height: int,
	cell_width: int,
	cell_height: int,
	errors: Array[String]
) -> void:
	var state_key := String(state_name)
	if not animation_rows.has(state_key) or not layout_rows.has(state_key):
		errors.append("%s is missing required state '%s'." % [context, state_key])
		return
	var metadata_value: Variant = animation_rows[state_key]
	var rects_value: Variant = layout_rows[state_key]
	if not metadata_value is Dictionary or not rects_value is Array:
		errors.append("%s state '%s' metadata/rects have invalid types." % [context, state_key])
		return
	var metadata: Dictionary = metadata_value
	var rects: Array = rects_value
	var frame_count := _positive_int(metadata.get("frames"), context + " " + state_key + ".frames", errors)
	var fps := _positive_number(metadata.get("fps"), context + " " + state_key + ".fps", errors)
	if fps <= 0.0:
		return
	if not metadata.get("loop") is bool:
		errors.append("%s state '%s' loop must be a bool." % [context, state_key])
	if frame_count != rects.size():
		errors.append(
			"%s state '%s' declares %d frames but has %d rects."
			% [context, state_key, frame_count, rects.size()]
		)
	var seen_rects: Dictionary = {}
	for index: int in range(rects.size()):
		var rect_value: Variant = rects[index]
		if not rect_value is Dictionary:
			errors.append("%s state '%s' rect %d must be a Dictionary." % [context, state_key, index])
			continue
		var rect: Dictionary = rect_value
		var x := _nonnegative_int(rect.get("x"), "%s %s rect %d x" % [context, state_key, index], errors)
		var y := _nonnegative_int(rect.get("y"), "%s %s rect %d y" % [context, state_key, index], errors)
		var width := _positive_int(rect.get("w"), "%s %s rect %d w" % [context, state_key, index], errors)
		var height := _positive_int(rect.get("h"), "%s %s rect %d h" % [context, state_key, index], errors)
		var absolute_rect := Rect2i(x, y, width, height)
		if seen_rects.has(absolute_rect):
			errors.append("%s state '%s' rect %d duplicates another frame rect." % [context, state_key, index])
		seen_rects[absolute_rect] = true
		if width != cell_width or height != cell_height:
			errors.append(
				"%s state '%s' rect %d must be %dx%d, got %dx%d."
				% [context, state_key, index, cell_width, cell_height, width, height]
			)
		if x + width > sheet_width or y + height > sheet_height:
			errors.append("%s state '%s' rect %d is outside the atlas bounds." % [context, state_key, index])


static func _make_sprite_frames(asset_id: StringName) -> SpriteFrames:
	var run: Dictionary = _sprite_runs[asset_id]
	var manifest: Dictionary = run["manifest"]
	var animation: Dictionary = manifest["animation"]
	var animation_rows: Dictionary = animation["rows"]
	var layout: Dictionary = manifest["frame_layout"]
	var layout_rows: Dictionary = layout["rows"]
	var atlas: Texture2D = run["atlas"]
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for state_value: Variant in animation_rows.keys():
		var state := StringName(String(state_value))
		var metadata: Dictionary = animation_rows[state_value]
		var rects: Array = layout_rows[String(state)]
		frames.add_animation(state)
		frames.set_animation_speed(state, float(metadata["fps"]))
		frames.set_animation_loop(state, bool(metadata["loop"]))
		for rect_value: Variant in rects:
			var rect: Dictionary = rect_value
			var frame := AtlasTexture.new()
			frame.atlas = atlas
			frame.region = Rect2(
				int(rect["x"]),
				int(rect["y"]),
				int(rect["w"]),
				int(rect["h"])
			)
			frame.filter_clip = true
			frames.add_frame(state, frame)
	return frames


static func _make_static_frames(texture: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 1.0)
	frames.set_animation_loop(&"idle", true)
	frames.add_frame(&"idle", texture)
	return frames


static func _load_json_dictionary(path: String, context: String, errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Missing %s: %s" % [context, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Could not read %s: %s" % [context, path])
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		errors.append(
			"Invalid JSON in %s %s at line %d: %s"
			% [context, path, parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not parser.data is Dictionary:
		errors.append("%s root must be a Dictionary: %s" % [context, path])
		return {}
	return parser.data


static func _validate_hash(
	path: String,
	expected_hash: String,
	context: String,
	errors: Array[String]
) -> bool:
	if not FileAccess.file_exists(path):
		errors.append("%s is missing file: %s" % [context, path])
		return false
	var actual_hash := FileAccess.get_sha256(ProjectSettings.globalize_path(path))
	if expected_hash.is_empty() or expected_hash != actual_hash:
		errors.append("%s SHA-256 mismatch for %s." % [context, path])
		return false
	return true


static func _validate_imported_resource_hash(
	path: String,
	expected_hash: String,
	context: String,
	errors: Array[String]
) -> bool:
	if FileAccess.file_exists(path):
		return _validate_hash(path, expected_hash, context, errors)
	if (
		not OS.has_feature("editor")
		and expected_hash.length() == 64
		and expected_hash.is_valid_hex_number(false)
	):
		return true
	errors.append("%s is missing file: %s" % [context, path])
	return false


static func _positive_int(value: Variant, context: String, errors: Array[String]) -> int:
	var result := _integer(value, context, errors)
	if result <= 0:
		errors.append("%s must be a positive integer." % context)
	return result


static func _nonnegative_int(value: Variant, context: String, errors: Array[String]) -> int:
	var result := _integer(value, context, errors)
	if result < 0:
		errors.append("%s must be a nonnegative integer." % context)
	return result


static func _integer(value: Variant, context: String, errors: Array[String]) -> int:
	if not (value is int or value is float):
		errors.append("%s must be an integer." % context)
		return -1
	var result := int(value)
	if float(result) != float(value):
		errors.append("%s must be an integer." % context)
		return -1
	return result


static func _positive_number(value: Variant, context: String, errors: Array[String]) -> float:
	if not (value is int or value is float):
		errors.append("%s must be a number." % context)
		return -1.0
	var result := float(value)
	if result <= 0.0:
		errors.append("%s must be positive." % context)
	return result
