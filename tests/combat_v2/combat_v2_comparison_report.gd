extends SceneTree

const CurrentSessionScript := preload("res://game/app/game_session.gd")
const V2SessionScript := preload("res://game/app/combat_v2_integration_session.gd")
const V2PrototypeScript := preload("res://game/app/combat_v2_prototype_session.gd")
const V2LoaderScript := preload("res://game/content/combat_v2/combat_v2_loader.gd")
const ContentLoaderScript := preload("res://game/content/content_loader.gd")
const ProgressionRulesScript := preload("res://game/domain/progression_rules.gd")

const LEGACY_STEP := 0.25
const REPORT_STEP := 5.0
const DECISION_INTERVAL := 60.0
const LEGACY_TARGET_STAGE := 10
const FULL_RUN_TARGET_STAGE := 20
const MAX_SECONDS := 2400.0
const EPSILON := 0.000001

const CURRENT_POLICIES: Array[String] = [
	"debugger_focus",
	"cheapest",
	"balanced",
	"diagnosis_follow",
]
const V2_POLICIES: Array[String] = [
	"debugger_focus",
	"cheapest",
	"balanced",
	"diagnosis_follow",
	"appeal_only",
	"diagnosis_plus_appeal",
]
const OPERATOR_IDS: Array[StringName] = [
	&"debugger",
	&"build_engineer",
	&"sprite_artist",
	&"qa_imp",
]
const RECOVERY_PRIORITY: Array[StringName] = [
	&"qa_imp",
	&"sprite_artist",
	&"debugger",
	&"build_engineer",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var results: Array[Dictionary] = []
	for policy: String in CURRENT_POLICIES:
		results.append(simulate_current_twenty_stage_policy(policy))
	for policy: String in V2_POLICIES:
		results.append(simulate_v2_twenty_stage_policy(policy))

	print("Pixel Night Shift - 20-stage CURRENT / Combat V2 policy comparison")
	print("================================================================")
	_print_table(results)
	_print_milestone_table(results)

	var passed := true
	for result: Dictionary in results:
		if not bool(result["valid"]):
			print("FAIL [%s/%s]: %s" % [
				String(result["engine"]),
				String(result["policy"]),
				String(result["error"]),
			])
			passed = false

	if passed and _all_results_completed(results):
		var anti_debugger_passed := _check_anti_debugger(results)
		_report_product_risks(results)
		passed = anti_debugger_passed
	elif passed:
		_report_incomplete_risk(results)
	quit(0 if passed else 1)


static func simulate_v2_policy(policy: String) -> Dictionary:
	return _simulate_policy(
		V2SessionScript.new(), policy, true, LEGACY_TARGET_STAGE, LEGACY_STEP
	)


static func simulate_current_policy(policy: String) -> Dictionary:
	return _simulate_policy(
		CurrentSessionScript.new(), policy, false, LEGACY_TARGET_STAGE, LEGACY_STEP
	)


static func simulate_v2_twenty_stage_policy(policy: String) -> Dictionary:
	var load_result: Variant = V2LoaderScript.load_default()
	if not load_result.is_valid():
		return _invalid_result(
			"V2", policy,
			"Combat V2 content failed validation: %s" % "; ".join(load_result.errors)
		)
	load_result.catalog.balance.max_stage = FULL_RUN_TARGET_STAGE
	var prototype: Variant = V2PrototypeScript.new(load_result.catalog)
	return _simulate_policy(
		V2SessionScript.new(prototype), policy, true, FULL_RUN_TARGET_STAGE, REPORT_STEP
	)


static func simulate_current_twenty_stage_policy(policy: String) -> Dictionary:
	return _simulate_policy(
		CurrentSessionScript.new(), policy, false, FULL_RUN_TARGET_STAGE, REPORT_STEP
	)


static func _simulate_policy(
	session: Variant,
	policy: String,
	is_v2: bool,
	target_stage: int,
	step_seconds: float
) -> Dictionary:
	var engine := "V2" if is_v2 else "CURRENT"
	if not (V2_POLICIES if is_v2 else CURRENT_POLICIES).has(policy):
		return _invalid_result(engine, policy, "unknown policy")

	var load_result: ContentLoadResult = ContentLoaderScript.load_default()
	if not load_result.is_valid():
		return _invalid_result(
			engine,
			policy,
			"production content failed validation: %s" % "; ".join(load_result.errors)
		)
	var catalog: ContentCatalog = load_result.catalog

	var elapsed := 0.0
	var next_decision := 0.0
	var stage_10_arrival := INF
	var stage_10_clear := INF
	var maintenance_entries := 0
	var boss_failures_by_stage := {"10": 0, "20": 0}
	var boss_failure_reasons := {"10": {}, "20": {}}
	var command_spent_bits := 0.0
	var initial_bits := 0.0
	var has_initial_bits := false
	var previous_mode := ""
	var decision_count := 0
	var first_decision_at := INF
	var last_decision_at := 0.0
	var longest_action_gap := 0.0
	var first_patch_at := INF
	var last_snapshot: Dictionary = {}
	var decision_interval := DECISION_INTERVAL

	while elapsed <= MAX_SECONDS + EPSILON:
		last_snapshot = session.snapshot()
		var validation_errors := _validate_snapshot(last_snapshot, is_v2)
		if not validation_errors.is_empty():
			return _invalid_result(
				engine,
				policy,
				"invalid snapshot at %.2fs: %s" % [
					elapsed,
					"; ".join(validation_errors),
				]
			)
		if is_v2 and (
			int(last_snapshot["paid_redeploy_count"]) != 0
			or float(last_snapshot["emergency_spent_bits"]) > EPSILON
		):
			return _invalid_result(
				engine,
				policy,
				"non-interactive policy triggered paid emergency redeploy"
			)

		var stage := int(last_snapshot["stage"])
		var mode := String(last_snapshot["mode"])
		if not has_initial_bits:
			initial_bits = float(last_snapshot["bits"])
			has_initial_bits = true
		if stage >= 10 and not is_finite(stage_10_arrival):
			stage_10_arrival = elapsed
		if stage >= 11 and not is_finite(stage_10_clear):
			stage_10_clear = elapsed
		if mode == "maintenance" and previous_mode != "maintenance":
			maintenance_entries += 1
			if previous_mode == "boss" and boss_failures_by_stage.has(str(stage)):
				var stage_key := str(stage)
				boss_failures_by_stage[stage_key] += 1
				var reason := (
					String(last_snapshot["last_failure_reason"])
					if is_v2
					else "boss_timeout"
				)
				var reasons := boss_failure_reasons[stage_key] as Dictionary
				reasons[reason] = int(reasons.get(reason, 0)) + 1
		previous_mode = mode

		if _is_complete(last_snapshot, is_v2, target_stage):
			if not is_finite(stage_10_arrival):
				return _invalid_result(engine, policy, "completion preceded stage 10 arrival")
			if target_stage >= FULL_RUN_TARGET_STAGE and not is_finite(stage_10_clear):
				return _invalid_result(engine, policy, "completion preceded stage 10 clear")
			if is_v2 and int(last_snapshot["failure_count"]) != maintenance_entries:
				return _invalid_result(
					engine,
					policy,
					"observed %d maintenance entries but snapshot reports %d total failures"
					% [maintenance_entries, int(last_snapshot["failure_count"])]
				)
			var completed_result := _completed_result(
				engine,
				policy,
				elapsed,
				stage_10_arrival,
				stage_10_clear,
				maintenance_entries,
				boss_failures_by_stage,
				boss_failure_reasons,
				last_snapshot,
				catalog,
				is_v2,
				initial_bits,
				command_spent_bits,
				target_stage,
				decision_count,
				first_decision_at,
				first_patch_at,
				maxf(longest_action_gap, elapsed - last_decision_at),
				true
			)
			if not is_v2 and target_stage >= FULL_RUN_TARGET_STAGE:
				var second_run := _simulate_second_run_stage_10(session, policy, catalog)
				if not bool(second_run["valid"]):
					return _invalid_result(engine, policy, String(second_run["error"]))
				completed_result["second_run_stage_10_arrival"] = float(second_run["elapsed"])
				completed_result["second_run_stage_10_reduction"] = (
					1.0 - float(second_run["elapsed"]) / stage_10_arrival
				)
			return completed_result

		if elapsed + EPSILON >= next_decision:
			var decision_signature_before := _decision_signature(last_snapshot)
			var patch_slots_before := (last_snapshot["patch_slots"] as Array).duplicate()
			var bits_before_decision := float(last_snapshot["bits"])
			var decision_error := _apply_decision(session, last_snapshot, policy, catalog)
			if not decision_error.is_empty():
				return _invalid_result(
					engine,
					policy,
					"decision failed at %.2fs: %s" % [elapsed, decision_error]
				)
			var post_decision_snapshot: Dictionary = session.snapshot()
			var post_decision_errors := _validate_snapshot(post_decision_snapshot, is_v2)
			if not post_decision_errors.is_empty():
				return _invalid_result(
					engine,
					policy,
					"invalid post-decision snapshot at %.2fs: %s" % [
						elapsed,
						"; ".join(post_decision_errors),
					]
				)
			var bits_after_decision := float(post_decision_snapshot["bits"])
			if bits_after_decision > bits_before_decision + EPSILON:
				return _invalid_result(
					engine,
					policy,
					"decision unexpectedly awarded %.2f bits" % (
						bits_after_decision - bits_before_decision
					)
				)
			command_spent_bits += maxf(0.0, bits_before_decision - bits_after_decision)
			if _decision_signature(post_decision_snapshot) != decision_signature_before:
				decision_count += 1
				if not is_finite(first_decision_at):
					first_decision_at = elapsed
				longest_action_gap = maxf(longest_action_gap, elapsed - last_decision_at)
				last_decision_at = elapsed
				if (
					not is_finite(first_patch_at)
					and (post_decision_snapshot["patch_slots"] as Array) != patch_slots_before
				):
					first_patch_at = elapsed
			next_decision += decision_interval

		session.tick(step_seconds)
		elapsed += step_seconds

	if last_snapshot.is_empty():
		return _invalid_result(engine, policy, "simulation produced no snapshot")
	var timeout := _completed_result(
		engine,
		policy,
		elapsed,
		stage_10_arrival,
		stage_10_clear,
		maintenance_entries,
		boss_failures_by_stage,
		boss_failure_reasons,
		last_snapshot,
		catalog,
		is_v2,
		initial_bits,
		command_spent_bits,
		target_stage,
		decision_count,
		first_decision_at,
		first_patch_at,
		maxf(longest_action_gap, elapsed - last_decision_at),
		false
	)
	timeout["timed_out"] = true
	timeout["error"] = "timed out after %.0fs" % MAX_SECONDS
	return timeout


static func _simulate_second_run_stage_10(
	session: Variant,
	policy: String,
	catalog: ContentCatalog
) -> Dictionary:
	if not session.prestige():
		return {"valid": false, "error": "current session rejected version update"}
	if not session.buy_legacy_cache():
		return {"valid": false, "error": "current session rejected legacy cache purchase"}
	var elapsed := 0.0
	var next_decision := 0.0
	while elapsed <= MAX_SECONDS + EPSILON:
		var snapshot: Dictionary = session.snapshot()
		if int(snapshot["stage"]) >= 10:
			return {"valid": true, "error": "", "elapsed": elapsed}
		if elapsed + EPSILON >= next_decision:
			var decision_error := _apply_decision(session, snapshot, policy, catalog)
			if not decision_error.is_empty():
				return {
					"valid": false,
					"error": "second-run decision failed at %.2fs: %s" % [
						elapsed, decision_error,
					],
				}
			next_decision += DECISION_INTERVAL
		session.tick(REPORT_STEP)
		elapsed += REPORT_STEP
	return {"valid": false, "error": "second run timed out before stage 10"}


static func _apply_decision(
	session: Variant,
	snapshot: Dictionary,
	policy: String,
	catalog: ContentCatalog
) -> String:
	var patch_error := _sync_product_patch(session, snapshot)
	if not patch_error.is_empty():
		return patch_error

	var decision_snapshot: Dictionary = session.snapshot()
	var operator_id := _choose_upgrade(decision_snapshot, policy, catalog)
	if operator_id == &"":
		return ""
	if not session.upgrade_operator(operator_id):
		return "affordable operator upgrade was rejected: %s" % operator_id
	return ""


static func _sync_product_patch(session: Variant, snapshot: Dictionary) -> String:
	if int(snapshot["unlocked_patch_slots"]) <= 0:
		return ""
	var slots := snapshot["patch_slots"] as Array
	if slots.is_empty():
		return "unlocked patch slot is missing from patch_slots"

	var desired_id := (
		&"rollback_lock"
		if ProgressionRulesScript.is_boss_stage(int(snapshot["stage"]))
		else &"frame_skip"
	)
	var desired_unlocked := false
	for raw_patch: Variant in snapshot["patches"] as Array:
		var patch := raw_patch as Dictionary
		if StringName(String(patch["id"])) == desired_id:
			desired_unlocked = bool(patch["unlocked"])
			break
	if not desired_unlocked or StringName(String(slots[0])) == desired_id:
		return ""

	var replacing := not String(slots[0]).is_empty()
	var preview: Dictionary = session.get_patch_preview(0, desired_id)
	var preview_error := _validate_patch_preview(preview)
	if not preview_error.is_empty():
		return "invalid patch preview for %s: %s" % [desired_id, preview_error]
	if not bool(preview["can_equip"]):
		return "unlocked patch preview rejected a valid replacement: %s" % desired_id
	if float(snapshot["bits"]) + EPSILON < float(preview["cost"]):
		return ""
	var equipped := bool(session.equip_patch(0, desired_id))
	if not equipped:
		return "%s patch equip was rejected despite sufficient bits: %s" % [
			"replacement" if replacing else "free",
			desired_id,
		]
	return ""


static func _validate_patch_preview(preview: Dictionary) -> String:
	for key: String in ["can_equip", "cost"]:
		if not preview.has(key):
			return "%s is required" % key
	if typeof(preview["can_equip"]) != TYPE_BOOL:
		return "can_equip must be boolean"
	if not _is_finite_number(preview["cost"]) or float(preview["cost"]) < 0.0:
		return "cost must be a non-negative finite number"
	return ""


static func _choose_upgrade(
	snapshot: Dictionary,
	policy: String,
	catalog: ContentCatalog
) -> StringName:
	var affordable := _affordable_rows(snapshot)
	if affordable.is_empty():
		return &""
	match policy:
		"debugger_focus":
			return &"debugger" if affordable.has(&"debugger") else &""
		"cheapest":
			return _choose_cheapest(affordable)
		"balanced":
			return _choose_lowest_level(affordable)
		"diagnosis_follow":
			return _choose_from_diagnosis(snapshot, affordable, catalog)
		"appeal_only":
			return _choose_from_appeals(snapshot, affordable, false)
		"diagnosis_plus_appeal":
			return _choose_from_appeals(snapshot, affordable, true)
	return &""


static func _choose_from_appeals(
	snapshot: Dictionary,
	affordable: Dictionary,
	require_diagnosis_alignment: bool
) -> StringName:
	var diagnosis_kind := String((snapshot["diagnosis"] as Dictionary)["kind"])
	for raw_appeal: Variant in snapshot["appeals"] as Array:
		var appeal := raw_appeal as Dictionary
		var operator_id := StringName(String(appeal["operator_id"]))
		if not affordable.has(operator_id):
			continue
		if require_diagnosis_alignment and not _role_aligns_with_diagnosis(
			operator_id, diagnosis_kind
		):
			continue
		return operator_id
	return &""


static func _role_aligns_with_diagnosis(operator_id: StringName, diagnosis_kind: String) -> bool:
	match operator_id:
		&"debugger":
			return diagnosis_kind in [
				"incoming_damage", "recovery_delay", "maintenance", "wipe_risk", "patch_tradeoff",
			]
		&"build_engineer":
			return diagnosis_kind in ["firepower", "boss_rollback"]
		&"sprite_artist":
			return diagnosis_kind in ["firepower", "stable"]
		&"qa_imp":
			return diagnosis_kind in ["incoming_damage", "recovery_delay", "maintenance", "wipe_risk"]
	return false


static func _affordable_rows(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var bits := float(snapshot["bits"])
	for raw_operator: Variant in snapshot["operators"] as Array:
		var operator := raw_operator as Dictionary
		var operator_id := StringName(String(operator["id"]))
		if bool(operator["unlocked"]) and float(operator["upgrade_cost"]) <= bits + EPSILON:
			result[operator_id] = operator
	return result


static func _choose_cheapest(affordable: Dictionary) -> StringName:
	var selected := &""
	var selected_cost := INF
	for operator_id: StringName in OPERATOR_IDS:
		if not affordable.has(operator_id):
			continue
		var row := affordable[operator_id] as Dictionary
		var cost := float(row["upgrade_cost"])
		if cost < selected_cost - EPSILON:
			selected = operator_id
			selected_cost = cost
	return selected


static func _choose_lowest_level(affordable: Dictionary) -> StringName:
	var selected := &""
	var selected_level := 2147483647
	for operator_id: StringName in OPERATOR_IDS:
		if not affordable.has(operator_id):
			continue
		var row := affordable[operator_id] as Dictionary
		var level := int(row["level"])
		if level < selected_level:
			selected = operator_id
			selected_level = level
	return selected


static func _choose_from_diagnosis(
	snapshot: Dictionary,
	affordable: Dictionary,
	catalog: ContentCatalog
) -> StringName:
	var diagnosis := snapshot["diagnosis"] as Dictionary
	var kind := String(diagnosis["kind"])
	if kind in ["incoming_damage", "recovery_delay", "maintenance"]:
		for operator_id: StringName in RECOVERY_PRIORITY:
			if affordable.has(operator_id):
				return operator_id
	if kind in ["firepower", "boss_rollback", "throughput", "rule_response"]:
		return _choose_offense(snapshot, affordable, catalog)
	return _choose_lowest_level(affordable)


static func _choose_offense(
	snapshot: Dictionary,
	affordable: Dictionary,
	catalog: ContentCatalog
) -> StringName:
	if (
		ProgressionRulesScript.is_boss_stage(int(snapshot["stage"]))
		and affordable.has(&"build_engineer")
	):
		return &"build_engineer"
	var selected := &""
	var selected_score := -INF
	for operator_id: StringName in OPERATOR_IDS:
		if not affordable.has(operator_id):
			continue
		var row := affordable[operator_id] as Dictionary
		var definition: OperatorDefinition = catalog.get_operator(operator_id)
		var level := int(row["level"])
		var current_dps := ProgressionRulesScript.operator_dps(definition, level)
		var next_dps := ProgressionRulesScript.operator_dps(definition, level + 1)
		var score := (next_dps - current_dps) / float(row["upgrade_cost"])
		if score > selected_score + EPSILON:
			selected = operator_id
			selected_score = score
	return selected


static func _decision_signature(snapshot: Dictionary) -> String:
	var levels: Array[String] = []
	for raw_operator: Variant in snapshot["operators"] as Array:
		var operator := raw_operator as Dictionary
		levels.append("%s:%d" % [String(operator["id"]), int(operator["level"])])
	return "%s|%s" % [",".join(levels), str(snapshot["patch_slots"])]


static func _is_complete(snapshot: Dictionary, is_v2: bool, target_stage: int) -> bool:
	if target_stage >= FULL_RUN_TARGET_STAGE:
		return bool(snapshot["prestige_available"])
	if is_v2:
		return bool(snapshot["prestige_available"])
	return int(snapshot["stage"]) > 10


static func _completed_result(
	engine: String,
	policy: String,
	elapsed: float,
	stage_10_arrival: float,
	stage_10_clear: float,
	maintenance_entries: int,
	boss_failures_by_stage: Dictionary,
	boss_failure_reasons: Dictionary,
	snapshot: Dictionary,
	catalog: ContentCatalog,
	is_v2: bool,
	initial_bits: float,
	command_spent_bits: float,
	target_stage: int,
	decision_count: int,
	first_decision_at: float,
	first_patch_at: float,
	longest_action_gap: float,
	completed: bool
) -> Dictionary:
	var economics := _reconstruct_economics(snapshot, catalog)
	var normal_failures := 0
	var boss_failures := maintenance_entries
	var total_failures := maintenance_entries
	var qa_rescues := 0
	var paid_redeploys := 0
	var emergency_spent_bits := 0.0
	var gross_bits := float(snapshot["bits"]) - initial_bits + command_spent_bits
	var net_bits := float(snapshot["bits"])
	if is_v2:
		normal_failures = int(snapshot["normal_failure_count"])
		boss_failures = int(snapshot["boss_failure_count"])
		total_failures = int(snapshot["failure_count"])
		qa_rescues = int(snapshot["qa_rescue_count"])
		paid_redeploys = int(snapshot["paid_redeploy_count"])
		emergency_spent_bits = float(snapshot["emergency_spent_bits"])
		gross_bits = float(snapshot["gross_bits"])
		net_bits = float(snapshot["net_bits"])
	var result := {
		"valid": true,
		"error": "",
		"timed_out": false,
		"engine": engine,
		"policy": policy,
		"stage": int(snapshot["stage"]),
		"stage_10_arrival": stage_10_arrival,
		"stage_10_clear": stage_10_clear,
		"stage_20_clear": (
			elapsed if completed and target_stage >= FULL_RUN_TARGET_STAGE else INF
		),
		"clear_time": elapsed,
		"maintenance_entries": maintenance_entries,
		"boss_failures_by_stage": boss_failures_by_stage.duplicate(true),
		"boss_failure_reasons": boss_failure_reasons.duplicate(true),
		"normal_failures": normal_failures,
		"boss_failures": boss_failures,
		"total_failures": total_failures,
		"qa_rescues": qa_rescues,
		"paid_redeploys": paid_redeploys,
		"emergency_spent_bits": emergency_spent_bits,
		"gross_bits": gross_bits,
		"net_bits": net_bits,
		"leftover_bits": float(snapshot["bits"]),
		"investment": float(economics["investment"]),
		"total_value": float(economics["total_value"]),
		"operator_levels": economics["operator_levels"],
		"operator_investment": economics["operator_investment"],
		"operator_investment_share": economics["operator_investment_share"],
		"operator_uptime": {},
		"operator_down_count": {},
		"operator_down_seconds": {},
		"appeals_shown": 0,
		"appeals_accepted": 0,
		"appeals_ignored": 0,
		"appeal_rule_count": 0,
		"decision_count": decision_count,
		"first_decision_at": first_decision_at,
		"first_patch_at": first_patch_at,
		"longest_action_gap": longest_action_gap,
		"target_stage": target_stage,
		"completed": completed,
		"second_run_stage_10_arrival": INF,
		"second_run_stage_10_reduction": INF,
	}
	if is_v2:
		if paid_redeploys != 0 or emergency_spent_bits > EPSILON:
			return _invalid_result(
				engine,
				policy,
				"non-interactive policy spent emergency redeploy resources "
				+ "(count=%d, bits=%.2f)" % [paid_redeploys, emergency_spent_bits]
			)
		var counters := _v2_operator_counters(snapshot)
		result["operator_uptime"] = counters["operator_uptime"]
		result["operator_down_count"] = counters["operator_down_count"]
		result["operator_down_seconds"] = counters["operator_down_seconds"]
		var appeal_stats := snapshot["appeal_stats"] as Dictionary
		result["appeals_shown"] = int(appeal_stats["shown"])
		result["appeals_accepted"] = int(appeal_stats["accepted"])
		result["appeals_ignored"] = int(appeal_stats["ignored"])
		result["appeal_rule_count"] = int(snapshot["appeal_rule_count"])
	return result


static func _reconstruct_economics(snapshot: Dictionary, catalog: ContentCatalog) -> Dictionary:
	var levels: Dictionary = {}
	var investments: Dictionary = {}
	var shares: Dictionary = {}
	var total_investment := 0.0
	for operator_id: StringName in OPERATOR_IDS:
		var row := _operator_row(snapshot, operator_id)
		var level := int(row["level"])
		var definition: OperatorDefinition = catalog.get_operator(operator_id)
		var invested := 0.0
		for purchased_from_level: int in range(1, level):
			invested += ProgressionRulesScript.operator_upgrade_cost(
				purchased_from_level,
				definition.base_cost,
				definition.cost_growth
			)
		levels[String(operator_id)] = level
		investments[String(operator_id)] = invested
		total_investment += invested
	for operator_id: StringName in OPERATOR_IDS:
		var key := String(operator_id)
		shares[key] = (
			0.0
			if total_investment <= EPSILON
			else float(investments[key]) / total_investment
		)
	return {
		"investment": total_investment,
		"total_value": total_investment + float(snapshot["bits"]),
		"operator_levels": levels,
		"operator_investment": investments,
		"operator_investment_share": shares,
	}


static func _v2_operator_counters(snapshot: Dictionary) -> Dictionary:
	var uptime: Dictionary = {}
	var downs: Dictionary = {}
	var down_seconds: Dictionary = {}
	for operator_id: StringName in OPERATOR_IDS:
		var row := _operator_row(snapshot, operator_id)
		var active_time := float(row["active_time"])
		var down_time := float(row["down_time"])
		var observed_time := active_time + down_time
		var key := String(operator_id)
		uptime[key] = 0.0 if observed_time <= EPSILON else active_time / observed_time
		downs[key] = int(row["down_count"])
		down_seconds[key] = down_time
	return {
		"operator_uptime": uptime,
		"operator_down_count": downs,
		"operator_down_seconds": down_seconds,
	}


static func _operator_row(snapshot: Dictionary, operator_id: StringName) -> Dictionary:
	for raw_operator: Variant in snapshot["operators"] as Array:
		var row := raw_operator as Dictionary
		if StringName(String(row["id"])) == operator_id:
			return row
	assert(false, "validated snapshot lost operator row: %s" % operator_id)
	return {}


static func _validate_snapshot(snapshot: Dictionary, is_v2: bool) -> PackedStringArray:
	var errors := PackedStringArray()
	_require_fields(
		snapshot,
		[
			"stage", "bits", "mode", "enemy", "operators", "patch_slots",
			"patches", "unlocked_patch_slots", "diagnosis", "prestige_available",
		],
		"snapshot",
		errors
	)
	if is_v2:
		_require_fields(
			snapshot,
			[
				"failure_count",
				"normal_failure_count",
				"boss_failure_count",
				"last_failure_reason",
				"qa_rescue_count",
				"paid_redeploy_count",
				"emergency_spent_bits",
				"gross_bits",
				"net_bits",
				"combat_metrics",
				"appeals",
				"appeal_stats",
			],
			"snapshot",
			errors
		)
	if not errors.is_empty():
		return errors
	if typeof(snapshot["stage"]) != TYPE_INT or int(snapshot["stage"]) < 1:
		errors.append("snapshot.stage must be a positive integer")
	if not _is_finite_number(snapshot["bits"]) or float(snapshot["bits"]) < 0.0:
		errors.append("snapshot.bits must be a non-negative finite number")
	if typeof(snapshot["mode"]) != TYPE_STRING or String(snapshot["mode"]).is_empty():
		errors.append("snapshot.mode must be a non-empty string")
	if typeof(snapshot["enemy"]) != TYPE_DICTIONARY:
		errors.append("snapshot.enemy must be a dictionary")
	if typeof(snapshot["operators"]) != TYPE_ARRAY:
		errors.append("snapshot.operators must be an array")
	if typeof(snapshot["patch_slots"]) != TYPE_ARRAY:
		errors.append("snapshot.patch_slots must be an array")
	if typeof(snapshot["patches"]) != TYPE_ARRAY:
		errors.append("snapshot.patches must be an array")
	if typeof(snapshot["unlocked_patch_slots"]) != TYPE_INT:
		errors.append("snapshot.unlocked_patch_slots must be an integer")
	if typeof(snapshot["diagnosis"]) != TYPE_DICTIONARY:
		errors.append("snapshot.diagnosis must be a dictionary")
	if typeof(snapshot["prestige_available"]) != TYPE_BOOL:
		errors.append("snapshot.prestige_available must be boolean")
	if is_v2:
		for key: String in [
			"failure_count",
			"normal_failure_count",
			"boss_failure_count",
			"qa_rescue_count",
			"paid_redeploy_count",
		]:
			if typeof(snapshot[key]) != TYPE_INT or int(snapshot[key]) < 0:
				errors.append("snapshot.%s must be a non-negative integer" % key)
		for key: String in ["emergency_spent_bits", "gross_bits", "net_bits"]:
			if not _is_finite_number(snapshot[key]) or float(snapshot[key]) < 0.0:
				errors.append("snapshot.%s must be a non-negative finite number" % key)
		if typeof(snapshot["last_failure_reason"]) != TYPE_STRING:
			errors.append("snapshot.last_failure_reason must be a string")
		if typeof(snapshot["combat_metrics"]) != TYPE_DICTIONARY:
			errors.append("snapshot.combat_metrics must be a dictionary")
	if not errors.is_empty():
		return errors

	_validate_operator_rows(snapshot["operators"] as Array, is_v2, errors)
	_validate_patch_rows(snapshot["patches"] as Array, errors)
	if is_v2:
		_validate_combat_metrics(snapshot, errors)
		if absf(float(snapshot["net_bits"]) - float(snapshot["bits"])) > EPSILON:
			errors.append("snapshot.net_bits must equal snapshot.bits")
		if float(snapshot["gross_bits"]) + EPSILON < float(snapshot["net_bits"]):
			errors.append("snapshot.gross_bits must not be less than snapshot.net_bits")
		if int(snapshot["failure_count"]) != (
			int(snapshot["normal_failure_count"]) + int(snapshot["boss_failure_count"])
		):
			errors.append(
				"snapshot.failure_count must equal normal_failure_count + boss_failure_count"
			)
	var diagnosis := snapshot["diagnosis"] as Dictionary
	_require_fields(diagnosis, ["kind"], "snapshot.diagnosis", errors)
	if diagnosis.has("kind") and (
		typeof(diagnosis["kind"]) != TYPE_STRING
		or String(diagnosis["kind"]).is_empty()
	):
		errors.append("snapshot.diagnosis.kind must be a non-empty string")
	return errors


static func _validate_combat_metrics(
	snapshot: Dictionary,
	errors: PackedStringArray
) -> void:
	var metrics := snapshot["combat_metrics"] as Dictionary
	var numeric_fields: Array[String] = [
		"total_elapsed",
		"damage_taken",
		"down_count",
		"down_time",
		"boss_healed",
		"enemies_defeated",
		"stages_cleared",
		"failure_count",
		"normal_failure_count",
		"boss_failure_count",
		"qa_rescue_count",
		"paid_redeploy_count",
		"emergency_spent_bits",
	]
	_require_fields(metrics, numeric_fields, "snapshot.combat_metrics", errors)
	if not _has_fields(metrics, numeric_fields):
		return
	for key: String in numeric_fields:
		if not _is_finite_number(metrics[key]) or float(metrics[key]) < 0.0:
			errors.append(
				"snapshot.combat_metrics.%s must be a non-negative finite number" % key
			)
	for key: String in [
		"failure_count",
		"normal_failure_count",
		"boss_failure_count",
		"qa_rescue_count",
		"paid_redeploy_count",
		"emergency_spent_bits",
	]:
		if not metrics.has(key) or not snapshot.has(key):
			continue
		if absf(float(metrics[key]) - float(snapshot[key])) > EPSILON:
			errors.append(
				"snapshot.combat_metrics.%s must match snapshot.%s" % [key, key]
			)


static func _validate_operator_rows(
	rows: Array,
	is_v2: bool,
	errors: PackedStringArray
) -> void:
	var seen: Dictionary = {}
	for index: int in rows.size():
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("snapshot.operators[%d] must be a dictionary" % index)
			continue
		var row := rows[index] as Dictionary
		var required: Array[String] = [
			"id", "level", "unlocked", "dps", "upgrade_cost",
		]
		if is_v2:
			required.append_array(["active_time", "down_time", "down_count"])
		_require_fields(row, required, "snapshot.operators[%d]" % index, errors)
		if not _has_fields(row, required):
			continue
		if typeof(row["id"]) != TYPE_STRING:
			errors.append("snapshot.operators[%d].id must be a string" % index)
			continue
		var operator_id := StringName(String(row["id"]))
		if not OPERATOR_IDS.has(operator_id):
			errors.append("snapshot.operators[%d].id is unknown: %s" % [index, operator_id])
			continue
		if seen.has(operator_id):
			errors.append("snapshot.operators has duplicate id: %s" % operator_id)
		seen[operator_id] = true
		if typeof(row["level"]) != TYPE_INT or int(row["level"]) < 0:
			errors.append("snapshot.operators[%d].level must be non-negative integer" % index)
		if typeof(row["unlocked"]) != TYPE_BOOL:
			errors.append("snapshot.operators[%d].unlocked must be boolean" % index)
		for key: String in ["dps", "upgrade_cost"]:
			if not _is_finite_number(row[key]) or float(row[key]) < 0.0:
				errors.append("snapshot.operators[%d].%s must be non-negative finite number" % [index, key])
		if is_v2:
			for key: String in ["active_time", "down_time"]:
				if not _is_finite_number(row[key]) or float(row[key]) < 0.0:
					errors.append("snapshot.operators[%d].%s must be non-negative finite number" % [index, key])
			if typeof(row["down_count"]) != TYPE_INT or int(row["down_count"]) < 0:
				errors.append("snapshot.operators[%d].down_count must be non-negative integer" % index)
	for operator_id: StringName in OPERATOR_IDS:
		if not seen.has(operator_id):
			errors.append("snapshot.operators is missing id: %s" % operator_id)


static func _validate_patch_rows(rows: Array, errors: PackedStringArray) -> void:
	for index: int in rows.size():
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("snapshot.patches[%d] must be a dictionary" % index)
			continue
		var row := rows[index] as Dictionary
		_require_fields(
			row,
			["id", "unlocked", "equipped"],
			"snapshot.patches[%d]" % index,
			errors
		)
		if row.has("id") and typeof(row["id"]) != TYPE_STRING:
			errors.append("snapshot.patches[%d].id must be a string" % index)
		if row.has("unlocked") and typeof(row["unlocked"]) != TYPE_BOOL:
			errors.append("snapshot.patches[%d].unlocked must be boolean" % index)
		if row.has("equipped") and typeof(row["equipped"]) != TYPE_BOOL:
			errors.append("snapshot.patches[%d].equipped must be boolean" % index)


static func _require_fields(
	data: Dictionary,
	fields: Array[String],
	context: String,
	errors: PackedStringArray
) -> void:
	for key: String in fields:
		if not data.has(key):
			errors.append("%s.%s is required" % [context, key])


static func _has_fields(data: Dictionary, fields: Array[String]) -> bool:
	for key: String in fields:
		if not data.has(key):
			return false
	return true


static func _is_finite_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
	)


static func _invalid_result(engine: String, policy: String, error: String) -> Dictionary:
	return {
		"valid": false,
		"error": error,
		"timed_out": false,
		"engine": engine,
		"policy": policy,
		"stage": 0,
	}


static func _all_results_completed(results: Array[Dictionary]) -> bool:
	for result: Dictionary in results:
		if not bool(result.get("valid", false)) or not bool(result.get("completed", false)):
			return false
	return true


static func _report_incomplete_risk(results: Array[Dictionary]) -> void:
	for result: Dictionary in results:
		if not bool(result.get("valid", false)) or bool(result.get("completed", false)):
			continue
		print("RISK: %s/%s did not complete the 20-stage run (stage %d)" % [
			String(result["engine"]),
			String(result["policy"]),
			int(result["stage"]),
		])


static func _print_table(results: Array[Dictionary]) -> void:
	print(
		"ENGINE  POLICY             ST10(s)    END(s)  NF  BF  TF  QA  PAID  "
		+ "SPENT   GROSS  NET    VALUE  LEVELS          AP(S/A/I)  V2 UPTIME             V2 DOWNS"
	)
	for result: Dictionary in results:
		if not bool(result["valid"]):
			print("%-7s %-18s INVALID: %s" % [
				String(result["engine"]),
				String(result["policy"]),
				String(result["error"]),
			])
			continue
		var uptime_text := "-"
		var downs_text := "-"
		var appeals_text := "-"
		if String(result["engine"]) == "V2":
			uptime_text = _uptime_text(result["operator_uptime"] as Dictionary)
			downs_text = _downs_text(result["operator_down_count"] as Dictionary)
			appeals_text = "%d/%d/%d" % [
				int(result["appeals_shown"]),
				int(result["appeals_accepted"]),
				int(result["appeals_ignored"]),
			]
		print("%-7s %-22s %7.2f  %8.2f  %2d  %2d  %2d  %2d  %4d  %6.0f  %5.0f  %5.0f  %5.0f  %-15s %-10s %-21s %s" % [
			String(result["engine"]),
			String(result["policy"]),
			float(result["stage_10_arrival"]),
			float(result["clear_time"]),
			int(result["normal_failures"]),
			int(result["boss_failures"]),
			int(result["total_failures"]),
			int(result["qa_rescues"]),
			int(result["paid_redeploys"]),
			float(result["emergency_spent_bits"]),
			float(result["gross_bits"]),
			float(result["net_bits"]),
			float(result["total_value"]),
			_levels_text(result["operator_levels"] as Dictionary),
			appeals_text,
			uptime_text,
			downs_text,
		])


static func _print_milestone_table(results: Array[Dictionary]) -> void:
	print("")
	print(
		"ENGINE  POLICY                 ST10 ARR  ST10 CLR  ST20 CLR  "
		+ "B10  B20  DEC  FIRST  PATCH  MAX GAP  RUN2 ST10  REDUCE"
	)
	for result: Dictionary in results:
		if not bool(result.get("valid", false)):
			continue
		var boss_failures := result["boss_failures_by_stage"] as Dictionary
		print("%-7s %-22s %8.2f  %8.2f  %8.2f  %3d  %3d  %3d  %5s  %5s  %7.2f  %9s  %6s" % [
			String(result["engine"]),
			String(result["policy"]),
			float(result["stage_10_arrival"]),
			float(result["stage_10_clear"]),
			float(result["stage_20_clear"]),
			int(boss_failures["10"]),
			int(boss_failures["20"]),
			int(result["decision_count"]),
			_time_text(float(result["first_decision_at"])),
			_time_text(float(result["first_patch_at"])),
			float(result["longest_action_gap"]),
			_time_text(float(result["second_run_stage_10_arrival"])),
			_percent_text(float(result["second_run_stage_10_reduction"])),
		])
		var reasons := result["boss_failure_reasons"] as Dictionary
		if not (reasons["10"] as Dictionary).is_empty() or not (reasons["20"] as Dictionary).is_empty():
			print("        boss failure reasons: ST10=%s ST20=%s" % [
				str(reasons["10"]),
				str(reasons["20"]),
			])


static func _time_text(value: float) -> String:
	return "-" if not is_finite(value) else "%.1f" % value


static func _percent_text(value: float) -> String:
	return "-" if not is_finite(value) else "%.1f%%" % (value * 100.0)


static func _levels_text(levels: Dictionary) -> String:
	return "D%d B%d S%d Q%d" % [
		int(levels["debugger"]),
		int(levels["build_engineer"]),
		int(levels["sprite_artist"]),
		int(levels["qa_imp"]),
	]


static func _uptime_text(uptime: Dictionary) -> String:
	return "D%.0f B%.0f S%.0f Q%.0f%%" % [
		float(uptime["debugger"]) * 100.0,
		float(uptime["build_engineer"]) * 100.0,
		float(uptime["sprite_artist"]) * 100.0,
		float(uptime["qa_imp"]) * 100.0,
	]


static func _downs_text(downs: Dictionary) -> String:
	return "D%d B%d S%d Q%d" % [
		int(downs["debugger"]),
		int(downs["build_engineer"]),
		int(downs["sprite_artist"]),
		int(downs["qa_imp"]),
	]


static func _check_anti_debugger(results: Array[Dictionary]) -> bool:
	var v2_results: Dictionary = {}
	for result: Dictionary in results:
		if String(result["engine"]) == "V2" and bool(result["valid"]):
			v2_results[String(result["policy"])] = result
	if v2_results.size() != V2_POLICIES.size():
		print("FAIL: anti-debugger matrix requires every valid V2 policy result")
		return false

	var focus := v2_results["debugger_focus"] as Dictionary
	var dominates_all := true
	var strict_any := false
	var threshold_pass := false
	for policy: String in V2_POLICIES:
		if policy == "debugger_focus":
			continue
		var candidate := v2_results[policy] as Dictionary
		var no_slower := float(focus["clear_time"]) <= float(candidate["clear_time"]) + EPSILON
		var no_more_failures := (
			int(focus["total_failures"]) <= int(candidate["total_failures"])
		)
		var no_less_value := float(focus["total_value"]) + EPSILON >= float(candidate["total_value"])
		dominates_all = dominates_all and no_slower and no_more_failures and no_less_value
		strict_any = strict_any or (
			float(focus["clear_time"]) < float(candidate["clear_time"]) - EPSILON
			or int(focus["total_failures"]) < int(candidate["total_failures"])
			or float(focus["total_value"]) > float(candidate["total_value"]) + EPSILON
		)
		if (
			float(candidate["clear_time"]) <= float(focus["clear_time"]) * 0.90 + EPSILON
			or int(candidate["total_failures"]) <= int(focus["total_failures"]) - 1
		):
			threshold_pass = true

	var passed := true
	if dominates_all and strict_any:
		print("FAIL: debugger_focus Pareto-dominates every non-focus V2 policy")
		passed = false
	if not threshold_pass:
		print(
			"FAIL: no non-debugger policy clears 10% faster or enters maintenance at least once less"
		)
		passed = false
	if passed:
		print("PASS: debugger_focus is not dominant and a non-focus policy meets the 10%/failure margin")
	return passed


static func _report_product_risks(results: Array[Dictionary]) -> void:
	var v2_results: Dictionary = {}
	for result: Dictionary in results:
		if String(result["engine"]) == "V2" and bool(result["valid"]):
			v2_results[String(result["policy"])] = result
	if v2_results.size() != V2_POLICIES.size():
		print("RISK CHECK SKIPPED: product risks require every valid V2 policy result")
		return

	var focus := v2_results["debugger_focus"] as Dictionary
	var balanced := v2_results["balanced"] as Dictionary
	var diagnosis := v2_results["diagnosis_follow"] as Dictionary
	var appeal_only := v2_results["appeal_only"] as Dictionary
	var diagnosis_appeal := v2_results["diagnosis_plus_appeal"] as Dictionary
	var focus_time := float(focus["clear_time"])
	var balanced_time := float(balanced["clear_time"])
	var diagnosis_time := float(diagnosis["clear_time"])
	var time_gap_from_focus := absf(diagnosis_time - focus_time)
	var focus_debugger_share := float(
		(focus["operator_investment_share"] as Dictionary)["debugger"]
	)
	var diagnosis_debugger_share := float(
		(diagnosis["operator_investment_share"] as Dictionary)["debugger"]
	)
	var diagnosis_similar_to_focus := (
		time_gap_from_focus <= maxf(focus_time * 0.05, REPORT_STEP) + EPSILON
		and int(diagnosis["total_failures"]) == int(focus["total_failures"])
		and absf(diagnosis_debugger_share - focus_debugger_share) <= 0.10 + EPSILON
	)
	var diagnosis_worse_than_balanced := (
		diagnosis_time > balanced_time * 1.10 + EPSILON
		or int(diagnosis["total_failures"]) >= int(balanced["total_failures"]) + 1
	)
	if diagnosis_similar_to_focus:
		print(
			"RISK: diagnosis_follow is meaningfully indistinct from debugger_focus "
			+ "(clear %.2fs vs %.2fs, failures %d vs %d, debugger share %.0f%% vs %.0f%%)"
			% [
				diagnosis_time,
				focus_time,
				int(diagnosis["total_failures"]),
				int(focus["total_failures"]),
				diagnosis_debugger_share * 100.0,
				focus_debugger_share * 100.0,
			]
		)
	if diagnosis_worse_than_balanced:
		print(
			(
				"RISK: diagnosis_follow materially trails balanced "
				+ "(clear %.2fs vs %.2fs, failures %d vs %d, levels %s vs %s). "
				+ "CAUSE: the comparison policy's offense heuristic scores base DPS growth, "
				+ "so it overvalues debugger levels despite the V2 role exponent."
			) % [
				diagnosis_time,
				balanced_time,
				int(diagnosis["total_failures"]),
				int(balanced["total_failures"]),
				_levels_text(diagnosis["operator_levels"] as Dictionary),
				_levels_text(balanced["operator_levels"] as Dictionary),
			]
		)
	if not diagnosis_similar_to_focus and not diagnosis_worse_than_balanced:
		print(
			"PASS: diagnosis_follow is distinct from debugger_focus and within the "
			+ "10%/failure margin of balanced"
		)
	_report_appeal_policy_targets(balanced, appeal_only, diagnosis_appeal)

	var all_zero_boss_failures := true
	for policy: String in V2_POLICIES:
		all_zero_boss_failures = (
			all_zero_boss_failures
			and int((v2_results[policy] as Dictionary)["boss_failures"]) == 0
		)
	if all_zero_boss_failures:
		print(
			"RISK: boss failures are zero for every V2 policy; boss pressure may be "
			+ "too low to validate the failure/retry loop in representative runs"
		)
	else:
		print("PASS: at least one V2 policy experiences a boss failure")


static func _report_appeal_policy_targets(
	balanced: Dictionary,
	appeal_only: Dictionary,
	diagnosis_appeal: Dictionary
) -> void:
	var time_delta := (
		float(diagnosis_appeal["clear_time"]) - float(balanced["clear_time"])
	) / float(balanced["clear_time"])
	var net_delta := (
		float(diagnosis_appeal["net_bits"]) - float(balanced["net_bits"])
	) / maxf(EPSILON, float(balanced["net_bits"]))
	var failures_ok := (
		int(diagnosis_appeal["total_failures"]) <= int(balanced["total_failures"])
	)
	var appeal_only_dominates := (
		float(appeal_only["clear_time"]) <= float(diagnosis_appeal["clear_time"]) + EPSILON
		and int(appeal_only["total_failures"]) <= int(diagnosis_appeal["total_failures"])
		and float(appeal_only["net_bits"]) + EPSILON >= float(diagnosis_appeal["net_bits"])
	)
	var targets_met := (
		time_delta >= -0.07 - EPSILON
		and time_delta <= 0.02 + EPSILON
		and failures_ok
		and net_delta >= 0.03 - EPSILON
		and net_delta <= 0.10 + EPSILON
		and not appeal_only_dominates
	)
	var prefix := "PASS" if targets_met else "RISK"
	print(
		(
			"%s: diagnosis_plus_appeal vs balanced: clear delta %.1f%%, failures %d vs %d, "
			+ "net bits delta %.1f%%; appeal_only dominates=%s"
		) % [
			prefix,
			time_delta * 100.0,
			int(diagnosis_appeal["total_failures"]),
			int(balanced["total_failures"]),
			net_delta * 100.0,
			str(appeal_only_dominates),
		]
	)
	if not targets_met:
		print(
			(
				"CAUSE CHECK: %d validated rules; %d shown/%d accepted. Diagnosis-role mapping or "
				+ "existing role balance may be limiting the target; no hidden bonus was applied."
			) % [
				int(diagnosis_appeal["appeal_rule_count"]),
				int(diagnosis_appeal["appeals_shown"]),
				int(diagnosis_appeal["appeals_accepted"]),
			]
		)
