class_name AppShellOnboardingView
extends Control

signal advance_requested
signal diagnosis_requested
signal skip_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const STEP_COUNT := 3

var _step := 0
var _configuration_error := ""
var _step_label: Label
var _title_label: Label
var _body_label: Label
var _primary_button: Button
var _card: PanelContainer
var _layout_column: VBoxContainer
var _layout_spacer: Control


func configure(step: int) -> bool:
	if step < 0 or step >= STEP_COUNT:
		_configuration_error = "onboarding step must be from 0 to %d" % (STEP_COUNT - 1)
		push_error(_configuration_error)
		return false
	_step = step
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
	_render()


func _build_interface() -> void:
	var blocker := ColorRect.new()
	blocker.name = "TutorialShade"
	blocker.color = Color(0.01, 0.02, 0.05, 0.66)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := MarginContainer.new()
	UI.add_margins(frame, 12, 12, 12, 12)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_column = VBoxContainer.new()
	_layout_column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	frame.add_child(_layout_column)
	_layout_spacer = UI.make_spacer()
	_layout_column.add_child(_layout_spacer)
	_card = UI.make_panel(UI.COLOR_PANEL_RAISED, UI.COLOR_INFO, 2, 12)
	_card.name = "OnboardingCard"
	_card.unique_name_in_owner = true
	_layout_column.add_child(_card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	_card.add_child(content)
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = UI.TOUCH_MIN
	header.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	content.add_child(header)
	_step_label = UI.make_label("", UI.SUPPORT_SIZE, UI.COLOR_INFO)
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_step_label)
	var skip_button: Button = UI.make_button("건너뛰기", &"quiet")
	skip_button.name = "SkipButton"
	skip_button.unique_name_in_owner = true
	skip_button.custom_minimum_size.x = 82.0
	skip_button.pressed.connect(skip_requested.emit)
	header.add_child(skip_button)
	_title_label = UI.make_label("", 16, UI.COLOR_TEXT, true)
	_title_label.name = "ScreenTitle"
	_title_label.unique_name_in_owner = true
	_title_label.custom_minimum_size.y = 36.0
	content.add_child(_title_label)
	_body_label = UI.make_label("", UI.BODY_SIZE, UI.COLOR_MUTED, true)
	_body_label.custom_minimum_size.y = 56.0
	content.add_child(_body_label)
	_primary_button = UI.make_button("", &"primary", UI.PRIMARY_HEIGHT)
	_primary_button.name = "PrimaryActionButton"
	_primary_button.unique_name_in_owner = true
	_primary_button.pressed.connect(_on_primary_pressed)
	content.add_child(_primary_button)


func _render() -> void:
	if _title_label == null:
		return
	_step_label.text = "운영 매뉴얼 %d / %d" % [_step + 1, STEP_COUNT]
	if _step == 2:
		_layout_column.move_child(_card, 0)
		_layout_column.move_child(_layout_spacer, 1)
	else:
		_layout_column.move_child(_layout_spacer, 0)
		_layout_column.move_child(_card, 1)
	match _step:
		0:
			_title_label.text = "전투는 요원들이 맡습니다."
			_body_label.text = "먼저 지켜보세요. 반복해서 누를 필요는 없습니다."
			_primary_button.text = "확인"
		1:
			_title_label.text = "병목이 감지되었습니다."
			_body_label.text = "진단 카드에서 느려진 원인과 근거를 확인하세요."
			_primary_button.text = "진단 보기"
		2:
			_title_label.text = "대응 방법은 하나가 아닙니다."
			_body_label.text = "요원을 강화하거나, 장점과 부작용이 있는 패치를 선택하세요."
			_primary_button.text = "직접 판단하기"


func _on_primary_pressed() -> void:
	if _step == 1:
		diagnosis_requested.emit()
		return
	advance_requested.emit()
