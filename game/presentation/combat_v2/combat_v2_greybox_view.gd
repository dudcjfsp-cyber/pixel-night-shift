class_name CombatV2GreyboxView
extends Control

const CURRENT_SESSION_SCRIPT := preload("res://game/app/game_session.gd")
const V2_SESSION_SCRIPT := preload("res://game/app/combat_v2_prototype_session.gd")

const OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]
const REFRESH_SECONDS := 0.10
const AUTO_DECISION_SECONDS := 60.0

var _current_session: GameSession
var _v2_session: CombatV2PrototypeSession
var _show_v2 := true
var _paused := false
var _auto_decisions := true
var _speed := 1.0
var _refresh_left := 0.0
var _decision_left := AUTO_DECISION_SECONDS
var _current_elapsed := 0.0
var _v2_elapsed := 0.0

var _mode_button: Button
var _pause_button: Button
var _auto_button: Button
var _speed_button: Button
var _comparison_label: Label
var _enemy_label: Label
var _enemy_bar: ProgressBar
var _next_action_label: Label
var _operator_labels: Array[Label] = []
var _operator_bars: Array[ProgressBar] = []
var _diagnosis_label: Label
var _patch_label: Label
var _event_log: RichTextLabel
var _status_label: Label


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_window().title = "Pixel Night Shift - Combat V2 Greybox"
	_current_session = CURRENT_SESSION_SCRIPT.new()
	_v2_session = V2_SESSION_SCRIPT.new()
	_build_ui()
	_refresh()


func _process(delta_seconds: float) -> void:
	if _paused:
		return
	var simulation_delta := delta_seconds * _speed
	_current_session.tick(simulation_delta)
	_v2_session.tick(simulation_delta)
	_current_elapsed += simulation_delta
	_v2_elapsed += simulation_delta
	_decision_left -= simulation_delta
	if _auto_decisions and _decision_left <= 0.0:
		_decision_left += AUTO_DECISION_SECONDS
		_apply_baseline_decision(_current_session)
		_apply_baseline_decision(_v2_session)
	_refresh_left -= delta_seconds
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		_refresh()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("10151f")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(328.0, 0.0)
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "COMBAT V2 · 독립 회색상자"
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	column.add_child(controls)
	_mode_button = _button("표시: V2", _toggle_mode)
	_pause_button = _button("일시정지", _toggle_pause)
	_auto_button = _button("자동판단: 켬", _toggle_auto)
	_speed_button = _button("속도 ×1", _cycle_speed)
	controls.add_child(_mode_button)
	controls.add_child(_pause_button)
	controls.add_child(_auto_button)
	controls.add_child(_speed_button)

	_comparison_label = Label.new()
	_comparison_label.name = "ComparisonLabel"
	_comparison_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_comparison_label.add_theme_color_override("font_color", Color("9dafc7"))
	column.add_child(_comparison_label)

	column.add_child(_section("현재 조우"))
	_enemy_label = Label.new()
	_enemy_label.name = "EnemyLabel"
	_enemy_label.add_theme_font_size_override("font_size", 15)
	column.add_child(_enemy_label)
	_enemy_bar = ProgressBar.new()
	_enemy_bar.custom_minimum_size.y = 20.0
	_enemy_bar.show_percentage = false
	column.add_child(_enemy_bar)
	_next_action_label = Label.new()
	_next_action_label.name = "NextActionLabel"
	_next_action_label.add_theme_color_override("font_color", Color("f4c95d"))
	column.add_child(_next_action_label)

	column.add_child(_section("요원 HP · 다운 · 복구"))
	for _operator_id: StringName in OPERATOR_IDS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		column.add_child(row)
		var label := Label.new()
		label.name = "Operator_%s" % String(_operator_id)
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)
		_operator_labels.append(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 14.0
		bar.show_percentage = false
		row.add_child(bar)
		_operator_bars.append(bar)

	column.add_child(_section("동일 명령 적용"))
	var upgrades := GridContainer.new()
	upgrades.columns = 2
	upgrades.add_theme_constant_override("h_separation", 4)
	upgrades.add_theme_constant_override("v_separation", 4)
	column.add_child(upgrades)
	for operator_id: StringName in OPERATOR_IDS:
		var captured_id := operator_id
		var upgrade := Button.new()
		upgrade.text = "%s 강화" % String(operator_id)
		upgrade.custom_minimum_size = Vector2(160.0, 38.0)
		upgrade.pressed.connect(func() -> void: _upgrade_both(captured_id))
		upgrades.add_child(upgrade)

	var patches := HBoxContainer.new()
	patches.add_theme_constant_override("separation", 4)
	column.add_child(patches)
	for patch_id: StringName in [&"frame_skip", &"unsafe_build", &"reward_bypass", &"rollback_lock"]:
		var captured_patch := patch_id
		var patch_button := Button.new()
		patch_button.text = String(patch_id)
		patch_button.custom_minimum_size.y = 34.0
		patch_button.pressed.connect(func() -> void: _equip_both(captured_patch))
		patches.add_child(patch_button)

	column.add_child(_section("진단"))
	_diagnosis_label = Label.new()
	_diagnosis_label.name = "DiagnosisLabel"
	_diagnosis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnosis_label.custom_minimum_size.y = 42.0
	column.add_child(_diagnosis_label)
	_patch_label = Label.new()
	_patch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_patch_label.add_theme_color_override("font_color", Color("9dafc7"))
	column.add_child(_patch_label)

	column.add_child(_section("최근 결정론 사건"))
	_event_log = RichTextLabel.new()
	_event_log.name = "EventLog"
	_event_log.bbcode_enabled = false
	_event_log.fit_content = true
	_event_log.custom_minimum_size.y = 88.0
	_event_log.add_theme_font_size_override("normal_font_size", 10)
	column.add_child(_event_log)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color("52d6c8"))
	column.add_child(_status_label)


func _button(text_value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text_value
	result.custom_minimum_size.y = 38.0
	result.pressed.connect(callback)
	return result


func _section(text_value: String) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", 13)
	result.add_theme_color_override("font_color", Color("52d6c8"))
	return result


func _toggle_mode() -> void:
	_show_v2 = not _show_v2
	_mode_button.text = "표시: V2" if _show_v2 else "표시: CURRENT"
	_refresh()


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_button.text = "계속" if _paused else "일시정지"


func _toggle_auto() -> void:
	_auto_decisions = not _auto_decisions
	_auto_button.text = "자동판단: 켬" if _auto_decisions else "자동판단: 끔"


func _cycle_speed() -> void:
	if is_equal_approx(_speed, 1.0):
		_speed = 4.0
	elif is_equal_approx(_speed, 4.0):
		_speed = 16.0
	else:
		_speed = 1.0
	_speed_button.text = "속도 ×%d" % int(_speed)


func _upgrade_both(operator_id: StringName) -> void:
	var current_ok := _current_session.upgrade_operator(operator_id)
	var v2_ok := _v2_session.upgrade_operator(operator_id)
	_status_label.text = "동일 강화 %s · CURRENT %s / V2 %s" % [
		operator_id, "성공" if current_ok else "거부", "성공" if v2_ok else "거부",
	]
	_refresh()


func _equip_both(patch_id: StringName) -> void:
	var current_ok := _current_session.equip_patch(0, patch_id)
	var v2_ok := _v2_session.equip_patch(0, patch_id)
	_status_label.text = "동일 패치 %s · CURRENT %s / V2 %s" % [
		patch_id, "성공" if current_ok else "거부", "성공" if v2_ok else "거부",
	]
	_refresh()


func _apply_baseline_decision(session: Variant) -> void:
	var snapshot: Dictionary = session.snapshot()
	_assert_snapshot_contract(snapshot, snapshot.has("prototype"))
	var stage := int(snapshot.get("stage", 0))
	var desired_patch: StringName = &"rollback_lock" if stage == 10 else &"frame_skip"
	var slots := snapshot.get("patch_slots", []) as Array
	if int(snapshot.get("unlocked_patch_slots", 0)) > 0:
		if slots.is_empty() or String(slots[0]) != String(desired_patch):
			var preview: Dictionary = session.get_patch_preview(0, desired_patch)
			if bool(preview["can_equip"]) and float(snapshot["bits"]) >= float(preview["cost"]):
				if not session.equip_patch(0, desired_patch):
					push_error("Affordable automatic patch intent was rejected: %s" % desired_patch)
	var bits := float(snapshot.get("bits", 0.0))
	var best_id := StringName()
	var best_cost := INF
	for operator_value: Variant in snapshot.get("operators", []) as Array:
		var operator := operator_value as Dictionary
		if not bool(operator.get("unlocked", false)):
			continue
		var cost := float(operator.get("upgrade_cost", INF))
		if cost <= bits and cost < best_cost:
			best_cost = cost
			best_id = StringName(String(operator.get("id", "")))
	if best_id != &"":
		if not session.upgrade_operator(best_id):
			push_error("Affordable automatic operator upgrade was rejected: %s" % best_id)


func _refresh() -> void:
	if _current_session == null or _v2_session == null:
		return
	var current := _current_session.snapshot()
	var v2 := _v2_session.snapshot()
	_assert_snapshot_contract(current, false)
	_assert_snapshot_contract(v2, true)
	var selected := v2 if _show_v2 else current
	_comparison_label.text = (
		"CURRENT  ST %d · %.1fs    |    V2  ST %d · %.1fs\n"
		+ "동일한 시간과 자동 판단 주기로 각각 독립 실행 중"
	) % [
		int(current.get("stage", 0)), _current_elapsed,
		int(v2.get("stage", 0)), _v2_elapsed,
	]

	var enemy := selected.get("enemy", {}) as Dictionary
	var enemy_hp := float(enemy.get("hp", 0.0))
	var enemy_max_hp := maxf(0.001, float(enemy.get("max_hp", 0.001)))
	_enemy_label.text = "ST %d · %s · %s" % [
		int(selected.get("stage", 0)), String(enemy.get("name", "")),
		String(selected.get("mode", "")),
	]
	_enemy_bar.max_value = enemy_max_hp
	_enemy_bar.value = clampf(enemy_hp, 0.0, enemy_max_hp)
	if _show_v2:
		_next_action_label.text = "다음 적 행동: %s · %.2f초" % [
			String(enemy.get("next_action", "대기")),
			float(enemy.get("next_action_in", 0.0)),
		]
	else:
		_next_action_label.text = "CURRENT는 적 공격이 없는 기준 전투입니다."

	var operators := selected.get("operators", []) as Array
	for index: int in OPERATOR_IDS.size():
		var label := _operator_labels[index]
		var bar := _operator_bars[index]
		if index >= operators.size():
			label.text = "%s · 데이터 없음" % OPERATOR_IDS[index]
			bar.max_value = 1.0
			bar.value = 0.0
			continue
		var item := operators[index] as Dictionary
		var unlocked := bool(item.get("unlocked", false))
		if not unlocked:
			label.text = "%s · 잠김" % String(item.get("name", OPERATOR_IDS[index]))
			bar.max_value = 1.0
			bar.value = 0.0
			continue
		if _show_v2:
			var hp := float(item.get("hp", 0.0))
			var max_hp := maxf(0.001, float(item.get("max_hp", 0.001)))
			var state_text := (
				"DOWN · %.1fs 후 자동 복구" % float(item.get("recovery_remaining", 0.0))
				if bool(item.get("down", false))
				else "공격 %.1fs" % float(item.get("attack_remaining", 0.0))
			)
			label.text = "%s · %s · LV %d · HP %.0f/%.0f · %s" % [
				String(item.get("name", "")), String(item.get("role", "")),
				int(item.get("level", 0)), hp, max_hp, state_text,
			]
			bar.max_value = max_hp
			bar.value = clampf(hp, 0.0, max_hp)
		else:
			label.text = "%s · LV %d · DPS %.1f · 피격 없음" % [
				String(item.get("name", "")), int(item.get("level", 0)),
				float(item.get("dps", 0.0)),
			]
			bar.max_value = 1.0
			bar.value = 1.0

	var diagnosis := selected.get("diagnosis", {}) as Dictionary
	_diagnosis_label.text = "%s\n%s" % [
		String(diagnosis.get("title", "진단 없음")),
		String(diagnosis.get("evidence", "")),
	]
	var slots := selected.get("patch_slots", []) as Array
	_patch_label.text = "장착 패치: %s · 비트 %.0f" % [
		", ".join(PackedStringArray(slots)), float(selected.get("bits", 0.0)),
	]
	if _show_v2:
		_event_log.text = "\n".join(PackedStringArray(selected.get("recent_events", [])))
		if bool(selected.get("waiting_for_recovery", false)):
			_status_label.text = "전원 DOWN · 자동 복구 대기 중 · 수동 입력 불필요"
	else:
		_event_log.text = "CURRENT 기준: 연속 DPS로 적 HP만 감소합니다."


func _assert_snapshot_contract(snapshot: Dictionary, is_v2: bool) -> void:
	var required: Array[String] = [
		"stage", "bits", "mode", "enemy", "operators", "patch_slots",
		"unlocked_patch_slots", "patches", "diagnosis",
	]
	if is_v2:
		required.append_array(["waiting_for_recovery", "recent_events", "combat_metrics"])
	for key: String in required:
		assert(snapshot.has(key), "Greybox snapshot is missing required field: %s" % key)
	assert(snapshot["enemy"] is Dictionary, "Greybox enemy snapshot must be a Dictionary")
	var enemy := snapshot["enemy"] as Dictionary
	for key: String in ["name", "hp", "max_hp"]:
		assert(enemy.has(key), "Greybox enemy snapshot is missing field: %s" % key)
	if is_v2:
		for key: String in ["id", "next_action", "next_action_in"]:
			assert(enemy.has(key), "Combat V2 enemy snapshot is missing field: %s" % key)
	assert(snapshot["operators"] is Array, "Greybox operators must be an Array")
	var operators := snapshot["operators"] as Array
	assert(operators.size() == OPERATOR_IDS.size(), "Greybox requires exactly four operators")
	for operator_value: Variant in operators:
		assert(operator_value is Dictionary, "Greybox operator row must be a Dictionary")
		var operator := operator_value as Dictionary
		for key: String in ["id", "name", "level", "unlocked", "dps", "upgrade_cost"]:
			assert(operator.has(key), "Greybox operator row is missing field: %s" % key)
		if is_v2:
			for key: String in [
				"role", "hp", "max_hp", "down", "attack_remaining", "recovery_remaining",
			]:
				assert(operator.has(key), "Combat V2 operator row is missing field: %s" % key)
	assert(snapshot["diagnosis"] is Dictionary, "Greybox diagnosis must be a Dictionary")
	for key: String in ["kind", "title", "evidence", "severity"]:
		assert((snapshot["diagnosis"] as Dictionary).has(key), "Diagnosis is missing field: %s" % key)
