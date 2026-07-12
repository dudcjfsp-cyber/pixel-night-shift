class_name AudioDirector
extends Node

const MUSIC_STREAMS := {
	&"night": preload("res://game/assets/audio/bgm/night_shift_loop.wav"),
	&"watchdog": preload("res://game/assets/audio/bgm/watchdog_loop.wav"),
	&"maintenance": preload("res://game/assets/audio/bgm/maintenance_loop.wav"),
}

const CUE_STREAMS := {
	&"ui_move": preload("res://game/assets/audio/sfx/ui_move.wav"),
	&"ui_confirm": preload("res://game/assets/audio/sfx/ui_confirm.wav"),
	&"ui_error": preload("res://game/assets/audio/sfx/ui_error.wav"),
	&"enemy_break": preload("res://game/assets/audio/sfx/enemy_break.wav"),
	&"stage_clear": preload("res://game/assets/audio/sfx/stage_clear.wav"),
	&"operator_upgrade": preload("res://game/assets/audio/sfx/operator_upgrade.wav"),
	&"patch_apply": preload("res://game/assets/audio/sfx/patch_apply.wav"),
	&"patch_remove": preload("res://game/assets/audio/sfx/patch_remove.wav"),
	&"boss_warning": preload("res://game/assets/audio/sfx/boss_warning.wav"),
	&"maintenance_enter": preload("res://game/assets/audio/sfx/maintenance_enter.wav"),
	&"update_ready": preload("res://game/assets/audio/sfx/update_ready.wav"),
	&"version_update": preload("res://game/assets/audio/sfx/version_update.wav"),
}

const SNAPSHOT_KEYS: PackedStringArray = [
	"stage",
	"stage_enemy_index",
	"mode",
	"enemy",
	"prestige_available",
]
const SFX_PLAYER_COUNT := 6

var _music_enabled := true
var _sfx_enabled := true
var _music_volume_percent := 100
var _sfx_volume_percent := 100
var _music_key: StringName = &""
var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player := 0
var _playback_available := true


func _ready() -> void:
	_playback_available = DisplayServer.get_name() != "headless"
	if _playback_available:
		_ensure_players()


func _exit_tree() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	for player: AudioStreamPlayer in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


func sync_snapshot(previous: Dictionary, current: Dictionary) -> void:
	if not _validate_snapshot(current, "current"):
		return
	if not _playback_available:
		return
	_ensure_players()

	var music_key := _music_for_mode(String(current["mode"]))
	if music_key.is_empty():
		return
	_set_music(music_key)
	if previous.is_empty():
		return
	if not _validate_snapshot(previous, "previous"):
		return

	var previous_mode := String(previous["mode"])
	var current_mode := String(current["mode"])
	var entered_maintenance := current_mode == "maintenance" and previous_mode != "maintenance"
	var entered_boss := current_mode == "boss" and previous_mode != "boss"
	if entered_maintenance:
		play_cue(&"maintenance_enter")
	elif entered_boss:
		play_cue(&"boss_warning")

	if bool(current["prestige_available"]) and not bool(previous["prestige_available"]):
		play_cue(&"update_ready")
	elif int(current["stage"]) > int(previous["stage"]) and not entered_boss:
		play_cue(&"stage_clear")
	elif (
		int(current["stage"]) == int(previous["stage"])
		and current_mode == previous_mode
		and current_mode in ["combat", "maintenance"]
		and int(current["stage_enemy_index"]) != int(previous["stage_enemy_index"])
	):
		play_cue(&"enemy_break")

func play_cue(cue: StringName) -> void:
	if not _sfx_enabled or not _playback_available:
		return
	if not CUE_STREAMS.has(cue):
		push_error("Unknown audio cue '%s'." % cue)
		return
	_ensure_players()
	var stream_value: Variant = CUE_STREAMS[cue]
	if not (stream_value is AudioStream):
		push_error("Audio cue '%s' did not load as an AudioStream." % cue)
		return
	var player := _sfx_players[_next_sfx_player]
	_next_sfx_player = (_next_sfx_player + 1) % _sfx_players.size()
	player.stop()
	player.stream = stream_value as AudioStream
	player.play()


func toggle_music() -> bool:
	set_music_enabled(not _music_enabled)
	return _music_enabled


func toggle_sfx() -> bool:
	set_sfx_enabled(not _sfx_enabled)
	return _sfx_enabled


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not _playback_available:
		return
	_ensure_players()
	if _music_enabled:
		_start_current_music()
	else:
		_music_player.stop()


func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled
	if not _playback_available:
		return
	_ensure_players()
	if not _sfx_enabled:
		for player: AudioStreamPlayer in _sfx_players:
			player.stop()


func set_music_volume_percent(volume_percent: int) -> bool:
	if volume_percent < 0 or volume_percent > 100:
		push_error("Music volume must be between 0 and 100, got %d." % volume_percent)
		return false
	_music_volume_percent = volume_percent
	_apply_music_volume()
	return true


func set_sfx_volume_percent(volume_percent: int) -> bool:
	if volume_percent < 0 or volume_percent > 100:
		push_error("SFX volume must be between 0 and 100, got %d." % volume_percent)
		return false
	_sfx_volume_percent = volume_percent
	_apply_sfx_volume()
	return true


func is_music_enabled() -> bool:
	return _music_enabled


func is_sfx_enabled() -> bool:
	return _sfx_enabled


func get_music_volume_percent() -> int:
	return _music_volume_percent


func get_sfx_volume_percent() -> int:
	return _sfx_volume_percent


func _ensure_players() -> void:
	if is_instance_valid(_music_player):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = &"Music"
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	_sfx_players.clear()
	for index: int in range(SFX_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % (index + 1)
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)
	_apply_music_volume()
	_apply_sfx_volume()


func _apply_music_volume() -> void:
	if not is_instance_valid(_music_player):
		return
	_music_player.volume_db = _volume_percent_to_db(_music_volume_percent)


func _apply_sfx_volume() -> void:
	var volume_db := _volume_percent_to_db(_sfx_volume_percent)
	for player: AudioStreamPlayer in _sfx_players:
		if is_instance_valid(player):
			player.volume_db = volume_db


func _volume_percent_to_db(volume_percent: int) -> float:
	if volume_percent == 0:
		return -80.0
	return linear_to_db(float(volume_percent) / 100.0)


func _set_music(next_key: StringName) -> void:
	if not MUSIC_STREAMS.has(next_key):
		push_error("Unknown music track '%s'." % next_key)
		return
	if _music_key == next_key:
		if _music_enabled and not _music_player.playing:
			_start_current_music()
		return
	_music_key = next_key
	if _music_enabled:
		_start_current_music()


func _start_current_music() -> void:
	if _music_key.is_empty() or not MUSIC_STREAMS.has(_music_key):
		return
	var source_value: Variant = MUSIC_STREAMS[_music_key]
	if not (source_value is AudioStream):
		push_error("Music track '%s' did not load as an AudioStream." % _music_key)
		return
	var stream := (source_value as AudioStream).duplicate() as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()


func _on_music_finished() -> void:
	if _music_enabled:
		_start_current_music()


func _music_for_mode(mode: String) -> StringName:
	match mode:
		"boss":
			return &"watchdog"
		"maintenance":
			return &"maintenance"
		"combat", "complete":
			return &"night"
		_:
			push_error("Unknown presentation mode '%s'." % mode)
			return &""


func _validate_snapshot(snapshot: Dictionary, label: String) -> bool:
	for key: String in SNAPSHOT_KEYS:
		if not snapshot.has(key):
			push_error("AudioDirector %s snapshot is missing '%s'." % [label, key])
			return false
	if not (snapshot["enemy"] is Dictionary):
		push_error("AudioDirector %s snapshot enemy must be a Dictionary." % label)
		return false
	return true
