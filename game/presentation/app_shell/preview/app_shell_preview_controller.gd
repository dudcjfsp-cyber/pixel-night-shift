extends Control

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const FIXTURES: GDScript = preload(
	"res://game/presentation/app_shell/preview/app_shell_preview_fixtures.gd"
)
const BOOT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/boot_view.tscn"
)
const FIRST_SHIFT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/first_shift_view.tscn"
)
const OPERATIONS_ROOM_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/operations_room_view.tscn"
)
const OFFLINE_REPORT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/offline_report_view.tscn"
)
const BOOT_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/boot_view.gd"
)
const FIRST_SHIFT_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/first_shift_view.gd"
)
const OPERATIONS_ROOM_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/operations_room_view.gd"
)
const OFFLINE_REPORT_VIEW_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/views/offline_report_view.gd"
)
const OPERATIONS_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/operations_room_view_data.gd"
)
const OFFLINE_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/offline_report_view_data.gd"
)

var _states: Array[Dictionary] = []
var _current_index := 0
var _product_host: Control
var _dev_layer: CanvasLayer
var _state_label: Label
var _event_label: Label


func _ready() -> void:
	custom_minimum_size = UI.LOGICAL_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_states = FIXTURES.states()
	assert(not _states.is_empty(), "App-shell preview fixtures cannot be empty.")
	_build_product_host()
	_build_dev_chrome()
	show_preview_state(0)


func show_preview_state(state_index: int) -> void:
	assert(not _states.is_empty(), "Preview states must be initialized before navigation.")
	_current_index = posmod(state_index, _states.size())
	_clear_product_host()
	var state := _states[_current_index]
	var screen := StringName(state["screen"])
	match screen:
		FIXTURES.SCREEN_BOOT:
			_show_boot(state)
		FIXTURES.SCREEN_FIRST_SHIFT:
			_show_first_shift()
		FIXTURES.SCREEN_OPERATIONS_ROOM:
			_show_operations_room(state["data"] as OPERATIONS_DATA_SCRIPT)
		FIXTURES.SCREEN_OFFLINE_REPORT:
			_show_offline_report(state["data"] as OFFLINE_DATA_SCRIPT)
		_:
			assert(false, "Unknown app-shell preview screen: %s" % screen)
	_state_label.text = "%d/%d · %s" % [
		_current_index + 1,
		_states.size(),
		String(state["label"]),
	]
	_event_label.text = "← → 또는 1~4 · F1 개발 UI 숨김"


func current_state_id() -> StringName:
	return StringName(_states[_current_index]["id"])


func preview_state_count() -> int:
	return _states.size()


func is_dev_chrome_visible() -> bool:
	return _dev_layer.visible


func set_dev_chrome_visible(visible_value: bool) -> void:
	_dev_layer.visible = visible_value


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_LEFT:
			show_preview_state(_current_index - 1)
		KEY_RIGHT:
			show_preview_state(_current_index + 1)
		KEY_1:
			_show_state_by_id(&"boot")
		KEY_2:
			_show_state_by_id(&"first_shift")
		KEY_3:
			_show_state_by_id(&"operations_normal")
		KEY_4:
			_show_state_by_id(&"offline_bottleneck")
		KEY_F1:
			_dev_layer.visible = not _dev_layer.visible
		_:
			return
	get_viewport().set_input_as_handled()


func _build_product_host() -> void:
	_product_host = Control.new()
	_product_host.name = "ProductHost"
	_product_host.unique_name_in_owner = true
	add_child(_product_host)
	_product_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_dev_chrome() -> void:
	_dev_layer = CanvasLayer.new()
	_dev_layer.name = "DevPreviewLayer"
	_dev_layer.layer = 100
	add_child(_dev_layer)

	var chrome := PanelContainer.new()
	chrome.name = "DevPreviewChrome"
	chrome.unique_name_in_owner = true
	chrome.anchor_left = 0.0
	chrome.anchor_top = 1.0
	chrome.anchor_right = 1.0
	chrome.anchor_bottom = 1.0
	chrome.offset_top = -88.0
	chrome.add_theme_stylebox_override(
		"panel", UI.make_style(UI.COLOR_DEV_PANEL, UI.COLOR_DEV, 2, 0, 6)
	)
	_dev_layer.add_child(chrome)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UI.GAP_SMALL)
	chrome.add_child(column)
	var developer_label: Label = UI.make_label(
		"DEV PREVIEW · 제품 UI가 아님", 9, UI.COLOR_DEV
	)
	developer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(developer_label)

	var controls := HBoxContainer.new()
	controls.custom_minimum_size.y = UI.TOUCH_MIN
	controls.add_theme_constant_override("separation", UI.GAP_SMALL)
	column.add_child(controls)
	var previous_button: Button = UI.make_button("‹", &"dev")
	previous_button.name = "PreviewPreviousButton"
	previous_button.unique_name_in_owner = true
	previous_button.pressed.connect(_show_previous)
	controls.add_child(previous_button)

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 0)
	controls.add_child(labels)
	_state_label = UI.make_label("", 10, UI.COLOR_TEXT)
	_state_label.name = "PreviewStateLabel"
	_state_label.unique_name_in_owner = true
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.add_child(_state_label)
	_event_label = UI.make_label("", 9, UI.COLOR_MUTED)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.add_child(_event_label)

	var next_button: Button = UI.make_button("›", &"dev")
	next_button.name = "PreviewNextButton"
	next_button.unique_name_in_owner = true
	next_button.pressed.connect(_show_next)
	controls.add_child(next_button)
	var hide_button: Button = UI.make_button("HUD 끄기", &"dev")
	hide_button.name = "PreviewHideButton"
	hide_button.unique_name_in_owner = true
	hide_button.custom_minimum_size.x = 68.0
	hide_button.pressed.connect(_hide_dev_chrome)
	controls.add_child(hide_button)


func _show_boot(state: Dictionary) -> void:
	var view: BOOT_VIEW_SCRIPT = BOOT_SCENE.instantiate() as BOOT_VIEW_SCRIPT
	assert(view != null, "Boot preview scene must instantiate as AppShellBootView.")
	view.configure(String(state["status"]))
	_product_host.add_child(view)


func _show_first_shift() -> void:
	var view: FIRST_SHIFT_VIEW_SCRIPT = (
		FIRST_SHIFT_SCENE.instantiate() as FIRST_SHIFT_VIEW_SCRIPT
	)
	assert(view != null, "First-shift preview scene must instantiate as AppShellFirstShiftView.")
	view.first_shift_requested.connect(_on_first_shift_requested)
	view.settings_requested.connect(_on_settings_requested)
	_product_host.add_child(view)


func _show_operations_room(data: OPERATIONS_DATA_SCRIPT) -> void:
	var view: OPERATIONS_ROOM_VIEW_SCRIPT = (
		OPERATIONS_ROOM_SCENE.instantiate() as OPERATIONS_ROOM_VIEW_SCRIPT
	)
	assert(view != null, "Operations preview scene must instantiate as AppShellOperationsRoomView.")
	view.configure(data)
	view.continue_requested.connect(_on_continue_requested)
	view.manual_requested.connect(_on_manual_requested)
	view.settings_requested.connect(_on_settings_requested)
	_product_host.add_child(view)


func _show_offline_report(data: OFFLINE_DATA_SCRIPT) -> void:
	_show_operations_room(FIXTURES.operations_normal())
	var view: OFFLINE_REPORT_VIEW_SCRIPT = (
		OFFLINE_REPORT_SCENE.instantiate() as OFFLINE_REPORT_VIEW_SCRIPT
	)
	assert(view != null, "Offline preview scene must instantiate as AppShellOfflineReportView.")
	view.configure(data)
	view.bottleneck_requested.connect(_on_bottleneck_requested)
	view.continue_requested.connect(_on_report_continue_requested)
	view.operations_room_requested.connect(_on_operations_room_requested)
	_product_host.add_child(view)


func _show_previous() -> void:
	show_preview_state(_current_index - 1)


func _show_next() -> void:
	show_preview_state(_current_index + 1)


func _hide_dev_chrome() -> void:
	_dev_layer.visible = false


func _show_state_by_id(state_id: StringName) -> void:
	for state_index: int in range(_states.size()):
		if StringName(_states[state_index]["id"]) == state_id:
			show_preview_state(state_index)
			return
	assert(false, "Unknown app-shell preview state id: %s" % state_id)


func _clear_product_host() -> void:
	for child: Node in _product_host.get_children():
		_product_host.remove_child(child)
		child.queue_free()


func _on_first_shift_requested() -> void:
	_show_state_by_id(&"operations_normal")
	_event_label.text = "[신호] first_shift_requested"


func _on_continue_requested() -> void:
	_event_label.text = "[신호] continue_requested · 현장은 이번 preview 범위 밖"


func _on_manual_requested() -> void:
	_event_label.text = "[신호] manual_requested"


func _on_settings_requested() -> void:
	_event_label.text = "[신호] settings_requested"


func _on_bottleneck_requested() -> void:
	_show_state_by_id(&"operations_normal")
	_event_label.text = "[신호] bottleneck_requested"


func _on_report_continue_requested() -> void:
	_show_state_by_id(&"operations_normal")
	_event_label.text = "[신호] continue_requested"


func _on_operations_room_requested() -> void:
	_show_state_by_id(&"operations_normal")
	_event_label.text = "[신호] operations_room_requested"
