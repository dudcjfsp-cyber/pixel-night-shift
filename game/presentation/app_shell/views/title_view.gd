class_name AppShellTitleView
extends Control

signal start_requested
signal continue_requested
signal prologue_replay_requested
signal settings_requested
signal audio_unlock_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const ASSETS: GDScript = preload("res://game/presentation/presentation_assets.gd")
const TITLE_FONT: Font = preload("res://game/assets/fonts/Galmuri11-Bold.ttf")

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
	var header := Control.new()
	header.name = "TitleHeader"
	header.custom_minimum_size.y = 148.0
	parent.add_child(header)

	var settings_button: Button = UI.make_button("설정", &"quiet", UI.TOUCH_MIN)
	settings_button.name = "SettingsButton"
	settings_button.unique_name_in_owner = true
	settings_button.anchor_left = 1.0
	settings_button.anchor_right = 1.0
	settings_button.offset_left = -48.0
	settings_button.offset_bottom = 48.0
	settings_button.custom_minimum_size.x = 48.0
	settings_button.add_theme_font_size_override("font_size", 10)
	settings_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	settings_button.pressed.connect(_on_settings_pressed)
	header.add_child(settings_button)

	var brand_stage := Control.new()
	brand_stage.name = "BrandStage"
	brand_stage.anchor_right = 1.0
	brand_stage.offset_left = 20.0
	brand_stage.offset_right = -20.0
	brand_stage.offset_top = 40.0
	brand_stage.offset_bottom = 145.0
	brand_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(brand_stage)

	var pixel_word := _make_arc_word(
		"픽셀",
		Vector2(4.0, 29.0),
		Vector2(96.0, 54.0),
		-13.0
	)
	pixel_word.name = "TitleWordPixel"
	brand_stage.add_child(pixel_word)

	var night_word := _make_arc_word(
		"야간",
		Vector2(104.0, 5.0),
		Vector2(96.0, 54.0),
		0.0
	)
	night_word.name = "TitleWordNight"
	brand_stage.add_child(night_word)

	var shift_word := _make_arc_word(
		"근무",
		Vector2(204.0, 29.0),
		Vector2(96.0, 54.0),
		13.0
	)
	shift_word.name = "TitleWordShift"
	brand_stage.add_child(shift_word)

	var subtitle_row := HBoxContainer.new()
	subtitle_row.anchor_right = 1.0
	subtitle_row.offset_top = 63.0
	subtitle_row.offset_bottom = 94.0
	subtitle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brand_stage.add_child(subtitle_row)

	var subtitle: Label = UI.make_label("서버가 살아있다", 12, UI.COLOR_TEXT)
	subtitle.name = "BrandSubtitle"
	subtitle.unique_name_in_owner = true
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	subtitle.add_theme_color_override("font_outline_color", UI.COLOR_DEEP)
	subtitle.add_theme_constant_override("outline_size", 1)
	subtitle_row.add_child(subtitle)


func _make_arc_word(
	text_value: String,
	position_value: Vector2,
	size_value: Vector2,
	rotation_degrees_value: float
) -> Label:
	var label: Label = UI.make_label(text_value, 36, Color("ffcf5c"))
	label.position = position_value
	label.size = size_value
	label.pivot_offset = size_value * 0.5
	label.rotation_degrees = rotation_degrees_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_color_override("font_outline_color", UI.COLOR_DEEP)
	label.add_theme_color_override("font_shadow_color", Color("28656d"))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


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
