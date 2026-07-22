extends SceneTree

const SAMPLE_RATE := 22050
const BGM_BARS := 8
const OUTPUT_ROOT := "res://game/assets/audio"
const GENERATOR_VERSION := "2.1.0"
const TARGET_PEAK := 0.82
const ORIGINAL_SFX_GENERATOR := "res://tools/generate_original_sfx.py"
const ORIGINAL_SFX_GENERATOR_VERSION := "1.0.0"
const ORIGINAL_SFX_TOOLCHAIN := "NumPy + Pedalboard"

const MUSIC_SPECS := [
	{
		"id": "maintenance_loop",
		"bpm": 76.0,
		"seed": 77213,
		"lead": [69, -1, -1, 72, -1, -1, 76, -1, 74, -1, -1, 69, -1, -1, 67, -1,
			65, -1, -1, 69, -1, -1, 72, -1, 71, -1, -1, 67, -1, 64, -1, -1],
		"harmony": [53, 57, 60, 64, 53, 57, 60, 64, 50, 53, 57, 60, 50, 53, 57, 60],
		"bass": [41, -1, -1, -1, 41, -1, -1, -1, 38, -1, -1, -1, 38, -1, -1, -1],
		"drum_density": 0,
		"lead_duty": 0.5,
	},
]

const PROJECT_ORIGINAL_SFX_SPECS := [
	{
		"file": "res://game/assets/audio/sfx/combat_hit.wav",
		"seed": 41_057,
	},
	{
		"file": "res://game/assets/audio/sfx/enemy_break.wav",
		"seed": 41_063,
	},
	{
		"file": "res://game/assets/audio/sfx/operator_upgrade.wav",
		"seed": 41_071,
	},
	{
		"file": "res://game/assets/audio/sfx/boss_warning.wav",
		"seed": 41_077,
	},
]

const EXTERNAL_AUDIO_SPECS := [
	{
		"file": "res://game/assets/audio/bgm/night_shift_loop.ogg",
		"author": "Wolfgang_ (Theodore Kerr)",
		"title": "8-Bit Battle Loop",
		"license": "CC0-1.0",
		"source_url": "https://opengameart.org/content/8-bit-battle-loop",
		"loop": true,
	},
	{
		"file": "res://game/assets/audio/bgm/watchdog_loop.ogg",
		"author": "MintoDog",
		"title": "8bit Action Boss Battle",
		"license": "CC0-1.0",
		"source_url": "https://opengameart.org/content/8bit-action-boss-battle",
		"loop": true,
	},
	{
		"file": "res://game/assets/audio/sfx/ui_move.ogg",
		"author": "Kenney",
		"title": "Digital Audio / phaserUp5.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/ui_confirm.ogg",
		"author": "Kenney",
		"title": "Digital Audio / pepSound1.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/ui_error.ogg",
		"author": "Kenney",
		"title": "Digital Audio / lowDown.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/stage_clear.ogg",
		"author": "Kenney",
		"title": "Digital Audio / threeTone1.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/patch_apply.ogg",
		"author": "Kenney",
		"title": "Digital Audio / phaseJump2.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/patch_remove.ogg",
		"author": "Kenney",
		"title": "Digital Audio / highDown.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/maintenance_enter.ogg",
		"author": "Kenney",
		"title": "Digital Audio / zapThreeToneDown.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/update_ready.ogg",
		"author": "Kenney",
		"title": "Digital Audio / powerUp3.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
	{
		"file": "res://game/assets/audio/sfx/version_update.ogg",
		"author": "Kenney",
		"title": "Digital Audio / powerUp12.ogg",
		"license": "CC0-1.0",
		"source_url": "https://kenney.nl/assets/digital-audio",
		"loop": false,
	},
]


func _init() -> void:
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var error := DirAccess.make_dir_recursive_absolute(output_absolute.path_join("bgm"))
	if error != OK:
		push_error("Unable to create BGM output directory: %s" % error_string(error))
		quit(1)
		return
	error = DirAccess.make_dir_recursive_absolute(output_absolute.path_join("sfx"))
	if error != OK:
		push_error("Unable to create SFX output directory: %s" % error_string(error))
		quit(1)
		return

	var entries: Array[Dictionary] = []
	for spec: Dictionary in EXTERNAL_AUDIO_SPECS:
		var external_entry := _external_manifest_entry(spec)
		if external_entry.is_empty():
			quit(1)
			return
		entries.append(external_entry)
	for spec: Dictionary in PROJECT_ORIGINAL_SFX_SPECS:
		var original_sfx_entry := _project_original_sfx_manifest_entry(spec)
		if original_sfx_entry.is_empty():
			quit(1)
			return
		entries.append(original_sfx_entry)
	for spec: Dictionary in MUSIC_SPECS:
		var samples := _render_music(spec)
		var resource_path := "%s/bgm/%s.wav" % [OUTPUT_ROOT, String(spec["id"])]
		if not _write_wav(resource_path, samples):
			quit(1)
			return
		entries.append(_manifest_entry(resource_path, samples.size(), true, int(spec["seed"])))

	var manifest := {
		"schema_version": 2,
		"generator": "res://tools/generate_audio.gd",
		"generator_version": GENERATOR_VERSION,
		"engine": "Godot 4.7",
		"generated_sample_rate_hz": SAMPLE_RATE,
		"generated_channels": 1,
		"generated_sample_format": "PCM signed 16-bit little-endian",
		"provenance": "Mixed final delivery: external CC0 music and utility SFX, plus project-original maintenance music and four deterministic SFX synthesized with NumPy and Pedalboard by res://tools/generate_original_sfx.py without source audio or external samples.",
		"license": "Per-file; see each entry and game/assets/audio/ATTRIBUTION.md.",
		"files": entries,
	}
	var manifest_path := output_absolute.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		push_error("Unable to write audio manifest: %s" % FileAccess.get_open_error())
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t", true, false) + "\n")
	manifest_file.close()
	print("Prepared %d final audio assets in %s" % [entries.size(), OUTPUT_ROOT])
	quit(0)


func _render_music(spec: Dictionary) -> PackedFloat32Array:
	var bpm := float(spec["bpm"])
	var step_seconds := 60.0 / bpm / 4.0
	var total_steps := BGM_BARS * 16
	var duration := step_seconds * float(total_steps)
	var frame_count := int(round(duration * SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["seed"])
	var lead_pattern: Array = spec["lead"]
	var harmony_pattern: Array = spec["harmony"]
	var bass_pattern: Array = spec["bass"]
	var drum_density := int(spec["drum_density"])
	var lead_duty := float(spec["lead_duty"])

	for frame: int in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var step_index := int(floor(time / step_seconds)) % total_steps
		var step_time := fposmod(time, step_seconds)
		var step_phase := step_time / step_seconds
		var gate := _note_envelope(step_phase, 0.045, 0.78)
		var lead_note := int(lead_pattern[step_index % lead_pattern.size()])
		var harmony_note := int(harmony_pattern[step_index % harmony_pattern.size()])
		var bass_note := int(bass_pattern[step_index % bass_pattern.size()])
		var mixed := 0.0
		if lead_note >= 0:
			var lead_frequency := _midi_frequency(lead_note)
			mixed += _pulse(time * lead_frequency, lead_duty) * gate * 0.16
		if harmony_note >= 0:
			var harmony_frequency := _midi_frequency(harmony_note)
			mixed += _pulse(time * harmony_frequency, 0.5) * gate * 0.085
		if bass_note >= 0:
			var bass_frequency := _midi_frequency(bass_note)
			mixed += _triangle(time * bass_frequency) * _note_envelope(step_phase, 0.025, 0.90) * 0.21

		var beat_step := step_index % 16
		var noise := rng.randf_range(-1.0, 1.0)
		if beat_step == 0 or beat_step == 8 or (drum_density >= 2 and (beat_step == 4 or beat_step == 12)):
			var kick_decay := exp(-step_time * 22.0)
			mixed += sin(TAU * (72.0 - 28.0 * step_phase) * step_time) * kick_decay * 0.20
		if drum_density > 0 and (beat_step == 4 or beat_step == 12):
			mixed += noise * exp(-step_time * 28.0) * 0.16
		var hat_interval := 1 if drum_density >= 2 else 2
		if drum_density > 0 and beat_step % hat_interval == 0:
			mixed += noise * exp(-step_time * 78.0) * 0.065
		if drum_density == 0 and beat_step == 12:
			mixed += noise * exp(-step_time * 42.0) * 0.035
		samples[frame] = mixed

	_fade_loop_edges(samples, 0.004)
	_normalize(samples, TARGET_PEAK)
	return samples


func _midi_frequency(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


func _pulse(cycles: float, duty: float) -> float:
	var raw := 1.0 if fposmod(cycles, 1.0) < duty else -1.0
	return raw - (2.0 * duty - 1.0)


func _triangle(cycles: float) -> float:
	return 1.0 - 4.0 * absf(fposmod(cycles, 1.0) - 0.5)


func _note_envelope(phase: float, attack_end: float, release_start: float) -> float:
	if phase < attack_end:
		return phase / attack_end
	if phase > release_start:
		return maxf(0.0, (1.0 - phase) / (1.0 - release_start))
	return 1.0


func _fade_loop_edges(samples: PackedFloat32Array, seconds: float) -> void:
	var fade_frames := mini(int(seconds * SAMPLE_RATE), samples.size() / 2)
	for index: int in range(fade_frames):
		var weight := float(index) / maxf(1.0, float(fade_frames - 1))
		samples[index] *= weight
		samples[samples.size() - 1 - index] *= weight


func _normalize(samples: PackedFloat32Array, target_peak: float) -> void:
	var peak := 0.0
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
	if peak <= 0.000001:
		return
	var gain := target_peak / peak
	for index: int in range(samples.size()):
		samples[index] *= gain


func _write_wav(resource_path: String, samples: PackedFloat32Array) -> bool:
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index: int in range(samples.size()):
		var signed_sample := int(round(clampf(samples[index], -1.0, 1.0) * 32767.0))
		var encoded := signed_sample if signed_sample >= 0 else 65536 + signed_sample
		pcm[index * 2] = encoded & 0xff
		pcm[index * 2 + 1] = (encoded >> 8) & 0xff

	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write %s: %s" % [resource_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string("RIFF")
	file.store_32(36 + pcm.size())
	file.store_string("WAVE")
	file.store_string("fmt ")
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(SAMPLE_RATE)
	file.store_32(SAMPLE_RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_string("data")
	file.store_32(pcm.size())
	file.store_buffer(pcm)
	file.close()
	return true


func _manifest_entry(resource_path: String, frame_count: int, loops: bool, seed: int) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	return {
		"file": resource_path.trim_prefix("res://"),
		"sha256": FileAccess.get_sha256(absolute_path),
		"seed": seed,
		"duration_seconds": snappedf(float(frame_count) / SAMPLE_RATE, 0.000001),
		"loop": loops,
		"source_type": "generated",
		"license": "Project-original",
		"sample_rate_hz": SAMPLE_RATE,
		"generator": "res://tools/generate_audio.gd",
		"generator_version": GENERATOR_VERSION,
		"provenance": "Deterministic procedural synthesis; no source audio or external samples.",
	}


func _project_original_sfx_manifest_entry(spec: Dictionary) -> Dictionary:
	var resource_path := String(spec["file"])
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		push_error("Missing project-original SFX asset: %s" % resource_path)
		return {}
	var resource := load(resource_path)
	if not (resource is AudioStreamWAV):
		push_error("Project-original SFX did not load as AudioStreamWAV: %s" % resource_path)
		return {}
	var stream := resource as AudioStreamWAV
	if stream.mix_rate != SAMPLE_RATE or stream.stereo:
		push_error("Project-original SFX must be 22050 Hz mono PCM: %s" % resource_path)
		return {}
	return {
		"file": resource_path.trim_prefix("res://"),
		"sha256": FileAccess.get_sha256(absolute_path),
		"seed": int(spec["seed"]),
		"duration_seconds": snappedf(stream.get_length(), 0.000001),
		"loop": false,
		"source_type": "generated",
		"license": "Project-original",
		"sample_rate_hz": SAMPLE_RATE,
		"generator": ORIGINAL_SFX_GENERATOR,
		"generator_version": ORIGINAL_SFX_GENERATOR_VERSION,
		"toolchain": ORIGINAL_SFX_TOOLCHAIN,
		"provenance": "Deterministic oscillator and seeded-noise synthesis; no source audio or external samples.",
	}


func _external_manifest_entry(spec: Dictionary) -> Dictionary:
	var resource_path := String(spec["file"])
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		push_error("Missing external audio asset: %s" % resource_path)
		return {}
	var resource := load(resource_path)
	if not (resource is AudioStream):
		push_error("External audio asset did not load as AudioStream: %s" % resource_path)
		return {}
	return {
		"file": resource_path.trim_prefix("res://"),
		"sha256": FileAccess.get_sha256(absolute_path),
		"duration_seconds": snappedf((resource as AudioStream).get_length(), 0.000001),
		"loop": bool(spec["loop"]),
		"source_type": "external",
		"author": String(spec["author"]),
		"title": String(spec["title"]),
		"license": String(spec["license"]),
		"source_url": String(spec["source_url"]),
	}
