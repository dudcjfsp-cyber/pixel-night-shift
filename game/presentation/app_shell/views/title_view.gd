class_name AppShellTitleView
extends Control

signal start_requested
signal continue_requested
signal prologue_replay_requested
signal settings_requested
signal audio_unlock_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const ASSETS: GDScript = preload("res://game/presentation/presentation_assets.gd")

var _has_saved_shift := false
var _error_message := ""
var _audio_unlock_emitted := false
var _status_label: Label
var _error_label: Label
var _primary_button: Button
var _replay_button: Button


func configure(has_saved_shift: bool, error_message: String = "") -> void:
	_has_saved_shift = has_saved_shift
	_error_message = error_message
	if is_node_ready():
		_render()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	_render()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed:
		_emit_audio_unlock_once()
	elif event is InputEventScreenTouch and event.pressed:
		_emit_audio_unlock_once()
	elif event is InputEventKey and event.pressed and not event.echo:
		_emit_audio_unlock_once()


func _build_interface() -> void:
	var background := TextureRect.new()
	background.name = "TitleBackground"
	background.texture = ASSETS.TITLE_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe_margin := MarginContainer.new()
	safe_margin.name = "SafeContent"
	UI.add_margins(
		safe_margin,
		UI.CONTENT_MARGIN,
		UI.CONTENT_MARGIN,
		UI.CONTENT_MARGIN,
		UI.CONTENT_MARGIN
	)
	add_child(safe_margin)
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var screen_column := VBoxContainer.new()
	screen_column.name = "ScreenColumn"
	screen_column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	safe_margin.add_child(screen_column)
	_build_header(screen_column)
	screen_column.add_child(UI.make_spacer())
	_build_action_panel(screen_column)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = UI.TOUCH_MIN
	header.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	parent.add_child(header)

	var brand_column := VBoxContainer.new()
	brand_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_column.add_theme_constant_override("separation", 0)
	header.add_child(brand_column)

	var brand: Label = UI.make_label("PIXEL NIGHT SHIFT", 16, UI.COLOR_INFO)
	brand.name = "BrandLabel"
	brand_column.add_child(brand)
	brand_column.add_child(UI.make_label("픽셀 야간근무", 11, UI.COLOR_MUTED))

	var settings_button: Button = UI.make_button("설정", &"quiet", UI.TOUCH_MIN)
	settings_button.name = "SettingsButton"
	settings_button.unique_name_in_owner = true
	settings_button.custom_minimum_size.x = 64.0
	settings_button.pressed.connect(_on_settings_pressed)
	header.add_child(settings_button)


func _build_action_panel(parent: VBoxContainer) -> void:
	var panel: PanelContainer = UI.make_panel(UI.COLOR_BACKGROUND, UI.COLOR_INFO, 2, 10)
	panel.name = "TitleActionPanel"
	parent.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(column)

	var access_label: Label = UI.make_label("야간 운영 권한 대기 중", 16, UI.COLOR_TEXT)
	access_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(access_label)

	_status_label = UI.make_label("", UI.BODY_SIZE, UI.COLOR_INFO, true)
	_status_label.name = "StatusLabel"
	_status_label.unique_name_in_owner = true
	_status_label.custom_minimum_size.y = 28.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)

	_error_label = UI.make_label("", UI.SUPPORT_SIZE, UI.COLOR_DANGER, true)
	_error_label.name = "ErrorLabel"
	_error_label.unique_name_in_owner = true
	_error_label.custom_minimum_size.y = 28.0
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_error_label)

	_primary_button = UI.make_button("", &"primary", UI.PRIMARY_HEIGHT)
	_primary_button.name = "PrimaryActionButton"
	_primary_button.unique_name_in_owner = true
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.pressed.connect(_on_primary_pressed)
	column.add_child(_primary_button)

	var account_button: Button = UI.make_button(
		"계정 연동 · 준비 중", &"secondary", UI.TOUCH_MIN
	)
	account_button.name = "AccountLinkButton"
	account_button.unique_name_in_owner = true
	account_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_button.disabled = true
	column.add_child(account_button)

	var storage_label: Label = UI.make_label(
		"임시 테스트에서는 이 기기의 근무 기록을 사용합니다.",
		UI.SUPPORT_SIZE,
		UI.COLOR_MUTED,
		true
	)
	storage_label.custom_minimum_size.y = 28.0
	storage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(storage_label)

	_replay_button = UI.make_button("오프닝 다시 보기", &"quiet", UI.TOUCH_MIN)
	_replay_button.name = "PrologueReplayButton"
	_replay_button.unique_name_in_owner = true
	_replay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_button.pressed.connect(_on_replay_pressed)
	column.add_child(_replay_button)


func _render() -> void:
	if _primary_button == null:
		return
	_primary_button.text = "이어하기" if _has_saved_shift else "게임 시작"
	_status_label.text = (
		"저장된 야간근무가 대기 중입니다."
		if _has_saved_shift
		else "첫 야간근무를 준비합니다."
	)
	_error_label.visible = not _error_message.is_empty()
	_error_label.text = "[오류] %s" % _error_message if not _error_message.is_empty() else ""
	_replay_button.visible = _has_saved_shift


func _emit_audio_unlock_once() -> void:
	if _audio_unlock_emitted:
		return
	_audio_unlock_emitted = true
	audio_unlock_requested.emit()


func _on_primary_pressed() -> void:
	_emit_audio_unlock_once()
	if _has_saved_shift:
		continue_requested.emit()
	else:
		start_requested.emit()


func _on_replay_pressed() -> void:
	_emit_audio_unlock_once()
	prologue_replay_requested.emit()


func _on_settings_pressed() -> void:
	_emit_audio_unlock_once()
	settings_requested.emit()
