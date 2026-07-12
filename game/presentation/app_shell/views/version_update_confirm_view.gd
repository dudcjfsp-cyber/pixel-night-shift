class_name AppShellVersionUpdateConfirmView
extends Control

signal confirm_requested
signal cancel_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")

var _error_message := ""
var _error_label: Label
var _confirm_button: Button


func set_error(message: String) -> void:
	_error_message = message
	if is_node_ready():
		_render_error()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	_render_error()


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
	var center := CenterContainer.new()
	outer.add_child(center)
	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL_RAISED, UI.COLOR_SPECIAL, 2, 14)
	panel.name = "ModalPanel"
	panel.unique_name_in_owner = true
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(column)
	var title: Label = UI.make_label("버전 업데이트 승인", 18, UI.COLOR_TEXT)
	title.name = "ScreenTitle"
	title.unique_name_in_owner = true
	column.add_child(title)
	var intro: Label = UI.make_label(
		"현재 회차를 정리하고 다음 야간근무를 시작합니다.", UI.BODY_SIZE, UI.COLOR_MUTED, true
	)
	intro.custom_minimum_size.y = 42.0
	column.add_child(intro)

	var lists := HBoxContainer.new()
	lists.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	column.add_child(lists)
	lists.add_child(_make_list_panel("[초기화됩니다]", "STAGE 진행\n비트\n요원 레벨\n장착 패치", UI.COLOR_WARNING))
	lists.add_child(_make_list_panel("[유지됩니다]", "패치노트\n발견 기록\n열린 슬롯\n레거시 캐시", UI.COLOR_SAFE))
	var reward: Label = UI.make_label("[이번 보상] 패치노트 +1", 13, UI.COLOR_SPECIAL)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.custom_minimum_size.y = 34.0
	column.add_child(reward)
	_error_label = UI.make_label("", UI.SUPPORT_SIZE, UI.COLOR_DANGER, true)
	_error_label.name = "ErrorLabel"
	_error_label.unique_name_in_owner = true
	_error_label.custom_minimum_size.y = 34.0
	column.add_child(_error_label)
	_confirm_button = UI.make_button("업데이트 실행", &"primary", UI.PRIMARY_HEIGHT)
	_confirm_button.name = "ConfirmButton"
	_confirm_button.unique_name_in_owner = true
	_confirm_button.pressed.connect(confirm_requested.emit)
	column.add_child(_confirm_button)
	var cancel_button: Button = UI.make_button("조금 더 운영", &"secondary")
	cancel_button.name = "CancelButton"
	cancel_button.unique_name_in_owner = true
	cancel_button.pressed.connect(cancel_requested.emit)
	column.add_child(cancel_button)


func _make_list_panel(title_text: String, body_text: String, accent: Color) -> PanelContainer:
	var panel: PanelContainer = UI.make_panel(UI.COLOR_DEEP, accent, 1, 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_SMALL)
	panel.add_child(column)
	column.add_child(UI.make_label(title_text, UI.SUPPORT_SIZE, accent))
	var body: Label = UI.make_label(body_text, UI.SUPPORT_SIZE, UI.COLOR_TEXT, true)
	body.custom_minimum_size.y = 82.0
	column.add_child(body)
	return panel


func _render_error() -> void:
	if _error_label == null:
		return
	_error_label.visible = not _error_message.is_empty()
	_error_label.text = "[오류] %s" % _error_message if not _error_message.is_empty() else ""
	_confirm_button.disabled = false
