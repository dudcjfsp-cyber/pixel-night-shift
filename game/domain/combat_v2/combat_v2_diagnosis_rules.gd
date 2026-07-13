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
			"info"
		)

	var is_boss := (
		state.progression.stage == catalog.balance.max_stage
		and not state.progression.is_maintenance
	)
	var down_count := _current_down_count(state)
	var max_recovery_remaining := _max_recovery_remaining(state)
	if (
		not is_boss
		and CombatV2Simulator.unlocked_operator_count(state) > 0
		and CombatV2Simulator.active_operator_count(state) == 0
	):
		return _diagnosis(
			"recovery_wait",
			"자동 복구 대기",
			"모든 요원이 다운되었습니다. 최장 자동 복구까지 %.1f초 남았습니다."
			% max_recovery_remaining,
			"warning"
		)

	var forecast := CombatV2Forecast.estimate(state, catalog)
	var patch_tradeoff := _patch_tradeoff(state, catalog, forecast)
	if not patch_tradeoff.is_empty():
		return patch_tradeoff

	if (
		down_count >= 2
		or max_recovery_remaining > catalog.diagnosis.recovery_delay_seconds
		or float(forecast.uptime) < catalog.diagnosis.minimum_uptime_fraction
	):
		return _diagnosis(
			"recovery_delay",
			"복구 지연",
			"현재 다운 %d명, 최장 복구 %.1f초, 예상 가동률 %.0f%%입니다."
			% [down_count, max_recovery_remaining, float(forecast.uptime) * 100.0],
			"critical" if down_count >= 2 else "warning"
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
			"critical" if int(forecast.downs) >= 2 else "warning"
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
				"critical" if recovered_ratio >= 0.20 else "warning"
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
				"critical"
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
				"critical" if estimated_seconds > target_ttk * 1.5 else "warning"
			)

	return _diagnosis(
		"stable",
		"운영 안정",
		"현재 화력, 피해, 복구와 패치 부작용이 목표 범위 안에 있습니다.",
		"info"
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
		if runtime.recovery_remaining > EPSILON:
			count += 1
	return count


static func _max_recovery_remaining(state: CombatV2State) -> float:
	var remaining := 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		remaining = maxf(remaining, runtime.recovery_remaining)
	return remaining


static func _diagnosis(kind: String, title: String, evidence: String, severity: String) -> Dictionary:
	return {
		"kind": kind,
		"title": title,
		"evidence": evidence,
		"severity": severity,
	}
