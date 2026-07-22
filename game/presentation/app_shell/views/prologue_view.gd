class_name AppShellPrologueView
extends Control

signal advance_requested
signal skip_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const ASSETS: GDScript = preload("res://game/presentation/presentation_assets.gd")
const STEP_COUNT := 5
const VISUAL_SIZE := Vector2(344.0, 224.0)
const TITLES := [
	"꺼지지 않는 도시",
	"깨어난 결함",
	"자동 대응",
	"자동화의 한계",
	"권한 인계",
]
const BODIES := [
	"도시가 잠든 뒤에도 서비스는 멈추지 않습니다.",
	"누적된 결함은 깨진 픽셀과 비정상 프로세스로 깨어납니다.",
	"요원들은 지시를 기다리지 않고 현장을 지킵니다.",
	"하지만 병목의 원인과 감수할 위험까지 결정하지는 못합니다.",
	"03:00, 야간 운영 권한이 당신에게 이관됩니다. 진단하고, 강화하고, 패치를 승인하십시오.",
]

var _step := 0
var _replay := false
var _reduced_motion := false
var _configuration_error := ""
var _step_label: Label
var _skip_button: Button
var _visual_layer: Control
var _title_label: Label
var _body_label: Label
var _primary_button: Button


func configure(step: int, replay: bool = false, reduced_motion: bool = false) -> bool:
	if step < 0 or step >= STEP_COUNT:
		_configuration_error = "prologue step must be from 0 to %d" % (STEP_COUNT - 1)
		push_error(_configuration_error)
		return false
	_step = step
	_replay = replay
	_reduced_motion = reduced_motion
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
	var column: VBoxContainer = UI.attach_screen_frame(self, UI.GAP_MEDIUM)
	_build_header(column)

	var visual_panel: PanelContainer = UI.make_panel(UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 0)
	visual_panel.name = "PrologueVisualPanel"
	visual_panel.custom_minimum_size = VISUAL_SIZE
	column.add_child(visual_panel)

	_visual_layer = Control.new()
	_visual_layer.name = "VisualLayer"
	_visual_layer.custom_minimum_size = VISUAL_SIZE
	_visual_layer.clip_contents = true
	_visual_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_panel.add_child(_visual_layer)

	var story_panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL, UI.COLOR_BORDER, 1, 12)
	story_panel.custom_minimum_size.y = 142.0
	column.add_child(story_panel)
	var story_column := VBoxContainer.new()
	story_column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	story_panel.add_child(story_column)

	_title_label = UI.make_label("", 18, UI.COLOR_TEXT, true)
	_title_label.name = "ScreenTitle"
	_title_label.unique_name_in_owner = true
	_title_label.custom_minimum_size.y = 30.0
	story_column.add_child(_title_label)

	_body_label = UI.make_label("", UI.BODY_SIZE, UI.COLOR_MUTED, true)
	_body_label.name = "StoryBody"
	_body_label.unique_name_in_owner = true
	_body_label.custom_minimum_size.y = 72.0
	story_column.add_child(_body_label)

	column.add_child(UI.make_spacer())
	_primary_button = UI.make_button("다음", &"primary", UI.PRIMARY_HEIGHT)
	_primary_button.name = "PrimaryActionButton"
	_primary_button.unique_name_in_owner = true
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.pressed.connect(advance_requested.emit)
	column.add_child(_primary_button)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = UI.TOUCH_MIN
	header.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	parent.add_child(header)

	_step_label = UI.make_label("", UI.SUPPORT_SIZE, UI.COLOR_INFO)
	_step_label.name = "StepLabel"
	_step_label.unique_name_in_owner = true
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_step_label)

	_skip_button = UI.make_button("건너뛰기", &"quiet", UI.TOUCH_MIN)
	_skip_button.name = "SkipButton"
	_skip_button.unique_name_in_owner = true
	_skip_button.custom_minimum_size.x = 112.0
	_skip_button.pressed.connect(skip_requested.emit)
	header.add_child(_skip_button)


func _render() -> void:
	if _title_label == null:
		return
	_step_label.text = "야간 인수인계 %d / %d" % [_step + 1, STEP_COUNT]
	_skip_button.text = "타이틀로 돌아가기" if _replay else "건너뛰기"
	_title_label.text = String(TITLES[_step])
	_body_label.text = String(BODIES[_step])
	if _step == STEP_COUNT - 1:
		_primary_button.text = "타이틀로 돌아가기" if _replay else "근무 인계받기"
	else:
		_primary_button.text = "다음"
	_rebuild_visual()


func _rebuild_visual() -> void:
	for child: Node in _visual_layer.get_children():
		_visual_layer.remove_child(child)
		child.queue_free()
	match _step:
		0:
			_build_city_visual()
		1:
			_build_fault_visual()
		2:
			_build_operator_visual()
		3:
			_build_decision_visual()
		4:
			_build_handoff_visual()


func _build_city_visual() -> void:
	_add_texture(ASSETS.CITY_NETWORK_BACKGROUND, Rect2(Vector2.ZERO, VISUAL_SIZE))


func _build_fault_visual() -> void:
	_build_battle_stage()
	_add_animated_sprite(ASSETS.make_enemy_frames(1, false, "combat"), Vector2(64, 176), 2.0)
	_add_animated_sprite(ASSETS.make_enemy_frames(2, false, "combat"), Vector2(172, 176), 2.0)
	_add_animated_sprite(ASSETS.make_enemy_frames(3, false, "combat"), Vector2(280, 176), 2.0)
	_add_status_strip("[오류] 비정상 프로세스 증가", UI.COLOR_DANGER)


func _build_operator_visual() -> void:
	_build_battle_stage()
	var operator_ids: Array[StringName] = [
		&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
	]
	var positions: Array[Vector2] = [
		Vector2(42, 176), Vector2(126, 176), Vector2(218, 176), Vector2(302, 176),
	]
	for index: int in range(operator_ids.size()):
		_add_animated_sprite(
			ASSETS.make_operator_frames(operator_ids[index]), positions[index], 2.0
		)
	_add_status_strip("[자동] 현장 대응 계속", UI.COLOR_SAFE)


func _build_decision_visual() -> void:
	_add_grid_background()
	_add_signal_card(
		Rect2(18, 52, 92, 116), ASSETS.ui_texture(&"diagnosis"), "병목 진단", UI.COLOR_INFO
	)
	_add_signal_card(
		Rect2(126, 52, 92, 116), ASSETS.ui_texture(&"maintenance"), "위험 판단", UI.COLOR_WARNING
	)
	_add_signal_card(
		Rect2(234, 52, 92, 116), ASSETS.patch_texture(&"unsafe_build"), "패치 승인", UI.COLOR_SPECIAL
	)
	_add_status_strip("[대기] 운영 책임자의 판단 필요", UI.COLOR_DANGER)


func _build_handoff_visual() -> void:
	var crop := AtlasTexture.new()
	crop.atlas = ASSETS.TITLE_BACKGROUND
	crop.region = Rect2(8, 224, 344, 224)
	crop.filter_clip = true
	_add_texture(crop, Rect2(Vector2.ZERO, VISUAL_SIZE))
	_add_status_strip("03:00 // 야간 운영 권한 인계", UI.COLOR_INFO)


func _build_battle_stage() -> void:
	_add_rect(Rect2(Vector2.ZERO, VISUAL_SIZE), UI.COLOR_DEEP)
	_add_texture(ASSETS.BATTLE_BACKGROUND, Rect2(0, 72, 344, 64))
	_add_rect(Rect2(0, 136, 344, 88), Color("08101c"))
	_add_rect(Rect2(0, 136, 344, 2), UI.COLOR_BORDER)
	for x: int in range(0, 344, 32):
		_add_rect(Rect2(x, 200, 16, 1), Color(UI.COLOR_BORDER, 0.5))


func _add_grid_background() -> void:
	_add_rect(Rect2(Vector2.ZERO, VISUAL_SIZE), UI.COLOR_DEEP)
	for x: int in range(0, 344, 16):
		_add_rect(Rect2(x, 0, 1, 224), Color(UI.COLOR_BORDER, 0.18))
	for y: int in range(0, 224, 16):
		_add_rect(Rect2(0, y, 344, 1), Color(UI.COLOR_BORDER, 0.18))


func _add_signal_card(rect: Rect2, texture: Texture2D, caption: String, accent: Color) -> void:
	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL, accent, 2, 6)
	panel.position = rect.position
	panel.size = rect.size
	_visual_layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_SMALL)
	panel.add_child(column)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)
	var label: Label = UI.make_label(caption, UI.SUPPORT_SIZE, accent, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(label)


func _add_status_strip(text_value: String, accent: Color) -> void:
	var panel: PanelContainer = UI.make_panel(UI.COLOR_BACKGROUND, accent, 1, 4)
	panel.position = Vector2(22, 181)
	panel.size = Vector2(300, 32)
	_visual_layer.add_child(panel)
	var label: Label = UI.make_label(text_value, UI.SUPPORT_SIZE, accent)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)


func _add_animated_sprite(frames: SpriteFrames, position_value: Vector2, scale_value: float) -> void:
	if frames == null:
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = &"idle"
	sprite.frame = 0
	sprite.position = position_value
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual_layer.add_child(sprite)
	if not _reduced_motion:
		sprite.play(&"idle")


func _add_texture(texture: Texture2D, rect: Rect2) -> void:
	var texture_rect := TextureRect.new()
	texture_rect.texture = texture
	texture_rect.position = rect.position
	texture_rect.size = rect.size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_layer.add_child(texture_rect)


func _add_rect(rect: Rect2, color: Color) -> void:
	var color_rect := ColorRect.new()
	color_rect.color = color
	color_rect.position = rect.position
	color_rect.size = rect.size
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_layer.add_child(color_rect)
