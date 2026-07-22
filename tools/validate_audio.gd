extends SceneTree

const MANIFEST_PATH := "res://game/assets/audio/manifest.json"
const EXPECTED_PATHS: PackedStringArray = [
	"game/assets/audio/bgm/night_shift_loop.ogg",
	"game/assets/audio/bgm/watchdog_loop.ogg",
	"game/assets/audio/bgm/maintenance_loop.wav",
	"game/assets/audio/sfx/ui_move.ogg",
	"game/assets/audio/sfx/ui_confirm.ogg",
	"game/assets/audio/sfx/ui_error.ogg",
	"game/assets/audio/sfx/enemy_break.wav",
	"game/assets/audio/sfx/combat_hit.wav",
	"game/assets/audio/sfx/stage_clear.ogg",
	"game/assets/audio/sfx/operator_upgrade.wav",
	"game/assets/audio/sfx/patch_apply.ogg",
	"game/assets/audio/sfx/patch_remove.ogg",
	"game/assets/audio/sfx/boss_warning.wav",
	"game/assets/audio/sfx/maintenance_enter.ogg",
	"game/assets/audio/sfx/update_ready.ogg",
	"game/assets/audio/sfx/version_update.ogg",
]


func _init() -> void:
	var failures := _validate()
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		push_error("Audio validation failed with %d issue(s)." % failures.size())
		quit(1)
		return
	print("Validated %d final audio assets." % EXPECTED_PATHS.size())
	quit(0)


func _validate() -> Array[String]:
	var failures: Array[String] = []
	var manifest_text := FileAccess.get_file_as_string(MANIFEST_PATH)
	if manifest_text.is_empty():
		failures.append("Missing or empty audio manifest: %s" % MANIFEST_PATH)
		return failures
	var parsed: Variant = JSON.parse_string(manifest_text)
	if not (parsed is Dictionary):
		failures.append("Audio manifest root must be a Dictionary.")
		return failures
	var manifest: Dictionary = parsed
	if int(manifest.get("schema_version", 0)) != 2:
		failures.append("Audio manifest schema_version must be 2.")
	if int(manifest.get("generated_sample_rate_hz", 0)) != 22_050:
		failures.append("Generated audio sample rate must be 22050 Hz.")
	if String(manifest.get("provenance", "")).is_empty():
		failures.append("Audio manifest must state provenance.")

	var files_value: Variant = manifest.get("files", [])
	if not (files_value is Array):
		failures.append("Audio manifest files must be an Array.")
		return failures
	var files: Array = files_value
	if files.size() != EXPECTED_PATHS.size():
		failures.append("Expected %d audio entries, got %d." % [EXPECTED_PATHS.size(), files.size()])

	var seen: Dictionary = {}
	for entry_value: Variant in files:
		if not (entry_value is Dictionary):
			failures.append("Audio manifest entry must be a Dictionary.")
			continue
		var entry: Dictionary = entry_value
		var relative_path := String(entry.get("file", ""))
		if not EXPECTED_PATHS.has(relative_path):
			failures.append("Unexpected audio path: %s" % relative_path)
			continue
		if seen.has(relative_path):
			failures.append("Duplicate audio path: %s" % relative_path)
			continue
		seen[relative_path] = true
		_validate_entry(relative_path, entry, failures)
	for expected_path: String in EXPECTED_PATHS:
		if not seen.has(expected_path):
			failures.append("Audio manifest is missing: %s" % expected_path)
	return failures


func _validate_entry(relative_path: String, entry: Dictionary, failures: Array[String]) -> void:
	var resource_path := "res://%s" % relative_path
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		failures.append("Missing audio file: %s" % resource_path)
		return
	if FileAccess.get_sha256(absolute_path) != String(entry.get("sha256", "")):
		failures.append("SHA-256 mismatch for %s" % resource_path)
	if float(entry.get("duration_seconds", 0.0)) <= 0.05:
		failures.append("Audio duration is too short for %s" % resource_path)
	var source_type := String(entry.get("source_type", ""))
	if source_type not in ["generated", "external"]:
		failures.append("Unknown source_type for %s: %s" % [resource_path, source_type])
		return
	if String(entry.get("license", "")).is_empty():
		failures.append("Audio entry must state a license: %s" % resource_path)
	var resource: Resource = load(resource_path)
	if not (resource is AudioStream):
		failures.append("Audio resource did not load: %s" % resource_path)
		return
	if source_type == "external":
		if not (resource is AudioStreamOggVorbis):
			failures.append("External music must load as AudioStreamOggVorbis: %s" % resource_path)
		if String(entry.get("source_url", "")).is_empty():
			failures.append("External audio must include source_url: %s" % resource_path)
		if String(entry.get("author", "")).is_empty():
			failures.append("External audio must include author: %s" % resource_path)
		return
	if not (resource is AudioStreamWAV):
		failures.append("Generated audio is not AudioStreamWAV: %s" % resource_path)
		return
	var stream := resource as AudioStreamWAV
	if stream.mix_rate != 22_050:
		failures.append("Wrong sample rate for %s: %d" % [resource_path, stream.mix_rate])
	if stream.stereo:
		failures.append("Generated audio must remain mono: %s" % resource_path)
	if stream.data.is_empty():
		failures.append("Audio stream has no PCM data: %s" % resource_path)
