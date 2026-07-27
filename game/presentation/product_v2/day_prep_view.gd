class_name DayPrepView
extends Control

signal start_shift_requested(shift_index: int)
signal field_report_read_requested(report_key: String)
signal upgrade_operator_requested(operator_id: StringName)
signal patch_preview_requested(slot_index: int, patch_id: StringName)
signal patch_equip_requested(slot_index: int, patch_id: StringName)
signal version_update_requested
signal legacy_cache_purchase_requested
signal settings_requested

const DESIGN_SIZE := Vector2(360.0, 640.0)
const FONT: FontFile = preload("res://game/assets/fonts/Galmuri11-Bold.ttf")
const ASSETS: GDScript = preload(
	"res://game/presentation/presentation_assets.gd"
)

const TAB_OPERATORS: StringName = &"operators"
const TAB_PATCHES: StringName = &"patches"
const TAB_DUTY: StringName = &"duty"
const OPERATOR_IDS: Array[StringName] = [
	&"debugger",
	&"build_engineer",
	&"sprite_artist",
	&"qa_imp",
]
const PATCH_IDS: Array[StringName] = [
	&"frame_skip",
	&"unsafe_build",
	&"reward_bypass",
	&"rollback_lock",
	&"safe_mode",
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
const COLOR_PURPLE := Color("a995ff")
const COLOR_TEXT := Color("eef6ff")
const COLOR_MUTED := Color("91a7bf")

var _logical_root: Control
var _version_label: Label
var _bits_label: Label
var _notes_label: Label
var _offline_label: Label
var _tab_buttons: Dictionary = {}
var _tab_surfaces: Dictionary = {}
var _active_tab: StringName = TAB_OPERATORS

var _operator_buttons: Array[Button] = []
var _operator_detail_title: Label
var _operator_detail_role: Label
var _operator_detail_stats: Label
var _operator_detail_unlock: Label
var _operator_upgrade_button: Button
var _selected_operator_id: StringName = &"debugger"

var _slot_buttons: Array[Button] = []
var _patch_buttons: Array[Button] = []
var _patch_preview_title: Label
var _patch_preview_metrics: Label
var _patch_preview_effect: Label
var _patch_equip_button: Button
var _selected_slot_index := 0
var _selected_patch_id: StringName = &""
var _patch_preview: Dictionary = {}

var _shift_panels: Array[Panel] = []
var _shift_star_labels: Array[Label] = []
var _shift_condition_labels: Array[Label] = []
var _shift_buttons: Array[Button] = []
var _report_button: Button
var _update_panel: Panel
var _update_title: Label
var _update_body: Label
var _update_button: Button
var _legacy_title: Label
var _legacy_body: Label
var _legacy_button: Button

var _sheet_backdrop: ColorRect
var _report_sheet: Panel
var _report_sheet_title: Label
var _report_sheet_body: Label
var _version_sheet: Panel
var _version_sheet_body: Label
var _offline_sheet: Panel
var _offline_sheet_title: Label
var _offline_sheet_body: Label

var _snapshot: Dictionary = {}
var _report_key := ""
var _report_unread := false
var _report_pulse_elapsed := 0.0
var _reduced_motion := false
var _offline_handoff: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_build_ui()
	resized.connect(_fit_logical_root)
	_fit_logical_root()


func _process(delta_seconds: float) -> void:
	_update_report_pulse(delta_seconds)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_report_pulse_elapsed = 0.0
	_update_report_pulse(0.0)


func refresh(value: Dictionary) -> void:
	if not _snapshot.is_empty() and value != _snapshot:
		_patch_preview = {}
	_snapshot = value.duplicate(true)
	_version_label.text = "V%02d" % int(_snapshot.get("version", 1))
	_bits_label.text = "◆%d" % int(_snapshot.get("bits", 0))
	_notes_label.text = "▣%d" % int(_snapshot.get("patch_notes", 0))
	_refresh_offline_strip(_snapshot.get("offline", {}) as Dictionary)
	_refresh_operators()
	_refresh_patches()
	var records: Variant = _snapshot.get("shift_records", [])
	var unlocks := _snapshot.get("unlocks", {}) as Dictionary
	for shift_index: int in range(1, 3):
		_refresh_shift(shift_index, records, unlocks)
	_refresh_report(_snapshot.get("report", {}) as Dictionary)
	_refresh_update(unlocks, records)
	_refresh_legacy()


func set_patch_preview(value: Dictionary) -> void:
	_patch_preview = value.duplicate(true)
	_refresh_patch_preview()


func show_offline_handoff(value: Dictionary) -> void:
	if value.is_empty():
		return
	_offline_handoff = value.duplicate(true)
	var awarded := int(value.get(
		"awarded_bits",
		value.get("bits_awarded", value.get("earned_bits", 0))
	))
	var elapsed := int(value.get(
		"elapsed_seconds",
		value.get("absence_seconds", 0)
	))
	_offline_sheet_title.text = "주간 인수인계 · +%d 비트" % awarded
	_offline_sheet_body.text = (
		"자리를 비운 %s 동안 서버 정비 수입이 쌓였습니다.\n"
		+ "수입은 저장된 뒤 한 번만 반영되며 야간 전투는 진행하지 않았습니다."
	) % _duration_text(elapsed)
	_show_sheet(_offline_sheet)


func active_tab_for_test() -> StringName:
	return _active_tab


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

	_build_header()
	_build_tabs()
	_build_operator_surface()
	_build_patch_surface()
	_build_duty_surface()
	_build_sheets()
	_switch_tab(TAB_OPERATORS)


func _build_header() -> void:
	var header := _make_panel(Rect2(6.0, 6.0, 348.0, 66.0), COLOR_PANEL, COLOR_LINE)
	_logical_root.add_child(header)
	var eyebrow := _make_label(
		Rect2(10.0, 7.0, 190.0, 15.0),
		"주간근무 · 정비 시간",
		9,
		COLOR_CYAN
	)
	header.add_child(eyebrow)
	var title := _make_label(
		Rect2(10.0, 25.0, 174.0, 25.0),
		"다음 밤을 준비합니다",
		15,
		COLOR_TEXT
	)
	header.add_child(title)
	_version_label = _make_label(Rect2(190.0, 6.0, 46.0, 15.0), "V01", 9, COLOR_MUTED)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_version_label)
	_bits_label = _make_label(Rect2(188.0, 24.0, 48.0, 16.0), "◆30", 9, COLOR_YELLOW)
	_bits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bits_label.tooltip_text = "비트 · 요원 강화와 패치 교체에 사용"
	header.add_child(_bits_label)
	_notes_label = _make_label(Rect2(188.0, 41.0, 48.0, 16.0), "▣0", 9, COLOR_PURPLE)
	_notes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_notes_label.tooltip_text = "패치노트 · 버전 업데이트 보상"
	header.add_child(_notes_label)
	_report_button = _make_button(Rect2(240.0, 8.0, 48.0, 48.0), "")
	_report_button.name = "ReportButton"
	_report_button.icon = ASSETS.ui_texture(&"diagnosis")
	_report_button.expand_icon = true
	_report_button.add_theme_constant_override("icon_max_width", 20)
	_report_button.tooltip_text = "현장 보고서 · 아직 도착한 보고서가 없습니다."
	_report_button.pressed.connect(_open_report_sheet)
	header.add_child(_report_button)
	var settings_button := _make_button(
		Rect2(290.0, 8.0, 48.0, 48.0),
		"설정"
	)
	settings_button.name = "SettingsButton"
	settings_button.add_theme_font_size_override("font_size", 9)
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	header.add_child(settings_button)

	var offline_panel := _make_panel(
		Rect2(6.0, 77.0, 348.0, 34.0),
		Color("102b35"),
		COLOR_CYAN
	)
	_logical_root.add_child(offline_panel)
	_offline_label = _make_label(
		Rect2(10.0, 7.0, 328.0, 19.0),
		"☀ 주간 수입 · 20분마다 1비트 · 최대 36",
		9,
		COLOR_CYAN
	)
	_offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offline_panel.add_child(_offline_label)


func _build_tabs() -> void:
	var tab_data := [
		[TAB_OPERATORS, "요원 정비", "OperatorTabButton"],
		[TAB_PATCHES, "방어 설정", "PatchTabButton"],
		[TAB_DUTY, "근무 기록", "DutyTabButton"],
	]
	for index: int in tab_data.size():
		var row := tab_data[index] as Array
		var tab_id := StringName(String(row[0]))
		var button := _make_button(
			Rect2(6.0 + float(index) * 117.0, 117.0, 114.0, 48.0),
			String(row[1])
		)
		button.name = String(row[2])
		button.pressed.connect(_switch_tab.bind(tab_id))
		_logical_root.add_child(button)
		_tab_buttons[tab_id] = button


func _build_operator_surface() -> void:
	var surface := Control.new()
	surface.name = "OperatorSurface"
	surface.position = Vector2(6.0, 165.0)
	surface.size = Vector2(348.0, 468.0)
	_logical_root.add_child(surface)
	_tab_surfaces[TAB_OPERATORS] = surface

	var heading := _make_label(
		Rect2(2.0, 0.0, 344.0, 18.0),
		"요원 선택 · 네 명을 한눈에 비교",
		10,
		COLOR_MUTED
	)
	surface.add_child(heading)
	for index: int in OPERATOR_IDS.size():
		var x := float(index % 2) * 174.0
		var y := 23.0 + float(index / 2) * 62.0
		var button := _make_button(Rect2(x, y, 169.0, 56.0), "요원")
		button.name = "OperatorCard%d" % index
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_select_operator.bind(OPERATOR_IDS[index]))
		surface.add_child(button)
		_operator_buttons.append(button)

	var detail := _make_panel(
		Rect2(0.0, 153.0, 348.0, 233.0),
		COLOR_PANEL,
		COLOR_CYAN
	)
	detail.name = "OperatorDetailPanel"
	surface.add_child(detail)
	_operator_detail_title = _make_label(
		Rect2(12.0, 10.0, 324.0, 24.0),
		"디버거 · Lv.1",
		14,
		COLOR_CYAN
	)
	detail.add_child(_operator_detail_title)
	_operator_detail_role = _make_label(
		Rect2(12.0, 39.0, 324.0, 38.0),
		"전열 안정화 · 팀의 공격을 대신 받습니다.",
		10,
		COLOR_TEXT
	)
	_operator_detail_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_operator_detail_role)
	_operator_detail_stats = _make_label(
		Rect2(12.0, 83.0, 324.0, 46.0),
		"체력 0  ·  초당 공격 0\n다음 강화 변화 계산 중",
		10,
		COLOR_YELLOW
	)
	_operator_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_operator_detail_stats)
	_operator_detail_unlock = _make_label(
		Rect2(12.0, 137.0, 324.0, 36.0),
		"시작 요원",
		9,
		COLOR_MUTED
	)
	_operator_detail_unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_operator_detail_unlock)
	_operator_upgrade_button = _make_button(
		Rect2(12.0, 174.0, 324.0, 48.0),
		"12 비트 · 강화"
	)
	_operator_upgrade_button.name = "UpgradeButton"
	_operator_upgrade_button.pressed.connect(_request_operator_upgrade)
	detail.add_child(_operator_upgrade_button)

	var hint := _make_label(
		Rect2(6.0, 399.0, 336.0, 50.0),
		"강화 수치는 정수로 적용됩니다.\n야간근무가 시작되면 정비할 수 없습니다.",
		9,
		COLOR_MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	surface.add_child(hint)


func _build_patch_surface() -> void:
	var surface := Control.new()
	surface.name = "PatchSurface"
	surface.position = Vector2(6.0, 165.0)
	surface.size = Vector2(348.0, 468.0)
	_logical_root.add_child(surface)
	_tab_surfaces[TAB_PATCHES] = surface

	var slot_heading := _make_label(
		Rect2(2.0, 0.0, 344.0, 17.0),
		"장착 슬롯 · 잠금 조건을 누르면 진행도 확인",
		9,
		COLOR_MUTED
	)
	surface.add_child(slot_heading)
	for index: int in 3:
		var button := _make_button(
			Rect2(float(index) * 117.0, 21.0, 113.0, 52.0),
			"슬롯 %d\n잠김" % (index + 1)
		)
		button.name = "PatchSlot%dButton" % (index + 1)
		button.add_theme_font_size_override("font_size", 8)
		button.pressed.connect(_select_patch_slot.bind(index))
		surface.add_child(button)
		_slot_buttons.append(button)

	var patch_heading := _make_label(
		Rect2(2.0, 80.0, 344.0, 17.0),
		"방어 설정 선택 · 적용 전에 이점과 비용 비교",
		9,
		COLOR_MUTED
	)
	surface.add_child(patch_heading)
	for index: int in PATCH_IDS.size():
		var column := index % 3
		var row := index / 3
		var button := _make_button(
			Rect2(float(column) * 117.0, 101.0 + float(row) * 48.0, 113.0, 44.0),
			"패치"
		)
		button.name = "PatchCandidate%dButton" % index
		button.add_theme_font_size_override("font_size", 8)
		button.pressed.connect(_select_patch.bind(PATCH_IDS[index]))
		surface.add_child(button)
		_patch_buttons.append(button)

	var preview := _make_panel(
		Rect2(0.0, 200.0, 348.0, 198.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	preview.name = "PatchPreviewPanel"
	surface.add_child(preview)
	_patch_preview_title = _make_label(
		Rect2(11.0, 9.0, 326.0, 19.0),
		"패치를 선택해 비교하세요",
		11,
		COLOR_TEXT
	)
	preview.add_child(_patch_preview_title)
	_patch_preview_metrics = _make_label(
		Rect2(11.0, 35.0, 326.0, 89.0),
		"예상 처치시간  — → —\n예상 침입 수    — → —\n보스 위험       — → —\n비트 배율       — → —",
		9,
		COLOR_MUTED
	)
	_patch_preview_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(_patch_preview_metrics)
	_patch_preview_effect = _make_label(
		Rect2(11.0, 132.0, 326.0, 55.0),
		"장점과 부작용이 함께 표시됩니다.",
		9,
		COLOR_MUTED
	)
	_patch_preview_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(_patch_preview_effect)
	_patch_equip_button = _make_button(
		Rect2(12.0, 408.0, 324.0, 44.0),
		"패치 선택 필요"
	)
	_patch_equip_button.name = "EquipPatchButton"
	_patch_equip_button.disabled = true
	_patch_equip_button.pressed.connect(_request_patch_equip)
	surface.add_child(_patch_equip_button)


func _build_duty_surface() -> void:
	var surface := Control.new()
	surface.name = "DutySurface"
	surface.position = Vector2(6.0, 165.0)
	surface.size = Vector2(348.0, 468.0)
	_logical_root.add_child(surface)
	_tab_surfaces[TAB_DUTY] = surface

	var scroll := ScrollContainer.new()
	scroll.name = "DutyScroll"
	scroll.position = Vector2.ZERO
	scroll.size = surface.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	surface.add_child(scroll)
	var content := Control.new()
	content.name = "DutyScrollContent"
	content.custom_minimum_size = Vector2(336.0, 570.0)
	scroll.add_child(content)

	for array_index: int in 2:
		var shift_index := array_index + 1
		var panel := _make_panel(
			Rect2(0.0, float(array_index) * 128.0, 332.0, 121.0),
			COLOR_PANEL,
			COLOR_LINE
		)
		content.add_child(panel)
		_shift_panels.append(panel)
		var shift_label := _make_label(
			Rect2(10.0, 8.0, 196.0, 18.0),
			"%d차 야간근무" % shift_index,
			11,
			COLOR_TEXT
		)
		panel.add_child(shift_label)
		var stars := _make_label(
			Rect2(214.0, 7.0, 108.0, 21.0),
			"☆☆☆",
			15,
			COLOR_YELLOW
		)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(stars)
		_shift_star_labels.append(stars)
		var condition := _make_label(
			Rect2(10.0, 35.0, 195.0, 70.0),
			"준비 완료",
			9,
			COLOR_MUTED
		)
		condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		condition.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(condition)
		_shift_condition_labels.append(condition)
		var start_button := _make_button(
			Rect2(213.0, 43.0, 109.0, 55.0),
			"근무 시작"
		)
		start_button.name = "StartShift%dButton" % shift_index
		start_button.pressed.connect(
			func() -> void: start_shift_requested.emit(shift_index)
		)
		panel.add_child(start_button)
		_shift_buttons.append(start_button)

	_update_panel = _make_panel(
		Rect2(0.0, 256.0, 332.0, 143.0),
		COLOR_PANEL,
		COLOR_LINE
	)
	content.add_child(_update_panel)
	_update_title = _make_label(
		Rect2(10.0, 8.0, 202.0, 20.0),
		"버전 업데이트",
		11,
		COLOR_TEXT
	)
	_update_panel.add_child(_update_title)
	_update_body = _make_label(
		Rect2(10.0, 34.0, 202.0, 96.0),
		"2차 야간근무 ★★★ 뒤 주간에 직접 실행할 수 있습니다.",
		9,
		COLOR_MUTED
	)
	_update_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_panel.add_child(_update_body)
	_update_button = _make_button(
		Rect2(220.0, 43.0, 101.0, 58.0),
		"업데이트\n잠김"
	)
	_update_button.name = "VersionUpdateButton"
	_update_button.disabled = true
	_update_button.pressed.connect(_open_version_sheet)
	_update_panel.add_child(_update_button)

	var legacy_panel := _make_panel(
		Rect2(0.0, 407.0, 332.0, 153.0),
		Color("1b1d34"),
		Color("7563a8")
	)
	content.add_child(legacy_panel)
	_legacy_title = _make_label(
		Rect2(10.0, 9.0, 312.0, 20.0),
		"영구 공격 보너스 · Lv.0 / 1",
		11,
		COLOR_PURPLE
	)
	legacy_panel.add_child(_legacy_title)
	_legacy_body = _make_label(
		Rect2(10.0, 35.0, 312.0, 54.0),
		"패치노트 1개를 사용해 다음 버전에도 남는 영구 보너스를 활성화합니다.",
		9,
		COLOR_TEXT
	)
	_legacy_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legacy_panel.add_child(_legacy_body)
	_legacy_button = _make_button(
		Rect2(10.0, 96.0, 312.0, 44.0),
		"패치노트 1 · 영구 보너스 활성화"
	)
	_legacy_button.name = "LegacyCacheButton"
	_legacy_button.pressed.connect(
		func() -> void: legacy_cache_purchase_requested.emit()
	)
	legacy_panel.add_child(_legacy_button)


func _build_sheets() -> void:
	_sheet_backdrop = ColorRect.new()
	_sheet_backdrop.name = "SheetBackdrop"
	_sheet_backdrop.position = Vector2.ZERO
	_sheet_backdrop.size = DESIGN_SIZE
	_sheet_backdrop.color = Color("02050ad9")
	_sheet_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_backdrop.z_index = 20
	_sheet_backdrop.visible = false
	_sheet_backdrop.gui_input.connect(_on_sheet_backdrop_input)
	_logical_root.add_child(_sheet_backdrop)

	_report_sheet = _make_panel(
		Rect2(18.0, 135.0, 324.0, 360.0),
		COLOR_PANEL,
		COLOR_YELLOW,
		2
	)
	_report_sheet.name = "ReportSheet"
	_report_sheet.z_index = 21
	_report_sheet.visible = false
	_logical_root.add_child(_report_sheet)
	_report_sheet_title = _make_label(
		Rect2(14.0, 15.0, 296.0, 26.0),
		"현장 보고서",
		14,
		COLOR_YELLOW
	)
	_report_sheet.add_child(_report_sheet_title)
	var report_scroll := ScrollContainer.new()
	report_scroll.name = "ReportScroll"
	report_scroll.position = Vector2(14.0, 52.0)
	report_scroll.size = Vector2(296.0, 230.0)
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_report_sheet.add_child(report_scroll)
	_report_sheet_body = _make_label(Rect2(0.0, 0.0, 280.0, 220.0), "", 10, COLOR_TEXT)
	_report_sheet_body.custom_minimum_size = Vector2(280.0, 220.0)
	_report_sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_sheet_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_sheet_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	report_scroll.add_child(_report_sheet_body)
	var report_close := _make_button(Rect2(14.0, 296.0, 296.0, 48.0), "확인")
	report_close.name = "CloseReportButton"
	report_close.pressed.connect(_hide_sheets)
	_report_sheet.add_child(report_close)

	_version_sheet = _make_panel(
		Rect2(18.0, 91.0, 324.0, 458.0),
		Color("171a31"),
		COLOR_PURPLE,
		2
	)
	_version_sheet.name = "VersionConfirmPanel"
	_version_sheet.z_index = 21
	_version_sheet.visible = false
	_logical_root.add_child(_version_sheet)
	var version_title := _make_label(
		Rect2(14.0, 15.0, 296.0, 28.0),
		"버전 업데이트 확인",
		15,
		COLOR_PURPLE
	)
	_version_sheet.add_child(version_title)
	_version_sheet_body = _make_label(
		Rect2(14.0, 55.0, 296.0, 292.0),
		"",
		9,
		COLOR_TEXT
	)
	_version_sheet_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_version_sheet.add_child(_version_sheet_body)
	var confirm := _make_button(Rect2(14.0, 355.0, 296.0, 44.0), "업데이트 실행")
	confirm.name = "ConfirmVersionUpdateButton"
	confirm.pressed.connect(_confirm_version_update)
	_version_sheet.add_child(confirm)
	var cancel := _make_button(Rect2(14.0, 404.0, 296.0, 44.0), "취소")
	cancel.name = "CancelVersionUpdateButton"
	cancel.pressed.connect(_hide_sheets)
	_version_sheet.add_child(cancel)

	_offline_sheet = _make_panel(
		Rect2(18.0, 171.0, 324.0, 298.0),
		Color("102b35"),
		COLOR_CYAN,
		2
	)
	_offline_sheet.name = "OfflineHandoffPanel"
	_offline_sheet.z_index = 21
	_offline_sheet.visible = false
	_logical_root.add_child(_offline_sheet)
	_offline_sheet_title = _make_label(
		Rect2(14.0, 17.0, 296.0, 28.0),
		"주간 인수인계",
		14,
		COLOR_CYAN
	)
	_offline_sheet.add_child(_offline_sheet_title)
	_offline_sheet_body = _make_label(
		Rect2(14.0, 59.0, 296.0, 159.0),
		"",
		10,
		COLOR_TEXT
	)
	_offline_sheet_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offline_sheet_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_offline_sheet.add_child(_offline_sheet_body)
	var offline_close := _make_button(Rect2(14.0, 232.0, 296.0, 48.0), "인수인계 확인")
	offline_close.name = "CloseOfflineHandoffButton"
	offline_close.pressed.connect(_hide_sheets)
	_offline_sheet.add_child(offline_close)


func _refresh_offline_strip(offline: Dictionary) -> void:
	var pending := int(offline.get(
		"pending_bits",
		offline.get("available_bits", offline.get("earned_bits", 0))
	))
	var elapsed := int(offline.get(
		"elapsed_seconds",
		offline.get("absence_seconds", 0)
	))
	if pending > 0:
		_offline_label.text = "☀ 인수인계 +%d비트 · %s" % [
			pending,
			_duration_text(elapsed),
		]
		_offline_label.add_theme_color_override("font_color", COLOR_GREEN)
	else:
		_offline_label.text = "☀ 주간 수입 · 20분마다 1비트 · 최대 36"
		_offline_label.add_theme_color_override("font_color", COLOR_CYAN)


func _refresh_operators() -> void:
	var operators := _snapshot.get("operators", []) as Array
	if operators.is_empty():
		return
	if _operator_row(_selected_operator_id).is_empty():
		for value: Variant in operators:
			if value is Dictionary and bool((value as Dictionary).get("unlocked", false)):
				_selected_operator_id = StringName(String((value as Dictionary).get("id", "")))
				break
	for index: int in OPERATOR_IDS.size():
		var row := _operator_row(OPERATOR_IDS[index])
		var button := _operator_buttons[index]
		if row.is_empty():
			button.text = "%s\n데이터 준비 중" % _operator_fallback_name(OPERATOR_IDS[index])
			button.disabled = true
			continue
		var unlocked := bool(row.get("unlocked", false))
		var selected := OPERATOR_IDS[index] == _selected_operator_id
		var name := String(row.get(
			"display_name",
			row.get("name", _operator_fallback_name(OPERATOR_IDS[index]))
		))
		button.text = (
			"%s  Lv.%d\n%s"
			% [
				name,
				int(row.get("level", 1)),
				String(row.get("role", row.get("role_name", "정비 가능"))),
			]
			if unlocked
			else "%s  [잠김]\n%s" % [
				name,
				_short_condition(_operator_unlock_status(OPERATOR_IDS[index])),
			]
		)
		button.disabled = false
		button.add_theme_stylebox_override(
			"normal",
			_panel_style(
				COLOR_CYAN_DARK if selected else (COLOR_PANEL if unlocked else Color("0a1220")),
				COLOR_CYAN if selected else (COLOR_LINE if unlocked else Color("24364d")),
				2 if selected else 1
			)
		)
	var selected_row := _operator_row(_selected_operator_id)
	if selected_row.is_empty():
		return
	_refresh_operator_detail(selected_row)


func _refresh_operator_detail(row: Dictionary) -> void:
	var unlocked := bool(row.get("unlocked", false))
	var name := String(row.get(
		"display_name",
		row.get("name", _operator_fallback_name(_selected_operator_id))
	))
	var level := int(row.get("level", 1))
	_operator_detail_title.text = "%s · Lv.%d" % [name, level] if unlocked else "%s · 잠김" % name
	_operator_detail_title.add_theme_color_override(
		"font_color",
		COLOR_CYAN if unlocked else COLOR_MUTED
	)
	_operator_detail_role.text = String(row.get(
		"ability",
		row.get("role_description", row.get("role", "역할 정보를 준비 중입니다."))
	))
	var hp := int(row.get("hp", row.get("max_hp", 0)))
	var dps := int(row.get("dps", row.get("damage_per_second", 0)))
	var next_hp := int(row.get("next_hp", hp))
	var next_dps := int(row.get("next_dps", dps))
	_operator_detail_stats.text = (
		"체력 %d → %d  ·  초당 공격 %d → %d\n강화 수치는 소수점 없이 적용"
		% [hp, next_hp, dps, next_dps]
		if unlocked
		else "해금 뒤 수치와 강화 비용을 확인할 수 있습니다."
	)
	_operator_detail_unlock.text = _operator_unlock_status(_selected_operator_id)
	var cost := int(row.get("upgrade_cost", row.get("cost", 0)))
	var can_upgrade := bool(row.get(
		"can_upgrade",
		unlocked and int(_snapshot.get("bits", 0)) >= cost
	))
	_operator_upgrade_button.disabled = not can_upgrade
	_operator_upgrade_button.text = (
		"%d 비트 · 강화" % cost
		if unlocked
		else "요원 잠김"
	)


func _refresh_patches() -> void:
	var slots := _patch_slot_rows()
	for index: int in _slot_buttons.size():
		var slot := _slot_row(index, slots)
		var unlocked := bool(slot.get("unlocked", false))
		var equipped_id := StringName(String(slot.get(
			"equipped_patch_id",
			slot.get("patch_id", "")
		)))
		var selected := index == _selected_slot_index
		_slot_buttons[index].text = (
			"슬롯 %d\n%s" % [
				index + 1,
				_patch_display_name(equipped_id) if not equipped_id.is_empty() else "비어 있음",
			]
			if unlocked
			else "슬롯 %d · 잠김\n%s" % [
				index + 1,
				_short_condition(_slot_unlock_status(index)),
			]
		)
		_slot_buttons[index].disabled = false
		_slot_buttons[index].tooltip_text = _slot_unlock_status(index)
		_slot_buttons[index].add_theme_stylebox_override(
			"normal",
			_panel_style(
				COLOR_CYAN_DARK if selected else (COLOR_PANEL if unlocked else Color("0a1220")),
				COLOR_CYAN if selected else (COLOR_LINE if unlocked else Color("24364d")),
				2 if selected else 1
			)
		)
	for index: int in PATCH_IDS.size():
		var row := _patch_row(PATCH_IDS[index])
		var button := _patch_buttons[index]
		if row.is_empty():
			button.text = _patch_fallback_name(PATCH_IDS[index])
			button.disabled = true
			continue
		var unlocked := bool(row.get("unlocked", false))
		var name := String(row.get(
			"display_name",
			row.get("name", _patch_fallback_name(PATCH_IDS[index]))
		))
		var is_new := bool(row.get("new", row.get("is_new", false)))
		button.text = (
			("%s%s" % ["신규 · " if is_new else "", name])
			if unlocked
			else "%s\n[잠김]" % name
		)
		button.disabled = false
		button.tooltip_text = _patch_unlock_status(PATCH_IDS[index])
		button.add_theme_color_override(
			"font_color",
			COLOR_YELLOW if is_new else (COLOR_TEXT if unlocked else COLOR_MUTED)
		)
	_refresh_patch_preview()


func _refresh_patch_preview() -> void:
	if _selected_patch_id.is_empty():
		_patch_preview_title.text = "패치를 선택해 비교하세요"
		_patch_preview_metrics.text = (
			"예상 처치시간  — → —\n"
			+ "예상 침입 수    — → —\n"
			+ "보스 위험       — → —\n"
			+ "비트 배율       — → —\n"
			+ "반복 급여       — → —"
		)
		_patch_preview_effect.text = "장점과 부작용이 함께 표시됩니다."
		_patch_equip_button.text = "패치 선택 필요"
		_patch_equip_button.disabled = true
		return
	var patch := _patch_row(_selected_patch_id)
	var slot := _slot_row(_selected_slot_index, _patch_slot_rows())
	var patch_name := String(patch.get(
		"display_name",
		patch.get("name", _patch_fallback_name(_selected_patch_id))
	))
	_patch_preview_title.text = "슬롯 %d · %s" % [_selected_slot_index + 1, patch_name]
	var before := _patch_preview.get(
		"before",
		_patch_preview.get("current", {})
	) as Dictionary
	var after := _patch_preview.get(
		"after",
		_patch_preview.get("preview", {})
	) as Dictionary
	_patch_preview_metrics.text = "\n".join(PackedStringArray([
		_metric_line(
			"예상 처치시간",
			before,
			after,
			["kill_time", "kill_time_seconds", "expected_kill_time"],
			"초"
		),
		_metric_line("예상 침입 수", before, after, ["enemies_leaked", "expected_leaks"], "개"),
		_text_metric_line("보스 위험", before, after, ["boss_risk", "boss_risk_text"]),
		_metric_line("비트 배율", before, after, ["bit_multiplier", "reward_multiplier"], "×"),
		_metric_line("반복 급여", before, after, ["repeat_salary", "expected_salary"], " 비트"),
	]))
	var benefit := String(_patch_preview.get(
		"benefit",
		patch.get("benefit", patch.get("advantage", "이점 정보 준비 중"))
	))
	var tradeoff := String(_patch_preview.get(
		"tradeoff",
		patch.get("tradeoff", patch.get("downside", "부작용 정보 준비 중"))
	))
	_patch_preview_effect.text = "▲ %s\n▼ %s" % [benefit, tradeoff]
	var cost := int(_patch_preview.get(
		"cost",
		_patch_preview.get("equip_cost", patch.get("equip_cost", 0))
	))
	var can_equip := bool(_patch_preview.get(
		"can_equip",
		bool(slot.get("unlocked", false))
			and bool(patch.get("unlocked", false))
			and int(_snapshot.get("bits", 0)) >= cost
	))
	_patch_equip_button.text = (
		"%d 비트 · 이 슬롯에 교체" % cost
		if cost > 0
		else "이 슬롯에 장착"
	)
	if not bool(slot.get("unlocked", false)):
		_patch_equip_button.text = "선택한 슬롯 잠김"
	elif not bool(patch.get("unlocked", false)):
		_patch_equip_button.text = "선택한 패치 잠김"
	_patch_equip_button.disabled = not can_equip


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
		"최고 ★%d · %d/10 웨이브\n일반 5초 · 보스 30초\n%s"
		% [
			best_stars,
			highest_wave,
			"★★★ 재도전 2배속" if best_stars == 3 else "전투는 완전 자동",
		]
		if unlocked
		else "1차 야간근무 ★★★ 필요\n현재 ★%d / 3" % _shift_record_best_stars(records, 1)
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
	_report_unread = has_report and unread
	var report_lines := _report_lines(rows)
	_report_button.disabled = not has_report
	_report_button.tooltip_text = (
		"현장 보고서 · 새 보고서가 도착했습니다."
		if _report_unread
		else (
			"현장 보고서 · 눌러서 다시 확인합니다."
			if has_report
			else "현장 보고서 · 아직 도착한 보고서가 없습니다."
		)
	)
	_report_sheet_title.text = String(report.get(
		"title",
		"현장 보고서 · 무슨 일이 있었나요?"
	))
	_report_sheet_title.text = _plain_language(_report_sheet_title.text)
	_report_sheet_body.text = (
		"\n\n".join(report_lines)
		if not report_lines.is_empty()
		else "표시할 현장 보고서가 없습니다."
	)
	_update_report_pulse(0.0)


func _refresh_update(unlocks: Dictionary, records: Variant) -> void:
	var available := _unlock_value(
		unlocks,
		["version_update", "version_update_available"],
		_shift_record_best_stars(records, 2) >= 3
	)
	_update_title.text = "버전 업데이트 준비 완료" if available else "버전 업데이트"
	_update_title.add_theme_color_override(
		"font_color",
		COLOR_GREEN if available else COLOR_TEXT
	)
	_update_body.text = (
		"직접 실행하면 새 버전 준비금 30비트로 시작합니다.\n초기화·보존 항목을 먼저 확인합니다."
		if available
		else "2차 야간근무 ★★★ 필요\n현재 ★%d / 3\n전투 중 자동 실행되지 않습니다."
			% _shift_record_best_stars(records, 2)
	)
	_update_button.text = "업데이트\n확인" if available else "업데이트\n잠김"
	_update_button.disabled = not available
	_update_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			Color("102b25") if available else COLOR_PANEL,
			COLOR_GREEN if available else COLOR_LINE
		)
	)


func _refresh_legacy() -> void:
	var level := int(_snapshot.get("legacy_cache_level", 0))
	var notes := int(_snapshot.get("patch_notes", 0))
	var cost := int(_snapshot.get("legacy_cache_cost", 1))
	var bonus := float(_snapshot.get("legacy_cache_bonus", 0.0))
	_legacy_title.text = "영구 공격 보너스 · Lv.%d / 1" % level
	_legacy_body.text = (
		"활성화 완료 · 다음 버전에도 유지되는 공격 보너스 +%d%%"
			% roundi(bonus * 100.0)
		if level >= 1
		else "패치노트 %d개를 사용해 다음 버전에도 남는 영구 보너스를 활성화합니다."
			% cost
	)
	_legacy_button.disabled = not bool(_snapshot.get(
		"can_buy_legacy_cache",
		level < 1 and notes >= cost
	))
	_legacy_button.text = (
		"캐시 활성화 완료"
		if level >= 1
		else (
			"패치노트 %d · 캐시 활성화" % cost
			if notes >= cost
			else "패치노트 %d 필요" % cost
		)
	)


func _switch_tab(tab_id: StringName) -> void:
	if not _tab_surfaces.has(tab_id):
		return
	_active_tab = tab_id
	for key: Variant in _tab_surfaces:
		(_tab_surfaces[key] as Control).visible = StringName(key) == tab_id
	for key: Variant in _tab_buttons:
		var selected := StringName(key) == tab_id
		var button := _tab_buttons[key] as Button
		button.add_theme_stylebox_override(
			"normal",
			_panel_style(
				COLOR_CYAN_DARK if selected else COLOR_NAVY,
				COLOR_CYAN if selected else COLOR_LINE,
				2 if selected else 1
			)
		)
		button.add_theme_color_override(
			"font_color",
			COLOR_CYAN if selected else COLOR_TEXT
		)


func _select_operator(operator_id: StringName) -> void:
	_selected_operator_id = operator_id
	_refresh_operators()


func _request_operator_upgrade() -> void:
	if _selected_operator_id.is_empty():
		return
	upgrade_operator_requested.emit(_selected_operator_id)


func _select_patch_slot(slot_index: int) -> void:
	_selected_slot_index = clampi(slot_index, 0, 2)
	_patch_preview = {}
	_refresh_patches()
	if (
		not _selected_patch_id.is_empty()
		and bool(_patch_row(_selected_patch_id).get("unlocked", false))
		and bool(_slot_row(
			_selected_slot_index,
			_patch_slot_rows()
		).get("unlocked", false))
	):
		patch_preview_requested.emit(_selected_slot_index, _selected_patch_id)


func _select_patch(patch_id: StringName) -> void:
	_selected_patch_id = patch_id
	_patch_preview = {}
	_refresh_patches()
	if (
		bool(_patch_row(_selected_patch_id).get("unlocked", false))
		and bool(_slot_row(
			_selected_slot_index,
			_patch_slot_rows()
		).get("unlocked", false))
	):
		patch_preview_requested.emit(_selected_slot_index, _selected_patch_id)


func _request_patch_equip() -> void:
	if _selected_patch_id.is_empty():
		return
	patch_equip_requested.emit(_selected_slot_index, _selected_patch_id)


func _open_report_sheet() -> void:
	if _report_button.disabled:
		return
	if not _report_key.is_empty():
		field_report_read_requested.emit(_report_key)
	_show_sheet(_report_sheet)


func _open_version_sheet() -> void:
	var operator_levels := PackedStringArray()
	for value: Variant in _snapshot.get("operators", []) as Array:
		if value is Dictionary and bool((value as Dictionary).get("unlocked", false)):
			operator_levels.append(
				"%s Lv.%d" % [
					String((value as Dictionary).get(
						"display_name",
						(value as Dictionary).get("name", "요원")
					)),
					int((value as Dictionary).get("level", 1)),
				]
			)
	var equipped_count := 0
	for value: Variant in _patch_slot_rows():
		if value is Dictionary and not String((value as Dictionary).get(
			"equipped_patch_id",
			(value as Dictionary).get("patch_id", "")
		)).is_empty():
			equipped_count += 1
	_version_sheet_body.text = (
		"[초기화]\n"
		+ "· 보유 %d비트 → 준비금 30비트\n" % int(_snapshot.get("bits", 0))
		+ "· 요원 레벨: %s\n" % (
			", ".join(operator_levels) if not operator_levels.is_empty() else "기본 레벨"
		)
		+ "· 장착 패치 %d개와 이번 버전 근무 기록\n\n" % equipped_count
		+ "[보존]\n"
		+ "· 발견한 요원·패치와 열린 슬롯\n"
		+ "· 패치노트, 회차, 영구 공격 보너스\n\n"
		+ "업데이트 보상으로 패치노트 1개를 받습니다."
	)
	_show_sheet(_version_sheet)


func _confirm_version_update() -> void:
	_hide_sheets()
	version_update_requested.emit()


func _show_sheet(sheet: Control) -> void:
	_hide_sheets()
	_sheet_backdrop.visible = true
	sheet.visible = true


func _hide_sheets() -> void:
	_sheet_backdrop.visible = false
	_report_sheet.visible = false
	_version_sheet.visible = false
	_offline_sheet.visible = false


func _on_sheet_backdrop_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
	) or (
		event is InputEventScreenTouch
		and (event as InputEventScreenTouch).pressed
	):
		_hide_sheets()


func _update_report_pulse(delta_seconds: float) -> void:
	if _report_button == null:
		return
	if not _report_unread:
		_report_pulse_elapsed = 0.0
		_report_button.self_modulate = Color.WHITE
		return
	if _reduced_motion:
		_report_button.self_modulate = COLOR_YELLOW
		return
	_report_pulse_elapsed = fmod(
		_report_pulse_elapsed + maxf(0.0, delta_seconds),
		1.2
	)
	var pulse := (
		sin((_report_pulse_elapsed / 1.2) * TAU - PI * 0.5) * 0.5
		+ 0.5
	)
	_report_button.self_modulate = Color.WHITE.lerp(
		COLOR_YELLOW,
		0.25 + pulse * 0.75
	)


func _operator_row(operator_id: StringName) -> Dictionary:
	for value: Variant in _snapshot.get("operators", []) as Array:
		if value is Dictionary and StringName(String((value as Dictionary).get("id", ""))) == operator_id:
			return value as Dictionary
	return {}


func _patch_row(patch_id: StringName) -> Dictionary:
	for value: Variant in _snapshot.get("patches", []) as Array:
		if value is Dictionary and StringName(String((value as Dictionary).get("id", ""))) == patch_id:
			return value as Dictionary
	return {}


func _slot_row(slot_index: int, slots: Array) -> Dictionary:
	for value: Variant in slots:
		if value is Dictionary and int((value as Dictionary).get(
			"index",
			(value as Dictionary).get("slot_index", -1)
		)) == slot_index:
			return value as Dictionary
	if slot_index >= 0 and slot_index < slots.size() and slots[slot_index] is Dictionary:
		return slots[slot_index] as Dictionary
	return {}


func _patch_slot_rows() -> Array:
	var rows := _snapshot.get("patch_slot_rows", []) as Array
	if not rows.is_empty():
		return rows
	var result: Array[Dictionary] = []
	var raw_slots := _snapshot.get("patch_slots", []) as Array
	var unlocked_count := int(_snapshot.get("unlocked_patch_slots", 0))
	for index: int in 3:
		var patch_id := String(raw_slots[index]) if index < raw_slots.size() else ""
		result.append({
			"index": index,
			"slot_index": index,
			"unlocked": index < unlocked_count,
			"patch_id": patch_id,
			"equipped_patch_id": patch_id,
			"unlock_text": "해금 조건 확인",
		})
	return result


func _patch_display_name(patch_id: StringName) -> String:
	if patch_id.is_empty():
		return ""
	var row := _patch_row(patch_id)
	return String(row.get(
		"display_name",
		row.get("name", _patch_fallback_name(patch_id))
	))


func _metric_line(
	label_text: String,
	before: Dictionary,
	after: Dictionary,
	keys: Array,
	suffix: String
) -> String:
	var before_value: Variant = _first_value(before, keys)
	var after_value: Variant = _first_value(after, keys)
	if before_value == null or after_value == null:
		return "%s  — → —" % label_text
	var before_number := float(before_value)
	var after_number := float(after_value)
	var before_text := _metric_number(before_number, suffix)
	var after_text := _metric_number(after_number, suffix)
	var delta := after_number - before_number
	var delta_text := ""
	if not is_zero_approx(delta):
		delta_text = "  (%s%s)" % [
			"+" if delta > 0.0 else "",
			_metric_number(delta, suffix),
		]
	return "%s  %s → %s%s" % [
		label_text,
		before_text,
		after_text,
		delta_text,
	]


func _text_metric_line(
	label_text: String,
	before: Dictionary,
	after: Dictionary,
	keys: Array
) -> String:
	var before_value: Variant = _first_value(before, keys)
	var after_value: Variant = _first_value(after, keys)
	if before_value == null or after_value == null:
		return "%s  — → —" % label_text
	return "%s  %s → %s" % [
		label_text,
		_metric_text(String(before_value)),
		_metric_text(String(after_value)),
	]


func _first_value(source: Dictionary, keys: Array) -> Variant:
	for key: String in keys:
		if source.has(key):
			return source[key]
	return null


func _metric_number(value: float, suffix: String) -> String:
	if suffix == "×":
		return "%.2f×" % value
	if is_equal_approx(value, floorf(value)):
		return "%d%s" % [int(value), suffix]
	return "%.1f%s" % [value, suffix]


func _metric_text(value: String) -> String:
	match value:
		"low":
			return "낮음"
		"timeout":
			return "시간초과"
		"process_down":
			return "전원 쓰러짐"
		"server_breach":
			return "서버 침입"
		"unknown":
			return "판단 대기"
	return value


func _report_lines(rows: Array) -> PackedStringArray:
	var result := PackedStringArray()
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
		if result.size() >= 2:
			break
	return result


func _plain_language(source: String) -> String:
	var result := source.replace("보스 프로세스", "보스")
	result = result.replace("프로세스 다운", "쓰러짐")
	result = result.replace("WATCHDOG", "보스")
	result = result.replace("DOWN", "쓰러짐")
	result = result.replace("코어", "서버")
	result = result.replace("BIT", "비트")
	return result


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


func _operator_unlock_status(operator_id: StringName) -> String:
	var first_stars := _shift_record_best_stars(
		_snapshot.get("shift_records", []),
		1
	)
	match operator_id:
		&"debugger", &"build_engineer":
			return "시작 요원 · 해금 완료"
		&"sprite_artist":
			return "1차 야간 ★ · 현재 ★%d / 1" % first_stars
		&"qa_imp":
			return "1차 야간 ★★ · 현재 ★%d / 2" % first_stars
	return "해금 조건 확인"


func _patch_unlock_status(patch_id: StringName) -> String:
	var records: Variant = _snapshot.get("shift_records", [])
	var first := _shift_record(records, 1)
	var second := _shift_record(records, 2)
	var first_stars := clampi(int(first.get("best_stars", 0)), 0, 3)
	var first_wave := clampi(int(first.get("highest_completed_waves", 0)), 0, 10)
	match patch_id:
		&"frame_skip":
			return "1차 야간 ★ · 현재 ★%d / 1" % first_stars
		&"unsafe_build":
			return "1차 야간 5웨이브 · 현재 %d / 5" % mini(first_wave, 5)
		&"reward_bypass":
			return "1차 야간 7웨이브 · 현재 %d / 7" % mini(first_wave, 7)
		&"rollback_lock":
			return "1차 야간 9웨이브 · 현재 %d / 9" % mini(first_wave, 9)
		&"safe_mode":
			return "2차 야간 보스 조우 · 현재 %s" % (
				"조우" if bool(second.get("boss_encountered", false)) else "미조우"
			)
	return "해금 조건 확인"


func _slot_unlock_status(slot_index: int) -> String:
	var records: Variant = _snapshot.get("shift_records", [])
	var first_stars := _shift_record_best_stars(records, 1)
	var second_stars := _shift_record_best_stars(records, 2)
	match slot_index:
		0:
			return "1차 야간 ★ · 현재 ★%d / 1" % first_stars
		1:
			return "1차 야간 ★★★ · 현재 ★%d / 3" % first_stars
		2:
			return "2차 야간 ★★ · 현재 ★%d / 2" % second_stars
	return "해금 조건 확인"


func _operator_fallback_name(operator_id: StringName) -> String:
	match operator_id:
		&"debugger":
			return "디버거"
		&"build_engineer":
			return "빌드 엔지니어"
		&"sprite_artist":
			return "스프라이트 장인"
		&"qa_imp":
			return "QA 임프"
		_:
			return String(operator_id)


func _patch_fallback_name(patch_id: StringName) -> String:
	match patch_id:
		&"frame_skip":
			return "프레임 생략"
		&"unsafe_build":
			return "검증 생략"
		&"reward_bypass":
			return "보상 우회"
		&"rollback_lock":
			return "롤백 잠금"
		&"safe_mode":
			return "안전 모드"
		_:
			return String(patch_id)


func _short_condition(value: String) -> String:
	var compact := value
	compact = compact.replace("첫째 야간근무", "1차")
	compact = compact.replace("둘째 야간근무", "2차")
	compact = compact.replace(" 야간", "")
	compact = compact.replace("웨이브", "W")
	compact = compact.replace(" · 현재 ", " · ")
	compact = compact.replace(" / ", "/")
	return compact.left(20)


func _duration_text(seconds: int) -> String:
	var safe_seconds := maxi(0, seconds)
	var hours := safe_seconds / 3600
	var minutes := (safe_seconds % 3600) / 60
	if hours > 0:
		return "%d시간 %d분" % [hours, minutes]
	return "%d분" % minutes


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
