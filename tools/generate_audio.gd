extends SceneTree

const SAMPLE_RATE := 22050
const BGM_BARS := 8
const OUTPUT_ROOT := "res://game/assets/audio"
const GENERATOR_VERSION := "1.0.0"
const TARGET_PEAK := 0.82

const MUSIC_SPECS := [
	{
		"id": "night_shift_loop",
		"bpm": 96.0,
		"seed": 41021,
		"lead": [74, -1, 77, -1, 81, -1, 84, -1, 81, -1, 77, -1, 76, -1, 72, -1,
			74, -1, 77, 79, 81, -1, 86, -1, 84, -1, 81, -1, 77, 76, 72, -1],
		"harmony": [62, 65, 69, 72, 62, 65, 69, 72, 60, 64, 67, 71, 60, 64, 67, 71],
		"bass": [38, -1, -1, -1, 38, -1, 41, -1, 36, -1, -1, -1, 36, -1, 43, -1],
		"drum_density": 1,
		"lead_duty": 0.25,
	},
	{
		"id": "watchdog_loop",
		"bpm": 148.0,
		"seed": 91487,
		"lead": [74, 75, 74, -1, 80, 79, 75, -1, 74, 75, 77, 75, 74, -1, 68, -1,
			74, 75, 74, 80, 82, 80, 79, 75, 74, -1, 68, 70, 71, 70, 68, -1],
		"harmony": [50, 56, 57, 63, 50, 56, 57, 65, 50, 56, 57, 63, 50, 56, 57, 68],
		"bass": [38, -1, 39, -1, 38, -1, 44, -1, 38, -1, 39, -1, 32, -1, 36, -1],
		"drum_density": 2,
		"lead_duty": 0.125,
	},
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

const SFX_SPECS := [
	{"id": "ui_move", "duration": 0.07, "seed": 1101},
	{"id": "ui_confirm", "duration": 0.16, "seed": 1102},
	{"id": "ui_error", "duration": 0.24, "seed": 1103},
	{"id": "enemy_break", "duration": 0.34, "seed": 1104},
	{"id": "stage_clear", "duration": 0.58, "seed": 1105},
	{"id": "operator_upgrade", "duration": 0.48, "seed": 1106},
	{"id": "patch_apply", "duration": 0.38, "seed": 1107},
	{"id": "patch_remove", "duration": 0.28, "seed": 1108},
	{"id": "boss_warning", "duration": 0.92, "seed": 1109},
	{"id": "maintenance_enter", "duration": 0.68, "seed": 1110},
	{"id": "update_ready", "duration": 1.05, "seed": 1111},
	{"id": "version_update", "duration": 1.65, "seed": 1112},
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
	for spec: Dictionary in MUSIC_SPECS:
		var samples := _render_music(spec)
		var resource_path := "%s/bgm/%s.wav" % [OUTPUT_ROOT, String(spec["id"])]
		if not _write_wav(resource_path, samples):
			quit(1)
			return
		entries.append(_manifest_entry(resource_path, samples.size(), true, int(spec["seed"])))

	for spec: Dictionary in SFX_SPECS:
		var samples := _render_sfx(spec)
		var resource_path := "%s/sfx/%s.wav" % [OUTPUT_ROOT, String(spec["id"])]
		if not _write_wav(resource_path, samples):
			quit(1)
			return
		entries.append(_manifest_entry(resource_path, samples.size(), false, int(spec["seed"])))

	var manifest := {
		"schema_version": 1,
		"generator": "res://tools/generate_audio.gd",
		"generator_version": GENERATOR_VERSION,
		"engine": "Godot 4.7",
		"sample_rate_hz": SAMPLE_RATE,
		"channels": 1,
		"sample_format": "PCM signed 16-bit little-endian",
		"provenance": "Original procedural synthesis; no recordings, samples, or external melodies.",
		"license": "Project-original",
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
	print("Generated %d deterministic audio assets in %s" % [entries.size(), OUTPUT_ROOT])
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


func _render_sfx(spec: Dictionary) -> PackedFloat32Array:
	var cue := String(spec["id"])
	var duration := float(spec["duration"])
	var frame_count := int(round(duration * SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["seed"])
	for frame: int in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var progress := clampf(time / duration, 0.0, 1.0)
		var noise := rng.randf_range(-1.0, 1.0)
		samples[frame] = _sfx_sample(cue, time, progress, duration, noise)
	_fade_one_shot_edges(samples, 0.003, 0.018)
	_normalize(samples, TARGET_PEAK)
	return samples


func _sfx_sample(cue: String, time: float, progress: float, duration: float, noise: float) -> float:
	var release := pow(1.0 - progress, 1.6)
	match cue:
		"ui_move":
			return _pulse(time * lerpf(880.0, 1180.0, progress), 0.25) * release
		"ui_confirm":
			var frequency := 620.0 if progress < 0.48 else 930.0
			var segment_phase := fposmod(progress, 0.5) * 2.0
			return _pulse(time * frequency, 0.25) * pow(1.0 - segment_phase, 0.8) * 0.8
		"ui_error":
			var error_frequency := lerpf(260.0, 105.0, progress)
			return _pulse(time * error_frequency, 0.5) * release * 0.75 + noise * release * 0.12
		"enemy_break":
			var break_frequency := lerpf(520.0, 72.0, progress)
			return _triangle(time * break_frequency) * release * 0.55 + noise * exp(-time * 12.0) * 0.7
		"stage_clear":
			var clear_notes := [523.25, 659.25, 783.99, 1046.50]
			var clear_index := mini(int(progress * clear_notes.size()), clear_notes.size() - 1)
			var clear_phase := fposmod(progress * clear_notes.size(), 1.0)
			return _pulse(time * float(clear_notes[clear_index]), 0.25) * pow(1.0 - clear_phase, 0.65) * release
		"operator_upgrade":
			var upgrade_frequency := lerpf(330.0, 1320.0, progress * progress)
			var sparkle := _pulse(time * (1760.0 + 220.0 * sin(TAU * progress * 3.0)), 0.125)
			return _triangle(time * upgrade_frequency) * release * 0.65 + sparkle * release * 0.18
		"patch_apply":
			var apply_step := int(progress * 6.0)
			var apply_frequency := 280.0 + float(apply_step) * 125.0
			return _pulse(time * apply_frequency, 0.25) * release * 0.8 + noise * exp(-time * 30.0) * 0.18
		"patch_remove":
			var remove_frequency := lerpf(980.0, 210.0, progress)
			return _pulse(time * remove_frequency, 0.125) * release * 0.78
		"boss_warning":
			var alarm_gate := 1.0 if fposmod(time, 0.30) < 0.20 else 0.0
			var alarm_frequency := 138.0 if int(time / 0.30) % 2 == 0 else 184.0
			return _pulse(time * alarm_frequency, 0.5) * alarm_gate * release * 0.82 + noise * alarm_gate * 0.08
		"maintenance_enter":
			var maintenance_frequency := lerpf(460.0, 88.0, progress)
			return _triangle(time * maintenance_frequency) * release * 0.72 + noise * exp(-time * 8.0) * 0.22
		"update_ready":
			var ready_notes := [392.0, 523.25, 659.25, 783.99, 1046.50]
			var ready_index := mini(int(progress * ready_notes.size()), ready_notes.size() - 1)
			var ready_phase := fposmod(progress * ready_notes.size(), 1.0)
			return (_pulse(time * float(ready_notes[ready_index]), 0.25) * pow(1.0 - ready_phase, 0.5) * 0.72
				+ _triangle(time * float(ready_notes[ready_index]) * 0.5) * release * 0.28)
		"version_update":
			var update_notes := [261.63, 329.63, 392.0, 523.25, 659.25, 783.99, 1046.50, 1318.51]
			var update_index := mini(int(progress * update_notes.size()), update_notes.size() - 1)
			var update_phase := fposmod(progress * update_notes.size(), 1.0)
			var update_frequency := float(update_notes[update_index])
			return (_pulse(time * update_frequency, 0.25) * pow(1.0 - update_phase, 0.45) * release * 0.72
				+ _triangle(time * update_frequency * 0.5) * release * 0.32
				+ noise * exp(-time * 10.0) * 0.08)
		_:
			push_error("Unknown SFX cue: %s" % cue)
			return 0.0


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


func _fade_one_shot_edges(samples: PackedFloat32Array, attack_seconds: float, release_seconds: float) -> void:
	var attack_frames := mini(int(attack_seconds * SAMPLE_RATE), samples.size())
	var release_frames := mini(int(release_seconds * SAMPLE_RATE), samples.size())
	for index: int in range(attack_frames):
		samples[index] *= float(index) / maxf(1.0, float(attack_frames - 1))
	for index: int in range(release_frames):
		var sample_index := samples.size() - 1 - index
		samples[sample_index] *= float(index) / maxf(1.0, float(release_frames - 1))


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
	}
