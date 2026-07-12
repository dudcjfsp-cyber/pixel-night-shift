class_name AppShellOperationsRoomView
extends Control

signal continue_requested
signal manual_requested
signal settings_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const ARTWORK_SLOT_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/app_shell_artwork_slot.gd"
)
const OPERATIONS_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/operations_room_view_data.gd"
)

var _data: OPERATIONS_DATA_SCRIPT
var _configuration_error := ""
var _artwork_slot: ARTWORK_SLOT_SCRIPT
var _artwork: Texture2D
var _run_status_label: Label
var _automatic_value: Label
var _stage_value: Label
var _bottleneck_value: Label
var _patch_value: Label
var _goal_value: Label
var _save_panel: PanelContainer
var _save_status_label: Label
var _primary_button: Button


func configure(data: OPERATIONS_DATA_SCRIPT) -> bool:
	if data == null:
		_reject_configuration("OperationsRoomViewData is required.")
		return false
	var errors: PackedStringArray = data.validation_errors()
	if not errors.is_empty():
		_reject_configuration("Invalid OperationsRoomViewData: %s" % "; ".join(errors))
		return false
	_configuration_error = ""
	_data = data
	if is_node_ready():
		_render_data()
	return true


func set_artwork(texture: Texture2D) -> void:
	_artwork = texture
	if _artwork_slot != null:
		_artwork_slot.set_artwork(_artwork)


func configuration_error() -> String:
	return _configuration_error


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	if _data != null:
		_render_data()
	elif not _configuration_error.is_empty():
		_render_configuration_error()


func _build_interface() -> void:
	var column: VBoxContainer = UI.attach_scrollable_screen_frame(self, UI.GAP_MEDIUM)
	_build_header(column)

	var artwork_panel: PanelContainer = UI.make_panel(UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 0)
	artwork_panel.custom_minimum_size.y = 224.0
	column.add_child(artwork_panel)
	_artwork_slot = ARTWORK_SLOT_SCRIPT.new()
	_artwork_slot.name = "ArtworkSlot"
	_artwork_slot.set_fallback_kind(ARTWORK_SLOT_SCRIPT.OPERATIONS_ROOM)
	if _artwork != null:
		_artwork_slot.set_artwork(_artwork)
	artwork_panel.add_child(_artwork_slot)

	var summary_panel: PanelContainer = UI.make_panel(
		UI.COLOR_PANEL, UI.COLOR_BORDER, 1, 8
	)
	column.add_child(summary_panel)
	var summary_column := VBoxContainer.new()
	summary_column.add_theme_constant_override("separation", UI.GAP_SMALL)
	summary_panel.add_child(summary_column)
	_automatic_value = _add_summary_row(summary_column, "운영 상태")
	_stage_value = _add_summary_row(summary_column, "현재 현장")
	_bottleneck_value = _add_summary_row(summary_column, "주요 병목")
	_patch_value = _add_summary_row(summary_column, "장착 패치")
	_goal_value = _add_summary_row(summary_column, "다음 목표")

	_save_panel = UI.make_panel(UI.COLOR_PANEL, UI.COLOR_SAFE, 1, 6)
	_save_panel.custom_minimum_size.y = 34.0
	column.add_child(_save_panel)
	_save_status_label = UI.make_label("[미연결] 저장 상태를 기다리는 중", 11, UI.COLOR_MUTED)
	_save_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_panel.add_child(_save_status_label)

	_primary_button = UI.make_button(
		"현장 복귀", &"primary", UI.PRIMARY_HEIGHT
	)
	_primary_button.name = "PrimaryActionButton"
	_primary_button.unique_name_in_owner = true
	_primary_button.disabled = true
	_primary_button.pressed.connect(continue_requested.emit)
	column.add_child(_primary_button)

	var secondary_row := HBoxContainer.new()
	secondary_row.custom_minimum_size.y = UI.TOUCH_MIN
	secondary_row.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	column.add_child(secondary_row)
	var manual_button: Button = UI.make_button("운영 매뉴얼", &"secondary")
	manual_button.name = "ManualButton"
	manual_button.unique_name_in_owner = true
	manual_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_button.pressed.connect(manual_requested.emit)
	secondary_row.add_child(manual_button)
	var footer_settings_button: Button = UI.make_button("설정", &"secondary")
	footer_settings_button.name = "FooterSettingsButton"
	footer_settings_button.unique_name_in_owner = true
	footer_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_settings_button.pressed.connect(settings_requested.emit)
	secondary_row.add_child(footer_settings_button)


func _build_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 52.0
	header.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	column.add_child(header)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	header.add_child(title_column)
	var title: Label = UI.make_label("야간 운영실", UI.TITLE_SIZE, UI.COLOR_TEXT)
	title.name = "ScreenTitle"
	title.unique_name_in_owner = true
	title_column.add_child(title)
	_run_status_label = UI.make_label("[미연결] 운영 상태를 기다리는 중", 11, UI.COLOR_MUTED)
	title_column.add_child(_run_status_label)

	var settings_button: Button = UI.make_button("설정", &"quiet", UI.TOUCH_MIN)
	settings_button.name = "SettingsButton"
	settings_button.unique_name_in_owner = true
	settings_button.custom_minimum_size.x = 64.0
	settings_button.pressed.connect(settings_requested.emit)
	header.add_child(settings_button)


func _add_summary_row(parent: VBoxContainer, caption: String) -> Label:
	var row: HBoxContainer = UI.make_value_row(caption, "—")
	parent.add_child(row)
	return row.get_child(1) as Label


func _render_data() -> void:
	if _data == null:
		return
	var automatic_tag := "[자동]" if _data.automatic_running else "[정지]"
	var automatic_color := UI.COLOR_SAFE if _data.automatic_running else UI.COLOR_WARNING
	_run_status_label.text = "야간근무 %d회차" % _data.run_number
	_run_status_label.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_automatic_value.text = "%s %s" % [automatic_tag, _data.automatic_status_label]
	_automatic_value.add_theme_color_override("font_color", automatic_color)
	_stage_value.text = "STAGE %02d" % _data.stage
	_stage_value.add_theme_color_override("font_color", UI.COLOR_TEXT)
	_bottleneck_value.text = _data.bottleneck
	_bottleneck_value.add_theme_color_override("font_color", UI.COLOR_WARNING)
	_patch_value.text = "%d / %d" % [_data.equipped_patch_count, _data.patch_slot_count]
	_patch_value.add_theme_color_override("font_color", UI.COLOR_TEXT)
	_goal_value.text = _data.next_goal
	_goal_value.add_theme_color_override("font_color", UI.COLOR_TEXT)

	var save_color := UI.COLOR_SAFE
	var save_tag := "[저장]"
	if _data.save_state == OPERATIONS_DATA_SCRIPT.SaveState.SAVING:
		save_color = UI.COLOR_INFO
		save_tag = "[저장 중]"
	elif _data.save_state == OPERATIONS_DATA_SCRIPT.SaveState.ERROR:
		save_color = UI.COLOR_DANGER
		save_tag = "[오류]"
	_save_status_label.text = "%s %s" % [save_tag, _data.save_status_label]
	_save_status_label.add_theme_color_override("font_color", save_color)
	_save_panel.add_theme_stylebox_override(
		"panel", UI.make_style(UI.COLOR_PANEL, save_color, 2, 4, 6)
	)
	_primary_button.disabled = false


func _reject_configuration(message: String) -> void:
	_data = null
	_configuration_error = message
	if is_node_ready():
		_render_configuration_error()


func _render_configuration_error() -> void:
	_run_status_label.text = "[오류] 운영실 데이터를 표시할 수 없습니다"
	_run_status_label.add_theme_color_override("font_color", UI.COLOR_DANGER)
	_automatic_value.text = "[오류] 구성 데이터 없음"
	_automatic_value.add_theme_color_override("font_color", UI.COLOR_DANGER)
	_stage_value.text = "—"
	_stage_value.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_bottleneck_value.text = "화면 구성 오류"
	_bottleneck_value.add_theme_color_override("font_color", UI.COLOR_DANGER)
	_patch_value.text = "—"
	_patch_value.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_goal_value.text = "—"
	_goal_value.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_save_status_label.text = "[오류] 화면 데이터가 올바르지 않음"
	_save_status_label.add_theme_color_override("font_color", UI.COLOR_DANGER)
	_save_panel.add_theme_stylebox_override(
		"panel", UI.make_style(UI.COLOR_PANEL, UI.COLOR_DANGER, 2, 4, 6)
	)
	_primary_button.disabled = true
