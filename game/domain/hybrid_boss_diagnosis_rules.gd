class_name HybridBossDiagnosisRules
extends RefCounted

const EPSILON := 0.000001
const ROLLBACK_PRESSURE_RATIO := 0.08


static func evaluate(state: GameState, catalog: ContentCatalog) -> Dictionary:
	assert(state != null, "Hybrid boss diagnosis requires a state")
	assert(
		catalog != null and catalog.balance != null,
		"Hybrid boss diagnosis requires content"
	)
	assert(
		ProgressionRules.is_boss_stage(state.stage),
		"Hybrid boss diagnosis only evaluates boss stages"
	)

	if state.can_prestige:
		return _diagnosis(
			"version_ready",
			"버전 업데이트 준비 완료",
			"스테이지 20의 감시견 프로세스가 격리되었습니다.",
			"현재 보스 HP 0 · 이번 회차 보스 실패 %d회" % state.boss_failure_count,
			[]
		)
	if state.is_maintenance:
		return _maintenance_diagnosis(state, catalog)

	var forecast := HybridBossForecast.estimate(state, catalog)
	var evidence := _forecast_evidence(state, catalog, forecast)
	var failure_reason := StringName(forecast.get("failure_reason", ""))
	if failure_reason == &"boss_all_down":
		return _diagnosis(
			"wipe_risk",
			"전원 PROCESS DOWN 예상",
			"현재 배치의 복제 시뮬레이션에서 보스 처치 전에 모든 요원이 DOWN됩니다.",
			evidence,
			_recommend_from_down_events(state, catalog, forecast)
		)
	if failure_reason == &"boss_timeout":
		return _diagnosis(
			"timeout_risk",
			"보스 제한 시간 초과 예상",
			"현재 배치의 복제 시뮬레이션에서 남은 제한 시간 안에 보스를 처치하지 못합니다.",
			evidence,
			_available_ids(state, catalog, [&"build_engineer", &"sprite_artist"])
		)

	var forecast_downs := int(forecast.get("downs", 0))
	if forecast_downs > 0:
		return _diagnosis(
			"process_down_risk",
			"요원 PROCESS DOWN 예상",
			"보스는 처치 가능하지만 현재 시도 종료 전 추가 DOWN이 예상됩니다.",
			evidence,
			_recommend_from_down_events(state, catalog, forecast)
		)

	var recent_qa_cancel := _latest_event(
		state,
		[&"qa_rescue_cancelled"],
		state.boss_attempt_serial
	)
	if not recent_qa_cancel.is_empty():
		var qa_cancel_ids: Array[StringName] = [&"qa_imp"]
		var cancelled_target := StringName(recent_qa_cancel.get("operator_id", ""))
		if cancelled_target != &"":
			qa_cancel_ids.append(cancelled_target)
		return _diagnosis(
			"qa_rescue_cancelled",
			"QA 자동 구조 취소",
			"예약된 구조가 완료되기 전에 QA 임프가 가동 불능이 됐거나 시도가 종료됐습니다.",
			evidence,
			_available_ids(state, catalog, qa_cancel_ids)
		)

	if state.qa_rescue_target_id != &"":
		return _diagnosis(
			"qa_rescue_pending",
			"QA 자동 구조 예약",
			"DOWN 요원의 자동 구조가 예약되어 있으며 전투는 자동으로 계속됩니다.",
			evidence,
			_available_ids(
				state,
				catalog,
				[state.qa_rescue_target_id, &"qa_imp"]
			)
		)

	var healed_ratio := float(forecast.get("attempt_boss_healed_ratio", 0.0))
	if healed_ratio >= ROLLBACK_PRESSURE_RATIO:
		return _diagnosis(
			"rollback_pressure",
			"ROLLBACK 회복 압력",
			"현재 시도와 남은 전투 예측에서 보스 회복량이 의미 있는 비중을 차지합니다.",
			evidence,
			_available_ids(state, catalog, [&"build_engineer", &"sprite_artist"])
		)

	var recent_qa_success := _latest_event(
		state,
		[&"qa_rescue_succeeded"],
		state.boss_attempt_serial
	)
	if not recent_qa_success.is_empty():
		return _diagnosis(
			"qa_rescue_used",
			"QA 자동 구조 사용됨",
			"이번 시도의 자동 구조 1회가 이미 사용됐고 추가 구조는 예약되지 않습니다.",
			evidence,
			_available_ids(
				state,
				catalog,
				[
					StringName(recent_qa_success.get("operator_id", "")),
					&"qa_imp",
				]
			)
		)

	return _diagnosis(
		"stable",
		"보스 대응 안정",
		"현재 배치의 복제 시뮬레이션에서는 제한 시간 안에 보스를 처치합니다.",
		evidence,
		[]
	)


static func _maintenance_diagnosis(
	state: GameState,
	catalog: ContentCatalog
) -> Dictionary:
	var reason := state.last_boss_failure_reason
	if reason == &"":
		var failure_event := _latest_event(state, [&"boss_attempt_failed"], -1)
		reason = StringName(failure_event.get("reason", ""))
	var evidence := _maintenance_evidence(state, catalog, reason)
	if reason == &"boss_all_down":
		return _diagnosis(
			"recent_failure_all_down",
			"직전 보스 실패: 전원 DOWN",
			"직전 시도는 모든 가동 요원의 HP가 0이 되어 종료됐습니다.",
			evidence,
			_available_ids(state, catalog, [&"debugger", &"qa_imp"])
		)
	if reason == &"boss_timeout":
		return _diagnosis(
			"recent_failure_timeout",
			"직전 보스 실패: 제한 시간 초과",
			"직전 시도는 25초 제한 안에 보스 HP를 0으로 만들지 못했습니다.",
			evidence,
			_available_ids(state, catalog, [&"build_engineer", &"sprite_artist"])
		)
	return _diagnosis(
		"recent_failure",
		"보스 자동 재시도 준비",
		"직전 실패 기록을 유지한 채 유지보수 파밍 후 같은 보스에 자동 재시도합니다.",
		evidence,
		[]
	)


static func _forecast_evidence(
	state: GameState,
	catalog: ContentCatalog,
	forecast: Dictionary
) -> String:
	var qa_status := "사용 불가"
	if state.qa_rescue_target_id != &"":
		qa_status = "구조 예약 %.1f초" % state.qa_rescue_remaining
	elif bool(forecast.get("qa_rescue_available", false)):
		qa_status = "사용 가능"
	elif state.qa_rescue_consumed:
		qa_status = "이미 사용됨"
	var recent_reason := _recent_failure_reason(state)
	var recent_failures := _recent_stage_failure_count(state)
	return (
		"예상 종료 %.1f초 / 남은 제한 %.1f초 · 팀 HP %.0f/%.0f → %.0f · "
		+ "예상 DOWN %d명 · 전원 DOWN 위험 %s · ROLLBACK 누적 %.0f%% · "
		+ "최근 동일 스테이지 실패 %d회(%s) · QA 구조 %s · 다음 강화 %s"
	) % [
		float(forecast.get("seconds", 0.0)),
		float(forecast.get("remaining_limit", 0.0)),
		float(forecast.get("team_hp", 0.0)),
		float(forecast.get("team_max_hp", 0.0)),
		float(forecast.get("ending_team_hp", 0.0)),
		int(forecast.get("downs", 0)),
		_risk_label(String(forecast.get("wipe_risk", "low"))),
		float(forecast.get("attempt_boss_healed_ratio", 0.0)) * 100.0,
		recent_failures,
		_failure_label(recent_reason),
		qa_status,
		_upgrade_wait_label(state, catalog, forecast),
	]


static func _maintenance_evidence(
	state: GameState,
	catalog: ContentCatalog,
	reason: StringName
) -> String:
	var failure_count := _recent_stage_failure_count(state)
	if failure_count == 0:
		failure_count = 1
	return (
		"최근 동일 스테이지 실패 %d회 · 원인 %s · 유지보수 %d사이클 남음 · 다음 강화 %s"
	) % [
		failure_count,
		_failure_label(reason),
		state.maintenance_cycles_remaining,
		_upgrade_wait_label(state, catalog, {"seconds": 0.0, "resolved": false}),
	]


static func _upgrade_wait_label(
	state: GameState,
	catalog: ContentCatalog,
	forecast: Dictionary
) -> String:
	var cheapest := INF
	for definition: OperatorDefinition in catalog.operators:
		if not state.is_operator_unlocked(definition.id):
			continue
		var level := int(state.operator_levels.get(definition.id, 0))
		cheapest = minf(
			cheapest,
			ProgressionRules.operator_upgrade_cost(
				level, definition.base_cost, definition.cost_growth
			)
		)
	if state.bits + EPSILON >= cheapest:
		return "지금 가능"

	var elapsed := float(forecast.get("seconds", 0.0))
	var projected_bits := state.bits
	if bool(forecast.get("resolved", false)):
		var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
		projected_bits += (
			ProgressionRules.enemy_reward(
				state.stage, catalog.balance, float(modifiers.bits)
			)
			* catalog.balance.boss_health_multiplier
		)
		if projected_bits + EPSILON >= cheapest:
			return "%.1f초" % elapsed
		if state.stage >= 20:
			return "버전 업데이트 후"

	var dps := ProgressionRules.total_dps(state, catalog)
	if dps <= EPSILON:
		return "계산 불가"
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	var forecast_failed := bool(forecast.get("failed", false))
	var farm_health_stage := state.stage
	var farm_reward_stage := maxi(1, state.stage - 1)
	if not state.is_maintenance and not forecast_failed:
		farm_health_stage = mini(20, state.stage + 1)
		farm_reward_stage = farm_health_stage
	var farm_hp := ProgressionRules.enemy_max_hp(
		farm_health_stage,
		false,
		catalog.balance,
		float(modifiers.enemy_health)
	)
	var farm_reward := ProgressionRules.enemy_reward(
		farm_reward_stage,
		catalog.balance,
		float(modifiers.bits)
	)
	var bits_per_second := farm_reward / (farm_hp / dps)
	if bits_per_second <= EPSILON:
		return "계산 불가"
	return "%.1f초" % (elapsed + maxf(0.0, cheapest - projected_bits) / bits_per_second)


static func _recommend_from_down_events(
	state: GameState,
	catalog: ContentCatalog,
	forecast: Dictionary
) -> Array[StringName]:
	var preferred: Array[StringName] = []
	var raw_events: Variant = forecast.get("events", [])
	if raw_events is Array:
		var events := raw_events as Array
		for index: int in range(events.size() - 1, -1, -1):
			var raw_event: Variant = events[index]
			if not raw_event is Dictionary:
				continue
			var event := raw_event as Dictionary
			if StringName(event.get("kind", "")) != &"operator_down":
				continue
			var operator_id := StringName(event.get("operator_id", ""))
			if operator_id != &"" and not preferred.has(operator_id):
				preferred.append(operator_id)
			if preferred.size() >= 1:
				break
	preferred.append(&"qa_imp")
	preferred.append(&"debugger")
	return _available_ids(state, catalog, preferred)


static func _available_ids(
	state: GameState,
	catalog: ContentCatalog,
	preferred: Array[StringName]
) -> Array[StringName]:
	var result: Array[StringName] = []
	for operator_id: StringName in preferred:
		if (
			operator_id == &""
			or result.has(operator_id)
			or not catalog.has_operator(operator_id)
			or not state.is_operator_unlocked(operator_id)
			or int(state.operator_levels.get(operator_id, 0)) <= 0
		):
			continue
		result.append(operator_id)
		if result.size() >= 2:
			break
	return result


static func _latest_event(
	state: GameState,
	kinds: Array[StringName],
	attempt_serial: int
) -> Dictionary:
	for index: int in range(state.recent_boss_events.size() - 1, -1, -1):
		var event: Dictionary = state.recent_boss_events[index]
		if attempt_serial >= 0 and int(event.get("attempt_serial", -1)) != attempt_serial:
			continue
		if kinds.has(StringName(event.get("kind", ""))):
			return event
	return {}


static func _recent_stage_failure_count(state: GameState) -> int:
	var count := 0
	for event: Dictionary in state.recent_boss_events:
		if (
			int(event.get("stage", -1)) == state.stage
			and StringName(event.get("kind", "")) == &"boss_attempt_failed"
		):
			count += 1
	return count


static func _recent_failure_reason(state: GameState) -> StringName:
	if state.last_boss_failure_reason != &"":
		return state.last_boss_failure_reason
	var event := _latest_event(state, [&"boss_attempt_failed"], -1)
	return StringName(event.get("reason", ""))


static func _failure_label(reason: StringName) -> String:
	match reason:
		&"boss_all_down":
			return "전원 DOWN"
		&"boss_timeout":
			return "제한 시간 초과"
		&"":
			return "기록 없음"
		_:
			return String(reason)


static func _risk_label(risk: String) -> String:
	match risk:
		"high":
			return "높음"
		"medium":
			return "중간"
		_:
			return "낮음"


static func _diagnosis(
	kind: String,
	title: String,
	summary: String,
	evidence: String,
	recommended_operator_ids: Array[StringName]
) -> Dictionary:
	var ids: Array[String] = []
	for operator_id: StringName in recommended_operator_ids:
		ids.append(String(operator_id))
	return {
		"kind": kind,
		"title": title,
		"summary": summary,
		"evidence": evidence,
		"severity": _severity(kind),
		"recommended_operator_ids": ids,
	}


static func _severity(kind: String) -> String:
	if kind in ["wipe_risk", "timeout_risk"]:
		return "critical"
	if kind in [
		"process_down_risk",
		"qa_rescue_cancelled",
		"qa_rescue_used",
		"rollback_pressure",
		"recent_failure_all_down",
		"recent_failure_timeout",
		"recent_failure",
	]:
		return "warning"
	return "info"
