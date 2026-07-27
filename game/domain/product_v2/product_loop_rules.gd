class_name ProductLoopRules
extends RefCounted

const ProductLoopState := preload(
	"res://game/domain/product_v2/product_loop_state.gd"
)
const ProductMetaRules := preload(
	"res://game/domain/product_v2/product_meta_rules.gd"
)
const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)

const MAX_STARS := 3


static func is_shift_unlocked(state: ProductLoopState, shift_index: int) -> bool:
	if shift_index == 1:
		return true
	if shift_index == 2:
		return state.shift_2_unlocked
	return false


static func new_reward_stars(
	claimed_stars: int,
	achieved_stars: int
) -> Array[int]:
	var result: Array[int] = []
	for star: int in range(clampi(claimed_stars, 0, MAX_STARS) + 1, clampi(
		achieved_stars, 0, MAX_STARS
	) + 1):
		result.append(star)
	return result


static func first_reward_bits(
	claimed_stars: int,
	achieved_stars: int,
	reward_bits: PackedInt32Array
) -> int:
	assert(
		reward_bits.size() == MAX_STARS,
		"Product V2 requires one first-clear reward for each star tier"
	)
	var total := 0
	for star: int in new_reward_stars(claimed_stars, achieved_stars):
		total += reward_bits[star - 1]
	return total


static func settle_terminal(
	state: ProductLoopState,
	night_snapshot: Dictionary,
	catalog: ProductV2Catalog
) -> Dictionary:
	assert(
		state.phase == ProductLoopState.Phase.NIGHT_ACTIVE,
		"Only an active night can settle a Product V2 result"
	)
	assert(
		bool(night_snapshot.get("terminal", false)),
		"Product V2 settlement requires a terminal night snapshot"
	)
	var shift_index := int(night_snapshot["shift_index"])
	assert(
		shift_index == state.active_shift_index,
		"Terminal shift must match the active Product V2 shift"
	)
	var record := state.get_shift_record(shift_index)
	assert(record != null, "Product V2 result requires a shift record")

	var achieved_stars := clampi(int(night_snapshot["stars"]), 0, MAX_STARS)
	var completed_waves := clampi(int(night_snapshot["completed_waves"]), 0, 10)
	var previous_best := record.best_stars
	var newly_rewarded := new_reward_stars(
		record.claimed_reward_stars, achieved_stars
	)
	var first_bits := first_reward_bits(
		record.claimed_reward_stars,
		achieved_stars,
		catalog.balance.first_star_reward_bits
	)
	var bits_before := state.bits
	var success := bool(night_snapshot["success"])
	var completion_reward := (
		completed_waves * catalog.balance.completed_wave_salary_bits
	)
	var boss_reward := catalog.balance.boss_defeat_salary_bits if success else 0
	var stability := int(night_snapshot["stability"])
	var max_stability := int(night_snapshot["max_stability"])
	var stability_steps := floori(
		float(stability * 100)
		/ float(maxi(1, max_stability) * catalog.balance.stability_step_percent)
	)
	var stability_reward := (
		stability_steps * catalog.balance.stability_step_salary_bits
	)
	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids, catalog.base_catalog
	)
	var bit_multiplier := float(modifiers.bits)
	var performance_raw := completion_reward + boss_reward + stability_reward
	var performance_reward := floori(float(performance_raw) * bit_multiplier)
	var total_reward := (
		catalog.balance.base_salary_bits + performance_reward + first_bits
	)

	record.attempts += 1
	record.highest_completed_waves = maxi(
		record.highest_completed_waves, completed_waves
	)
	record.best_stars = maxi(record.best_stars, achieved_stars)
	record.claimed_reward_stars = maxi(
		record.claimed_reward_stars, achieved_stars
	)
	record.boss_encountered = (
		record.boss_encountered
		or int(night_snapshot.get("current_wave", 0)) == 10
	)
	state.bits += total_reward

	var unlocked_shift_2_now := (
		not state.shift_2_unlocked
		and shift_index == 1
		and record.best_stars == MAX_STARS
	)
	if unlocked_shift_2_now:
		state.shift_2_unlocked = true
	var unlocked_update_now := (
		not state.version_update_available
		and shift_index == 2
		and record.best_stars == MAX_STARS
	)
	if unlocked_update_now:
		state.version_update_available = true
	var new_unlocks := ProductMetaRules.refresh_unlocks(state, catalog)

	state.result_serial += 1
	var result_key := "v%d:s%d:r%d" % [
		state.version, shift_index, state.result_serial,
	]
	var report_rows := factual_report_rows(night_snapshot)
	state.report_key = result_key
	state.report_rows.clear()
	for row: Dictionary in report_rows:
		state.report_rows.append(row.duplicate(true))
	state.report_read = false

	var result := {
		"key": result_key,
		"version": state.version,
		"shift_index": shift_index,
		"success": success,
		"terminal_reason": String(night_snapshot["terminal_reason"]),
		"completed_waves": completed_waves,
		"stars": achieved_stars,
		"stability": int(night_snapshot["stability"]),
		"max_stability": int(night_snapshot["max_stability"]),
		"previous_best_stars": previous_best,
		"best_stars": record.best_stars,
		"first_reward_bits": first_bits,
		"new_reward_stars": newly_rewarded,
		"base_salary": catalog.balance.base_salary_bits,
		"completion_reward": completion_reward,
		"boss_reward": boss_reward,
		"stability_reward": stability_reward,
		"performance_raw": performance_raw,
		"bit_multiplier": bit_multiplier,
		"performance_reward": performance_reward,
		"total_reward": total_reward,
		"bits_before": bits_before,
		"bits_after": state.bits,
		"shift_2_unlocked_now": unlocked_shift_2_now,
		"version_update_available_now": unlocked_update_now,
		"new_unlocks": new_unlocks,
		"report_key": result_key,
		"boss": (night_snapshot["boss"] as Dictionary).duplicate(true),
		"combat_metrics": (
			night_snapshot["combat_metrics"] as Dictionary
		).duplicate(true),
		"down_evidence": (
			night_snapshot["down_evidence"] as Dictionary
		).duplicate(true),
		"qa_outcome": (
			night_snapshot["qa_outcome"] as Dictionary
		).duplicate(true),
	}
	state.last_result = result.duplicate(true)
	state.phase = ProductLoopState.Phase.SHIFT_RESULT
	return result


static func factual_report_rows(
	night_snapshot: Dictionary
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var terminal_reason := String(night_snapshot.get("terminal_reason", ""))
	var completed_waves := int(night_snapshot.get("completed_waves", 0))
	var stability := int(night_snapshot.get("stability", 0))
	var max_stability := int(night_snapshot.get("max_stability", 0))
	var metrics := night_snapshot.get("combat_metrics", {}) as Dictionary
	var boss := night_snapshot.get("boss", {}) as Dictionary
	var down_evidence := night_snapshot.get("down_evidence", {}) as Dictionary
	var qa_outcome := night_snapshot.get("qa_outcome", {}) as Dictionary
	var timers := night_snapshot.get("timers", {}) as Dictionary
	match terminal_reason:
		"stability_depleted":
			rows.append(_report_row(
				&"stability_depleted",
				"",
				"",
				"침입 피해 %d으로 서버 안정도가 %d/%d까지 감소했습니다."
				% [
					int(metrics.get("leak_damage", 0)),
					stability,
					max_stability,
				],
				float(stability),
				float(max_stability),
				int(metrics.get("enemies_leaked", 0)),
				float(timers.get("combat_elapsed", 0.0))
			))
		"boss_timeout":
			rows.append(_report_row(
				&"boss_timeout",
				"",
				"",
				"제한 시간이 끝났을 때 보스 HP가 %d/%d 남았습니다."
				% [
					ceili(float(boss.get("hp", 0.0))),
					ceili(float(boss.get("max_hp", 0.0))),
				],
				float(boss.get("hp", 0.0)),
				float(boss.get("max_hp", 0.0)),
				completed_waves,
				float(boss.get("time_limit", 0.0))
			))
			_append_latest_down_row(rows, night_snapshot, down_evidence)
		"boss_all_down":
			rows.append(_report_row(
				&"boss_all_down",
				"",
				"",
				"보스전에서 가동 중인 요원이 모두 DOWN 상태가 되었습니다.",
				float(down_evidence.get("total_count", 0)),
				float(_unlocked_operator_count(night_snapshot)),
				int(down_evidence.get("total_count", 0)),
				float(timers.get("boss_elapsed", 0.0))
			))
			var qa_target_id := String(qa_outcome.get("target_id", ""))
			var qa_name := _operator_name(night_snapshot, qa_target_id)
			rows.append(_report_row(
				&"qa_outcome",
				qa_target_id,
				qa_name,
				"QA 자동 구조 결과: %s%s" % [
					String(qa_outcome.get("outcome", "unused")),
					(
						" · %s" % String(qa_outcome.get("reason", ""))
						if not String(qa_outcome.get("reason", "")).is_empty()
						else ""
					),
				],
				float(qa_outcome.get("rescue_count", 0)),
				1.0,
				int(qa_outcome.get("rescue_count", 0)),
				float(qa_outcome.get("time", 0.0))
			))
		"boss_defeated":
			rows.append(_report_row(
				&"boss_defeated",
				"",
				"",
				"보스를 처치해 10개 웨이브 방어를 완료했습니다.",
				float(completed_waves),
				10.0,
				int(metrics.get("enemies_defeated", 0)),
				float(timers.get("combat_elapsed", 0.0))
			))
	assert(rows.size() >= 1 and rows.size() <= 2, "A field report requires one or two factual rows")
	return rows


static func _append_latest_down_row(
	rows: Array[Dictionary],
	night_snapshot: Dictionary,
	down_evidence: Dictionary
) -> void:
	var records := down_evidence.get("records", []) as Array
	if records.is_empty() or rows.size() >= 2:
		return
	var latest := records.back() as Dictionary
	var operator_id := String(latest.get("operator_id", ""))
	var operator_name := _operator_name(night_snapshot, operator_id)
	rows.append(_report_row(
		&"operator_down",
		operator_id,
		operator_name,
		"%s 요원이 보스의 %s 공격으로 %.1f초에 DOWN되었습니다."
		% [
			operator_name,
			String(latest.get("attack", "")),
			float(latest.get("boss_time", 0.0)),
		],
		float(latest.get("boss_time", 0.0)),
		float((night_snapshot.get("boss", {}) as Dictionary).get("time_limit", 0.0)),
		int(down_evidence.get("total_count", 0)),
		float(latest.get("boss_time", 0.0))
	))


static func _report_row(
	kind: StringName,
	operator_id: String,
	operator_name: String,
	summary: String,
	primary_value: float,
	primary_max: float,
	count: int,
	seconds: float
) -> Dictionary:
	return {
		"kind": String(kind),
		"operator_id": operator_id,
		"operator_name": operator_name,
		"summary": summary,
		"primary_value": primary_value,
		"primary_max": primary_max,
		"count": count,
		"seconds": seconds,
	}


static func _operator_name(night_snapshot: Dictionary, operator_id: String) -> String:
	for raw_operator: Variant in night_snapshot.get("operators", []) as Array:
		var operator := raw_operator as Dictionary
		if String(operator.get("id", "")) == operator_id:
			return String(operator.get("name", ""))
	return operator_id


static func _unlocked_operator_count(night_snapshot: Dictionary) -> int:
	var result := 0
	for raw_operator: Variant in night_snapshot.get("operators", []) as Array:
		if bool((raw_operator as Dictionary).get("unlocked", false)):
			result += 1
	return result
