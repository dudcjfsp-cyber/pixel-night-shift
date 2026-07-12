class_name AppShellRunSummaryView
extends Control

signal continue_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const REQUIRED_KEYS: PackedStringArray = [
	"new_run_number",
	"patch_note_gain",
	"previous_highest_stage",
	"bottleneck",
	"used_patch_count",
	"next_goal",
]

var _data: Dictionary = {}
var _configuration_error := ""
var _run_label: Label
var _reward_label: Label
var _stage_value: Label
var _bottleneck_value: Label
var _patch_value: Label
var _goal_label: Label
var _continue_button: Button


func configure(data: Dictionary) -> bool:
	var errors := _validation_errors(data)
	if not errors.is_empty():
		_configuration_error = "; ".join(errors)
		push_error("Invalid run summary data: %s" % _configuration_error)
		return false
	_data = data.duplicate(true)
	_configuration_error = ""
	if is_node_ready():
		_render()
	return true


func configuration_error() -> String:
	return _configuration_error


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	if _data.is_empty():
		_configuration_error = "run summary must be configured before entering the tree"
		push_error(_configuration_error)
	else:
		_render()


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.name = "ModalShade"
	shade.color = UI.COLOR_MODAL_SHADE
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outer := MarginContainer.new()
	UI.add_margins(outer, 16, 16, 12, 12)
	add_child(outer)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	outer.add_child(center)
	center.add_child(UI.make_spacer())
	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL_RAISED, UI.COLOR_SAFE, 2, 14)
	panel.name = "ModalPanel"
	panel.unique_name_in_owner = true
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(panel)
	center.add_child(UI.make_spacer())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(column)
	var title: Label = UI.make_label("버전 업데이트 완료", 18, UI.COLOR_SAFE)
	title.name = "ScreenTitle"
	title.unique_name_in_owner = true
	column.add_child(title)
	_run_label = UI.make_label("", 13, UI.COLOR_TEXT, true)
	_run_label.custom_minimum_size.y = 36.0
	column.add_child(_run_label)
	_reward_label = UI.make_label("", 13, UI.COLOR_SPECIAL)
	column.add_child(_reward_label)
	var summary_panel: PanelContainer = UI.make_panel(UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 8)
	column.add_child(summary_panel)
	var summary_column := VBoxContainer.new()
	summary_column.add_theme_constant_override("separation", UI.GAP_SMALL)
	summary_panel.add_child(summary_column)
	_stage_value = _add_row(summary_column, "이전 회차 최고")
	_bottleneck_value = _add_row(summary_column, "업데이트 직전 병목")
	_patch_value = _add_row(summary_column, "사용한 패치")
	_goal_label = UI.make_label("", UI.BODY_SIZE, UI.COLOR_INFO, true)
	_goal_label.custom_minimum_size.y = 52.0
	column.add_child(_goal_label)
	_continue_button = UI.make_button("새 회차 시작", &"primary", UI.PRIMARY_HEIGHT)
	_continue_button.name = "PrimaryActionButton"
	_continue_button.unique_name_in_owner = true
	_continue_button.disabled = true
	_continue_button.pressed.connect(continue_requested.emit)
	column.add_child(_continue_button)


func _add_row(parent: VBoxContainer, caption: String) -> Label:
	var row: HBoxContainer = UI.make_value_row(caption, "—")
	parent.add_child(row)
	return row.get_child(1) as Label


func _render() -> void:
	if _data.is_empty() or _run_label == null:
		return
	_run_label.text = "야간근무 %d회차가 시작되었습니다." % int(_data["new_run_number"])
	_reward_label.text = "패치노트 +%d" % int(_data["patch_note_gain"])
	_stage_value.text = "STAGE %02d" % int(_data["previous_highest_stage"])
	_bottleneck_value.text = String(_data["bottleneck"])
	_patch_value.text = "%d개" % int(_data["used_patch_count"])
	_goal_label.text = "[다음 목표] %s" % String(_data["next_goal"])
	_continue_button.disabled = false


func _validation_errors(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			errors.append("missing '%s'" % key)
	if data.has("new_run_number") and (
		typeof(data["new_run_number"]) != TYPE_INT or int(data["new_run_number"]) < 2
	):
		errors.append("new_run_number must be an integer of at least 2")
	for key: String in ["patch_note_gain", "previous_highest_stage", "used_patch_count"]:
		if data.has(key) and (typeof(data[key]) != TYPE_INT or int(data[key]) < 0):
			errors.append("%s must be a nonnegative integer" % key)
	for key: String in ["bottleneck", "next_goal"]:
		if data.has(key) and (typeof(data[key]) != TYPE_STRING or String(data[key]).is_empty()):
			errors.append("%s must be a nonempty string" % key)
	return errors
