class_name DayPrepView
extends Control

signal start_shift_requested(shift_index: int)
signal field_report_read_requested(report_key: String)

const DESIGN_SIZE := Vector2(360.0, 640.0)
const FONT: FontFile = preload("res://game/assets/fonts/Galmuri11-Bold.ttf")

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

var _logical_root: Control
var _version_label: Label
var _bits_label: Label
var _shift_panels: Array[Panel] = []
var _shift_star_labels: Array[Label] = []
var _shift_condition_labels: Array[Label] = []
var _shift_buttons: Array[Button] = []
var _report_panel: Panel
var _report_badge: Label
var _report_title: Label
var _report_body: Label
var _report_button: Button
var _update_panel: Panel
var _update_title: Label
var _update_body: Label
var _update_button: Button

var _snapshot: Dictionary = {}
var _report_key := ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_build_ui()
	resized.connect(_fit_logical_root)
	_fit_logical_root()


func refresh(value: Dictionary) -> void:
	_snapshot = value.duplicate(true)
	_version_label.text = "VERSION %02d" % int(_snapshot.get("version", 1))
	_bits_label.text = "◆ %d BIT" % int(_snapshot.get("bits", 0))
	var records: Variant = _snapshot.get("shift_records", [])
	var unlocks := _snapshot.get("unlocks", {}) as Dictionary
	for shift_index: int in range(1, 3):
		_refresh_shift(shift_index, records, unlocks)
	_refresh_report(_snapshot.get("report", {}) as Dictionary)
	_refresh_update(unlocks, records)


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
	var day_theme := Theme.new()
	day_theme.default_font = FONT
	day_theme.default_font_size = 11
	_logical_root.theme = day_theme
	add_child(_logical_root)

	var background := ColorRect.new()
	background.color = COLOR_NAVY
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.position = Vector2.ZERO
	background.size = DESIGN_SIZE
	_logical_root.add_child(background)

	var header := _make_panel(Rect2(6.0, 6.0, 348.0, 68.0), COLOR_PANEL, COLOR_LINE)
	_logical_root.add_child(header)
	var eyebrow := _make_label(
		Rect2(10.0, 8.0, 150.0, 16.0),
		"DAY SHIFT · 주간 정비",
		9,
		COLOR_CYAN
	)
	header.add_child(eyebrow)
	var title := _make_label(
		Rect2(10.0, 27.0, 190.0, 29.0),
		"오늘 밤을 준비합니다",
		17,
		COLOR_TEXT
	)
	header.add_child(title)
	_version_label = _make_label(
		Rect2(220.0, 9.0, 116.0, 17.0),
		"VERSION 01",
		9,
		COLOR_MUTED
	)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_version_label)
	_bits_label = _make_label(
		Rect2(200.0, 31.0, 136.0, 22.0),
		"◆ 0 BIT",
		13,
		COLOR_YELLOW
	)
	_bits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_bits_label)

	var briefing := _make_panel(
		Rect2(6.0, 80.0, 348.0, 63.0),
		Color("102b35"),
		COLOR_CYAN
	)
	_logical_root.add_child(briefing)
	var briefing_title := _make_label(
		Rect2(11.0, 8.0, 326.0, 18.0),
		"서버는 낮 동안 안전합니다",
		12,
		COLOR_CYAN
	)
	briefing.add_child(briefing_title)
	var briefing_body := _make_label(
		Rect2(11.0, 29.0, 326.0, 27.0),
		"근무 기록을 확인하고 준비가 끝나면 바로 야간 방어를 시작하세요.",
		9,
		COLOR_TEXT
	)
	briefing_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.add_child(briefing_body)

	for array_index: int in 2:
		var shift_index := array_index + 1
		var panel := _make_panel(
			Rect2(6.0 + float(array_index) * 176.0, 149.0, 172.0, 155.0),
			COLOR_PANEL,
			COLOR_LINE
		)
		_logical_root.add_child(panel)
		_shift_panels.append(panel)
		var shift_label := _make_label(
			Rect2(10.0, 8.0, 152.0, 18.0),
			"%d차 야간근무" % shift_index,
			12,
			COLOR_TEXT
		)
		panel.add_child(shift_label)
		var stars := _make_label(
			Rect2(10.0, 32.0, 152.0, 28.0),
			"☆☆☆",
			20,
			COLOR_YELLOW
		)
		panel.add_child(stars)
		_shift_star_labels.append(stars)
		var condition := _make_label(
			Rect2(10.0, 66.0, 152.0, 36.0),
			"준비 완료",
			9,
			COLOR_MUTED
		)
		condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(condition)
		_shift_condition_labels.append(condition)
		var start_button := _make_button(
			Rect2(10.0, 111.0, 152.0, 34.0),
			"근무 시작"
		)
		start_button.name = "StartShift%dButton" % shift_index
		start_button.pressed.connect(
			func() -> void: start_shift_requested.emit(shift_index)
		)
		panel.add_child(start_button)
		_shift_buttons.append(start_button)

	_report_panel = _make_panel(
		Rect2(6.0, 310.0, 348.0, 157.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	_logical_root.add_child(_report_panel)
	_report_badge = _make_label(
		Rect2(10.0, 9.0, 48.0, 18.0),
		"NEW",
		9,
		COLOR_YELLOW
	)
	_report_panel.add_child(_report_badge)
	_report_title = _make_label(
		Rect2(62.0, 8.0, 274.0, 20.0),
		"현장 보고서 없음",
		12,
		COLOR_TEXT
	)
	_report_panel.add_child(_report_title)
	_report_body = _make_label(
		Rect2(11.0, 36.0, 326.0, 72.0),
		"첫 야간근무를 마치면 요원들이 서버 상태를 보고합니다.",
		10,
		COLOR_MUTED
	)
	_report_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_report_panel.add_child(_report_body)
	_report_button = _make_button(
		Rect2(11.0, 115.0, 326.0, 31.0),
		"보고서 확인"
	)
	_report_button.name = "ReportButton"
	_report_button.pressed.connect(_request_report_read)
	_report_panel.add_child(_report_button)

	_update_panel = _make_panel(
		Rect2(6.0, 473.0, 348.0, 112.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	_logical_root.add_child(_update_panel)
	_update_title = _make_label(
		Rect2(11.0, 9.0, 210.0, 20.0),
		"버전 업데이트",
		12,
		COLOR_TEXT
	)
	_update_panel.add_child(_update_title)
	_update_body = _make_label(
		Rect2(11.0, 35.0, 208.0, 59.0),
		"두 번째 야간근무에서 ★★★를 기록하면 업데이트 준비가 끝납니다.",
		9,
		COLOR_MUTED
	)
	_update_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_panel.add_child(_update_body)
	_update_button = _make_button(
		Rect2(228.0, 25.0, 109.0, 61.0),
		"업데이트\n잠김"
	)
	_update_button.disabled = true
	_update_button.focus_mode = Control.FOCUS_NONE
	_update_panel.add_child(_update_button)

	var footer := _make_label(
		Rect2(12.0, 594.0, 336.0, 35.0),
		"야간에는 전투가 자동으로 진행되며 강화와 패치 교체는 할 수 없습니다.",
		9,
		COLOR_MUTED
	)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_logical_root.add_child(footer)


func _refresh_shift(
	shift_index: int,
	records: Variant,
	unlocks: Dictionary
) -> void:
	var array_index := shift_index - 1
	var record := _shift_record(records, shift_index)
	var best_stars := clampi(int(record.get(
		"best_stars",
		record.get("stars", 0)
	)), 0, 3)
	var unlocked := bool(record.get(
		"unlocked",
		true if shift_index == 1 else _unlock_value(
			unlocks,
			["shift_2_unlocked"],
			_shift_record_best_stars(records, 1) >= 3
		)
	))
	var highest_wave := clampi(int(record.get("highest_completed_waves", 0)), 0, 10)
	_shift_star_labels[array_index].text = (
		"★".repeat(best_stars) + "☆".repeat(3 - best_stars)
	)
	_shift_buttons[array_index].disabled = not unlocked
	_shift_buttons[array_index].text = "근무 시작" if unlocked else "잠김"
	_shift_condition_labels[array_index].text = (
		"최고 ★%d · %d/10 웨이브\n10웨이브 자동 방어"
		% [best_stars, highest_wave]
		if unlocked
		else "1차 야간근무 ★★★ 필요"
	)
	_shift_condition_labels[array_index].add_theme_color_override(
		"font_color",
		COLOR_MUTED if unlocked else COLOR_RED
	)
	_shift_panels[array_index].add_theme_stylebox_override(
		"panel",
		_panel_style(
			COLOR_PANEL if unlocked else Color("0b1421"),
			COLOR_CYAN if unlocked else Color("24364d")
		)
	)


func _refresh_report(report: Dictionary) -> void:
	_report_key = String(report.get("key", report.get("report_key", "")))
	var rows := report.get("rows", []) as Array
	var unread := not bool(report.get("read", report.get("is_read", true)))
	var has_report := not _report_key.is_empty() or not rows.is_empty()
	_report_badge.visible = has_report and unread
	_report_title.position.x = 62.0 if _report_badge.visible else 11.0
	_report_title.size.x = 274.0 if _report_badge.visible else 325.0
	_report_title.text = (
		String(report.get("title", "최신 현장 보고서"))
		if has_report
		else "현장 보고서 없음"
	)
	var report_lines := PackedStringArray()
	for value: Variant in rows:
		if value is Dictionary:
			var row := value as Dictionary
			var speaker := String(row.get(
				"speaker",
				row.get("operator_name", "")
			))
			var message := String(row.get("message", row.get("text", "")))
			if message.is_empty():
				message = String(row.get("summary", ""))
			report_lines.append(
				("%s · %s" % [speaker, message]) if not speaker.is_empty() else message
			)
		else:
			report_lines.append(String(value))
		if report_lines.size() >= 2:
			break
	_report_body.text = (
		"\n".join(report_lines)
		if not report_lines.is_empty()
		else "첫 야간근무를 마치면 요원들이 서버 상태를 보고합니다."
	)
	_report_body.add_theme_color_override(
		"font_color",
		COLOR_TEXT if has_report else COLOR_MUTED
	)
	_report_button.disabled = not has_report
	_report_button.text = (
		"보고서 없음"
		if not has_report
		else ("보고서 확인" if unread else "보고서 다시 보기")
	)
	_report_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			Color("182b39") if unread else COLOR_PANEL,
			COLOR_YELLOW if unread else COLOR_LINE
		)
	)


func _refresh_update(unlocks: Dictionary, records: Variant) -> void:
	var available := _unlock_value(
		unlocks,
		["version_update", "version_update_available"],
		_shift_record_best_stars(records, 2) >= 3
	)
	_update_title.text = (
		"버전 업데이트 준비 완료"
		if available
		else "버전 업데이트"
	)
	_update_title.add_theme_color_override(
		"font_color",
		COLOR_GREEN if available else COLOR_TEXT
	)
	_update_body.text = (
		"두 차례 야간 기록이 검증되었습니다. 업데이트 실행은 다음 단계에서 연결됩니다."
		if available
		else "2차 야간근무에서 ★★★를 기록하면 업데이트가 열립니다."
	)
	_update_button.text = "준비\n완료" if available else "업데이트\n잠김"
	_update_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			Color("102b25") if available else COLOR_PANEL,
			COLOR_GREEN if available else COLOR_LINE
		)
	)


func _request_report_read() -> void:
	if _report_key.is_empty():
		return
	field_report_read_requested.emit(_report_key)


func _shift_record(records: Variant, shift_index: int) -> Dictionary:
	if records is Array:
		for value: Variant in records:
			if (
				value is Dictionary
				and int((value as Dictionary).get("shift_index", 0)) == shift_index
			):
				return value as Dictionary
		return {}
	if not records is Dictionary:
		return {}
	var record_map := records as Dictionary
	for key: Variant in [str(shift_index), shift_index, "shift_%d" % shift_index]:
		if record_map.has(key) and record_map[key] is Dictionary:
			return record_map[key] as Dictionary
	return {}


func _shift_record_best_stars(records: Variant, shift_index: int) -> int:
	var record := _shift_record(records, shift_index)
	return clampi(int(record.get("best_stars", record.get("stars", 0))), 0, 3)


func _unlock_value(
	unlocks: Dictionary,
	keys: Array,
	fallback: bool
) -> bool:
	for key: String in keys:
		if unlocks.has(key):
			return bool(unlocks[key])
	return fallback


func _fit_logical_root() -> void:
	if _logical_root == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var factor := maxf(
		0.01,
		minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	)
	_logical_root.scale = Vector2.ONE * factor
	_logical_root.position = (available - DESIGN_SIZE * factor) * 0.5


func _make_panel(rect: Rect2, fill: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _panel_style(fill, border))
	return panel


func _make_button(rect: Rect2, text_value: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text_value
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_YELLOW)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(COLOR_NAVY, COLOR_LINE)
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(COLOR_PANEL_LIGHT, COLOR_CYAN)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(COLOR_CYAN_DARK, COLOR_YELLOW)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_panel_style(Color("0a1220"), Color("24364d"))
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(Color.TRANSPARENT, COLOR_YELLOW)
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


func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 3.0
	style.content_margin_top = 2.0
	style.content_margin_right = 3.0
	style.content_margin_bottom = 2.0
	return style
