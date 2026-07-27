class_name ShiftResultView
extends Control

signal continue_to_day_requested
signal settings_requested

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
var _base_salary_value: Label
var _performance_value: Label
var _first_reward_value: Label
var _total_value: Label
var _wallet_label: Label
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

	_eyebrow.text = "야간근무 %d차 · 결과" % shift_index
	_title.text = "야간근무 성공" if success else "야간근무 실패"
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

	var base_salary := int(result.get(
		"base_salary",
		result.get("base_salary_bits", 0)
	))
	var first_reward := int(result.get(
		"first_star_reward",
		result.get("first_reward_bits", result.get("first_reward", 0))
	))
	var performance_reward := int(result.get(
		"performance_reward",
		result.get(
			"performance_reward_bits",
			maxi(0, int(result.get("salary_bits", 0)) - base_salary)
		)
	))
	var total_reward := int(result.get(
		"total_reward",
		result.get(
			"total_reward_bits",
			base_salary + performance_reward + first_reward
		)
	))
	var bits_after := int(result.get("bits_after", value.get("bits", 0)))
	_base_salary_value.text = "+%d" % base_salary
	_performance_value.text = "+%d" % performance_reward
	_first_reward_value.text = "+%d" % first_reward
	_total_value.text = "+%d" % total_reward
	_wallet_label.text = "정산 후 보유 · %d비트" % bits_after

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
	_report_title.text = _plain_language(String(report.get(
		"title",
		"현장 보고서 · 무슨 일이 있었나요?"
	)))
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
		Rect2(6.0, 6.0, 348.0, 208.0),
		COLOR_PANEL,
		COLOR_LINE,
		2
	)
	_logical_root.add_child(result_panel)
	_eyebrow = _make_label(
		Rect2(14.0, 12.0, 265.0, 18.0),
		"야간근무 1차 · 결과",
		9,
		COLOR_CYAN
	)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(_eyebrow)
	var settings_button := _make_button(
		Rect2(286.0, 9.0, 48.0, 48.0),
		"설정"
	)
	settings_button.name = "SettingsButton"
	settings_button.add_theme_font_size_override("font_size", 9)
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	result_panel.add_child(settings_button)
	_title = _make_label(
		Rect2(14.0, 38.0, 320.0, 32.0),
		"야간근무 실패",
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
		Rect2(25.0, 145.0, 298.0, 46.0),
		"서버 방어 기록을 정리하는 중입니다.",
		10,
		COLOR_MUTED
	)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel.add_child(_reason)

	var reward_panel := _make_panel(
		Rect2(6.0, 220.0, 348.0, 106.0),
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
	var reward_names := ["기본급", "성과급", "최초 별", "이번 합계"]
	for index: int in 4:
		var x := 5.0 + float(index) * 84.0
		var name_label := _make_label(
			Rect2(x, 29.0, 82.0, 17.0),
			reward_names[index],
			8,
			COLOR_MUTED
		)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_panel.add_child(name_label)
		var value_label := _make_label(
			Rect2(x, 48.0, 82.0, 21.0),
			"+0",
			11,
			COLOR_GREEN if index == 3 else COLOR_YELLOW
		)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_panel.add_child(value_label)
		match index:
			0:
				_base_salary_value = value_label
			1:
				_performance_value = value_label
			2:
				_first_reward_value = value_label
			3:
				_total_value = value_label
	_wallet_label = _make_label(
		Rect2(10.0, 76.0, 328.0, 18.0),
		"정산 후 보유 · 0비트",
		9,
		COLOR_CYAN
	)
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_panel.add_child(_wallet_label)

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
		"현장 보고서 · 무슨 일이 있었나요?",
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
		Rect2(24.0, 578.0, 312.0, 48.0),
		"주간 정비로 이동"
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
			message = _plain_language(message)
			result.append(
				("%s · %s" % [speaker, message]) if not speaker.is_empty() else message
			)
		else:
			result.append(_plain_language(String(value)))
		if result.size() >= 3:
			break
	return result


func _result_unlock_rows(source: Dictionary) -> PackedStringArray:
	var rows := PackedStringArray()
	var unlock_value: Variant = source.get(
		"unlock_summary",
		source.get("new_unlocks", {})
	)
	if unlock_value is Dictionary:
		var groups := unlock_value as Dictionary
		var operator_names := _unlock_names(
			groups.get("operator_ids", []) as Array,
			true
		)
		if not operator_names.is_empty():
			rows.append("신규 요원 · %s" % ", ".join(operator_names))
		if bool(source.get("shift_2_unlocked_now", false)):
			rows.append("다음 근무 · 둘째 야간근무")
		elif bool(source.get("version_update_available_now", false)):
			rows.append("다음 단계 · 주간 버전 업데이트")
		var patch_names := _unlock_names(
			groups.get("patch_ids", []) as Array,
			false
		)
		var slots := groups.get("patch_slots", []) as Array
		var system_parts := PackedStringArray()
		if not patch_names.is_empty():
			system_parts.append("패치 %s" % ", ".join(patch_names))
		if not slots.is_empty():
			system_parts.append("슬롯 %d칸" % (int(slots.back()) + 1))
		if not system_parts.is_empty():
			rows.append("새 시스템 · %s" % " / ".join(system_parts))
	elif unlock_value is Array:
		for value: Variant in unlock_value as Array:
			if value is Dictionary:
				var row_text := String((value as Dictionary).get(
					"label",
					(value as Dictionary).get("display_name", "")
				))
				if not row_text.is_empty() and not rows.has(row_text):
					rows.append(row_text)
			else:
				var value_text := String(value)
				if not value_text.is_empty() and not rows.has(value_text):
					rows.append(value_text)
			if rows.size() >= 3:
				return rows
	if (
		not rows.has("다음 근무 · 둘째 야간근무")
		and bool(source.get("shift_2_unlocked_now", false))
	):
		rows.append("다음 근무 · 둘째 야간근무")
	if (
		not rows.has("다음 단계 · 주간 버전 업데이트")
		and bool(source.get("version_update_available_now", false))
	):
		rows.append("다음 단계 · 주간 버전 업데이트")
	if rows.size() > 3:
		rows.resize(3)
	return rows


func _unlock_names(values: Array, operators: bool) -> PackedStringArray:
	var result := PackedStringArray()
	for value: Variant in values:
		var content_id := StringName(String(value))
		if operators:
			match content_id:
				&"debugger":
					result.append("디버거")
				&"build_engineer":
					result.append("빌드 엔지니어")
				&"sprite_artist":
					result.append("스프라이트 장인")
				&"qa_imp":
					result.append("QA 임프")
				_:
					result.append(String(content_id))
		else:
			match content_id:
				&"frame_skip":
					result.append("프레임 생략")
				&"unsafe_build":
					result.append("검증 생략")
				&"reward_bypass":
					result.append("보상 우회")
				&"rollback_lock":
					result.append("롤백 잠금")
				&"safe_mode":
					result.append("안전 모드")
				_:
					result.append(String(content_id))
	return result


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
			return "30초 안에 보스를 쓰러뜨리지 못했습니다."
		"boss_all_down":
			return "모든 요원이 쓰러졌습니다."
	return (
		"완료하지 못한 원인을 현장 보고서에서 확인하세요."
		if reason.is_empty()
		else "종료 이유 · %s" % _plain_language(reason)
	)


func _plain_language(source: String) -> String:
	var result := source.replace("보스 프로세스", "보스")
	result = result.replace("프로세스 다운", "쓰러짐")
	result = result.replace("WATCHDOG", "보스")
	result = result.replace("DOWN", "쓰러짐")
	result = result.replace("코어", "서버")
	return result


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
