extends SceneTree

const MANIFEST_PATH := "res://game/assets/audio/manifest.json"
const EXPECTED_PATHS: PackedStringArray = [
	"game/assets/audio/bgm/night_shift_loop.wav",
	"game/assets/audio/bgm/watchdog_loop.wav",
	"game/assets/audio/bgm/maintenance_loop.wav",
	"game/assets/audio/sfx/ui_move.wav",
	"game/assets/audio/sfx/ui_confirm.wav",
	"game/assets/audio/sfx/ui_error.wav",
	"game/assets/audio/sfx/enemy_break.wav",
	"game/assets/audio/sfx/stage_clear.wav",
	"game/assets/audio/sfx/operator_upgrade.wav",
	"game/assets/audio/sfx/patch_apply.wav",
	"game/assets/audio/sfx/patch_remove.wav",
	"game/assets/audio/sfx/boss_warning.wav",
	"game/assets/audio/sfx/maintenance_enter.wav",
	"game/assets/audio/sfx/update_ready.wav",
	"game/assets/audio/sfx/version_update.wav",
]


func _init() -> void:
	var failures := _validate()
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		push_error("Audio validation failed with %d issue(s)." % failures.size())
		quit(1)
		return
	print("Validated %d generated audio assets." % EXPECTED_PATHS.size())
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
	if int(manifest.get("schema_version", 0)) != 1:
		failures.append("Audio manifest schema_version must be 1.")
	if int(manifest.get("sample_rate_hz", 0)) != 22_050:
		failures.append("Audio manifest sample rate must be 22050 Hz.")
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
		failures.append("Missing WAV: %s" % resource_path)
		return
	if FileAccess.get_sha256(absolute_path) != String(entry.get("sha256", "")):
		failures.append("SHA-256 mismatch for %s" % resource_path)
	if float(entry.get("duration_seconds", 0.0)) <= 0.05:
		failures.append("Audio duration is too short for %s" % resource_path)
	var resource: Resource = load(resource_path)
	if not (resource is AudioStreamWAV):
		failures.append("Audio resource is not AudioStreamWAV: %s" % resource_path)
		return
	var stream := resource as AudioStreamWAV
	if stream.mix_rate != 22_050:
		failures.append("Wrong sample rate for %s: %d" % [resource_path, stream.mix_rate])
	if stream.stereo:
		failures.append("Prototype audio must remain mono: %s" % resource_path)
	if stream.data.is_empty():
		failures.append("Audio stream has no PCM data: %s" % resource_path)
