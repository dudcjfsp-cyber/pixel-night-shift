class_name BattleLaneView
extends PanelContainer

const ASSETS: GDScript = preload("res://game/presentation/presentation_assets.gd")

const COLOR_PANEL := Color("182232")
const COLOR_BORDER := Color("40526c")
const COLOR_TEXT := Color("edf4ff")
const COLOR_MUTED := Color("9dafc7")
const COLOR_RED := Color("ff6b72")
const COLOR_GREEN := Color("7be495")
const COLOR_YELLOW := Color("f4c95d")
const COLOR_CYAN := Color("52d6c8")
const OPERATOR_UPGRADE_DURATION := 0.55


class PortraitPlayback extends RefCounted:
	var portrait: TextureRect
	var frames: SpriteFrames
	var animation: StringName = &"idle"
	var frame_index := 0
	var elapsed_seconds := 0.0

	func bind(target: TextureRect, source: SpriteFrames) -> void:
		portrait = target
		frames = source
		animation = &"idle"
		frame_index = 0
		elapsed_seconds = 0.0
		_apply_frame()

	func play(animation_name: StringName) -> void:
		if frames == null or not frames.has_animation(animation_name):
			return
		animation = animation_name
		frame_index = 0
		elapsed_seconds = 0.0
		_apply_frame()

	func advance(delta_seconds: float) -> void:
		if frames == null or portrait == null:
			return
		var frame_count := frames.get_frame_count(animation)
		var fps := frames.get_animation_speed(animation)
		if frame_count <= 1 or fps <= 0.0:
			return
		var frame_seconds := 1.0 / fps
		elapsed_seconds += delta_seconds
		while elapsed_seconds >= frame_seconds:
			elapsed_seconds -= frame_seconds
			frame_index += 1
			if frame_index >= frame_count:
				if frames.get_animation_loop(animation):
					frame_index = 0
				else:
					animation = &"idle"
					frame_index = 0
					elapsed_seconds = 0.0
			_apply_frame()

	func _apply_frame() -> void:
		if portrait == null or frames == null:
			return
		portrait.texture = frames.get_frame_texture(animation, frame_index)

var _enemy_name_label: Label
var _mode_icon: TextureRect
var _mode_label: Label
var _operator_portraits: Dictionary = {}
var _operator_hp_bars: Dictionary = {}
var _operator_status_labels: Dictionary = {}
var _operator_playbacks: Dictionary = {}
var _operator_base_modulates: Dictionary = {}
var _operator_upgrade_times: Dictionary = {}
var _enemy_portrait_slot: Control
var _enemy_portrait: TextureRect
var _enemy_playback: PortraitPlayback
var _enemy_asset_id: StringName = &""
var _enemy_hp_bar: ProgressBar
var _enemy_hp_label: Label
var _timer_label: Label
var _hit_feedback_time_left: float = 0.0
var _enemy_base_modulate := Color.WHITE
var _reduced_flashes := false
var _reduced_motion := false


func configure_accessibility(reduced_flashes: bool, reduced_motion: bool) -> void:
	_reduced_flashes = reduced_flashes
	_reduced_motion = reduced_motion
	if not is_node_ready():
		return
	if _reduced_flashes or _reduced_motion:
		_clear_transient_effects()
	if _reduced_motion:
		for playback_value: Variant in _operator_playbacks.values():
			var playback: PortraitPlayback = playback_value
			playback.play(&"idle")
		if _enemy_playback != null:
			_enemy_playback.play(&"idle")


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size.y = 150.0
	add_theme_stylebox_override("panel", _make_style(COLOR_PANEL, COLOR_BORDER, 1))
	_build_interface()


func _process(delta_seconds: float) -> void:
	if not _reduced_motion:
		for playback_value: Variant in _operator_playbacks.values():
			var playback: PortraitPlayback = playback_value
			playback.advance(delta_seconds)
		if _enemy_playback != null:
			_enemy_playback.advance(delta_seconds)
	_hit_feedback_time_left = maxf(0.0, _hit_feedback_time_left - delta_seconds)
	if _hit_feedback_time_left <= 0.0 and is_instance_valid(_enemy_portrait):
		_enemy_portrait.modulate = _enemy_base_modulate
	if not _reduced_motion and not _reduced_flashes:
		_update_operator_upgrade_effects(delta_seconds)


func play_operator_upgrade(operator_id: StringName) -> void:
	var key := String(operator_id)
	if not _operator_portraits.has(key):
		push_error("Missing battle portrait for operator '%s'." % operator_id)
		return
	if _reduced_motion or _reduced_flashes:
		return
	var portrait: TextureRect = _operator_portraits[key]
	portrait.pivot_offset = Vector2(portrait.size.x * 0.5, portrait.size.y)
	portrait.z_index = 2
	_operator_upgrade_times[key] = OPERATOR_UPGRADE_DURATION
	var playback: PortraitPlayback = _operator_playbacks[key]
	playback.play(&"upgrade")


func update_from_snapshot(snapshot: Dictionary, previous_snapshot: Dictionary) -> void:
	var enemy: Dictionary = snapshot["enemy"]
	var stage := int(snapshot["stage"])
	var enemy_index := int(snapshot["stage_enemy_index"])
	var enemy_total := int(snapshot["stage_enemy_total"])
	var mode := String(snapshot["mode"])
	var hp := float(enemy["hp"])
	var max_hp := maxf(1.0, float(enemy["max_hp"]))

	_enemy_name_label.text = "%s  ·  %d/%d" % [String(enemy["name"]), enemy_index, enemy_total]
	_mode_label.text = _mode_display_text(mode)
	_mode_label.add_theme_color_override("font_color", _mode_color(mode))
	_mode_icon.texture = ASSETS.mode_texture(mode)
	var next_enemy_id: StringName = ASSETS.enemy_id(stage, bool(enemy["is_boss"]), mode)
	if next_enemy_id != _enemy_asset_id:
		_bind_enemy(next_enemy_id, stage, bool(enemy["is_boss"]), mode)
	_enemy_base_modulate = Color("ffc2ee") if bool(enemy["is_boss"]) and stage >= 20 else Color.WHITE
	if _hit_feedback_time_left <= 0.0:
		_enemy_portrait.modulate = _enemy_base_modulate

	for item: Variant in snapshot["operators"]:
		var operator_data: Dictionary = item
		var operator_id := String(operator_data["id"])
		var portrait: TextureRect = _operator_portraits[operator_id]
		var is_v2 := bool(snapshot["combat_v2_test_mode"])
		var process_down := is_v2 and bool(operator_data["process_down"])
		var base_modulate := (
			Color("6f7785a0") if process_down
			else Color.WHITE if bool(operator_data["unlocked"])
			else Color("33405280")
		)
		_operator_base_modulates[operator_id] = base_modulate
		if float(_operator_upgrade_times.get(operator_id, 0.0)) <= 0.0:
			portrait.modulate = base_modulate
		var hp_bar: ProgressBar = _operator_hp_bars[operator_id]
		var status_label: Label = _operator_status_labels[operator_id]
		hp_bar.visible = is_v2 and bool(operator_data["unlocked"])
		status_label.visible = hp_bar.visible
		if hp_bar.visible:
			var operator_max_hp := maxf(1.0, float(operator_data["max_hp"]))
			hp_bar.value = clampf(float(operator_data["hp"]) / operator_max_hp * 100.0, 0.0, 100.0)
			status_label.text = "DOWN" if process_down else "%d" % int(round(float(operator_data["hp"])))
			status_label.add_theme_color_override("font_color", COLOR_RED if process_down else COLOR_TEXT)

	_enemy_hp_bar.value = clampf(hp / max_hp * 100.0, 0.0, 100.0)
	_enemy_hp_label.text = "HP %s / %s" % [_format_number(hp), _format_number(max_hp)]
	if mode == "maintenance":
		_timer_label.text = "재시도 %.1f초 · %s" % [
			float(snapshot["maintenance_time_left"]),
			_failure_display(String(snapshot["last_failure_reason"])),
		]
		_timer_label.add_theme_color_override("font_color", COLOR_YELLOW)
	elif bool(snapshot["combat_v2_test_mode"]):
		_timer_label.text = "%s · %.1f초" % [String(enemy["next_action"]), float(enemy["next_action_in"])]
		if bool(enemy["is_boss"]):
			_timer_label.text += " · 제한 %.1f초" % float(enemy["time_left"])
		_timer_label.add_theme_color_override("font_color", COLOR_RED if bool(enemy["is_boss"]) else COLOR_YELLOW)
	elif bool(enemy["is_boss"]):
		_timer_label.text = "제한 %.1f초" % float(enemy["time_left"])
		_timer_label.add_theme_color_override("font_color", COLOR_RED)
	else:
		_timer_label.text = "자동 처리 중"
		_timer_label.add_theme_color_override("font_color", COLOR_MUTED)

	_show_damage_feedback(previous_snapshot, snapshot)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	_add_margins(margin, 8, 8, 5, 5)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size.y = 20.0
	column.add_child(title_row)
	_enemy_name_label = _make_label("시스템 대기 중", 13)
	_enemy_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_enemy_name_label)
	_mode_icon = _make_texture_rect(16)
	title_row.add_child(_mode_icon)
	_mode_label = _make_label("[자동] 준비", 10)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(_mode_label)

	var arena := Control.new()
	arena.custom_minimum_size.y = 72.0
	column.add_child(arena)

	var background := TextureRect.new()
	background.texture = ASSETS.BATTLE_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.add_child(background)

	var shade := ColorRect.new()
	shade.color = Color("0b1119a8")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.add_child(shade)

	var operator_row := HBoxContainer.new()
	operator_row.position = Vector2(7.0, 19.0)
	operator_row.add_theme_constant_override("separation", 2)
	arena.add_child(operator_row)
	for operator_id: StringName in [&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp"]:
		var operator_slot := Control.new()
		operator_slot.custom_minimum_size = Vector2(32.0, 49.0)
		operator_slot.size = Vector2(32.0, 49.0)
		operator_row.add_child(operator_slot)
		var portrait := _make_texture_rect(32)
		portrait.name = "OperatorPortrait_%s" % operator_id
		portrait.tooltip_text = String(operator_id)
		operator_slot.add_child(portrait)
		_operator_portraits[String(operator_id)] = portrait
		var hp_bar := ProgressBar.new()
		hp_bar.name = "OperatorHP_%s" % operator_id
		hp_bar.position = Vector2(0.0, 33.0)
		hp_bar.size = Vector2(32.0, 5.0)
		hp_bar.min_value = 0.0
		hp_bar.max_value = 100.0
		hp_bar.show_percentage = false
		hp_bar.visible = false
		hp_bar.add_theme_stylebox_override("background", _make_style(Color("0c111a"), COLOR_BORDER, 0))
		hp_bar.add_theme_stylebox_override("fill", _make_style(COLOR_GREEN, COLOR_GREEN, 0))
		operator_slot.add_child(hp_bar)
		_operator_hp_bars[String(operator_id)] = hp_bar
		var status_label := _make_label("", 7)
		status_label.name = "OperatorStatus_%s" % operator_id
		status_label.position = Vector2(-2.0, 38.0)
		status_label.size = Vector2(36.0, 10.0)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.visible = false
		operator_slot.add_child(status_label)
		_operator_status_labels[String(operator_id)] = status_label
		var frames: SpriteFrames = ASSETS.make_operator_frames(operator_id)
		assert(frames != null, "Missing animation frames for operator '%s'." % operator_id)
		var playback := PortraitPlayback.new()
		playback.bind(portrait, frames)
		_operator_playbacks[String(operator_id)] = playback

	var flow_label := _make_label("▶  AUTO  ▶", 9)
	flow_label.position = Vector2(142.0, 26.0)
	flow_label.size = Vector2(86.0, 20.0)
	flow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flow_label.add_theme_color_override("font_color", COLOR_CYAN)
	arena.add_child(flow_label)

	_enemy_portrait_slot = Control.new()
	_enemy_portrait_slot.name = "EnemyPortraitSlot"
	_enemy_portrait_slot.position = Vector2(260.0, 11.0)
	_enemy_portrait_slot.size = Vector2(48.0, 48.0)
	_enemy_portrait_slot.custom_minimum_size = Vector2(48.0, 48.0)
	arena.add_child(_enemy_portrait_slot)
	_enemy_portrait = _make_texture_rect(32)
	_enemy_portrait.name = "EnemyPortrait"
	_enemy_portrait_slot.add_child(_enemy_portrait)

	_enemy_hp_bar = ProgressBar.new()
	_enemy_hp_bar.custom_minimum_size.y = 17.0
	_enemy_hp_bar.min_value = 0.0
	_enemy_hp_bar.max_value = 100.0
	_enemy_hp_bar.value = 100.0
	_enemy_hp_bar.show_percentage = false
	_enemy_hp_bar.add_theme_stylebox_override("background", _make_style(Color("0c111a"), COLOR_BORDER, 1))
	_enemy_hp_bar.add_theme_stylebox_override("fill", _make_style(Color("b5414b"), COLOR_RED, 0))
	column.add_child(_enemy_hp_bar)

	var detail_row := HBoxContainer.new()
	detail_row.custom_minimum_size.y = 17.0
	column.add_child(detail_row)
	_enemy_hp_label = _make_label("HP -- / --", 9)
	_enemy_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_row.add_child(_enemy_hp_label)
	_timer_label = _make_label("자동 처리 중", 9)
	_timer_label.custom_minimum_size.x = 142.0
	_timer_label.clip_text = true
	_timer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_color_override("font_color", COLOR_MUTED)
	detail_row.add_child(_timer_label)


func _show_damage_feedback(previous_snapshot: Dictionary, snapshot: Dictionary) -> void:
	if previous_snapshot.is_empty() or _hit_feedback_time_left > 0.0:
		return
	if int(previous_snapshot["stage"]) != int(snapshot["stage"]):
		return
	if int(previous_snapshot["stage_enemy_index"]) != int(snapshot["stage_enemy_index"]):
		return
	var previous_enemy: Dictionary = previous_snapshot["enemy"]
	var current_enemy: Dictionary = snapshot["enemy"]
	if float(current_enemy["hp"]) >= float(previous_enemy["hp"]):
		return
	if not _reduced_flashes:
		_hit_feedback_time_left = 0.18
		_enemy_portrait.modulate = Color("ff9ca6")
	if _enemy_playback != null and not _reduced_motion:
		_enemy_playback.play(&"hurt")


func _clear_transient_effects() -> void:
	_hit_feedback_time_left = 0.0
	if is_instance_valid(_enemy_portrait):
		_enemy_portrait.modulate = _enemy_base_modulate
	for operator_id_value: Variant in _operator_upgrade_times.keys():
		var operator_id := String(operator_id_value)
		if not _operator_portraits.has(operator_id):
			continue
		var portrait := _operator_portraits[operator_id] as TextureRect
		portrait.scale = Vector2.ONE
		portrait.z_index = 0
		if _operator_base_modulates.has(operator_id):
			portrait.modulate = _operator_base_modulates[operator_id]
	_operator_upgrade_times.clear()


func _bind_enemy(asset_id: StringName, stage: int, is_boss: bool, mode: String) -> void:
	var frames: SpriteFrames = ASSETS.make_enemy_frames(stage, is_boss, mode)
	assert(frames != null, "Missing animation frames for enemy '%s'." % asset_id)
	var cell_size: Vector2i = ASSETS.sprite_cell_size(asset_id)
	assert(cell_size in [Vector2i(32, 32), Vector2i(48, 48)], "Unsupported enemy cell: %s" % cell_size)
	_enemy_portrait.custom_minimum_size = Vector2(cell_size)
	_enemy_portrait.size = Vector2(cell_size)
	_enemy_portrait.position = Vector2(
		(48.0 - float(cell_size.x)) * 0.5,
		48.0 - float(cell_size.y)
	)
	_enemy_playback = PortraitPlayback.new()
	_enemy_playback.bind(_enemy_portrait, frames)
	_enemy_asset_id = asset_id


func _update_operator_upgrade_effects(delta_seconds: float) -> void:
	var active_ids: Array = _operator_upgrade_times.keys()
	for operator_id_value: Variant in active_ids:
		var operator_id := String(operator_id_value)
		var time_left := maxf(
			0.0,
			float(_operator_upgrade_times[operator_id]) - delta_seconds
		)
		var portrait: TextureRect = _operator_portraits[operator_id]
		assert(
			_operator_base_modulates.has(operator_id),
			"Missing base portrait color for operator '%s'." % operator_id
		)
		var base_modulate: Color = _operator_base_modulates[operator_id]
		if time_left <= 0.0:
			portrait.scale = Vector2.ONE
			portrait.modulate = base_modulate
			portrait.z_index = 0
			_operator_upgrade_times.erase(operator_id)
			continue
		_operator_upgrade_times[operator_id] = time_left
		var progress := clampf(
			1.0 - time_left / OPERATOR_UPGRADE_DURATION,
			0.0,
			1.0
		)
		var pulse := sin(progress * PI)
		portrait.scale = Vector2.ONE * (1.0 + pulse * 0.18)
		portrait.modulate = base_modulate.lerp(COLOR_CYAN, pulse * 0.9)


func _mode_display_text(mode: String) -> String:
	match mode:
		"boss":
			return "[보스] 교전"
		"maintenance":
			return "[복구] 파밍"
		"complete":
			return "[완료] 대기"
		_:
			return "[자동] 전투"


func _failure_display(reason: String) -> String:
	match reason:
		"normal_all_down":
			return "일반전 전원 DOWN"
		"boss_all_down":
			return "보스전 전원 DOWN"
		"boss_timeout":
			return "보스 시간 초과"
	return reason


func _mode_color(mode: String) -> Color:
	match mode:
		"boss":
			return COLOR_RED
		"maintenance":
			return COLOR_YELLOW
		"complete":
			return COLOR_CYAN
		_:
			return COLOR_GREEN


func _format_number(value: float) -> String:
	var absolute := absf(value)
	if absolute >= 1_000_000.0:
		return "%.2fM" % (value / 1_000_000.0)
	if absolute >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _make_texture_rect(size_pixels: int) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(size_pixels, size_pixels)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


func _make_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _make_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _add_margins(container: MarginContainer, left: int, right: int, top: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_bottom", bottom)
