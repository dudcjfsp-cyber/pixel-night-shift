class_name ShiftResultView
extends Control

signal continue_to_day_requested

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
var _eyebrow: Label
var _title: Label
var _stars: Label
var _completion: Label
var _reason: Label
var _salary_value: Label
var _first_reward_value: Label
var _total_value: Label
var _unlock_title: Label
var _unlock_body: Label
var _report_title: Label
var _report_body: Label


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_build_ui()
	resized.connect(_fit_logical_root)
	_fit_logical_root()


func refresh(value: Dictionary) -> void:
	var result := value.get("result", {}) as Dictionary
	var report := value.get("report", {}) as Dictionary
	var stars := clampi(int(result.get(
		"stars",
		result.get("star_count", 0)
	)), 0, 3)
	var completed := clampi(int(result.get(
		"completed_waves",
		result.get("waves_completed", 0)
	)), 0, 10)
	var success := bool(result.get(
		"success",
		String(result.get("terminal_reason", "")) == "success"
	))
	var shift_index := int(result.get(
		"shift_index",
		value.get("active_shift_index", 1)
	))

	_eyebrow.text = "NIGHT SHIFT %d · 근무 결과" % shift_index
	_title.text = "서버 방어 완료" if success else "야간근무 중단"
	_title.add_theme_color_override(
		"font_color",
		COLOR_GREEN if success else COLOR_RED
	)
	_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	_completion.text = "완료 웨이브  %d / 10" % completed
	_reason.text = _reason_text(
		String(result.get(
			"terminal_reason",
			result.get("reason", "")
		)),
		success
	)

	var first_reward := int(result.get(
		"first_star_reward",
		result.get("first_reward_bits", result.get("first_reward", 0))
	))
	var previous_best := clampi(int(result.get("previous_best_stars", 0)), 0, 3)
	var best_stars := clampi(int(result.get("best_stars", stars)), 0, 3)
	var bits_after := int(result.get("bits_after", value.get("bits", 0)))
	_salary_value.text = "★%d → ★%d" % [previous_best, best_stars]
	_first_reward_value.text = "+%d" % first_reward
	_total_value.text = "%d BIT" % bits_after

	var unlock_rows := _result_unlock_rows(result)
	_unlock_title.text = (
		"새로 열린 항목"
		if not unlock_rows.is_empty()
		else "해금 기록"
	)
	_unlock_body.text = (
		"\n".join(unlock_rows)
		if not unlock_rows.is_empty()
		else "이번 근무에서 새로 열린 항목은 없습니다."
	)
	_unlock_body.add_theme_color_override(
		"font_color",
		COLOR_GREEN if not unlock_rows.is_empty() else COLOR_MUTED
	)

	var report_rows := _report_rows(report)
	_report_title.text = String(report.get(
		"title",
		"현장 보고서 · 사실 확인 후 판단"
	))
	_report_body.text = (
		"\n".join(report_rows)
		if not report_rows.is_empty()
		else _fallback_report(result, completed)
	)


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
	var result_theme := Theme.new()
	result_theme.default_font = FONT
	result_theme.default_font_size = 11
	_logical_root.theme = result_theme
	add_child(_logical_root)

	var background := ColorRect.new()
	background.color = COLOR_NAVY
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.position = Vector2.ZERO
	background.size = DESIGN_SIZE
	_logical_root.add_child(background)

	var result_panel := _make_panel(
		Rect2(6.0, 6.0, 348.0, 226.0),
		COLOR_PANEL,
		COLOR_LINE,
		2
	)
	_logical_root.add_child(result_panel)
	_eyebrow = _make_label(
		Rect2(14.0, 12.0, 320.0, 18.0),
		"NIGHT SHIFT 1 · 근무 결과",
		9,
		COLOR_CYAN
	)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(_eyebrow)
	_title = _make_label(
		Rect2(14.0, 38.0, 320.0, 32.0),
		"야간근무 중단",
		21,
		COLOR_RED
	)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(_title)
	_stars = _make_label(
		Rect2(14.0, 75.0, 320.0, 39.0),
		"☆☆☆",
		27,
		COLOR_YELLOW
	)
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(_stars)
	_completion = _make_label(
		Rect2(14.0, 119.0, 320.0, 21.0),
		"완료 웨이브  0 / 10",
		12,
		COLOR_TEXT
	)
	_completion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(_completion)
	_reason = _make_label(
		Rect2(25.0, 149.0, 298.0, 58.0),
		"서버 방어 기록을 정리하는 중입니다.",
		10,
		COLOR_MUTED
	)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel.add_child(_reason)

	var reward_panel := _make_panel(
		Rect2(6.0, 238.0, 348.0, 88.0),
		Color("102b35"),
		COLOR_CYAN
	)
	_logical_root.add_child(reward_panel)
	var reward_title := _make_label(
		Rect2(10.0, 7.0, 328.0, 18.0),
		"근무 정산",
		11,
		COLOR_CYAN
	)
	reward_panel.add_child(reward_title)
	var reward_names := ["최고 기록", "최초 별 보상", "보유 비트"]
	for index: int in 3:
		var x := 8.0 + float(index) * 110.0
		var name_label := _make_label(
			Rect2(x, 31.0, 104.0, 17.0),
			reward_names[index],
			9,
			COLOR_MUTED
		)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_panel.add_child(name_label)
		var value_label := _make_label(
			Rect2(x, 51.0, 104.0, 23.0),
			"+0",
			13,
			COLOR_YELLOW if index < 2 else COLOR_GREEN
		)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_panel.add_child(value_label)
		match index:
			0:
				_salary_value = value_label
			1:
				_first_reward_value = value_label
			2:
				_total_value = value_label

	var unlock_panel := _make_panel(
		Rect2(6.0, 332.0, 348.0, 93.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	_logical_root.add_child(unlock_panel)
	_unlock_title = _make_label(
		Rect2(11.0, 8.0, 326.0, 18.0),
		"해금 기록",
		11,
		COLOR_TEXT
	)
	unlock_panel.add_child(_unlock_title)
	_unlock_body = _make_label(
		Rect2(11.0, 31.0, 326.0, 52.0),
		"이번 근무에서 새로 열린 항목은 없습니다.",
		9,
		COLOR_MUTED
	)
	_unlock_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unlock_panel.add_child(_unlock_body)

	var report_panel := _make_panel(
		Rect2(6.0, 431.0, 348.0, 139.0),
		COLOR_PANEL,
		COLOR_YELLOW
	)
	_logical_root.add_child(report_panel)
	_report_title = _make_label(
		Rect2(11.0, 8.0, 326.0, 19.0),
		"현장 보고서 · 사실 확인 후 판단",
		11,
		COLOR_YELLOW
	)
	report_panel.add_child(_report_title)
	_report_body = _make_label(
		Rect2(11.0, 34.0, 326.0, 94.0),
		"",
		9,
		COLOR_TEXT
	)
	_report_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	report_panel.add_child(_report_body)

	var continue_button := _make_button(
		Rect2(24.0, 581.0, 312.0, 45.0),
		"주간 정비로"
	)
	continue_button.name = "ContinueToDayButton"
	continue_button.add_theme_font_size_override("font_size", 13)
	continue_button.pressed.connect(
		func() -> void: continue_to_day_requested.emit()
	)
	_logical_root.add_child(continue_button)


func _report_rows(report: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var rows := report.get("rows", []) as Array
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
			result.append(
				("%s · %s" % [speaker, message]) if not speaker.is_empty() else message
			)
		else:
			result.append(String(value))
		if result.size() >= 3:
			break
	return result


func _result_unlock_rows(source: Dictionary) -> PackedStringArray:
	var rows := PackedStringArray()
	if bool(source.get("shift_2_unlocked_now", false)):
		rows.append("둘째 야간근무")
	if bool(source.get("version_update_available_now", false)):
		rows.append("주간 버전 업데이트")
	var reward_stars := source.get("new_reward_stars", []) as Array
	if not reward_stars.is_empty():
		rows.append("별 최초 보상 ★%d까지" % int(reward_stars.back()))
	return rows


func _fallback_report(
	result: Dictionary,
	completed_waves: int
) -> String:
	var metrics := result.get("combat_metrics", {}) as Dictionary
	var leaked := int(metrics.get(
		"enemies_leaked",
		metrics.get("total_enemies_leaked", 0)
	))
	if leaked > 0:
		return "관제 · 적 %d개가 서버에 도달했습니다.\n정비 때 처리량과 편성을 확인해 주세요." % leaked
	if completed_waves >= 10:
		return "관제 · 전 웨이브 방어를 확인했습니다.\n다음 근무 준비가 가능합니다."
	return "관제 · %d웨이브까지 방어했습니다.\n종료 원인을 확인한 뒤 같은 근무에 재도전할 수 있습니다." % completed_waves


func _reason_text(reason: String, success: bool) -> String:
	if success:
		return "10개 웨이브의 방어를 마쳤습니다. 정산과 새 해금을 확인하세요."
	match reason:
		"stability_depleted":
			return "적이 서버에 도달해 안정도가 0이 되었습니다."
		"boss_timeout":
			return "30초 안에 보스 프로세스를 종료하지 못했습니다."
		"boss_all_down":
			return "모든 요원이 프로세스 다운 상태가 되었습니다."
	return (
		"완료하지 못한 원인을 현장 보고서에서 확인하세요."
		if reason.is_empty()
		else "종료 이유 · %s" % reason
	)


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
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_YELLOW)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(COLOR_NAVY, COLOR_CYAN)
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(COLOR_PANEL_LIGHT, COLOR_YELLOW)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(COLOR_CYAN_DARK, COLOR_YELLOW)
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


func _panel_style(
	fill: Color,
	border: Color,
	border_width: int = 1
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
