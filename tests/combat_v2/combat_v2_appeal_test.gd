extends SceneTree

const STEP := 0.25

var _passed := 0
var _failed := 0
var _assertion_failures := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("Pixel Night Shift Combat V2 appeal tests")
	print("=========================================")
	await _run_test("strict content validation and four-operator coverage", _test_content_validation)
	await _run_test("visible evidence predicates and truthful templates", _test_visible_evidence_contract)
	await _run_test("max two, cooldown, dedupe, and stable ordering", _test_rule_selection)
	await _run_test("failure presents two factual role-biased opinions", _test_failure_opinions)
	await _run_test("upgrade acknowledgment and ignored no-penalty", _test_acceptance_and_no_penalty)
	await _run_test("save reload prevents duplicate appeal counts", _test_save_reload_dedupe)
	await _run_test(
		"360-wide field report opens, reads, and reopens without covering combat",
		_test_pointer_ui
	)
	print("=========================================")
	print("RESULT: %d passed, %d failed, %d assertion failures" % [
		_passed, _failed, _assertion_failures,
	])
	quit(0 if _failed == 0 else 1)


func _run_test(test_name: String, callable: Callable) -> void:
	var before := _assertion_failures
	await callable.call()
	if _assertion_failures == before:
		_passed += 1
		print("PASS  %s" % test_name)
	else:
		_failed += 1
		print("FAIL  %s" % test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_assertion_failures += 1
	print("      - %s" % message)


func _test_content_validation() -> void:
	var loaded := AppealLoader.load_default()
	_check(loaded.is_valid(), "default appeal content must pass strict validation")
	if not loaded.is_valid():
		return
	_check(loaded.catalog.definitions.size() == 24, "appeal content must contain exactly 24 rules")
	var counts: Dictionary = {}
	for operator_id: StringName in AppealLoader.SUPPORTED_OPERATORS:
		counts[operator_id] = 0
	for definition: AppealDefinition in loaded.catalog.definitions:
		counts[definition.operator_id] = int(counts[definition.operator_id]) + 1
	for operator_id: StringName in AppealLoader.SUPPORTED_OPERATORS:
		_check(int(counts[operator_id]) >= 4, "%s must have broad appeal coverage" % operator_id)

	var mutations: Array[Dictionary] = [
		{"kind": "missing", "error": "required field"},
		{"kind": "operator", "error": "unknown operator"},
		{"kind": "trigger", "error": "unknown trigger"},
		{"kind": "empty", "error": "non-empty string"},
		{"kind": "evidence", "error": "unsupported visible evidence"},
		{"kind": "duplicate", "error": "duplicate id"},
		{"kind": "threshold", "error": "numeric evidence requires"},
	]
	for mutation: Dictionary in mutations:
		var rejected := AppealLoader.load_from_json(_mutated_content(String(mutation["kind"])))
		_check(not rejected.is_valid(), "%s mutation must be rejected" % mutation["kind"])
		_check(
			String(mutation["error"]) in "; ".join(rejected.errors),
			"%s mutation must report its explicit cause" % mutation["kind"]
		)


func _test_visible_evidence_contract() -> void:
	var loaded := AppealLoader.load_default()
	var snapshot := CombatV2IntegrationSession.new().snapshot()
	var visible := snapshot["appeal_evidence"] as Dictionary
	var diagnosis_observation_terms := {
		"incoming_damage": "피해 과다",
		"patch_tradeoff": "패치 부작용",
		"firepower": "화력 부족",
		"boss_rollback": "rollback",
		"stable": "운영 안정",
		"recovery_delay": "복구 지연",
	}
	for definition: AppealDefinition in loaded.catalog.definitions:
		_check(not definition.observation_template.is_empty(), "%s observation must not be empty" % definition.id)
		_check(not definition.request_template.is_empty(), "%s request must not be empty" % definition.id)
		for condition: AppealDefinition.EvidenceCondition in definition.conditions:
			_check(
				visible.has(condition.key),
				"%s must use evidence present in the player-visible snapshot" % definition.id
			)
			if definition.trigger == &"diagnosis_changed" and condition.key == &"diagnosis_kind":
				var kind := String(condition.value)
				_check(
					diagnosis_observation_terms.has(kind)
					and String(diagnosis_observation_terms[kind]) in definition.observation_template,
					"%s observation must agree with its diagnosis predicate" % definition.id
				)
		for forbidden: String in AppealLoader.FORBIDDEN_CLAIMS:
			_check(forbidden not in definition.observation_template, "%s observation claims certainty" % definition.id)
			_check(forbidden not in definition.request_template, "%s request claims certainty" % definition.id)


func _test_rule_selection() -> void:
	var catalog := AppealLoader.load_default().catalog
	var evidence := _failure_evidence()
	var selected := OperatorAppealRules.evaluate(
		catalog, &"normal_failure", evidence, 1, 10.0, {}, _ready_times(), 0.0, true
	)
	_check(selected.size() == 2, "failure selection must cap output at two")
	_check(
		selected.size() == 2
		and selected[0].operator_id == &"debugger"
		and selected[1].operator_id == &"sprite_artist",
		"priority and stable operator ordering must be deterministic"
	)
	var dedupes := {
		"1:debugger_normal_failure": true,
		"1:sprite_normal_failure": true,
		"1:qa_normal_failure": true,
	}
	var repeated_failure := OperatorAppealRules.evaluate(
		catalog, &"normal_failure", evidence, 1, 10.0, dedupes, _ready_times(), 0.0, true
	)
	_check(
		repeated_failure.size() == 2,
		"same-stage normal failures must present a fresh report"
	)
	var boss_evidence := evidence.duplicate(true)
	boss_evidence["boss_failure_count"] = 1
	var repeated_boss_failure := OperatorAppealRules.evaluate(
		catalog,
		&"boss_failure",
		boss_evidence,
		1,
		10.0,
		{
			"1:debugger_boss_failure": true,
			"1:build_boss_failure": true,
			"1:qa_boss_failure": true,
		},
		_ready_times(),
		0.0,
		true
	)
	_check(
		repeated_boss_failure.size() == 2,
		"same-stage boss failures must present a fresh report"
	)
	var down_evidence := evidence.duplicate(true)
	down_evidence["current_downs"] = 1
	down_evidence["event_operator_id"] = "debugger"
	_check(
		OperatorAppealRules.evaluate(
			catalog,
			&"operator_down",
			down_evidence,
			1,
			10.0,
			{
				"1:debugger_operator_down": true,
				"1:sprite_operator_down": true,
			},
			_ready_times(),
			0.0,
			true
		).is_empty(),
		"same-stage dedupe must continue suppressing ordinary repeated opinions"
	)
	var incoming := evidence.duplicate(true)
	incoming["diagnosis_kind"] = "incoming_damage"
	_check(
		OperatorAppealRules.evaluate(
			catalog, &"diagnosis_changed", incoming, 2, 5.0, {}, _ready_times(20.0), 20.0
		).is_empty(),
		"global and per-operator cooldowns must suppress ordinary triggers"
	)

	var tie_catalog := AppealCatalog.new()
	var condition := AppealDefinition.EvidenceCondition.new(&"diagnosis_kind", &"eq", "incoming_damage")
	for operator_id: StringName in [&"build_engineer", &"debugger"]:
		tie_catalog.definitions.append(AppealDefinition.new(
			StringName("tie_%s" % operator_id), operator_id, &"diagnosis_changed", [condition],
			"피해 과다 진단이 표시됐습니다.", "제 역할 강화를 검토해 주세요.",
			50, 0.0, 0.0, StringName("tie_%s" % operator_id)
		))
	tie_catalog.build_indexes()
	var tied := OperatorAppealRules.evaluate(
		tie_catalog, &"diagnosis_changed", incoming, 2, 5.0, {}, _ready_times(), 0.0
	)
	_check(tied[0].operator_id == &"debugger", "equal priority must use stable operator ID order")


func _test_failure_opinions() -> void:
	var results := OperatorAppealRules.evaluate(
		AppealLoader.load_default().catalog,
		&"normal_failure",
		_failure_evidence(),
		4,
		100.0,
		{},
		_ready_times(),
		0.0,
		true
	)
	_check(results.size() == 2, "normal failure must expose two opinions when both are valid")
	if results.size() != 2:
		return
	_check(results[0].observation == results[1].observation, "failure opinions must share objective evidence")
	_check(results[0].request != results[1].request, "failure opinions must interpret evidence through different roles")
	_check(results[0].operator_id != results[1].operator_id, "failure opinions must come from different operators")
	var session := _live_failure_session()
	session.tick(0.01)
	var snapshot := session.snapshot()
	_check(String(snapshot["mode"]) == "maintenance", "live all-down event must enter maintenance")
	var live_appeals := snapshot["appeals"] as Array
	_check(live_appeals.size() == 2, "live failure event must replace stale opinions with two failure opinions")
	if live_appeals.size() == 2:
		_check(
			String((live_appeals[0] as Dictionary)["trigger"]) == "normal_failure"
			and String((live_appeals[1] as Dictionary)["trigger"]) == "normal_failure",
			"live failure opinions must be attributed to the failure trigger"
		)


func _test_acceptance_and_no_penalty() -> void:
	var prototype := _rich_prototype()
	var baseline := CombatV2PrototypeSession.new()
	_check(baseline.restore_state(prototype.export_state()).is_empty(), "baseline prototype must restore")
	var session := CombatV2IntegrationSession.new(prototype)
	var before := session.snapshot()
	_check(not (before["appeals"] as Array).is_empty(), "rich fixture must expose at least one appeal")
	if (before["appeals"] as Array).is_empty():
		return
	var target := StringName(String(((before["appeals"] as Array)[0] as Dictionary)["operator_id"]))
	_check(session.upgrade_operator(target), "appeal target must still use the existing upgrade command")
	var after := session.snapshot()
	_check(int((after["appeal_stats"] as Dictionary)["accepted"]) == 1, "matching upgrade must count one accepted appeal")
	_check(not String(after["appeal_acknowledgment"]).is_empty(), "matching upgrade must show one-line acknowledgment")
	for raw_appeal: Variant in after["appeals"] as Array:
		_check(StringName(String((raw_appeal as Dictionary)["operator_id"])) != target, "accepted appeal must be removed")

	var ignored_prototype := _rich_prototype()
	var direct := CombatV2PrototypeSession.new()
	_check(direct.restore_state(ignored_prototype.export_state()).is_empty(), "direct comparison must restore")
	var ignored := CombatV2IntegrationSession.new(ignored_prototype)
	ignored.tick(1.0)
	direct.tick(1.0)
	_check(
		ignored.export_state()["combat"] == direct.export_state(),
		"ignoring appeals must not change combat, efficiency, morale, or hidden state"
	)
	var clearing_prototype := _rich_prototype()
	for _upgrade: int in range(7):
		assert(clearing_prototype.upgrade_operator(&"debugger"))
	var clearing := CombatV2IntegrationSession.new(clearing_prototype)
	var initial_visible := (clearing.snapshot()["appeals"] as Array).size()
	for _step: int in range(int(120.0 / STEP)):
		if int(clearing.snapshot()["stage"]) > 1:
			break
		clearing.tick(STEP)
	var cleared_snapshot := clearing.snapshot()
	_check(int(cleared_snapshot["stage"]) > 1, "stage-clear fixture must advance")
	_check(
		int((cleared_snapshot["appeal_stats"] as Dictionary)["ignored"]) >= initial_visible,
		"stage clear must retire the previous stage's unresolved appeals without penalty"
	)


func _test_save_reload_dedupe() -> void:
	var source := CombatV2IntegrationSession.new(_rich_prototype())
	var exported := source.export_state()
	var before_stats := source.snapshot()["appeal_stats"] as Dictionary
	var restored := CombatV2IntegrationSession.new()
	_check(restored.restore_state(exported).is_empty(), "appeal state must restore")
	_check(restored.export_state() == exported, "appeal state roundtrip must be canonical")
	restored.tick(0.0)
	var after_stats := restored.snapshot()["appeal_stats"] as Dictionary
	_check(after_stats == before_stats, "reload and zero tick must not re-show or double-count appeals")
	var canonical := restored.export_state()
	var corrupt := canonical.duplicate(true)
	corrupt["appeals"]["shown_count"] = int(corrupt["appeals"]["shown_count"]) + 1
	_check(not restored.restore_state(corrupt).is_empty(), "corrupt appeal counters must be rejected")
	_check(restored.export_state() == canonical, "corrupt appeal restore must leave the active session atomic")


func _test_pointer_ui() -> void:
	root.size = Vector2i(360, 640)
	var audio := AudioDirector.new()
	root.add_child(audio)
	var view := MainView.new()
	var session := _live_failure_session()
	session.tick(0.01)
	var snapshot := session.snapshot()
	var report_key := "v2:%d:%d" % [
		int(snapshot["run_count"]),
		int(snapshot["failure_count"]),
	]
	_check(view.configure(session, audio), "view must configure")
	_check(
		view.set_field_report_state({
			"key": report_key,
			"rows": (snapshot["appeals"] as Array).duplicate(true),
			"is_v2": true,
			"unread": true,
		}),
		"view must accept a cached unread failure report"
	)
	var read_keys: Array[String] = []
	view.field_report_read.connect(func(key: String) -> void: read_keys.append(key))
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _wait_frames(8)
	var panel := view.find_child("OperatorAppealPanel", true, false) as Control
	var card := view.find_child("OperatorAppealCard0", true, false) as Button
	var report_button := view.find_child("FieldReportButton", true, false) as Button
	var battle := view.find_child("BattleLaneView", true, false) as Control
	var diagnosis := view.find_child("DiagnosisActionButton", true, false) as Control
	_check(
		report_button != null
			and report_button.visible
			and report_button.custom_minimum_size == Vector2(48.0, 48.0),
		"field report alert must keep a visible 48px touch target"
	)
	_check(panel != null and not panel.visible, "unread field report must start collapsed")
	_check(
		report_button != null and "새 보고서" in report_button.tooltip_text,
		"unread report icon must identify the new report"
	)
	_check(view.size.x == 360.0, "pointer fixture must use the 360-wide authority layout")
	if report_button != null:
		report_button.pressed.emit()
		await _wait_frames(2)
	_check(panel != null and panel.visible, "report icon must open the cached failure report")
	_check(
		card != null
			and card.visible
			and card.size.y >= 44.0
			and card.focus_mode == Control.FOCUS_NONE
			and card.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"field report rows must be readable, non-interactive cards"
	)
	_check(
		read_keys == [report_key],
		"first report opening must acknowledge exactly the current report key"
	)
	_check(
		report_button != null
			and not "새 보고서" in report_button.tooltip_text
			and is_equal_approx(report_button.self_modulate.a, 1.0),
		"reading the report must stop its unread pulse"
	)
	if panel != null and battle != null:
		_check(not panel.get_global_rect().intersects(battle.get_global_rect()), "appeals must not cover combat")
	if panel != null and diagnosis != null:
		_check(not panel.get_global_rect().intersects(diagnosis.get_global_rect()), "appeals must not cover diagnosis controls")
	if report_button != null:
		report_button.pressed.emit()
		await _wait_frames(2)
	_check(panel != null and not panel.visible, "report icon must collapse an open report")
	if report_button != null:
		report_button.pressed.emit()
		await _wait_frames(2)
	_check(
		panel != null and panel.visible and read_keys == [report_key],
		"read report must reopen without becoming unread again"
	)
	view.queue_free()
	audio.queue_free()
	await _wait_frames(3)


func _mutated_content(kind: String) -> String:
	var file := FileAccess.open(AppealLoader.CONTENT_PATH, FileAccess.READ)
	assert(file != null)
	var data := JSON.parse_string(file.get_as_text()) as Dictionary
	var rules := data["rules"] as Array
	var first := rules[0] as Dictionary
	match kind:
		"missing":
			first.erase("request_template")
		"operator":
			first["operator_id"] = "unknown_operator"
		"trigger":
			first["trigger"] = "random_prompt"
		"empty":
			first["observation_template"] = ""
		"evidence":
			(first["conditions"] as Array)[0]["key"] = "hidden_damage_exponent"
		"duplicate":
			(rules[1] as Dictionary)["id"] = String(first["id"])
		"threshold":
			(first["conditions"] as Array)[0]["key"] = "current_downs"
			(first["conditions"] as Array)[0]["op"] = "eq"
			(first["conditions"] as Array)[0]["value"] = "future"
		_:
			assert(false, "Unknown content mutation: %s" % kind)
	return JSON.stringify(data)


func _failure_evidence() -> Dictionary:
	var evidence := CombatV2IntegrationSession.new().snapshot()["appeal_evidence"] as Dictionary
	evidence = evidence.duplicate(true)
	evidence["diagnosis_kind"] = "maintenance"
	evidence["maintenance"] = true
	evidence["current_downs"] = 4
	evidence["failure_count"] = 1
	evidence["normal_failure_count"] = 1
	evidence["last_failure_reason"] = "normal_all_down"
	evidence["event_reason"] = "normal_all_down"
	evidence["unlocked_operator_ids"] = [
		"debugger", "build_engineer", "sprite_artist", "qa_imp",
	]
	return evidence


func _ready_times(value: float = 0.0) -> Dictionary:
	return {
		&"debugger": value,
		&"build_engineer": value,
		&"sprite_artist": value,
		&"qa_imp": value,
	}


func _rich_prototype() -> CombatV2PrototypeSession:
	var prototype := CombatV2PrototypeSession.new()
	var state := prototype.debug_state_copy()
	state.progression.bits = 1000.0
	var errors := prototype.restore_state(CombatV2StateDto.export_state(state))
	assert(errors.is_empty(), "; ".join(errors))
	return prototype


func _live_failure_session() -> CombatV2IntegrationSession:
	var prototype := CombatV2PrototypeSession.new()
	_drive_to_stage(prototype, 6)
	var state := prototype.debug_state_copy()
	var loaded := CombatV2Loader.load_default()
	assert(loaded.is_valid())
	var catalog: CombatV2Catalog = loaded.catalog
	state.progression.is_maintenance = false
	state.maintenance_remaining = 0.0
	state.last_failure_reason = &""
	state.qa_rescue_consumed = true
	state.qa_recovery_target_id = &""
	state.enemy_attack_remaining = 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if not state.progression.is_operator_unlocked(runtime.operator_id):
			continue
		runtime.current_hp = 0.0
		runtime.attack_remaining = INF
		runtime.recovery_remaining = 0.0
		runtime.recovery_source = &""
	var debugger := state.get_operator(&"debugger")
	debugger.current_hp = 1.0
	debugger.attack_remaining = 1.0
	state.progression.enemy_health = maxf(
		1.0, ProgressionRules.current_enemy_max_hp(state.progression, catalog.base_catalog)
	)
	var errors := prototype.restore_state(CombatV2StateDto.export_state(state))
	assert(errors.is_empty(), "; ".join(errors))
	return CombatV2IntegrationSession.new(prototype)


func _drive_to_stage(prototype: CombatV2PrototypeSession, target_stage: int) -> void:
	var next_decision := 0.0
	for step: int in range(int(1800.0 / STEP)):
		var snapshot := prototype.snapshot()
		if int(snapshot["stage"]) >= target_stage:
			return
		var elapsed := step * STEP
		if elapsed + 0.000001 >= next_decision:
			_apply_balanced_decision(prototype, snapshot)
			next_decision += 1.0
		prototype.tick(STEP)
	assert(false, "Cannot reach stage %d for live failure fixture" % target_stage)


func _apply_balanced_decision(session: CombatV2PrototypeSession, snapshot: Dictionary) -> void:
	var selected := &""
	var lowest_level := 2147483647
	var bits := float(snapshot["bits"])
	for raw_operator: Variant in snapshot["operators"] as Array:
		var operator := raw_operator as Dictionary
		if not bool(operator["unlocked"]) or float(operator["upgrade_cost"]) > bits + 0.000001:
			continue
		if int(operator["level"]) < lowest_level:
			selected = StringName(String(operator["id"]))
			lowest_level = int(operator["level"])
	if selected != &"":
		session.upgrade_operator(selected)


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame
