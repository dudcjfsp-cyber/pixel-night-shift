class_name AppShellFirstShiftView
extends Control

signal first_shift_requested
signal settings_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const ARTWORK_SLOT_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/app_shell_artwork_slot.gd"
)

var _artwork_slot: ARTWORK_SLOT_SCRIPT
var _artwork: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()


func set_artwork(texture: Texture2D) -> void:
	_artwork = texture
	if _artwork_slot != null:
		_artwork_slot.set_artwork(_artwork)


func _build_interface() -> void:
	var column: VBoxContainer = UI.attach_screen_frame(self, UI.GAP_MEDIUM)
	_build_header(column)

	var artwork_panel: PanelContainer = UI.make_panel(UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 0)
	artwork_panel.custom_minimum_size.y = 208.0
	artwork_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(artwork_panel)
	_artwork_slot = ARTWORK_SLOT_SCRIPT.new()
	_artwork_slot.name = "ArtworkSlot"
	_artwork_slot.set_fallback_kind(ARTWORK_SLOT_SCRIPT.FIRST_SHIFT)
	if _artwork != null:
		_artwork_slot.set_artwork(_artwork)
	artwork_panel.add_child(_artwork_slot)

	var message_column := VBoxContainer.new()
	message_column.add_theme_constant_override("separation", UI.GAP_SMALL)
	column.add_child(message_column)

	var title: Label = UI.make_label("픽셀 야간근무", UI.TITLE_SIZE, UI.COLOR_TEXT)
	title.name = "ScreenTitle"
	title.unique_name_in_owner = true
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_column.add_child(title)

	var subtitle: Label = UI.make_label("서버는 아직 살아 있다", 13, UI.COLOR_INFO)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_column.add_child(subtitle)

	var description: Label = UI.make_label(
		"전투는 요원들이 맡습니다.\n병목을 진단하고 장점과 부작용이 있는 패치를 선택하세요.",
		UI.BODY_SIZE,
		UI.COLOR_MUTED,
		true
	)
	description.custom_minimum_size.y = 62.0
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_column.add_child(description)

	var primary_button: Button = UI.make_button(
		"첫 근무 시작", &"primary", UI.PRIMARY_HEIGHT
	)
	primary_button.name = "PrimaryActionButton"
	primary_button.unique_name_in_owner = true
	primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_button.pressed.connect(first_shift_requested.emit)
	column.add_child(primary_button)


func _build_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 52.0
	header.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	column.add_child(header)

	var brand: Label = UI.make_label("PIXEL NIGHT SHIFT", 14, UI.COLOR_INFO)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)

	var settings_button: Button = UI.make_button("설정", &"quiet", UI.TOUCH_MIN)
	settings_button.name = "SettingsButton"
	settings_button.unique_name_in_owner = true
	settings_button.custom_minimum_size.x = 64.0
	settings_button.pressed.connect(settings_requested.emit)
	header.add_child(settings_button)
