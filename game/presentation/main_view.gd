class_name MainView
extends Control

signal operations_room_requested
signal settings_requested
signal version_update_requested
signal session_changed
signal active_tab_changed(tab_index: int)

const BATTLE_LANE_VIEW_SCRIPT: GDScript = preload("res://game/presentation/battle_lane_view.gd")
const OPERATOR_UPGRADE_EFFECT_SCRIPT: GDScript = preload(
	"res://game/presentation/operator_upgrade_effect.gd"
)
const ASSETS: GDScript = preload("res://game/presentation/presentation_assets.gd")

const COLOR_BACKGROUND := Color("10151f")
const COLOR_PANEL := Color("182232")
const COLOR_PANEL_RAISED := Color("213047")
const COLOR_BORDER := Color("40526c")
const COLOR_TEXT := Color("edf4ff")
const COLOR_MUTED := Color("9dafc7")
const COLOR_CYAN := Color("52d6c8")
const COLOR_YELLOW := Color("f4c95d")
const COLOR_RED := Color("ff6b72")
const COLOR_GREEN := Color("7be495")

const TAB_OPERATORS := 0
const TAB_PATCHES := 1
const TAB_VERSION := 2
const SNAPSHOT_REFRESH_INTERVAL := 0.12

const REQUIRED_SNAPSHOT_KEYS: PackedStringArray = [
	"stage",
	"stage_enemy_index",
	"stage_enemy_total",
	"bits",
	"patch_notes",
	"run_count",
	"mode",
	"enemy",
	"operators",
	"patch_slots",
	"patches",
	"unlocked_patch_slots",
	"diagnosis",
	"prestige_available",
	"legacy_cache_level",
	"legacy_cache_cost",
	"maintenance_time_left",
	"combat_v2_test_mode",
	"combat_v2_complete",
	"offline_progress_supported",
	"status_message",
	"last_error",
]

var _session: Variant
var _audio_director: AudioDirector
var _configured := false
var _snapshot: Dictionary = {}
var _save_warning := ""
var _screen_shake_enabled := true
var _reduced_flashes := false
var _reduced_motion := false
var _active_tab: int = TAB_OPERATORS
var _selected_patch_slot: int = 0
var _selected_patch_id: String = ""
var _refresh_time_left: float = 0.0
var _feedback_time_left: float = 0.0

var _main_column: VBoxContainer
var _run_label: Label
var _bits_label: Label
var _notes_label: Label
var _stage_label: Label
var _battle_lane: BattleLaneView
var _diagnosis_title_label: Label
var _diagnosis_evidence_label: Label
var _diagnosis_panel: PanelContainer
var _diagnosis_icon: TextureRect
var _diagnosis_action_button: Button
var _diagnosis_severity: String = "info"
var _feedback_label: Label

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _operator_list: VBoxContainer
var _operator_rows: Dictionary = {}
var _slot_buttons: Array[Button] = []
var _patch_list: HBoxContainer
var _patch_buttons: Dictionary = {}
var _patch_preview_label: Label
var _equip_patch_button: Button
var _remove_patch_button: Button
var _legacy_title_label: Label
var _legacy_detail_label: Label
var _buy_legacy_button: Button
var _prestige_detail_label: Label
var _prestige_button: Button

var _button_normal_style: StyleBoxFlat
var _button_hover_style: StyleBoxFlat
var _button_selected_style: StyleBoxFlat
var _button_disabled_style: StyleBoxFlat


func configure(session: Variant, audio_director: AudioDirector) -> bool:
	if is_inside_tree():
		push_error("MainView.configure() must be called before the view enters the tree.")
		return false
	if _configured:
		push_error("MainView.configure() can only be called once.")
		return false
	if session == null:
		push_error("MainView.configure() requires an active gameplay session.")
		return false
	for method_name: StringName in [
		&"snapshot", &"upgrade_operator", &"equip_patch", &"remove_patch", &"get_patch_preview",
	]:
		if not session.has_method(method_name):
			push_error("Gameplay session is missing method '%s'." % method_name)
			return false
	if audio_director == null:
		push_error("MainView.configure() requires an AudioDirector.")
		return false
	_session = session
	_audio_director = audio_director
	_configured = true
	return true


func get_active_tab() -> int:
	return _active_tab


func set_active_tab(tab_index: int) -> bool:
	if tab_index < TAB_OPERATORS or tab_index > TAB_VERSION:
		push_error("Unknown gameplay tab index: %d" % tab_index)
		return false
	_show_tab(tab_index, false)
	return true


func refresh_from_session() -> void:
	if not _configured:
		push_error("MainView must be configured before it can refresh.")
		return
	if _feedback_label == null:
		push_error("MainView cannot refresh before its interface is built.")
		return
	_refresh_from_session()


func set_save_warning(message: String) -> void:
	_save_warning = message
	if is_node_ready() and _feedback_time_left <= 0.0:
		_refresh_feedback_from_snapshot()


func apply_accessibility(
	screen_shake_enabled: bool,
	reduced_flashes: bool,
	reduced_motion: bool
) -> void:
	_screen_shake_enabled = screen_shake_enabled
	_reduced_flashes = reduced_flashes
	_reduced_motion = reduced_motion
	if _battle_lane != null:
		_battle_lane.configure_accessibility(_reduced_flashes, _reduced_motion)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var asset_errors: PackedStringArray = ASSETS.initialize()
	if not asset_errors.is_empty():
		_show_asset_initialization_failure(asset_errors)
		set_process(false)
		return
	_build_styles()
	_build_interface()
	if not _configured:
		_show_feedback("초기화 실패: AppRoot가 현장 의존성을 전달하지 않았습니다.", true)
		set_process(false)
		return
	_refresh_from_session()


func _show_asset_initialization_failure(errors: PackedStringArray) -> void:
	for error_message: String in errors:
		push_error(error_message)
	var label := Label.new()
	label.text = "에셋 초기화 실패\n\n%s" % "\n".join(errors)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_RED)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 16.0
	label.offset_top = 16.0
	label.offset_right = -16.0
	label.offset_bottom = -16.0
	add_child(label)


func _process(delta_seconds: float) -> void:
	if not _configured:
		return

	_refresh_time_left -= delta_seconds
	_feedback_time_left = maxf(0.0, _feedback_time_left - delta_seconds)

	if _refresh_time_left <= 0.0:
		_refresh_time_left = SNAPSHOT_REFRESH_INTERVAL
		_refresh_from_session()
	if _feedback_time_left <= 0.0:
		_refresh_feedback_from_snapshot()


func _build_styles() -> void:
	_button_normal_style = _make_style(COLOR_PANEL_RAISED, COLOR_BORDER, 1)
	_button_hover_style = _make_style(Color("2b405c"), COLOR_CYAN, 2)
	_button_selected_style = _make_style(Color("183f44"), COLOR_CYAN, 2)
	_button_disabled_style = _make_style(Color("161d28"), Color("293545"), 1)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe_margin := MarginContainer.new()
	_add_margins(safe_margin, 8, 8, 8, 8)
	add_child(safe_margin)
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.name = "GameplayScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe_margin.add_child(scroll)

	_main_column = VBoxContainer.new()
	_main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_column.add_theme_constant_override("separation", 4)
	scroll.add_child(_main_column)

	_build_header()
	_build_resource_bar()
	_build_battle_panel()
	_build_diagnosis_panel()
	_build_tabs()
	_build_feedback_bar()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48.0
	row.add_theme_constant_override("separation", 4)
	_main_column.add_child(row)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	row.add_child(title_column)

	var title := _make_label("PIXEL NIGHT SHIFT", 15)
	title.add_theme_color_override("font_color", COLOR_CYAN)
	title_column.add_child(title)

	_run_label = _make_label("야간근무 1회차 · 자동 운영", 9)
	_run_label.add_theme_color_override("font_color", COLOR_MUTED)
	title_column.add_child(_run_label)

	var operations_button := _make_button("운영실", 10)
	operations_button.name = "OperationsRoomButton"
	operations_button.custom_minimum_size = Vector2(64.0, 48.0)
	operations_button.tooltip_text = "야간 운영실로 이동"
	operations_button.pressed.connect(_on_operations_room_pressed)
	row.add_child(operations_button)

	var settings_button := _make_button("설정", 10)
	settings_button.name = "SettingsButton"
	settings_button.custom_minimum_size = Vector2(56.0, 48.0)
	settings_button.tooltip_text = "소리와 접근성 설정 열기"
	settings_button.pressed.connect(_on_settings_pressed)
	row.add_child(settings_button)


func _build_resource_bar() -> void:
	var panel := _make_panel(COLOR_PANEL, COLOR_BORDER)
	panel.custom_minimum_size.y = 34.0
	_main_column.add_child(panel)

	var margin := MarginContainer.new()
	_add_margins(margin, 8, 8, 3, 3)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	_bits_label = _make_resource_label("0", COLOR_YELLOW)
	_notes_label = _make_resource_label("0", COLOR_CYAN)
	_stage_label = _make_resource_label("01", COLOR_TEXT)
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_make_resource_chip(&"bit", "비트", _bits_label))
	row.add_child(_make_resource_chip(&"patch_note", "노트", _notes_label))
	row.add_child(_make_resource_chip(&"stage", "ST", _stage_label))


func _build_battle_panel() -> void:
	_battle_lane = BATTLE_LANE_VIEW_SCRIPT.new()
	_battle_lane.name = "BattleLaneView"
	_battle_lane.configure_accessibility(_reduced_flashes, _reduced_motion)
	_main_column.add_child(_battle_lane)


func _build_diagnosis_panel() -> void:
	_diagnosis_panel = _make_panel(Color("192a37"), COLOR_CYAN)
	_diagnosis_panel.custom_minimum_size.y = 68.0
	_main_column.add_child(_diagnosis_panel)

	var margin := MarginContainer.new()
	_add_margins(margin, 8, 8, 5, 5)
	_diagnosis_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	_diagnosis_icon = _make_texture_rect(28)
	_diagnosis_icon.texture = ASSETS.ui_texture(&"diagnosis")
	row.add_child(_diagnosis_icon)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)
	_diagnosis_title_label = _make_label("[진단] 운영 데이터를 수집 중입니다", 12)
	_diagnosis_title_label.add_theme_color_override("font_color", COLOR_CYAN)
	column.add_child(_diagnosis_title_label)
	_diagnosis_evidence_label = _make_label("전투가 시작되면 가장 큰 병목 하나를 표시합니다.", 10)
	_diagnosis_evidence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnosis_evidence_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_diagnosis_evidence_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_diagnosis_evidence_label)

	_diagnosis_action_button = _make_button("패치\n보기", 9)
	_diagnosis_action_button.name = "DiagnosisActionButton"
	_diagnosis_action_button.custom_minimum_size = Vector2(58.0, 48.0)
	_diagnosis_action_button.pressed.connect(_on_diagnosis_action_pressed)
	row.add_child(_diagnosis_action_button)


func _build_tabs() -> void:
	var tab_row := HBoxContainer.new()
	tab_row.custom_minimum_size.y = 48.0
	tab_row.add_theme_constant_override("separation", 4)
	_main_column.add_child(tab_row)

	var labels: PackedStringArray = ["요원 강화", "패치 보드", "버전 업데이트"]
	for index: int in range(labels.size()):
		var button := _make_button(labels[index])
		button.name = "GameplayTabButton%d" % index
		button.custom_minimum_size.y = 48.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_tab_pressed.bind(index))
		tab_row.add_child(button)
		_tab_buttons.append(button)

	var page_host := Control.new()
	page_host.custom_minimum_size.y = 206.0
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_column.add_child(page_host)

	_build_operator_page(page_host)
	_build_patch_page(page_host)
	_build_version_page(page_host)
	_show_tab(_active_tab, false)


func _build_operator_page(page_host: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_host.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages.append(scroll)

	_operator_list = VBoxContainer.new()
	_operator_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_operator_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_operator_list)


func _build_patch_page(page_host: Control) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 4)
	page_host.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages.append(page)

	var slot_row := HBoxContainer.new()
	slot_row.custom_minimum_size.y = 48.0
	slot_row.add_theme_constant_override("separation", 4)
	page.add_child(slot_row)
	for slot_index: int in range(3):
		var slot_button := _make_button("슬롯 %d\n잠김" % (slot_index + 1), 10)
		slot_button.name = "PatchSlot%d" % slot_index
		slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_button.pressed.connect(_on_patch_slot_pressed.bind(slot_index))
		slot_row.add_child(slot_button)
		_slot_buttons.append(slot_button)

	var candidate_hint := _make_label("후보 5개 · 좌우로 넘겨 장점과 부작용 비교", 9)
	candidate_hint.custom_minimum_size.y = 14.0
	candidate_hint.add_theme_color_override("font_color", COLOR_MUTED)
	page.add_child(candidate_hint)

	var candidate_scroll := ScrollContainer.new()
	candidate_scroll.custom_minimum_size.y = 62.0
	candidate_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(candidate_scroll)
	_patch_list = HBoxContainer.new()
	_patch_list.add_theme_constant_override("separation", 4)
	candidate_scroll.add_child(_patch_list)

	var preview_panel := _make_panel(Color("111a27"), COLOR_BORDER)
	preview_panel.custom_minimum_size.y = 48.0
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(preview_panel)
	var preview_margin := MarginContainer.new()
	_add_margins(preview_margin, 7, 7, 3, 3)
	preview_panel.add_child(preview_margin)
	_patch_preview_label = _make_label("패치를 선택하면 예상 처치 시간과 비트 효율을 비교합니다.", 9)
	_patch_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_patch_preview_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	preview_margin.add_child(_patch_preview_label)

	var action_row := HBoxContainer.new()
	action_row.custom_minimum_size.y = 48.0
	action_row.add_theme_constant_override("separation", 4)
	page.add_child(action_row)
	_equip_patch_button = _make_button("선택한 패치 장착", 11)
	_equip_patch_button.name = "EquipPatchButton"
	_equip_patch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_patch_button.pressed.connect(_on_equip_patch_pressed)
	action_row.add_child(_equip_patch_button)
	_remove_patch_button = _make_button("비용으로 슬롯 비우기", 10)
	_remove_patch_button.name = "RemovePatchButton"
	_remove_patch_button.custom_minimum_size.x = 104.0
	_remove_patch_button.pressed.connect(_on_remove_patch_pressed)
	action_row.add_child(_remove_patch_button)


func _build_version_page(page_host: Control) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page_host.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages.append(page)

	var legacy_panel := _make_panel(COLOR_PANEL, COLOR_BORDER)
	legacy_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(legacy_panel)
	var legacy_margin := MarginContainer.new()
	_add_margins(legacy_margin, 9, 9, 6, 6)
	legacy_panel.add_child(legacy_margin)
	var legacy_column := VBoxContainer.new()
	legacy_column.add_theme_constant_override("separation", 2)
	legacy_margin.add_child(legacy_column)
	_legacy_title_label = _make_label("레거시 빌드 캐시 Lv.0", 13)
	_legacy_title_label.add_theme_color_override("font_color", COLOR_CYAN)
	legacy_column.add_child(_legacy_title_label)
	_legacy_detail_label = _make_label("패치노트로 다음 근무의 기본 화력을 높입니다.", 10)
	_legacy_detail_label.add_theme_color_override("font_color", COLOR_MUTED)
	legacy_column.add_child(_legacy_detail_label)
	_buy_legacy_button = _make_button("패치노트 1개로 구매", 11)
	_buy_legacy_button.pressed.connect(_on_buy_legacy_pressed)
	legacy_column.add_child(_buy_legacy_button)

	var prestige_panel := _make_panel(Color("201e31"), Color("7563a8"))
	prestige_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(prestige_panel)
	var prestige_margin := MarginContainer.new()
	_add_margins(prestige_margin, 9, 9, 6, 6)
	prestige_panel.add_child(prestige_margin)
	var prestige_column := VBoxContainer.new()
	prestige_column.add_theme_constant_override("separation", 2)
	prestige_margin.add_child(prestige_column)
	_prestige_detail_label = _make_label("STAGE 20을 복구하면 버전 업데이트가 열립니다.", 10)
	_prestige_detail_label.add_theme_color_override("font_color", COLOR_TEXT)
	prestige_column.add_child(_prestige_detail_label)
	_prestige_button = _make_button("버전 업데이트 잠김", 11)
	_prestige_button.name = "VersionUpdateButton"
	_prestige_button.pressed.connect(_on_prestige_pressed)
	prestige_column.add_child(_prestige_button)


func _build_feedback_bar() -> void:
	_feedback_label = _make_label("자동 운영 준비 중...", 10)
	_feedback_label.custom_minimum_size.y = 24.0
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_color_override("font_color", COLOR_MUTED)
	_main_column.add_child(_feedback_label)


func _refresh_from_session() -> void:
	var raw_snapshot: Variant = _session.snapshot()
	if not (raw_snapshot is Dictionary):
		_show_feedback("화면 데이터 오류: snapshot()이 Dictionary를 반환하지 않았습니다.", true)
		return

	var next_snapshot: Dictionary = raw_snapshot
	var validation_error := _validate_snapshot(next_snapshot)
	if not validation_error.is_empty():
		_show_feedback("화면 데이터 오류: %s" % validation_error, true)
		return

	var previous_snapshot := _snapshot
	_snapshot = next_snapshot
	_refresh_header()
	_refresh_battle(previous_snapshot)
	_refresh_diagnosis()
	_refresh_operators()
	_refresh_patches()
	_refresh_version_page()
	_refresh_tab_styles()


func _validate_snapshot(data: Dictionary) -> String:
	for key: String in REQUIRED_SNAPSHOT_KEYS:
		if not data.has(key):
			return "필수 항목 '%s'이(가) 없습니다." % key

	if not (data["enemy"] is Dictionary):
		return "enemy 항목이 Dictionary가 아닙니다."
	var enemy: Dictionary = data["enemy"]
	for key: String in ["name", "hp", "max_hp", "is_boss", "time_left"]:
		if not enemy.has(key):
			return "enemy.%s 항목이 없습니다." % key

	if not (data["operators"] is Array) or data["operators"].size() != 4:
		return "operators는 요원 4명의 Array여야 합니다."
	for item: Variant in data["operators"]:
		if not (item is Dictionary):
			return "operators 항목이 Dictionary가 아닙니다."
		for key: String in ["id", "name", "level", "unlocked", "dps", "upgrade_cost"]:
			if not item.has(key):
				return "operator.%s 항목이 없습니다." % key

	if not (data["patch_slots"] is Array) or data["patch_slots"].size() != 3:
		return "patch_slots는 슬롯 3개의 Array여야 합니다."
	if not (data["patches"] is Array) or data["patches"].size() != 5:
		return "patches는 후보 5개의 Array여야 합니다."
	for item: Variant in data["patches"]:
		if not (item is Dictionary):
			return "patches 항목이 Dictionary가 아닙니다."
		for key: String in ["id", "name", "description", "benefit", "drawback", "unlocked", "equipped"]:
			if not item.has(key):
				return "patch.%s 항목이 없습니다." % key

	if bool(data["combat_v2_test_mode"]):
		for key: String in [
			"failure_count", "normal_failure_count", "boss_failure_count", "last_failure_reason",
			"qa_rescue_count", "paid_redeploy_count", "emergency_spent_bits", "gross_bits",
			"net_bits", "combat_metrics",
		]:
			if not data.has(key):
				return "Combat V2 snapshot.%s is missing." % key
		for key: String in ["next_action", "next_action_in"]:
			if not enemy.has(key):
				return "Combat V2 enemy.%s is missing." % key
		if not data.has("emergency_redeploy") or not (data["emergency_redeploy"] is Dictionary):
			return "Combat V2 emergency_redeploy must be a Dictionary."
		var emergency := data["emergency_redeploy"] as Dictionary
		for key: String in ["cost", "available", "affordable", "remaining", "reserved_operator_id", "eligible_targets"]:
			if not emergency.has(key):
				return "Combat V2 emergency_redeploy.%s is missing." % key
		for item: Variant in data["operators"]:
			for key: String in [
				"role", "hp", "max_hp", "process_down", "recovery_source",
				"recovery_remaining", "redeploy_eligible",
			]:
				if not item.has(key):
					return "Combat V2 operator.%s is missing." % key
		var diagnosis := data["diagnosis"] as Dictionary
		if not diagnosis.has("evidence_data") or not (diagnosis["evidence_data"] is Dictionary):
			return "Combat V2 diagnosis.evidence_data must be a Dictionary."
		for key: String in [
			"recovery_cost", "current_downs", "forecast_downs", "estimated_wipe_risk",
			"failure_count", "maintenance", "maintenance_remaining", "emergency_available",
		]:
			if not diagnosis["evidence_data"].has(key):
				return "Combat V2 diagnosis.evidence_data.%s is missing." % key

	return ""


func _refresh_header() -> void:
	var run_number := int(_snapshot["run_count"]) + 1
	_run_label.text = (
		"COMBAT V2 TEST · 자동 전투"
		if bool(_snapshot["combat_v2_test_mode"])
		else "야간근무 %d회차 · 자동 운영" % run_number
	)
	_bits_label.text = _format_number(float(_snapshot["bits"]))
	_notes_label.text = (
		"F%d" % int(_snapshot["failure_count"])
		if bool(_snapshot["combat_v2_test_mode"])
		else str(int(_snapshot["patch_notes"]))
	)
	_stage_label.text = "%02d" % int(_snapshot["stage"])


func _refresh_battle(previous_snapshot: Dictionary) -> void:
	_battle_lane.update_from_snapshot(_snapshot, previous_snapshot)


func _refresh_diagnosis() -> void:
	var raw_diagnosis: Variant = _snapshot["diagnosis"]
	if not (raw_diagnosis is Dictionary):
		_set_diagnosis_error("get_diagnosis()이 Dictionary를 반환하지 않았습니다.")
		return

	var diagnosis: Dictionary = raw_diagnosis
	for key: String in ["kind", "title", "evidence", "severity"]:
		if not diagnosis.has(key):
			_set_diagnosis_error("diagnosis.%s 항목이 없습니다." % key)
			return

	var severity := String(diagnosis["severity"])
	_diagnosis_severity = severity
	var accent := _severity_color(severity)
	_diagnosis_title_label.text = "%s %s" % [_severity_tag(severity), String(diagnosis["title"])]
	_diagnosis_title_label.add_theme_color_override("font_color", accent)
	_diagnosis_evidence_label.text = String(diagnosis["evidence"])
	if bool(_snapshot["combat_v2_test_mode"]):
		var evidence_data := diagnosis["evidence_data"] as Dictionary
		_diagnosis_evidence_label.text += "\n현재/예상 다운 %d/%d · 실패 %d · wipe %s · 복구 %sb" % [
			int(evidence_data["current_downs"]),
			int(evidence_data["forecast_downs"]),
			int(evidence_data["failure_count"]),
			String(evidence_data["estimated_wipe_risk"]),
			_format_number(float(evidence_data["recovery_cost"])),
		]
	_diagnosis_icon.modulate = accent
	_diagnosis_panel.add_theme_stylebox_override("panel", _make_style(Color("192a37"), accent, 2))


func _set_diagnosis_error(message: String) -> void:
	_diagnosis_severity = "critical"
	_diagnosis_title_label.text = "[오류] 진단 데이터를 읽을 수 없습니다"
	_diagnosis_title_label.add_theme_color_override("font_color", COLOR_RED)
	_diagnosis_evidence_label.text = message
	_diagnosis_icon.modulate = COLOR_RED
	_diagnosis_panel.add_theme_stylebox_override("panel", _make_style(Color("321c25"), COLOR_RED, 2))
	_show_feedback("진단 화면 오류: %s" % message, true)


func _refresh_operators() -> void:
	for item: Variant in _snapshot["operators"]:
		var operator_data: Dictionary = item
		var operator_id := String(operator_data["id"])
		if not _operator_rows.has(operator_id):
			_create_operator_row(operator_data)

		var row_data: Dictionary = _operator_rows[operator_id]
		var info_label: Label = row_data["info"]
		var upgrade_button: Button = row_data["button"]
		var redeploy_button: Button = row_data["redeploy"]
		var unlocked := bool(operator_data["unlocked"])
		if unlocked:
			if bool(_snapshot["combat_v2_test_mode"]):
				var status := "가동"
				if bool(operator_data["process_down"]):
					status = "PROCESS DOWN"
				info_label.text = "%s Lv.%d · %s\n%s · HP %s/%s · D %s" % [
					String(operator_data["name"]), int(operator_data["level"]),
					String(operator_data["role"]), status,
					_format_number(float(operator_data["hp"])),
					_format_number(float(operator_data["max_hp"])),
					_format_number(float(operator_data["dps"])),
				]
			else:
				info_label.text = "%s  Lv.%d\n초당 피해 %s" % [
					String(operator_data["name"]),
					int(operator_data["level"]),
					_format_number(float(operator_data["dps"])),
				]
			upgrade_button.text = "비트 %s\n강화" % _format_number(float(operator_data["upgrade_cost"]))
		else:
			info_label.text = "%s\n진행하면 자동 합류" % String(operator_data["name"])
			upgrade_button.text = "잠김"
		upgrade_button.disabled = not unlocked
		redeploy_button.visible = (
			bool(_snapshot["combat_v2_test_mode"])
			and String(_snapshot["mode"]) != "maintenance"
			and unlocked
			and bool(operator_data["process_down"])
		)
		if redeploy_button.visible:
			var recovery_source := String(operator_data["recovery_source"])
			if recovery_source.is_empty():
				redeploy_button.text = "재배포\n%sb" % _format_number(float(_snapshot["emergency_redeploy"]["cost"]))
				redeploy_button.disabled = not bool(operator_data["redeploy_available"])
				redeploy_button.tooltip_text = String(operator_data["redeploy_error"])
			else:
				redeploy_button.text = "%s\n%.1fs" % [recovery_source.to_upper(), float(operator_data["recovery_remaining"])]
				redeploy_button.disabled = true


func _create_operator_row(operator_data: Dictionary) -> void:
	var operator_id := String(operator_data["id"])
	var panel := _make_panel(COLOR_PANEL, COLOR_BORDER)
	panel.custom_minimum_size.y = 62.0
	_operator_list.add_child(panel)

	var margin := MarginContainer.new()
	_add_margins(margin, 8, 5, 2, 2)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	var portrait_slot := Control.new()
	portrait_slot.custom_minimum_size = Vector2(36.0, 36.0)
	portrait_slot.size = Vector2(36.0, 36.0)
	row.add_child(portrait_slot)
	var portrait := _make_texture_rect(32)
	portrait.name = "OperatorCardPortrait_%s" % operator_id
	portrait.position = Vector2(2.0, 4.0)
	portrait.texture = ASSETS.operator_texture(StringName(operator_id))
	portrait_slot.add_child(portrait)
	var info := _make_label("", 9)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.clip_text = true
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.custom_minimum_size.x = 110.0
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var button := _make_button("강화", 10)
	button.name = "UpgradeOperator_%s" % operator_id
	button.custom_minimum_size = Vector2(72.0, 48.0)
	button.pressed.connect(_on_upgrade_pressed.bind(operator_id))
	row.add_child(button)
	var redeploy := _make_button("재배포", 9)
	redeploy.name = "EmergencyRedeploy_%s" % operator_id
	redeploy.custom_minimum_size = Vector2(58.0, 48.0)
	redeploy.visible = false
	redeploy.pressed.connect(_on_emergency_redeploy_pressed.bind(operator_id))
	row.add_child(redeploy)

	var upgrade_effect: Variant = OPERATOR_UPGRADE_EFFECT_SCRIPT.new()
	panel.add_child(upgrade_effect)
	upgrade_effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_effect.configure(panel, portrait)
	_operator_rows[operator_id] = {
		"info": info,
		"button": button,
		"redeploy": redeploy,
		"portrait": portrait,
		"upgrade_effect": upgrade_effect,
	}


func _refresh_patches() -> void:
	var patch_name_by_id: Dictionary = {}
	for item: Variant in _snapshot["patches"]:
		var patch_data: Dictionary = item
		var patch_id := String(patch_data["id"])
		patch_name_by_id[patch_id] = String(patch_data["name"])
		if not _patch_buttons.has(patch_id):
			_create_patch_button(patch_data)

		var button: Button = _patch_buttons[patch_id]
		var unlocked := bool(patch_data["unlocked"])
		var equipped_tag := "[장착] " if bool(patch_data["equipped"]) else ""
		button.text = "%s%s\n%s / %s" % [
			equipped_tag,
			String(patch_data["name"]),
			String(patch_data["benefit"]),
			String(patch_data["drawback"]),
		]
		button.disabled = not unlocked
		_set_button_selected(button, patch_id == _selected_patch_id)

	var unlocked_slots := int(_snapshot["unlocked_patch_slots"])
	var slots: Array = _snapshot["patch_slots"]
	for slot_index: int in range(3):
		var slot_button := _slot_buttons[slot_index]
		var unlocked := slot_index < unlocked_slots
		var equipped_patch_id := String(slots[slot_index])
		var patch_name := "비어 있음"
		if not equipped_patch_id.is_empty() and patch_name_by_id.has(equipped_patch_id):
			patch_name = String(patch_name_by_id[equipped_patch_id])
		slot_button.text = "슬롯 %d\n%s" % [slot_index + 1, patch_name if unlocked else "잠김"]
		slot_button.disabled = not unlocked
		_set_button_selected(slot_button, slot_index == _selected_patch_slot and unlocked)

	_remove_patch_button.disabled = _selected_patch_slot >= unlocked_slots or String(slots[_selected_patch_slot]).is_empty()
	_refresh_patch_preview()


func _create_patch_button(patch_data: Dictionary) -> void:
	var patch_id := String(patch_data["id"])
	var button := _make_button(String(patch_data["name"]), 9)
	button.name = "PatchCandidate_%s" % patch_id
	button.custom_minimum_size = Vector2(148.0, 62.0)
	button.icon = ASSETS.patch_texture(StringName(patch_id))
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = String(patch_data["description"])
	button.pressed.connect(_on_patch_candidate_pressed.bind(patch_id))
	_patch_list.add_child(button)
	_patch_buttons[patch_id] = button


func _refresh_patch_preview() -> void:
	if _selected_patch_id.is_empty():
		_patch_preview_label.text = "후보를 선택하면 장점과 부작용을 함께 비교합니다."
		_patch_preview_label.add_theme_color_override("font_color", COLOR_TEXT)
		_equip_patch_button.text = "선택한 패치 장착"
		_equip_patch_button.disabled = true
		return

	var raw_preview: Variant = _session.get_patch_preview(_selected_patch_slot, _selected_patch_id)
	if not (raw_preview is Dictionary):
		_set_patch_preview_error("미리보기가 Dictionary가 아닙니다.")
		return
	var preview: Dictionary = raw_preview
	for key: String in [
		"can_equip",
		"cost",
		"summary",
		"before_ttk",
		"after_ttk",
		"before_bits_multiplier",
		"after_bits_multiplier",
	]:
		if not preview.has(key):
			_set_patch_preview_error("preview.%s 항목이 없습니다." % key)
			return

	_patch_preview_label.add_theme_color_override("font_color", COLOR_TEXT)
	var selected_patch := _patch_data(_selected_patch_id)
	_patch_preview_label.text = "%s\n처치 %s → %s · 비트 ×%.2f → ×%.2f · 비용 %s" % [
		String(selected_patch["description"]),
		_format_seconds(float(preview["before_ttk"])),
		_format_seconds(float(preview["after_ttk"])),
		float(preview["before_bits_multiplier"]),
		float(preview["after_bits_multiplier"]),
		_format_number(float(preview["cost"])),
	]
	var can_equip := bool(preview["can_equip"])
	_equip_patch_button.text = "비트 %s로 장착" % _format_number(float(preview["cost"])) if can_equip else "현재 장착 불가"
	_equip_patch_button.disabled = not can_equip


func _set_patch_preview_error(message: String) -> void:
	_patch_preview_label.text = "[오류] %s" % message
	_patch_preview_label.add_theme_color_override("font_color", COLOR_RED)
	_equip_patch_button.disabled = true
	_show_feedback("패치 미리보기 오류: %s" % message, true)


func _refresh_version_page() -> void:
	if bool(_snapshot["combat_v2_test_mode"]):
		_legacy_title_label.text = "Combat V2 격리 테스트"
		_legacy_detail_label.text = "STAGE 1~10 · production 저장/버전 업데이트와 분리됨"
		_buy_legacy_button.text = "레거시 성장 미사용"
		_buy_legacy_button.disabled = true
		_prestige_detail_label.text = (
			"Watchdog 격리 완료 · 결과 화면으로 이동합니다."
			if bool(_snapshot["combat_v2_complete"])
			else "STAGE 10 Watchdog 격리 후 읽기 전용 결과를 확인합니다."
		)
		_prestige_button.text = "Combat V2 테스트 진행 중"
		_prestige_button.disabled = true
		_set_button_selected(_prestige_button, false)
		return
	var legacy_level := int(_snapshot["legacy_cache_level"])
	var legacy_cost := int(_snapshot["legacy_cache_cost"])
	var patch_notes := int(_snapshot["patch_notes"])
	var prestige_available := bool(_snapshot["prestige_available"])

	_legacy_title_label.text = "레거시 빌드 캐시 Lv.%d" % legacy_level
	_legacy_detail_label.text = "영구 화력 강화 · 보유 패치노트 %d개" % patch_notes
	if legacy_cost <= 0:
		_buy_legacy_button.text = "레거시 빌드 캐시 최대 단계"
		_buy_legacy_button.disabled = true
	else:
		_buy_legacy_button.text = "패치노트 %d개로 구매" % legacy_cost
		_buy_legacy_button.disabled = patch_notes < legacy_cost

	if prestige_available:
		_prestige_detail_label.text = "현재 진행을 초기화하고 패치노트 1개를 남깁니다. 직접 선택할 때만 실행됩니다."
		_prestige_button.text = "대규모 버전 업데이트 시작"
		_prestige_button.disabled = false
		_set_button_selected(_prestige_button, true)
	else:
		_prestige_detail_label.text = "STAGE 20을 복구하면 버전 업데이트가 열립니다."
		_prestige_button.text = "버전 업데이트 잠김"
		_prestige_button.disabled = true
		_set_button_selected(_prestige_button, false)


func _refresh_tab_styles() -> void:
	for index: int in range(_tab_buttons.size()):
		var button := _tab_buttons[index]
		_set_button_selected(button, index == _active_tab)
		if index == TAB_PATCHES and index != _active_tab and _diagnosis_severity in ["medium", "warning", "high", "critical"]:
			button.add_theme_stylebox_override("normal", _make_style(Color("2d2b25"), COLOR_YELLOW, 2))
			button.add_theme_color_override("font_color", COLOR_YELLOW)


func _refresh_feedback_from_snapshot() -> void:
	if _snapshot.is_empty():
		return
	if not _save_warning.is_empty():
		_feedback_label.text = "[저장 오류] %s" % _save_warning
		_feedback_label.add_theme_color_override("font_color", COLOR_RED)
		return
	var last_error := String(_snapshot["last_error"])
	if not last_error.is_empty():
		_feedback_label.text = "[오류] %s" % last_error
		_feedback_label.add_theme_color_override("font_color", COLOR_RED)
		return
	var status_message := String(_snapshot["status_message"])
	if status_message.is_empty():
		status_message = "자동 운영 중 · 전투 조작 없이 병목을 관찰하세요."
	_feedback_label.text = status_message
	_feedback_label.add_theme_color_override("font_color", COLOR_MUTED)


func _on_tab_pressed(tab_index: int) -> void:
	_audio_director.play_cue(&"ui_move")
	_show_tab(tab_index)


func _on_diagnosis_action_pressed() -> void:
	_audio_director.play_cue(&"ui_move")
	_show_tab(TAB_PATCHES)
	_show_feedback("진단 근거와 패치의 장단점을 비교하세요.", false)


func _on_operations_room_pressed() -> void:
	_audio_director.play_cue(&"ui_move")
	operations_room_requested.emit()


func _on_settings_pressed() -> void:
	_audio_director.play_cue(&"ui_move")
	settings_requested.emit()


func _show_tab(tab_index: int, notify_change: bool = true) -> void:
	var changed := _active_tab != tab_index
	_active_tab = tab_index
	for index: int in range(_pages.size()):
		_pages[index].visible = index == tab_index
	_refresh_tab_styles()
	if changed and notify_change:
		active_tab_changed.emit(_active_tab)


func _on_upgrade_pressed(operator_id: String) -> void:
	var operator_name := _operator_name(operator_id)
	var previous_dps := _operator_dps(operator_id)
	var succeeded := bool(_session.upgrade_operator(operator_id))
	_finish_command(succeeded, "%s LEVEL UP" % operator_name, &"operator_upgrade")
	if not succeeded:
		return
	var dps_delta := maxf(0.0, _operator_dps(operator_id) - previous_dps)
	_play_operator_upgrade_visual(operator_id, dps_delta)
	_show_feedback(
		"%s LEVEL UP · DPS +%s" % [operator_name, _format_number(dps_delta)],
		false
	)


func _on_emergency_redeploy_pressed(operator_id: String) -> void:
	if not bool(_snapshot.get("combat_v2_test_mode", false)):
		_show_feedback("긴급 재배포는 Combat V2 테스트에서만 사용할 수 있습니다.", true)
		return
	var succeeded := bool(_session.emergency_redeploy(operator_id))
	_finish_command(
		succeeded,
		"%s 긴급 재배포 예약 · 2초 후 40%% HP" % _operator_name(operator_id),
		&"ui_confirm"
	)


func _on_patch_slot_pressed(slot_index: int) -> void:
	_audio_director.play_cue(&"ui_move")
	_selected_patch_slot = slot_index
	_refresh_patches()
	_show_feedback("패치 슬롯 %d을 선택했습니다." % (slot_index + 1), false)


func _on_patch_candidate_pressed(patch_id: String) -> void:
	_audio_director.play_cue(&"ui_move")
	_selected_patch_id = patch_id
	_refresh_patches()
	_show_feedback("패치 효과를 미리 계산했습니다. 장점과 부작용을 확인하세요.", false)


func _on_equip_patch_pressed() -> void:
	if _selected_patch_id.is_empty():
		_show_feedback("장착할 패치를 먼저 선택하세요.", true)
		return
	var succeeded := bool(_session.equip_patch(_selected_patch_slot, _selected_patch_id))
	_finish_command(succeeded, "패치 슬롯 %d에 장착했습니다." % (_selected_patch_slot + 1), &"patch_apply")


func _on_remove_patch_pressed() -> void:
	var succeeded := bool(_session.remove_patch(_selected_patch_slot))
	_finish_command(succeeded, "패치 슬롯 %d을 비웠습니다." % (_selected_patch_slot + 1), &"patch_remove")


func _on_buy_legacy_pressed() -> void:
	var succeeded := bool(_session.buy_legacy_cache())
	_finish_command(succeeded, "레거시 빌드 캐시를 영구 강화했습니다.", &"ui_confirm")


func _on_prestige_pressed() -> void:
	_audio_director.play_cue(&"ui_confirm")
	version_update_requested.emit()


func _finish_command(
	succeeded: bool,
	success_message: String,
	success_cue: StringName = &"ui_confirm"
) -> void:
	_refresh_from_session()
	if succeeded:
		session_changed.emit()
		_audio_director.play_cue(success_cue)
		_show_feedback(success_message, false)
		return
	_audio_director.play_cue(&"ui_error")
	var failure_message := "요청을 처리하지 못했습니다."
	if not _snapshot.is_empty() and not String(_snapshot["last_error"]).is_empty():
		failure_message = String(_snapshot["last_error"])
	_show_feedback(failure_message, true)


func _show_feedback(message: String, is_error: bool) -> void:
	_feedback_label.text = ("[오류] " if is_error else "[완료] ") + message
	_feedback_label.add_theme_color_override("font_color", COLOR_RED if is_error else COLOR_GREEN)
	_feedback_time_left = 3.5


func _operator_name(operator_id: String) -> String:
	var operator_data := _operator_data(operator_id)
	return operator_id if operator_data.is_empty() else String(operator_data["name"])


func _operator_dps(operator_id: String) -> float:
	var operator_data := _operator_data(operator_id)
	assert(not operator_data.is_empty(), "Unknown operator id: %s" % operator_id)
	return float(operator_data["dps"])


func _operator_data(operator_id: String) -> Dictionary:
	if _snapshot.is_empty():
		return {}
	for item: Variant in _snapshot["operators"]:
		var operator_data: Dictionary = item
		if String(operator_data["id"]) == operator_id:
			return operator_data
	return {}


func _play_operator_upgrade_visual(operator_id: String, dps_delta: float) -> void:
	assert(_operator_rows.has(operator_id), "Missing operator row: %s" % operator_id)
	var row_data: Dictionary = _operator_rows[operator_id]
	var upgrade_effect: Variant = row_data["upgrade_effect"]
	if not _reduced_motion and not _reduced_flashes:
		upgrade_effect.play(dps_delta)
	_battle_lane.play_operator_upgrade(StringName(operator_id))


func _patch_data(patch_id: String) -> Dictionary:
	for item: Variant in _snapshot["patches"]:
		var patch_data: Dictionary = item
		if String(patch_data["id"]) == patch_id:
			return patch_data
	assert(false, "Unknown patch id: %s" % patch_id)
	return {}


func _severity_tag(severity: String) -> String:
	match severity:
		"high", "critical":
			return "[위험]"
		"medium", "warning":
			return "[주의]"
		"low", "info":
			return "[관찰]"
		_:
			return "[진단]"


func _severity_color(severity: String) -> Color:
	match severity:
		"high", "critical":
			return COLOR_RED
		"medium", "warning":
			return COLOR_YELLOW
		"low", "info":
			return COLOR_CYAN
		_:
			return COLOR_GREEN


func _format_number(value: float) -> String:
	var absolute := absf(value)
	if absolute >= 1_000_000_000.0:
		return "%.2fB" % (value / 1_000_000_000.0)
	if absolute >= 1_000_000.0:
		return "%.2fM" % (value / 1_000_000.0)
	if absolute >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _format_seconds(value: float) -> String:
	if is_inf(value):
		return "계산 불가"
	return "%.1f초" % maxf(0.0, value)


func _make_panel(background_color: Color, border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_style(background_color, border_color, 1))
	return panel


func _make_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _make_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _make_resource_label(text_value: String, text_color: Color) -> Label:
	var label := _make_label(text_value, 11)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", text_color)
	return label


func _make_resource_chip(icon_id: StringName, caption: String, value_label: Label) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_constant_override("separation", 3)
	var icon := _make_texture_rect(16)
	icon.texture = ASSETS.ui_texture(icon_id)
	chip.add_child(icon)
	var caption_label := _make_label(caption, 8)
	caption_label.add_theme_color_override("font_color", COLOR_MUTED)
	chip.add_child(caption_label)
	chip.add_child(value_label)
	return chip


func _make_texture_rect(size_pixels: int) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(size_pixels, size_pixels)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


func _make_button(text_value: String, font_size: int = 11) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 48.0
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color("66758a"))
	button.add_theme_stylebox_override("normal", _button_normal_style)
	button.add_theme_stylebox_override("hover", _button_hover_style)
	button.add_theme_stylebox_override("pressed", _button_selected_style)
	button.add_theme_stylebox_override("focus", _button_hover_style)
	button.add_theme_stylebox_override("disabled", _button_disabled_style)
	return button


func _set_button_selected(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", _button_selected_style if selected else _button_normal_style)
	button.add_theme_color_override("font_color", COLOR_CYAN if selected else COLOR_TEXT)


func _add_margins(container: MarginContainer, left: int, right: int, top: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_bottom", bottom)
