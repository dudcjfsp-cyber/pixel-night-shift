class_name DefenseLabView
extends Control

signal pause_requested
signal speed_requested
signal preset_requested
signal shift_requested
signal restart_requested

const DESIGN_SIZE := Vector2(360.0, 640.0)
const FONT: FontFile = preload("res://game/assets/fonts/Galmuri11-Bold.ttf")
const OPERATOR_IDS: Array[StringName] = [
	&"debugger",
	&"build_engineer",
	&"sprite_artist",
	&"qa_imp",
]

const COLOR_VOID := Color("050a12")
const COLOR_NAVY := Color("0d1727")
const COLOR_PANEL := Color("132238")
const COLOR_PANEL_LIGHT := Color("1c304b")
const COLOR_LINE := Color("31506d")
const COLOR_CYAN := Color("52d6c8")
const COLOR_CYAN_DARK := Color("174e52")
const COLOR_YELLOW := Color("f4c95d")
const COLOR_RED := Color("ff5c67")
const COLOR_GREEN := Color("70e49a")
const COLOR_TEXT := Color("eef6ff")
const COLOR_MUTED := Color("91a7bf")


class BattleField:
	extends Control

	const FIELD_RECT := Rect2(0.0, 0.0, 348.0, 390.0)
	const CORE_CENTER := Vector2(174.0, 292.0)
	const PATH_TOP := 50.0
	const PATH_BOTTOM := 268.0
	const OPERATOR_POSITIONS: Array[Vector2] = [
		Vector2(45.0, 350.0),
		Vector2(127.0, 350.0),
		Vector2(221.0, 350.0),
		Vector2(303.0, 350.0),
	]

	var lab_font: Font
	var snapshot: Dictionary = {}
	var effects: Array[Dictionary] = []
	var last_event_serial := 0
	var danger_pulse := 0.0
	var hit_pulse := 0.0


	func configure(font_value: Font) -> void:
		lab_font = font_value
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		set_process(true)


	func refresh(value: Dictionary) -> void:
		snapshot = value.duplicate(true)
		_consume_events(snapshot.get("recent_events", []) as Array)
		queue_redraw()


	func _process(delta_seconds: float) -> void:
		var changed := false
		danger_pulse = maxf(0.0, danger_pulse - delta_seconds)
		hit_pulse = maxf(0.0, hit_pulse - delta_seconds)
		for index: int in range(effects.size() - 1, -1, -1):
			var effect := effects[index]
			effect["remaining"] = float(effect["remaining"]) - delta_seconds
			if float(effect["remaining"]) <= 0.0:
				effects.remove_at(index)
			changed = true
		if danger_pulse > 0.0 or hit_pulse > 0.0:
			changed = true
		if changed:
			queue_redraw()


	func _draw() -> void:
		draw_rect(FIELD_RECT, COLOR_VOID)
		if PresentationAssets.BATTLE_BACKGROUND != null:
			draw_texture_rect(
				PresentationAssets.BATTLE_BACKGROUND,
				FIELD_RECT,
				false,
				Color(0.32, 0.43, 0.58, 0.48)
			)
		draw_rect(FIELD_RECT, Color(0.02, 0.05, 0.09, 0.44))
		_draw_server_grid()
		_draw_route()
		_draw_core()
		_draw_enemies()
		_draw_operators()
		_draw_effects()
		if danger_pulse > 0.0:
			var alpha := 0.16 * (danger_pulse / 0.45)
			draw_rect(FIELD_RECT, Color(COLOR_RED, alpha))
			draw_rect(FIELD_RECT.grow(-2.0), Color(COLOR_RED, alpha * 2.8), false, 2.0)
		if hit_pulse > 0.0:
			var alpha := 0.12 * (hit_pulse / 0.18)
			draw_rect(FIELD_RECT, Color(COLOR_CYAN, alpha))


	func _draw_server_grid() -> void:
		for y: int in range(24, 390, 24):
			draw_line(
				Vector2(0.0, float(y)),
				Vector2(348.0, float(y)),
				Color(0.14, 0.32, 0.43, 0.16),
				1.0
			)
		for x: int in range(18, 348, 42):
			draw_line(
				Vector2(float(x), 0.0),
				Vector2(float(x), 390.0),
				Color(0.08, 0.29, 0.39, 0.11),
				1.0
			)


	func _draw_route() -> void:
		var path_rect := Rect2(135.0, 30.0, 78.0, 266.0)
		draw_rect(path_rect, Color("081522"))
		draw_rect(path_rect, Color(0.21, 0.57, 0.66, 0.32), false, 2.0)
		draw_line(Vector2(146.0, 38.0), Vector2(146.0, 280.0), Color(0.3, 0.8, 0.81, 0.2))
		draw_line(Vector2(202.0, 38.0), Vector2(202.0, 280.0), Color(0.3, 0.8, 0.81, 0.2))
		for y: int in range(44, 278, 24):
			draw_line(
				Vector2(157.0, float(y)),
				Vector2(191.0, float(y)),
				Color(0.32, 0.84, 0.78, 0.22),
				2.0
			)


	func _draw_core() -> void:
		var danger := int(snapshot.get("stability", 100)) <= 40
		var edge := COLOR_RED if danger else COLOR_CYAN
		var core_rect := Rect2(CORE_CENTER - Vector2(31.0, 23.0), Vector2(62.0, 46.0))
		draw_rect(core_rect, Color("0a1724"))
		draw_rect(core_rect, edge, false, 2.0)
		draw_rect(core_rect.grow(-6.0), Color(edge, 0.16))
		if lab_font != null:
			draw_string(
				lab_font,
				CORE_CENTER + Vector2(-18.0, 4.0),
				"CORE",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				11,
				COLOR_TEXT
			)
		for offset: float in [-20.0, 0.0, 20.0]:
			draw_circle(CORE_CENTER + Vector2(offset, 15.0), 2.0, edge)


	func _draw_enemies() -> void:
		var phase_name := String(snapshot.get("phase_name", ""))
		var is_boss := phase_name == "boss_active"
		var boss := snapshot.get("boss", {}) as Dictionary
		if is_boss and float(boss.get("max_hp", 0.0)) > 0.0:
			var boss_texture := PresentationAssets.ENEMY_TEXTURES.get(
				&"watchdog_process"
			) as Texture2D
			if boss_texture != null:
				draw_texture_rect(
					boss_texture,
					Rect2(142.0, 105.0, 64.0, 64.0),
					false
				)
			else:
				draw_rect(Rect2(146.0, 109.0, 56.0, 56.0), COLOR_RED)
			return

		var enemies := snapshot.get("enemies", []) as Array
		var timers := snapshot.get("timers", {}) as Dictionary
		var wave_elapsed := float(timers.get(
			"wave_elapsed",
			snapshot.get("wave_elapsed", 0.0)
		))
		var wave_seconds := maxf(0.001, float(timers.get("normal_wave_seconds", 5.0)))
		var base_progress := clampf(wave_elapsed / wave_seconds, 0.0, 1.0)
		var living_index := 0
		for enemy_value: Variant in enemies:
			if not enemy_value is Dictionary:
				continue
			var enemy := enemy_value as Dictionary
			var hp := float(enemy.get("hp", enemy.get("current_hp", 0.0)))
			if hp <= 0.0:
				continue
			var serial := int(enemy.get("serial", living_index + 1))
			var progress := clampf(
				float(enemy.get("progress", base_progress)),
				0.0,
				1.0
			)
			var lane_offset := float(posmod(serial, 3) - 1) * 24.0
			var position := Vector2(
				174.0 + lane_offset,
				lerpf(PATH_TOP, PATH_BOTTOM, progress)
			)
			_draw_enemy(enemy, position)
			living_index += 1


	func _draw_enemy(enemy: Dictionary, center: Vector2) -> void:
		var enemy_id := StringName(String(enemy.get(
			"asset_id",
			enemy.get("id", enemy.get("enemy_id", "broken_pixel"))
		)))
		match enemy_id:
			&"small":
				enemy_id = &"broken_pixel"
			&"standard":
				enemy_id = &"missing_resource"
			&"surge":
				enemy_id = &"infinite_loop"
		var texture := PresentationAssets.ENEMY_TEXTURES.get(enemy_id) as Texture2D
		var sprite_size := 27.0 if enemy_id != &"infinite_loop" else 31.0
		if texture != null:
			draw_texture_rect(
				texture,
				Rect2(center - Vector2.ONE * sprite_size * 0.5, Vector2.ONE * sprite_size),
				false
			)
		else:
			draw_rect(
				Rect2(center - Vector2(11.0, 11.0), Vector2(22.0, 22.0)),
				COLOR_RED
			)
		var hp := maxf(0.0, float(enemy.get("hp", enemy.get("current_hp", 0.0))))
		var max_hp := maxf(0.001, float(enemy.get("max_hp", 1.0)))
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var bar_rect := Rect2(center + Vector2(-15.0, 17.0), Vector2(30.0, 3.0))
		draw_rect(bar_rect, Color("071019"))
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, 3.0)), COLOR_RED)


	func _draw_operators() -> void:
		var operators := snapshot.get("operators", []) as Array
		for index: int in OPERATOR_POSITIONS.size():
			var operator_id := OPERATOR_IDS[index]
			var row: Dictionary = {}
			for value: Variant in operators:
				if value is Dictionary and String(value.get("id", "")) == String(operator_id):
					row = value as Dictionary
					break
			var unlocked := bool(row.get("unlocked", false))
			if not unlocked:
				draw_rect(
					Rect2(OPERATOR_POSITIONS[index] - Vector2(14.0, 14.0), Vector2(28.0, 28.0)),
					Color(0.12, 0.18, 0.28, 0.72)
				)
				continue
			var texture := PresentationAssets.operator_texture(operator_id)
			var down := bool(row.get("down", row.get("process_down", false)))
			if texture != null:
				draw_texture_rect(
					texture,
					Rect2(OPERATOR_POSITIONS[index] - Vector2(16.0, 16.0), Vector2(32.0, 32.0)),
					false,
					Color(0.42, 0.42, 0.48, 0.8) if down else Color.WHITE
				)
			if down:
				draw_line(
					OPERATOR_POSITIONS[index] - Vector2(11.0, 11.0),
					OPERATOR_POSITIONS[index] + Vector2(11.0, 11.0),
					COLOR_RED,
					2.0
				)


	func _draw_effects() -> void:
		for effect: Dictionary in effects:
			var remaining := float(effect["remaining"])
			var duration := maxf(0.001, float(effect["duration"]))
			var ratio := clampf(remaining / duration, 0.0, 1.0)
			match StringName(String(effect["kind"])):
				&"shot":
					var from: Vector2 = effect["from"]
					var to: Vector2 = effect["to"]
					var head := to.lerp(from, ratio)
					draw_line(from, head, Color(COLOR_CYAN, 0.35 + 0.65 * ratio), 2.0)
					draw_circle(head, 2.5, COLOR_YELLOW)
				&"impact":
					var center: Vector2 = effect["position"]
					draw_circle(center, 14.0 * (1.0 - ratio), Color(COLOR_YELLOW, ratio), false, 2.0)
				&"rollback":
					draw_arc(
						Vector2(174.0, 137.0),
						28.0 + 12.0 * (1.0 - ratio),
						0.0,
						TAU,
						24,
						Color(COLOR_GREEN, ratio),
						2.0
					)


	func _consume_events(events_value: Array) -> void:
		var newest_serial := 0
		for value: Variant in events_value:
			if value is Dictionary:
				newest_serial = maxi(newest_serial, int(value.get("serial", 0)))
		if newest_serial < last_event_serial:
			last_event_serial = newest_serial
			effects.clear()
			return
		if last_event_serial == 0:
			last_event_serial = newest_serial
			return
		for value: Variant in events_value:
			if not value is Dictionary:
				continue
			var event := value as Dictionary
			var serial := int(event.get("serial", 0))
			if serial <= last_event_serial:
				continue
			_add_event_effect(event)
		last_event_serial = newest_serial


	func _add_event_effect(event: Dictionary) -> void:
		var kind := StringName(String(event.get("kind", "")))
		match kind:
			&"operator_attacked", &"operator_attacked_boss":
				var operator_id := StringName(String(event.get("operator_id", "")))
				var operator_index := OPERATOR_IDS.find(operator_id)
				var from := (
					OPERATOR_POSITIONS[operator_index]
					if operator_index >= 0
					else Vector2(174.0, 350.0)
				)
				var to := (
					Vector2(174.0, 137.0)
					if kind == &"operator_attacked_boss"
					else Vector2(174.0, 125.0)
				)
				effects.append({
					"kind": &"shot",
					"from": from,
					"to": to,
					"duration": 0.16,
					"remaining": 0.16,
				})
			&"enemy_defeated":
				effects.append({
					"kind": &"impact",
					"position": Vector2(174.0, 125.0),
					"duration": 0.20,
					"remaining": 0.20,
				})
				hit_pulse = 0.18
			&"wave_leak_resolved", &"operator_down", &"night_shift_failed":
				danger_pulse = 0.45
			&"boss_rollback":
				effects.append({
					"kind": &"rollback",
					"duration": 0.38,
					"remaining": 0.38,
				})


var _logical_root: Control
var _lab_button: Button
var _pause_button: Button
var _speed_button: Button
var _preset_button: Button
var _product_shift_label: Label
var _phase_label: Label
var _timer_label: Label
var _stability_label: Label
var _stability_bar: ProgressBar
var _progress_cells: Array[Panel] = []
var _progress_labels: Array[Label] = []
var _battle_field: BattleField
var _boss_label: Label
var _boss_bar: ProgressBar
var _operator_cards: Array[Panel] = []
var _operator_textures: Array[TextureRect] = []
var _operator_labels: Array[Label] = []
var _operator_bars: Array[ProgressBar] = []
var _terminal_overlay: Panel
var _terminal_title: Label
var _terminal_stars: Label
var _terminal_reason: Label
var _restart_button: Button

var _snapshot: Dictionary = {}
var _paused := false
var _speed := 1.0
var _preset: StringName = &"first_two"
var _shift_index := 1
var _product_mode := false
var _double_speed_unlocked := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_build_ui()
	resized.connect(_fit_logical_root)
	_fit_logical_root()


func configure(
	paused: bool,
	speed: float,
	preset: StringName,
	shift_index: int,
	save_status: String = ""
) -> void:
	_paused = paused
	_speed = speed
	_preset = preset
	_shift_index = shift_index
	_pause_button.text = "계속" if _paused else "일시정지"
	if _product_mode:
		_product_shift_label.text = "%d차 야간" % _shift_index
		_speed_button.text = (
			"×%d" % int(_speed)
			if _double_speed_unlocked
			else "2배속 잠김"
		)
		_speed_button.tooltip_text = (
			"이 야간근무를 ★★★로 완료하면 재도전 2배속이 열립니다."
			if not _double_speed_unlocked
			else "야간근무 배속 전환"
		)
		return
	_lab_button.text = "LAB · S%d" % _shift_index
	_lab_button.tooltip_text = (
		"Shift 전환"
		if save_status.is_empty()
		else "Shift 전환 · %s" % save_status
	)
	_speed_button.text = "×%d" % int(_speed)
	_preset_button.text = "편성 4" if _preset == &"full_team" else "편성 2"


func set_product_mode(
	enabled: bool,
	double_speed_unlocked: bool = false
) -> void:
	_product_mode = enabled
	_double_speed_unlocked = enabled and double_speed_unlocked
	if not is_node_ready():
		return
	_lab_button.visible = not enabled
	_preset_button.visible = not enabled
	_product_shift_label.visible = enabled
	_restart_button.visible = not enabled
	_pause_button.position = Vector2(7.0, 6.0) if enabled else Vector2(116.0, 6.0)
	_pause_button.size = Vector2(104.0, 25.0) if enabled else Vector2(82.0, 25.0)
	_speed_button.position = Vector2(228.0, 6.0) if enabled else Vector2(202.0, 6.0)
	_speed_button.size = Vector2(113.0, 25.0) if enabled else Vector2(50.0, 25.0)
	_speed_button.disabled = enabled and not _double_speed_unlocked
	_terminal_overlay.visible = (
		false if enabled else _terminal_overlay.visible
	)


func refresh(value: Dictionary) -> void:
	_snapshot = value.duplicate(true)
	_battle_field.refresh(_snapshot)
	var phase_name := String(_snapshot.get("phase_name", "countdown"))
	var completed := int(_snapshot.get("completed_waves", 0))
	var current_wave := int(_snapshot.get("current_wave", 0))
	var stability := clampi(int(_snapshot.get("stability", 100)), 0, 100)
	var stars := int(_snapshot.get("stars", 0))
	var timers := _snapshot.get("timers", {}) as Dictionary
	var phase_remaining := float(timers.get(
		"phase_remaining",
		_snapshot.get("phase_remaining", 0.0)
	))

	_phase_label.text = "%s  ·  %d★" % [_phase_display_name(phase_name), stars]
	_timer_label.text = _format_time(phase_remaining)
	_stability_label.text = "안정도 %d" % stability
	_stability_label.add_theme_color_override(
		"font_color",
		COLOR_RED if stability <= 40 else COLOR_TEXT
	)
	_stability_bar.value = stability
	_update_progress(completed, current_wave, phase_name)
	_update_boss(phase_name)
	_update_operators()
	_update_terminal()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = COLOR_VOID
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_logical_root = Control.new()
	_logical_root.name = "LogicalRoot"
	_logical_root.custom_minimum_size = DESIGN_SIZE
	_logical_root.size = DESIGN_SIZE
	_logical_root.clip_contents = true
	var lab_theme := Theme.new()
	lab_theme.default_font = FONT
	lab_theme.default_font_size = 11
	_logical_root.theme = lab_theme
	add_child(_logical_root)

	var logical_background := ColorRect.new()
	logical_background.color = COLOR_NAVY
	logical_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logical_background.position = Vector2.ZERO
	logical_background.size = DESIGN_SIZE
	_logical_root.add_child(logical_background)

	var top_panel := _make_panel(
		Rect2(6.0, 6.0, 348.0, 94.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	_logical_root.add_child(top_panel)

	_lab_button = _make_button(Rect2(7.0, 6.0, 105.0, 25.0), "LAB · S1")
	_lab_button.name = "LabButton"
	_lab_button.pressed.connect(func() -> void: shift_requested.emit())
	top_panel.add_child(_lab_button)
	_pause_button = _make_button(Rect2(116.0, 6.0, 82.0, 25.0), "일시정지")
	_pause_button.name = "PauseButton"
	_pause_button.pressed.connect(func() -> void: pause_requested.emit())
	top_panel.add_child(_pause_button)
	_speed_button = _make_button(Rect2(202.0, 6.0, 50.0, 25.0), "×1")
	_speed_button.name = "SpeedButton"
	_speed_button.pressed.connect(func() -> void: speed_requested.emit())
	top_panel.add_child(_speed_button)
	_preset_button = _make_button(Rect2(256.0, 6.0, 85.0, 25.0), "편성 2")
	_preset_button.name = "PresetButton"
	_preset_button.pressed.connect(func() -> void: preset_requested.emit())
	top_panel.add_child(_preset_button)
	_product_shift_label = _make_label(
		Rect2(116.0, 6.0, 108.0, 25.0),
		"1차 야간",
		11,
		COLOR_CYAN
	)
	_product_shift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_product_shift_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_product_shift_label.visible = false
	top_panel.add_child(_product_shift_label)

	_stability_label = _make_label(
		Rect2(8.0, 36.0, 74.0, 18.0),
		"안정도 100",
		11,
		COLOR_TEXT
	)
	top_panel.add_child(_stability_label)
	_stability_bar = _make_bar(Rect2(82.0, 40.0, 81.0, 9.0), COLOR_CYAN)
	_stability_bar.max_value = 100.0
	_stability_bar.value = 100.0
	top_panel.add_child(_stability_bar)
	_phase_label = _make_label(
		Rect2(168.0, 35.0, 105.0, 19.0),
		"준비 · 0★",
		11,
		COLOR_YELLOW
	)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_panel.add_child(_phase_label)
	_timer_label = _make_label(
		Rect2(278.0, 35.0, 62.0, 19.0),
		"00:02.0",
		11,
		COLOR_TEXT
	)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_panel.add_child(_timer_label)

	for index: int in 10:
		var cell := _make_panel(
			Rect2(7.0 + float(index) * 33.4, 61.0, 31.0, 24.0),
			COLOR_NAVY,
			COLOR_LINE
		)
		top_panel.add_child(cell)
		_progress_cells.append(cell)
		var label := _make_label(
			Rect2(0.0, 1.0, 31.0, 22.0),
			"B★" if index == 9 else ("%d★" % (index + 1) if index in [2, 5] else str(index + 1)),
			9,
			COLOR_MUTED
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(label)
		_progress_labels.append(label)

	_battle_field = BattleField.new()
	_battle_field.name = "BattleField"
	_battle_field.position = Vector2(6.0, 106.0)
	_battle_field.size = Vector2(348.0, 390.0)
	_battle_field.configure(FONT)
	_logical_root.add_child(_battle_field)

	var bottom_panel := _make_panel(
		Rect2(6.0, 502.0, 348.0, 132.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	_logical_root.add_child(bottom_panel)
	_boss_label = _make_label(
		Rect2(8.0, 5.0, 332.0, 18.0),
		"다음 웨이브 대기",
		11,
		COLOR_YELLOW
	)
	bottom_panel.add_child(_boss_label)
	_boss_bar = _make_bar(Rect2(8.0, 25.0, 332.0, 8.0), COLOR_RED)
	_boss_bar.visible = false
	bottom_panel.add_child(_boss_bar)

	for index: int in OPERATOR_IDS.size():
		var card := _make_panel(
			Rect2(7.0 + float(index) * 84.0, 40.0, 79.0, 84.0),
			COLOR_NAVY,
			COLOR_LINE
		)
		bottom_panel.add_child(card)
		_operator_cards.append(card)
		var portrait := TextureRect.new()
		portrait.position = Vector2(23.0, 4.0)
		portrait.size = Vector2(34.0, 34.0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
		_operator_textures.append(portrait)
		var operator_label := _make_label(
			Rect2(3.0, 39.0, 73.0, 28.0),
			String(OPERATOR_IDS[index]),
			8,
			COLOR_TEXT
		)
		operator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		operator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		operator_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(operator_label)
		_operator_labels.append(operator_label)
		var hp_bar := _make_bar(Rect2(6.0, 70.0, 67.0, 6.0), COLOR_GREEN)
		card.add_child(hp_bar)
		_operator_bars.append(hp_bar)

	_build_terminal_overlay()


func _build_terminal_overlay() -> void:
	_terminal_overlay = _make_panel(
		Rect2(31.0, 218.0, 298.0, 187.0),
		Color("111d2e"),
		COLOR_YELLOW,
		3
	)
	_terminal_overlay.visible = false
	_terminal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_logical_root.add_child(_terminal_overlay)
	var eyebrow := _make_label(
		Rect2(16.0, 13.0, 266.0, 17.0),
		"NIGHT SHIFT RESULT",
		9,
		COLOR_MUTED
	)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_terminal_overlay.add_child(eyebrow)
	_terminal_title = _make_label(
		Rect2(16.0, 34.0, 266.0, 30.0),
		"야간근무 완료",
		20,
		COLOR_YELLOW
	)
	_terminal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_terminal_overlay.add_child(_terminal_title)
	_terminal_stars = _make_label(
		Rect2(16.0, 68.0, 266.0, 31.0),
		"☆☆☆",
		23,
		COLOR_YELLOW
	)
	_terminal_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_terminal_overlay.add_child(_terminal_stars)
	_terminal_reason = _make_label(
		Rect2(22.0, 103.0, 254.0, 30.0),
		"",
		10,
		COLOR_TEXT
	)
	_terminal_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_terminal_reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_terminal_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_terminal_overlay.add_child(_terminal_reason)
	_restart_button = _make_button(
		Rect2(35.0, 142.0, 228.0, 32.0),
		"같은 조건으로 재시작"
	)
	_restart_button.name = "RestartButton"
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_terminal_overlay.add_child(_restart_button)


func _fit_logical_root() -> void:
	if _logical_root == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var factor := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	factor = maxf(0.01, factor)
	_logical_root.scale = Vector2.ONE * factor
	_logical_root.position = (available - DESIGN_SIZE * factor) * 0.5


func _update_progress(completed: int, current_wave: int, phase_name: String) -> void:
	for index: int in _progress_cells.size():
		var wave_number := index + 1
		var fill := COLOR_NAVY
		var edge := COLOR_LINE
		var text_color := COLOR_MUTED
		if wave_number <= completed:
			fill = COLOR_CYAN_DARK
			edge = COLOR_CYAN
			text_color = COLOR_TEXT
		elif wave_number == current_wave:
			fill = Color("493829") if wave_number < 10 else Color("4a202b")
			edge = COLOR_YELLOW if wave_number < 10 else COLOR_RED
			text_color = COLOR_YELLOW if wave_number < 10 else COLOR_RED
		elif phase_name == "boss_warning" and wave_number == 10:
			fill = Color("4a202b")
			edge = COLOR_RED
			text_color = COLOR_RED
		_progress_cells[index].add_theme_stylebox_override(
			"panel",
			_panel_style(fill, edge, 1)
		)
		_progress_labels[index].add_theme_color_override("font_color", text_color)


func _update_boss(phase_name: String) -> void:
	var boss := _snapshot.get("boss", {}) as Dictionary
	var boss_hp := maxf(0.0, float(boss.get("hp", 0.0)))
	var boss_max_hp := maxf(0.001, float(boss.get("max_hp", 0.001)))
	var boss_visible := (
		phase_name == "boss_active"
		or phase_name == "boss_warning"
		or bool(boss.get("active", false))
	)
	_boss_bar.visible = boss_visible and phase_name != "boss_warning"
	if phase_name == "boss_warning":
		_boss_label.text = "⚠ WATCHDOG 연결 중"
		_boss_label.add_theme_color_override("font_color", COLOR_RED)
	elif boss_visible:
		_boss_label.text = "WATCHDOG  HP %d / %d" % [
			int(floorf(boss_hp)),
			int(floorf(boss_max_hp)),
		]
		_boss_label.add_theme_color_override("font_color", COLOR_RED)
		_boss_bar.max_value = boss_max_hp
		_boss_bar.value = boss_hp
	else:
		var next_wave := _snapshot.get("next_wave", {}) as Dictionary
		var enemy_count := int(next_wave.get("total_count", 0))
		_boss_label.text = (
			"다음 웨이브 · 적 %d" % enemy_count
			if enemy_count > 0
			else "단일 경로 방어 가동 중"
		)
		_boss_label.add_theme_color_override("font_color", COLOR_YELLOW)


func _update_operators() -> void:
	var rows := _snapshot.get("operators", []) as Array
	for index: int in OPERATOR_IDS.size():
		var operator_id := OPERATOR_IDS[index]
		var row: Dictionary = {}
		for value: Variant in rows:
			if value is Dictionary and String(value.get("id", "")) == String(operator_id):
				row = value as Dictionary
				break
		var unlocked := bool(row.get("unlocked", false))
		var down := bool(row.get("down", row.get("process_down", false)))
		var hp := maxf(0.0, float(row.get("hp", 0.0)))
		var max_hp := maxf(0.001, float(row.get("max_hp", 0.001)))
		var display_name := _operator_short_name(operator_id)
		var level := int(row.get("level", 0))
		_operator_textures[index].texture = (
			PresentationAssets.operator_texture(operator_id)
			if unlocked
			else null
		)
		_operator_textures[index].modulate = (
			Color(0.42, 0.42, 0.48, 0.75)
			if down
			else Color.WHITE
		)
		if not unlocked:
			_operator_labels[index].text = "%s\n잠김" % display_name
			_operator_labels[index].add_theme_color_override("font_color", COLOR_MUTED)
			_operator_bars[index].max_value = 1.0
			_operator_bars[index].value = 0.0
			_operator_cards[index].add_theme_stylebox_override(
				"panel",
				_panel_style(Color("0a1220"), Color("24364d"), 1)
			)
		elif down:
			_operator_labels[index].text = "%s Lv.%d\nDOWN" % [display_name, level]
			_operator_labels[index].add_theme_color_override("font_color", COLOR_RED)
			_operator_bars[index].max_value = max_hp
			_operator_bars[index].value = hp
			_operator_cards[index].add_theme_stylebox_override(
				"panel",
				_panel_style(Color("21131e"), COLOR_RED, 1)
			)
		else:
			_operator_labels[index].text = "%s Lv.%d\nHP %d" % [
				display_name,
				level,
				int(floorf(hp)),
			]
			_operator_labels[index].add_theme_color_override("font_color", COLOR_TEXT)
			_operator_bars[index].max_value = max_hp
			_operator_bars[index].value = hp
			_operator_cards[index].add_theme_stylebox_override(
				"panel",
				_panel_style(COLOR_NAVY, COLOR_CYAN_DARK, 1)
			)


func _update_terminal() -> void:
	if _product_mode:
		_terminal_overlay.visible = false
		return
	var terminal_value: Variant = _snapshot.get("terminal", false)
	var is_terminal := false
	if typeof(terminal_value) == TYPE_BOOL:
		is_terminal = bool(terminal_value)
	elif terminal_value is Dictionary:
		is_terminal = bool((terminal_value as Dictionary).get("active", true))
	var phase_name := String(_snapshot.get("phase_name", ""))
	is_terminal = is_terminal or phase_name in ["success", "failure"]
	_terminal_overlay.visible = is_terminal
	if not is_terminal:
		return
	var success := phase_name == "success"
	var stars := clampi(int(_snapshot.get("stars", 0)), 0, 3)
	_terminal_title.text = "야간근무 완료" if success else "야간근무 중단"
	_terminal_title.add_theme_color_override(
		"font_color",
		COLOR_YELLOW if success else COLOR_RED
	)
	_terminal_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	var reason := String(_snapshot.get("terminal_reason", ""))
	_terminal_reason.text = _terminal_reason_text(reason, success)


func _make_panel(
	rect: Rect2,
	fill: Color,
	border: Color,
	border_width: int = 1
) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override(
		"panel",
		_panel_style(fill, border, border_width)
	)
	return panel


func _make_button(rect: Rect2, text_value: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_YELLOW)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(COLOR_NAVY, COLOR_LINE, 1)
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(COLOR_PANEL_LIGHT, COLOR_CYAN, 1)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(COLOR_CYAN_DARK, COLOR_YELLOW, 1)
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(Color.TRANSPARENT, COLOR_YELLOW, 1)
	)
	return button


func _make_label(
	rect: Rect2,
	text_value: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_bar(rect: Rect2, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(
		"background",
		_panel_style(Color("071019"), COLOR_LINE, 0)
	)
	bar.add_theme_stylebox_override(
		"fill",
		_panel_style(fill_color, fill_color, 0)
	)
	return bar


func _panel_style(
	fill: Color,
	border: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 3.0
	style.content_margin_top = 2.0
	style.content_margin_right = 3.0
	style.content_margin_bottom = 2.0
	return style


func _phase_display_name(phase_name: String) -> String:
	match phase_name:
		"countdown":
			return "근무 준비"
		"normal_active":
			return "방어 중"
		"inter_wave":
			return "다음 연결"
		"boss_warning":
			return "보스 경보"
		"boss_active":
			return "보스 대응"
		"success":
			return "근무 완료"
		"failure":
			return "근무 중단"
	return phase_name.replace("_", " ").capitalize()


func _format_time(seconds: float) -> String:
	var safe_seconds := maxf(0.0, seconds)
	return "%02d:%04.1f" % [int(safe_seconds) / 60, fmod(safe_seconds, 60.0)]


func _operator_short_name(operator_id: StringName) -> String:
	match operator_id:
		&"debugger":
			return "디버거"
		&"build_engineer":
			return "빌드"
		&"sprite_artist":
			return "스프라이트"
		&"qa_imp":
			return "QA"
	return String(operator_id)


func _terminal_reason_text(reason: String, success: bool) -> String:
	if success:
		return "10개 웨이브의 방어 기록이 저장되었습니다."
	match reason:
		"stability_depleted":
			return "안정도가 0이 되어 코어 방어가 중단되었습니다."
		"boss_timeout":
			return "30초 안에 WATCHDOG을 종료하지 못했습니다."
		"boss_all_down":
			return "모든 요원이 프로세스 다운 상태입니다."
	return "방어 기록: %s" % (reason if not reason.is_empty() else "알 수 없음")
