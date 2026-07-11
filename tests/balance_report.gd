extends SceneTree

const GameSessionScript := preload("res://game/app/game_session.gd")
const STEP_SECONDS := 0.25
const DECISION_INTERVAL := 60.0
const MAX_RUN_SECONDS := 1200.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := GameSessionScript.new()
	var first_run := _simulate_until(session, 20, true)
	print("Pixel Night Shift balance report")
	print("================================")
	_print_run("first run", first_run)
	var passed := true
	var first_elapsed := float(first_run.get("elapsed", INF))
	var first_boss_time := float(first_run.get("first_boss_time", INF))
	var first_boss_clear_time := float(first_run.get("first_boss_clear_time", INF))
	if not bool(first_run.get("prestige_available", false)):
		print("FAIL: baseline strategy did not reach the version update within 20 minutes")
		passed = false
	if first_elapsed < 900.0 or first_elapsed > 1200.0:
		print("FAIL: first run must stay within the 15..20 minute target window")
		passed = false
	if first_boss_time < 180.0 or first_boss_time > 360.0:
		print("FAIL: the first boss must appear within the 3..6 minute teaching window")
		passed = false
	if first_boss_clear_time > 480.0:
		print("FAIL: the first boss must clear within 8 minutes under the baseline strategy")
		passed = false
	if not passed:
		quit(1)
		return

	session.prestige()
	session.buy_legacy_cache()
	var second_run := _simulate_until(session, 10, false)
	_print_run("second run to first boss", second_run)
	var second_boss_time := float(second_run.get("first_boss_time", INF))
	var reduction := 0.0
	if is_finite(first_boss_time) and first_boss_time > 0.0:
		reduction = 1.0 - second_boss_time / first_boss_time
	print("first-boss time reduction: %.1f%%" % (reduction * 100.0))
	if reduction < 0.25:
		print("FAIL: the second run must reach the first boss at least 25% faster")
		quit(1)
		return
	quit(0)


func _simulate_until(session: Variant, target_stage: int, require_prestige: bool) -> Dictionary:
	var elapsed := 0.0
	var next_decision := 0.0
	var first_boss_time := INF
	var first_boss_clear_time := INF
	while elapsed < MAX_RUN_SECONDS:
		var snapshot: Dictionary = session.snapshot()
		var stage := int(snapshot.get("stage", 0))
		if stage >= 10 and not is_finite(first_boss_time):
			first_boss_time = elapsed
		if stage >= 11 and not is_finite(first_boss_clear_time):
			first_boss_clear_time = elapsed
		if require_prestige and bool(snapshot.get("prestige_available", false)):
			return _result(elapsed, first_boss_time, first_boss_clear_time, snapshot)
		if not require_prestige and stage >= target_stage:
			return _result(elapsed, first_boss_time, first_boss_clear_time, snapshot)
		if elapsed + 0.0001 >= next_decision:
			_apply_baseline_decision(session, snapshot)
			next_decision += DECISION_INTERVAL
		session.tick(STEP_SECONDS)
		elapsed += STEP_SECONDS
	return _result(elapsed, first_boss_time, first_boss_clear_time, session.snapshot())


func _apply_baseline_decision(session: Variant, snapshot: Dictionary) -> void:
	_sync_patches(session, snapshot)
	var bits := float(snapshot.get("bits", 0.0))
	var best_id := ""
	var best_cost := INF
	for item_value: Variant in snapshot.get("operators", []) as Array:
		var item := item_value as Dictionary
		if not bool(item.get("unlocked", false)):
			continue
		var cost := float(item.get("upgrade_cost", INF))
		if cost <= bits and cost < best_cost:
			best_cost = cost
			best_id = String(item.get("id", ""))
	if not best_id.is_empty():
		session.upgrade_operator(best_id)


func _sync_patches(session: Variant, snapshot: Dictionary) -> void:
	var stage := int(snapshot.get("stage", 0))
	var desired: Array[StringName]
	if stage == 10 or stage == 20:
		desired = [&"rollback_lock", &"frame_skip", &"unsafe_build"]
	elif stage >= 11:
		desired = [&"reward_bypass", &"frame_skip", &"unsafe_build"]
	else:
		desired = [&"frame_skip"]

	var available: Dictionary = {}
	for item_value: Variant in snapshot.get("patches", []) as Array:
		var item := item_value as Dictionary
		available[String(item.get("id", ""))] = bool(item.get("unlocked", false))
	var slots := snapshot.get("patch_slots", []) as Array
	var slot_count := mini(int(snapshot.get("unlocked_patch_slots", 0)), desired.size())
	for slot_index: int in range(slot_count):
		var desired_id := String(desired[slot_index])
		if not bool(available.get(desired_id, false)):
			continue
		if String(slots[slot_index]) == desired_id:
			continue
		session.equip_patch(slot_index, desired[slot_index])


func _result(
	elapsed: float,
	first_boss_time: float,
	first_boss_clear_time: float,
	snapshot: Dictionary
) -> Dictionary:
	return {
		"elapsed": elapsed,
		"first_boss_time": first_boss_time,
		"first_boss_clear_time": first_boss_clear_time,
		"stage": int(snapshot.get("stage", 0)),
		"prestige_available": bool(snapshot.get("prestige_available", false)),
	}


func _print_run(label: String, result: Dictionary) -> void:
	print(
		"%s: stage %d in %.1fs, first boss %.1fs, first boss clear %.1fs, prestige=%s"
		% [
			label,
			int(result.get("stage", 0)),
			float(result.get("elapsed", 0.0)),
			float(result.get("first_boss_time", INF)),
			float(result.get("first_boss_clear_time", INF)),
			str(bool(result.get("prestige_available", false))),
		]
	)
