class_name CombatV2ResultView
extends Control

signal operations_room_requested
signal restart_requested

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")

var _data: CombatV2ResultViewData


func configure(data: CombatV2ResultViewData) -> bool:
	if data == null or not data.validation_errors().is_empty():
		push_error("CombatV2ResultView requires valid result data.")
		return false
	_data = data
	return true


func _ready() -> void:
	assert(_data != null, "CombatV2ResultView must be configured before entering the tree")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = UI.attach_scrollable_screen_frame(self, UI.GAP_MEDIUM)
	var title: Label = UI.make_label("COMBAT V2 테스트 결과", UI.TITLE_SIZE, UI.COLOR_INFO)
	title.name = "ScreenTitle"
	column.add_child(title)
	column.add_child(UI.make_label(
		"Watchdog 격리 완료 · %.1f초" % _data.clear_time,
		14,
		UI.COLOR_SAFE
	))

	var summary: PanelContainer = UI.make_panel(UI.COLOR_PANEL, UI.COLOR_BORDER, 1, 8)
	column.add_child(summary)
	var summary_column := VBoxContainer.new()
	summary_column.add_theme_constant_override("separation", UI.GAP_SMALL)
	summary.add_child(summary_column)
	_add_row(summary_column, "실패", "일반 %d · 보스 %d · 합계 %d" % [
		_data.normal_failures, _data.boss_failures, _data.total_failures,
	])
	_add_row(summary_column, "복구", "QA %d · 유료 %d회 / %.0f bits" % [
		_data.qa_rescues, _data.paid_redeploy_count, _data.emergency_spent_bits,
	])
	_add_row(summary_column, "비트", "획득 %.0f · 잔여 %.0f" % [_data.gross_bits, _data.net_bits])
	_add_row(summary_column, "최종 레벨", "D%d · B%d · S%d · Q%d" % [
		int(_data.operator_levels["debugger"]),
		int(_data.operator_levels["build_engineer"]),
		int(_data.operator_levels["sprite_artist"]),
		int(_data.operator_levels["qa_imp"]),
	])

	_add_history(column, "주요 진단 이력", _data.diagnosis_history)
	_add_history(column, "패치 이력", _data.patch_history)

	var restart: Button = UI.make_button("Combat V2 테스트 새로 시작", &"primary", UI.PRIMARY_HEIGHT)
	restart.name = "RestartV2Button"
	restart.pressed.connect(restart_requested.emit)
	column.add_child(restart)
	var operations: Button = UI.make_button("Operations Room으로 복귀", &"secondary", UI.TOUCH_MIN)
	operations.name = "OperationsRoomButton"
	operations.pressed.connect(operations_room_requested.emit)
	column.add_child(operations)


func _add_row(parent: VBoxContainer, caption: String, value: String) -> void:
	parent.add_child(UI.make_value_row(caption, value))


func _add_history(parent: VBoxContainer, title: String, entries: Array[String]) -> void:
	var panel: PanelContainer = UI.make_panel(UI.COLOR_DEEP, UI.COLOR_BORDER, 1, 7)
	panel.custom_minimum_size.y = 72.0
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	column.add_child(UI.make_label(title, 12, UI.COLOR_INFO))
	var text := "기록 없음" if entries.is_empty() else "\n".join(PackedStringArray(entries))
	var label: Label = UI.make_label(text, 9, UI.COLOR_MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 36.0
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(label)
