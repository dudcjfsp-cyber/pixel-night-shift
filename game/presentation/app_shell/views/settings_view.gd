class_name AppShellSettingsView
extends Control

signal close_requested
signal music_volume_changed(value: int)
signal sfx_volume_changed(value: int)
signal vibration_changed(enabled: bool)
signal screen_shake_changed(enabled: bool)
signal reduced_flashes_changed(enabled: bool)
signal reduced_motion_changed(enabled: bool)
signal save_retry_requested
signal manual_requested
signal reset_records_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const REQUIRED_KEYS: PackedStringArray = [
	"music_volume_percent",
	"sfx_volume_percent",
	"vibration_enabled",
	"screen_shake_enabled",
	"reduced_flashes",
	"reduced_motion",
]

var _settings: Dictionary = {}
var _configuration_error := ""
var _save_status := "저장 상태 정상"
var _save_has_error := false
var _vibration_supported := false
var _save_status_label: Label
var _reset_panel: PanelContainer
var _normal_actions: VBoxContainer
var _toggle_buttons: Dictionary = {}
var _volume_sliders: Dictionary = {}
var _volume_value_labels: Dictionary = {}
var _manual_button: Button
var _manual_available := true


func configure(
	settings: Dictionary,
	save_status: String,
	save_has_error: bool,
	vibration_supported: bool
) -> bool:
	var errors := _validation_errors(settings)
	if not errors.is_empty():
		_configuration_error = "; ".join(errors)
		push_error("Invalid settings view data: %s" % _configuration_error)
		return false
	if save_status.is_empty():
		_configuration_error = "save_status cannot be empty"
		push_error("Invalid settings view data: %s" % _configuration_error)
		return false
	_settings = settings.duplicate(true)
	_save_status = save_status
	_save_has_error = save_has_error
	_vibration_supported = vibration_supported
	_configuration_error = ""
	if is_node_ready():
		_render()
	return true


func configuration_error() -> String:
	return _configuration_error


func set_save_status(message: String, has_error: bool) -> void:
	if message.is_empty():
		push_error("Settings save status cannot be empty.")
		return
	_save_status = message
	_save_has_error = has_error
	if is_node_ready():
		_render_save_status()


func show_reset_confirmation(visible: bool) -> void:
	if _reset_panel == null or _normal_actions == null:
		return
	_reset_panel.visible = visible
	_normal_actions.visible = not visible


func set_manual_available(available: bool) -> void:
	_manual_available = available
	if _manual_button == null:
		return
	_manual_button.disabled = not _manual_available
	_manual_button.text = (
		"운영 매뉴얼 다시 보기"
		if _manual_available
		else "운영 매뉴얼 · 첫 근무 후 사용"
	)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	if _settings.is_empty():
		_configuration_error = "settings must be configured before entering the tree"
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

	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL_RAISED, UI.COLOR_INFO, 2, 12)
	panel.name = "ModalPanel"
	panel.unique_name_in_owner = true
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = UI.TOUCH_MIN
	header.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	column.add_child(header)
	var title: Label = UI.make_label("설정", UI.TITLE_SIZE, UI.COLOR_TEXT)
	title.name = "ScreenTitle"
	title.unique_name_in_owner = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = UI.make_button("닫기", &"quiet")
	close_button.name = "CloseButton"
	close_button.unique_name_in_owner = true
	close_button.custom_minimum_size.x = 64.0
	close_button.pressed.connect(close_requested.emit)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	scroll.add_child(content)

	_add_volume_row(content, "배경음악 음량", "music_volume_percent", music_volume_changed.emit)
	_add_volume_row(content, "효과음 음량", "sfx_volume_percent", sfx_volume_changed.emit)
	_add_toggle_row(content, "진동 피드백", "vibration_enabled", vibration_changed.emit)
	var vibration_help: Label = UI.make_label(
		"진동 피드백은 Android 지원 기기에서만 사용할 수 있습니다.",
		UI.SUPPORT_SIZE,
		UI.COLOR_MUTED,
		true
	)
	vibration_help.custom_minimum_size.y = 30.0
	content.add_child(vibration_help)
	_add_toggle_row(content, "점멸 효과 줄이기", "reduced_flashes", reduced_flashes_changed.emit)
	_add_toggle_row(content, "동작 줄이기", "reduced_motion", reduced_motion_changed.emit)

	var motion_help: Label = UI.make_label(
		"동작 줄이기는 화면 전환과 반복 장식을 최소화합니다.",
		UI.SUPPORT_SIZE,
		UI.COLOR_MUTED,
		true
	)
	motion_help.custom_minimum_size.y = 34.0
	content.add_child(motion_help)

	var save_panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL, UI.COLOR_BORDER, 1, 8)
	content.add_child(save_panel)
	var save_column := VBoxContainer.new()
	save_column.add_theme_constant_override("separation", UI.GAP_SMALL)
	save_panel.add_child(save_column)
	_save_status_label = UI.make_label("", UI.BODY_SIZE, UI.COLOR_SAFE, true)
	_save_status_label.name = "SaveStatusLabel"
	_save_status_label.unique_name_in_owner = true
	_save_status_label.custom_minimum_size.y = 32.0
	save_column.add_child(_save_status_label)
	var retry_button: Button = UI.make_button("저장 다시 시도", &"secondary")
	retry_button.name = "SaveRetryButton"
	retry_button.unique_name_in_owner = true
	retry_button.pressed.connect(save_retry_requested.emit)
	save_column.add_child(retry_button)

	_normal_actions = VBoxContainer.new()
	_normal_actions.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	content.add_child(_normal_actions)
	_manual_button = UI.make_button("운영 매뉴얼 다시 보기", &"secondary")
	_manual_button.name = "ManualButton"
	_manual_button.unique_name_in_owner = true
	_manual_button.pressed.connect(manual_requested.emit)
	_normal_actions.add_child(_manual_button)
	set_manual_available(_manual_available)
	var reset_button: Button = UI.make_button("근무 기록 초기화…", &"danger")
	reset_button.name = "ResetRecordsButton"
	reset_button.unique_name_in_owner = true
	reset_button.pressed.connect(func() -> void: show_reset_confirmation(true))
	_normal_actions.add_child(reset_button)

	_reset_panel = UI.make_panel(Color("3a2028"), UI.COLOR_DANGER, 2, 10)
	_reset_panel.name = "ResetConfirmationPanel"
	_reset_panel.unique_name_in_owner = true
	_reset_panel.visible = false
	content.add_child(_reset_panel)
	var reset_column := VBoxContainer.new()
	reset_column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	_reset_panel.add_child(reset_column)
	reset_column.add_child(UI.make_label("근무 기록을 초기화할까요?", 15, UI.COLOR_DANGER))
	var warning: Label = UI.make_label(
		"현재 회차, 패치노트, 발견 기록과 영구 강화가 삭제됩니다. 이 작업은 되돌릴 수 없습니다. 소리와 접근성 설정은 유지됩니다.",
		UI.BODY_SIZE,
		UI.COLOR_TEXT,
		true
	)
	warning.custom_minimum_size.y = 78.0
	reset_column.add_child(warning)
	var confirm_button: Button = UI.make_button("모든 기록 삭제", &"danger", UI.PRIMARY_HEIGHT)
	confirm_button.name = "ConfirmResetButton"
	confirm_button.unique_name_in_owner = true
	confirm_button.pressed.connect(reset_records_requested.emit)
	reset_column.add_child(confirm_button)
	var cancel_button: Button = UI.make_button("취소", &"secondary")
	cancel_button.name = "CancelResetButton"
	cancel_button.unique_name_in_owner = true
	cancel_button.pressed.connect(func() -> void: show_reset_confirmation(false))
	reset_column.add_child(cancel_button)


func _add_volume_row(parent: VBoxContainer, caption: String, key: String, changed: Callable) -> void:
	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL, UI.COLOR_BORDER, 1, 6)
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = UI.TOUCH_MIN
	row.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(row)
	var label: Label = UI.make_label(caption, UI.BODY_SIZE, UI.COLOR_TEXT)
	label.custom_minimum_size.x = 108.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "%sSlider" % key.to_pascal_case()
	slider.unique_name_in_owner = true
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.custom_minimum_size = Vector2(104.0, UI.TOUCH_MIN)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	_volume_sliders[key] = slider
	var value_label: Label = UI.make_label("0%", UI.BODY_SIZE, UI.COLOR_INFO)
	value_label.name = "%sValue" % key.to_pascal_case()
	value_label.custom_minimum_size.x = 42.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_volume_value_labels[key] = value_label
	slider.value_changed.connect(func(value: float) -> void:
		var rounded := int(round(value))
		_settings[key] = rounded
		value_label.text = "%d%%" % rounded
		changed.call(rounded)
	)


func _add_toggle_row(parent: VBoxContainer, caption: String, key: String, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = UI.TOUCH_MIN
	row.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	parent.add_child(row)
	var label: Label = UI.make_label(caption, UI.BODY_SIZE, UI.COLOR_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button: Button = UI.make_button("—", &"secondary")
	button.name = "%sButton" % key.to_pascal_case()
	button.custom_minimum_size.x = 92.0
	button.pressed.connect(func() -> void:
		var next_value := not bool(_settings[key])
		_settings[key] = next_value
		_render_toggle(key)
		changed.call(next_value)
	)
	row.add_child(button)
	_toggle_buttons[key] = button


func _render() -> void:
	for key: String in ["music_volume_percent", "sfx_volume_percent"]:
		var slider := _volume_sliders.get(key) as HSlider
		var value_label := _volume_value_labels.get(key) as Label
		var percent := int(_settings[key])
		if slider != null:
			slider.set_value_no_signal(float(percent))
		if value_label != null:
			value_label.text = "%d%%" % percent
	for key: String in _toggle_buttons:
		_render_toggle(key)
	if _toggle_buttons.has("vibration_enabled"):
		var vibration_button := _toggle_buttons["vibration_enabled"] as Button
		vibration_button.disabled = not _vibration_supported
		if not _vibration_supported:
			vibration_button.text = "[미지원]"
		vibration_button.tooltip_text = (
			"이 기기에서는 진동 피드백을 지원하지 않습니다."
			if not _vibration_supported
			else "진동 피드백 켜기/끄기"
		)
	_render_save_status()


func _render_toggle(key: String) -> void:
	if not _toggle_buttons.has(key):
		return
	var button := _toggle_buttons[key] as Button
	button.text = "[켬]" if bool(_settings[key]) else "[끔]"


func _render_save_status() -> void:
	if _save_status_label == null:
		return
	_save_status_label.text = ("[오류] " if _save_has_error else "[저장] ") + _save_status
	_save_status_label.add_theme_color_override(
		"font_color", UI.COLOR_DANGER if _save_has_error else UI.COLOR_SAFE
	)


func _validation_errors(settings: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in REQUIRED_KEYS:
		if not settings.has(key):
			errors.append("missing '%s'" % key)
	for key: String in ["music_volume_percent", "sfx_volume_percent"]:
		if settings.has(key):
			var value: Variant = settings[key]
			if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > 100:
				errors.append("%s must be an integer from 0 to 100" % key)
	for key: String in [
		"vibration_enabled", "screen_shake_enabled", "reduced_flashes", "reduced_motion"
	]:
		if settings.has(key) and typeof(settings[key]) != TYPE_BOOL:
			errors.append("%s must be a bool" % key)
	return errors
