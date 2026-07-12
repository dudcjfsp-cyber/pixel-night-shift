class_name AppShellSaveRecoveryView
extends Control

signal backup_restore_requested
signal retry_requested
signal new_shift_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")

var _title_text := "[오류] 근무 기록에 문제가 있습니다."
var _detail_text := "현재 기록과 백업을 모두 읽을 수 없습니다."
var _backup_label := ""
var _backup_available := false
var _newer_schema := false
var _configuration_error := ""
var _title_label: Label
var _detail_label: Label
var _backup_info_label: Label
var _backup_button: Button
var _normal_actions: VBoxContainer
var _confirm_panel: PanelContainer


func configure(
	title_text: String,
	detail_text: String,
	backup_available: bool,
	backup_label: String,
	newer_schema: bool
) -> bool:
	if title_text.is_empty() or detail_text.is_empty():
		_configuration_error = "title_text and detail_text are required"
		push_error("Invalid save recovery data: %s" % _configuration_error)
		return false
	if backup_available and backup_label.is_empty():
		_configuration_error = "backup_label is required when a backup is available"
		push_error("Invalid save recovery data: %s" % _configuration_error)
		return false
	_title_text = title_text
	_detail_text = detail_text
	_backup_available = backup_available
	_backup_label = backup_label
	_newer_schema = newer_schema
	_configuration_error = ""
	if is_node_ready():
		_render()
	return true


func configuration_error() -> String:
	return _configuration_error


func set_error(message: String) -> void:
	if message.is_empty():
		push_error("Save recovery error message cannot be empty.")
		return
	_detail_text = "[오류] %s" % message
	if is_node_ready():
		_render()


func show_new_shift_confirmation(visible: bool) -> void:
	if _normal_actions == null or _confirm_panel == null:
		return
	_normal_actions.visible = not visible
	_confirm_panel.visible = visible


func is_confirming_new_shift() -> bool:
	return _confirm_panel != null and _confirm_panel.visible


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	_render()


func _build_interface() -> void:
	var column: VBoxContainer = UI.attach_screen_frame(self, UI.GAP_LARGE)
	column.add_child(UI.make_spacer())
	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL_RAISED, UI.COLOR_DANGER, 2, 14)
	panel.name = "RecoveryPanel"
	panel.unique_name_in_owner = true
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(content)

	_title_label = UI.make_label(_title_text, 18, UI.COLOR_DANGER, true)
	_title_label.name = "ScreenTitle"
	_title_label.unique_name_in_owner = true
	_title_label.custom_minimum_size.y = 54.0
	content.add_child(_title_label)
	content.add_child(UI.make_rule(UI.COLOR_DANGER))
	_detail_label = UI.make_label(_detail_text, UI.BODY_SIZE, UI.COLOR_TEXT, true)
	_detail_label.name = "RecoveryDetail"
	_detail_label.unique_name_in_owner = true
	_detail_label.custom_minimum_size.y = 72.0
	content.add_child(_detail_label)
	_backup_info_label = UI.make_label("", UI.BODY_SIZE, UI.COLOR_WARNING, true)
	_backup_info_label.name = "BackupInfo"
	_backup_info_label.unique_name_in_owner = true
	_backup_info_label.custom_minimum_size.y = 52.0
	content.add_child(_backup_info_label)

	_normal_actions = VBoxContainer.new()
	_normal_actions.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	content.add_child(_normal_actions)
	_backup_button = UI.make_button("백업으로 복구", &"primary", UI.PRIMARY_HEIGHT)
	_backup_button.name = "RestoreBackupButton"
	_backup_button.unique_name_in_owner = true
	_backup_button.pressed.connect(backup_restore_requested.emit)
	_normal_actions.add_child(_backup_button)
	var retry_button: Button = UI.make_button("다시 시도", &"secondary")
	retry_button.name = "RetryButton"
	retry_button.unique_name_in_owner = true
	retry_button.pressed.connect(retry_requested.emit)
	_normal_actions.add_child(retry_button)
	var new_shift_button: Button = UI.make_button("새 근무 시작…", &"danger")
	new_shift_button.name = "NewShiftButton"
	new_shift_button.unique_name_in_owner = true
	new_shift_button.pressed.connect(func() -> void: show_new_shift_confirmation(true))
	_normal_actions.add_child(new_shift_button)

	_confirm_panel = UI.make_panel(Color("3a2028"), UI.COLOR_DANGER, 2, 10)
	_confirm_panel.name = "NewShiftConfirmationPanel"
	_confirm_panel.unique_name_in_owner = true
	_confirm_panel.visible = false
	content.add_child(_confirm_panel)
	var confirm_column := VBoxContainer.new()
	confirm_column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	_confirm_panel.add_child(confirm_column)
	confirm_column.add_child(UI.make_label("기존 기록을 삭제할까요?", 15, UI.COLOR_DANGER))
	var warning: Label = UI.make_label(
		"주 기록과 백업이 모두 삭제됩니다. 소리와 접근성 설정은 유지됩니다.",
		UI.BODY_SIZE,
		UI.COLOR_TEXT,
		true
	)
	warning.custom_minimum_size.y = 58.0
	confirm_column.add_child(warning)
	var confirm_button: Button = UI.make_button("기록 삭제 후 새 근무", &"danger", UI.PRIMARY_HEIGHT)
	confirm_button.name = "ConfirmNewShiftButton"
	confirm_button.unique_name_in_owner = true
	confirm_button.pressed.connect(new_shift_requested.emit)
	confirm_column.add_child(confirm_button)
	var cancel_button: Button = UI.make_button("취소", &"secondary")
	cancel_button.name = "CancelNewShiftButton"
	cancel_button.unique_name_in_owner = true
	cancel_button.pressed.connect(func() -> void: show_new_shift_confirmation(false))
	confirm_column.add_child(cancel_button)
	column.add_child(UI.make_spacer())


func _render() -> void:
	if _title_label == null:
		return
	_title_label.text = _title_text
	_detail_label.text = _detail_text
	_backup_button.visible = _backup_available and not _newer_schema
	if _newer_schema:
		_backup_info_label.text = "[업데이트 필요] 이 기록은 더 새로운 게임 버전에서 만들어졌습니다."
		_backup_info_label.add_theme_color_override("font_color", UI.COLOR_WARNING)
	elif _backup_available:
		_backup_info_label.text = "%s\n일부 최근 진행은 반영되지 않을 수 있습니다." % _backup_label
		_backup_info_label.add_theme_color_override("font_color", UI.COLOR_WARNING)
	else:
		_backup_info_label.text = "[복구 불가] 사용할 수 있는 이전 백업이 없습니다."
		_backup_info_label.add_theme_color_override("font_color", UI.COLOR_DANGER)
