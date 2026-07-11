class_name AppShellOfflineReportView
extends Control

signal bottleneck_requested
signal continue_requested
signal operations_room_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const OFFLINE_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/offline_report_view_data.gd"
)

var _data: OFFLINE_DATA_SCRIPT
var _configuration_error := ""
var _description_label: Label
var _bits_value: Label
var _progress_value: Label
var _stall_stage_value: Label
var _stall_cause_value: Label
var _cap_label: Label
var _applied_panel: PanelContainer
var _primary_button: Button
var _operations_button: Button
var _primary_targets_bottleneck := false


func configure(data: OFFLINE_DATA_SCRIPT) -> bool:
	if data == null:
		_reject_configuration("OfflineReportViewData is required.")
		return false
	var errors: PackedStringArray = data.validation_errors()
	if not errors.is_empty():
		_reject_configuration("Invalid OfflineReportViewData: %s" % "; ".join(errors))
		return false
	_configuration_error = ""
	_data = data
	if is_node_ready():
		_render_data()
	return true


func configuration_error() -> String:
	return _configuration_error


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = UI.LOGICAL_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	if _data != null:
		_render_data()
	elif not _configuration_error.is_empty():
		_render_configuration_error()


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.name = "ModalShade"
	shade.color = UI.COLOR_MODAL_SHADE
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe_margin := MarginContainer.new()
	UI.add_margins(safe_margin, 16, 16, 12, 12)
	add_child(safe_margin)
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	safe_margin.add_child(center)
	var panel: PanelContainer = UI.make_panel(
		UI.COLOR_PANEL_RAISED, UI.COLOR_INFO, 2, 14
	)
	panel.name = "ModalPanel"
	panel.unique_name_in_owner = true
	panel.custom_minimum_size.x = 328.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(column)

	var title: Label = UI.make_label("야간 인수인계", UI.TITLE_SIZE, UI.COLOR_TEXT)
	title.name = "ScreenTitle"
	title.unique_name_in_owner = true
	column.add_child(title)

	_description_label = UI.make_label(
		"자동 운영 결과를 확인하는 중입니다.", UI.BODY_SIZE, UI.COLOR_MUTED, true
	)
	_description_label.custom_minimum_size.y = 42.0
	column.add_child(_description_label)

	var summary_panel: PanelContainer = UI.make_panel(
		UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 8
	)
	column.add_child(summary_panel)
	var summary_column := VBoxContainer.new()
	summary_column.add_theme_constant_override("separation", UI.GAP_SMALL)
	summary_panel.add_child(summary_column)
	_bits_value = _add_summary_row(summary_column, "회수한 비트")
	_progress_value = _add_summary_row(summary_column, "진행")
	_stall_stage_value = _add_summary_row(summary_column, "정체 지점")
	_stall_cause_value = _add_summary_row(summary_column, "정체 원인")
	_stall_cause_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stall_cause_value.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING

	_applied_panel = UI.make_panel(
		UI.COLOR_PANEL_SAFE, UI.COLOR_SAFE, 2, 8
	)
	_applied_panel.visible = false
	column.add_child(_applied_panel)
	var applied_label: Label = UI.make_label(
		"[반영 완료] 결과는 근무 기록에 이미 반영되었습니다.",
		UI.SUPPORT_SIZE,
		UI.COLOR_SAFE,
		true
	)
	applied_label.custom_minimum_size.y = 34.0
	_applied_panel.add_child(applied_label)

	_cap_label = UI.make_label(
		"[집계 상한] 8시간 이후의 결과는 집계되지 않았습니다.",
		UI.SUPPORT_SIZE,
		UI.COLOR_WARNING,
		true
	)
	_cap_label.custom_minimum_size.y = 30.0
	_cap_label.visible = false
	column.add_child(_cap_label)

	_primary_button = UI.make_button("현장 복귀", &"primary", UI.PRIMARY_HEIGHT)
	_primary_button.name = "PrimaryActionButton"
	_primary_button.unique_name_in_owner = true
	_primary_button.disabled = true
	_primary_button.pressed.connect(_on_primary_pressed)
	column.add_child(_primary_button)

	_operations_button = UI.make_button(
		"운영실 보기", &"secondary", UI.TOUCH_MIN
	)
	_operations_button.name = "OperationsRoomButton"
	_operations_button.unique_name_in_owner = true
	_operations_button.disabled = true
	_operations_button.pressed.connect(operations_room_requested.emit)
	column.add_child(_operations_button)


func _add_summary_row(parent: VBoxContainer, caption: String) -> Label:
	var row: HBoxContainer = UI.make_value_row(caption, "—")
	parent.add_child(row)
	return row.get_child(1) as Label


func _render_data() -> void:
	if _data == null:
		return
	_description_label.text = "%s 동안의 자동 운영 결과입니다." % UI.format_duration(
		_data.absence_seconds
	)
	_description_label.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_bits_value.text = "+%s" % UI.format_compact_number(_data.recovered_bits)
	_bits_value.add_theme_color_override("font_color", UI.COLOR_SAFE)
	_progress_value.text = "ST %02d → %02d" % [_data.stage_from, _data.stage_to]
	_progress_value.add_theme_color_override("font_color", UI.COLOR_TEXT)
	_primary_targets_bottleneck = _data.has_bottleneck
	if _data.has_bottleneck:
		_stall_stage_value.text = "STAGE %02d" % _data.bottleneck_stage
		_stall_stage_value.add_theme_color_override("font_color", UI.COLOR_WARNING)
		_stall_cause_value.text = _data.bottleneck_cause
		_stall_cause_value.add_theme_color_override("font_color", UI.COLOR_WARNING)
		_primary_button.text = "정체 지점 확인"
	else:
		_stall_stage_value.text = "없음"
		_stall_stage_value.add_theme_color_override("font_color", UI.COLOR_SAFE)
		_stall_cause_value.text = "자동 운영 정상"
		_stall_cause_value.add_theme_color_override("font_color", UI.COLOR_SAFE)
		_primary_button.text = "현장 복귀"
	_applied_panel.visible = true
	_cap_label.visible = _data.reached_cap
	_primary_button.disabled = false
	_operations_button.disabled = false


func _reject_configuration(message: String) -> void:
	_data = null
	_configuration_error = message
	if is_node_ready():
		_render_configuration_error()


func _render_configuration_error() -> void:
	_description_label.text = "[오류] 인수인계 데이터를 표시할 수 없습니다."
	_description_label.add_theme_color_override("font_color", UI.COLOR_DANGER)
	_bits_value.text = "—"
	_bits_value.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_progress_value.text = "—"
	_progress_value.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_stall_stage_value.text = "—"
	_stall_stage_value.add_theme_color_override("font_color", UI.COLOR_MUTED)
	_stall_cause_value.text = "화면 구성 오류"
	_stall_cause_value.add_theme_color_override("font_color", UI.COLOR_DANGER)
	_applied_panel.visible = false
	_cap_label.visible = false
	_primary_targets_bottleneck = false
	_primary_button.text = "데이터 확인 필요"
	_primary_button.disabled = true
	_operations_button.disabled = true


func _on_primary_pressed() -> void:
	if _data == null:
		push_error("Offline report must be configured before interaction.")
		return
	if _primary_targets_bottleneck:
		bottleneck_requested.emit()
		return
	continue_requested.emit()
