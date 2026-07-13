class_name CombatV2DiagnosisRules
extends RefCounted

const EPSILON := 0.000001


static func evaluate(state: CombatV2State, catalog: CombatV2Catalog) -> Dictionary:
	assert(state != null, "Combat V2 diagnosis requires a state")
	assert(catalog != null and catalog.diagnosis != null, "Combat V2 diagnosis requires thresholds")
	if state.progression.can_prestige:
		return _diagnosis(
			"complete",
			"수직 슬라이스 완료",
			"스테이지 10의 감시견 프로세스를 격리했습니다.",
			"info",
			_evidence_data(state, catalog, {})
		)

	var is_boss := (
		state.progression.stage == catalog.balance.max_stage
		and not state.progression.is_maintenance
	)
	var down_count := _current_down_count(state)
	var max_recovery_remaining := _max_recovery_remaining(state)
	var forecast := CombatV2Forecast.estimate(state, catalog)
	var evidence_data := _evidence_data(state, catalog, forecast)
	if state.progression.is_maintenance:
		return _diagnosis(
			"maintenance",
			"자동 재도전 준비",
			"%s 실패 후 전원 복구 중이며 %.1f초 뒤 같은 스테이지를 다시 시도합니다."
			% [_failure_label(state.last_failure_reason), state.maintenance_remaining],
			"warning",
			evidence_data
		)
	if CombatV2Simulator.active_operator_count(state) == 0:
		return _diagnosis(
			"wipe_risk",
			"전원 프로세스 다운",
			"현재 조우는 실패 조건에 도달했습니다. 자동 재도전 전환을 확인 중입니다.",
			"critical",
			evidence_data
		)

	var patch_tradeoff := _patch_tradeoff(state, catalog, forecast)
	if not patch_tradeoff.is_empty():
		patch_tradeoff["evidence_data"] = evidence_data
		return patch_tradeoff

	if (
		(down_count > 0 and max_recovery_remaining <= EPSILON)
		or down_count >= 2
		or max_recovery_remaining > catalog.diagnosis.recovery_delay_seconds
		or float(forecast.uptime) < catalog.diagnosis.minimum_uptime_fraction
	):
		return _diagnosis(
			"recovery_delay",
			"프로세스 손실 누적",
			"현재 다운 %d명, 예약 복구 %.1f초, 예상 가동률 %.0f%%입니다."
			% [down_count, max_recovery_remaining, float(forecast.uptime) * 100.0],
			"critical" if down_count >= 2 else "warning",
			evidence_data
		)

	var team_max_hp := CombatV2Simulator.team_max_hp(state, catalog)
	assert(team_max_hp > EPSILON, "Combat V2 diagnosis requires an unlocked team")
	var damage_ratio := float(forecast.damage_taken) / team_max_hp
	if (
		int(forecast.downs) >= 1
		or damage_ratio > catalog.diagnosis.team_hp_loss_fraction
	):
		return _diagnosis(
			"incoming_damage",
			"피해 과다",
			"현재 조우에서 예상 다운 %d회, 팀 최대 HP 대비 피해 %.0f%%입니다."
			% [int(forecast.downs), damage_ratio * 100.0],
			"critical" if int(forecast.downs) >= 2 else "warning",
			evidence_data
		)

	var max_enemy_hp := CombatV2Forecast.enemy_max_hp(state, catalog)
	assert(max_enemy_hp > EPSILON, "Combat V2 diagnosis requires positive enemy HP")
	if is_boss:
		var recovered_ratio := state.stage_boss_healed / max_enemy_hp
		if recovered_ratio >= catalog.diagnosis.boss_heal_regression_fraction:
			return _diagnosis(
				"boss_rollback",
				"보스 롤백 피해",
				"Watchdog가 최대 HP의 %.0f%%를 복구했습니다." % (recovered_ratio * 100.0),
				"critical" if recovered_ratio >= 0.20 else "warning",
				evidence_data
			)
		var remaining_limit := maxf(
			0.0,
			catalog.base_catalog.balance.boss_time_limit - state.progression.boss_elapsed
		)
		if not bool(forecast.resolved) or float(forecast.seconds) > remaining_limit + EPSILON:
			return _diagnosis(
				"firepower",
				"화력 부족",
				"남은 제한 시간 %.1f초 안에 Watchdog를 격리할 수 없습니다."
				% remaining_limit,
				"critical",
				evidence_data
			)
	else:
		var health_ratio := clampf(state.progression.enemy_health / max_enemy_hp, 0.0, 1.0)
		var target_ttk := catalog.base_catalog.balance.target_normal_ttk * health_ratio
		if not bool(forecast.resolved) or float(forecast.seconds) > target_ttk + EPSILON:
			var estimated_seconds := float(forecast.seconds)
			return _diagnosis(
				"firepower",
				"화력 부족",
				"남은 적 HP 기준 예상 처리 %.1f초 / 비례 목표 %.1f초입니다."
				% [estimated_seconds, target_ttk],
				"critical" if estimated_seconds > target_ttk * 1.5 else "warning",
				evidence_data
			)

	return _diagnosis(
		"stable",
		"운영 안정",
		"현재 화력, 피해, 프로세스 손실과 패치 부작용이 목표 범위 안에 있습니다.",
		"info",
		evidence_data
	)


static func _patch_tradeoff(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	current: Dictionary
) -> Dictionary:
	var equipped_ids: Array[StringName] = state.progression.equipped_patch_ids
	for index: int in range(equipped_ids.size()):
		var patch_id := equipped_ids[index]
		if patch_id == &"":
			continue
		var without_patch: Array[StringName] = equipped_ids.duplicate()
		without_patch[index] = &""
		var counterfactual := CombatV2Forecast.estimate(state, catalog, without_patch)
		var patch := catalog.base_catalog.get_patch(patch_id)
		assert(patch != null, "Unknown equipped patch in Combat V2 diagnosis: %s" % patch_id)

		if _ttk_improved(current, counterfactual, catalog.diagnosis.ttk_regression_fraction):
			return _diagnosis(
				"patch_tradeoff",
				"패치 부작용",
				"%s 패치를 빼면 예상 처리 시간이 %.0f%% 이상 줄어듭니다."
				% [patch.display_name, catalog.diagnosis.ttk_regression_fraction * 100.0],
				"warning"
			)
		var avoided_downs := int(current.downs) - int(counterfactual.downs)
		if avoided_downs >= 1:
			return _diagnosis(
				"patch_tradeoff",
				"패치 부작용",
				"%s 패치를 빼면 예상 다운이 %d회 줄어듭니다."
				% [patch.display_name, avoided_downs],
				"warning"
			)
		var heal_improvement := float(current.boss_healed) - float(counterfactual.boss_healed)
		var max_enemy_hp := CombatV2Forecast.enemy_max_hp(state, catalog)
		if heal_improvement >= max_enemy_hp * catalog.diagnosis.boss_heal_regression_fraction:
			return _diagnosis(
				"patch_tradeoff",
				"패치 부작용",
				"%s 패치를 빼면 보스 복구량이 최대 HP의 %.0f%% 이상 줄어듭니다."
				% [
					patch.display_name,
					catalog.diagnosis.boss_heal_regression_fraction * 100.0,
				],
				"warning"
			)
		var current_bits_per_second := _bits_per_second(current)
		var counterfactual_bits_per_second := _bits_per_second(counterfactual)
		if _relative_improvement(
			current_bits_per_second,
			counterfactual_bits_per_second,
			catalog.diagnosis.patch_bits_regression_fraction
		):
			return _diagnosis(
				"patch_tradeoff",
				"패치 부작용",
				"%s 패치를 빼면 초당 비트가 %.0f%% 이상 늘어납니다."
				% [
					patch.display_name,
					catalog.diagnosis.patch_bits_regression_fraction * 100.0,
				],
				"warning"
			)
	return {}


static func _ttk_improved(current: Dictionary, counterfactual: Dictionary, threshold: float) -> bool:
	if not bool(counterfactual.resolved):
		return false
	var current_seconds := float(current.seconds)
	if current_seconds <= EPSILON:
		return false
	return (
		current_seconds - float(counterfactual.seconds)
	) / current_seconds >= threshold


static func _bits_per_second(forecast: Dictionary) -> float:
	var seconds := float(forecast.seconds)
	if seconds <= EPSILON:
		return 0.0
	return float(forecast.bits_earned) / seconds


static func _relative_improvement(baseline: float, candidate: float, threshold: float) -> bool:
	if baseline <= EPSILON:
		return candidate > EPSILON
	return (candidate - baseline) / baseline >= threshold


static func _current_down_count(state: CombatV2State) -> int:
	var count := 0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if (
			state.progression.is_operator_unlocked(runtime.operator_id)
			and int(state.progression.operator_levels.get(runtime.operator_id, 0)) > 0
			and not runtime.is_active()
		):
			count += 1
	return count


static func _max_recovery_remaining(state: CombatV2State) -> float:
	var remaining := 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		remaining = maxf(remaining, runtime.recovery_remaining)
	return remaining


static func _evidence_data(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	forecast: Dictionary
) -> Dictionary:
	var current_downs := _current_down_count(state)
	var forecast_down_events := int(forecast.get("downs", 0))
	var forecast_ending_downs := int(forecast.get("ending_down_count", current_downs))
	var active_count := CombatV2Simulator.active_operator_count(state)
	var unlocked_count := CombatV2Simulator.unlocked_operator_count(state)
	var wipe := _wipe_risk(
		state,
		forecast,
		current_downs,
		forecast_down_events,
		forecast_ending_downs,
		active_count,
		unlocked_count
	)
	var emergency := CombatV2Simulator.emergency_redeploy_overview(state, catalog)
	var qa_runtime := state.get_operator(&"qa_imp")
	var qa_alive := qa_runtime != null and qa_runtime.is_active()
	return {
		"recovery_cost": float(emergency.cost),
		"current_downs": current_downs,
		"forecast_down_events": forecast_down_events,
		"forecast_downs": forecast_ending_downs,
		"estimated_wipe_risk": String(wipe.level),
		"wipe_risk_basis": String(wipe.basis),
		"failure_count": state.total_failure_count(),
		"normal_failure_count": state.normal_failure_count,
		"boss_failure_count": state.progression.boss_failure_count,
		"last_failure_reason": String(state.last_failure_reason),
		"maintenance": state.progression.is_maintenance,
		"maintenance_remaining": state.maintenance_remaining,
		"maintenance_reason": String(state.last_failure_reason),
		"emergency_available": bool(emergency.available),
		"emergency_affordable": bool(emergency.affordable),
		"emergency_remaining": int(emergency.remaining),
		"emergency_eligible_targets": emergency.eligible_targets,
		"qa_rescue_available": qa_alive and not state.qa_rescue_consumed,
		"qa_rescue_pending": state.qa_recovery_target_id != &"",
	}


static func _wipe_risk(
	state: CombatV2State,
	forecast: Dictionary,
	current_downs: int,
	forecast_down_events: int,
	forecast_ending_downs: int,
	active_count: int,
	unlocked_count: int
) -> Dictionary:
	if state.progression.is_maintenance:
		return {"level": "realized", "basis": "attempt_failed_maintenance"}
	if int(forecast.get("failures", 0)) > 0:
		return {"level": "high", "basis": "forecast_attempt_failure"}
	if active_count <= 0:
		return {"level": "high", "basis": "no_active_operators"}
	if forecast_ending_downs >= unlocked_count:
		return {"level": "high", "basis": "forecast_ends_with_full_team_down"}
	if forecast_ending_downs >= maxi(1, unlocked_count - 1):
		return {"level": "medium", "basis": "one_active_operator_margin"}
	if current_downs > 0 or forecast_ending_downs > 0 or forecast_down_events > 0:
		return {"level": "medium", "basis": "observed_or_forecast_downs"}
	return {"level": "low", "basis": "no_downs_in_forecast_window"}


static func _failure_label(reason: StringName) -> String:
	match reason:
		&"normal_all_down", &"boss_all_down":
			return "전원 다운"
		&"boss_timeout":
			return "보스 제한 시간 초과"
		&"":
			return "조우"
		_:
			return String(reason)


static func _diagnosis(
	kind: String,
	title: String,
	evidence: String,
	severity: String,
	evidence_data: Dictionary = {}
) -> Dictionary:
	return {
		"kind": kind,
		"title": title,
		"evidence": evidence,
		"evidence_data": evidence_data,
		"severity": severity,
	}
