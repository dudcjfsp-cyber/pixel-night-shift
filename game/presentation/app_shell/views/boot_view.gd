class_name AppShellBootView
extends Control

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")

var _status_text := "근무 기록 확인 중…"
var _status_label: Label


func configure(status_text: String) -> void:
	if status_text.is_empty():
		push_error("Boot status text cannot be empty.")
		return
	_status_text = status_text
	if is_node_ready():
		_status_label.text = _status_text


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	_status_label.text = _status_text


func _build_interface() -> void:
	var column: VBoxContainer = UI.attach_screen_frame(self, UI.GAP_LARGE)
	column.add_child(UI.make_spacer())

	var panel: PanelContainer = UI.make_panel(UI.COLOR_PANEL, UI.COLOR_INFO, 2, 16)
	panel.name = "BootTerminal"
	panel.custom_minimum_size = Vector2(304.0, 260.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)

	var terminal_column := VBoxContainer.new()
	terminal_column.add_theme_constant_override("separation", UI.GAP_MEDIUM)
	panel.add_child(terminal_column)

	var eyebrow: Label = UI.make_label("PIXEL NIGHT SHIFT // BOOT", 13, UI.COLOR_INFO)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terminal_column.add_child(eyebrow)
	terminal_column.add_child(UI.make_rule(UI.COLOR_INFO))

	var service_label: Label = UI.make_label("LOCAL NIGHT SERVICE", 11, UI.COLOR_MUTED)
	service_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terminal_column.add_child(service_label)

	_status_label = UI.make_label(_status_text, 14, UI.COLOR_TEXT, true)
	_status_label.name = "StatusLabel"
	_status_label.unique_name_in_owner = true
	_status_label.custom_minimum_size.y = 48.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terminal_column.add_child(_status_label)

	var handoff: PanelContainer = UI.make_panel(UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 8)
	terminal_column.add_child(handoff)
	var handoff_label: Label = UI.make_label(
		"[전환 상태] 로컬 근무 기록과 화면 경로를 확인합니다.",
		UI.SUPPORT_SIZE,
		UI.COLOR_MUTED,
		true
	)
	handoff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	handoff.add_child(handoff_label)

	var footer: Label = UI.make_label(
		"입력 없이 다음 화면으로 이동합니다.", UI.SUPPORT_SIZE, UI.COLOR_INFO
	)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terminal_column.add_child(footer)
	column.add_child(UI.make_spacer())
