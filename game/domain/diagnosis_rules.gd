class_name DiagnosisRules
extends RefCounted


static func evaluate(state: GameState, catalog: ContentCatalog) -> Dictionary:
	if state.can_prestige:
		return _diagnosis(
			"version_ready",
			"버전 업데이트 준비 완료",
			"스테이지 20의 감시견 프로세스를 격리했습니다.",
			"info"
		)
	if state.is_maintenance:
		return _diagnosis(
			"maintenance",
			"자동 유지보수 중",
			"이전 일반 구간을 파밍한 뒤 보스에 자동 재도전합니다.",
			"warning"
		)

	var max_hp: float = ProgressionRules.current_enemy_max_hp(state, catalog)
	if ProgressionRules.is_boss_stage(state.stage) and max_hp > 0.0:
		var recovered_ratio: float = state.boss_recovered_health / max_hp
		if recovered_ratio >= 0.08:
			return _diagnosis(
				"rule_response",
				"보스 규칙 대응 부족",
				"받은 피해의 일부를 롤백해 최대 체력의 %.0f%%를 복구했습니다."
				% (recovered_ratio * 100.0),
				"critical" if recovered_ratio >= 0.20 else "warning"
			)

	var estimated_ttk: float = ProgressionRules.estimated_time_to_kill(state, catalog)
	var target_ttk: float = (
		catalog.balance.boss_time_limit
		if ProgressionRules.is_boss_stage(state.stage)
		else catalog.balance.target_normal_ttk
	)
	if estimated_ttk > target_ttk:
		return _diagnosis(
			"throughput",
			"처리량 부족",
			"예상 처치 %.1f초 / 목표 %.0f초" % [estimated_ttk, target_ttk],
			"critical" if estimated_ttk > target_ttk * 1.5 else "warning"
		)

	var next_cost: float = _cheapest_upgrade_cost(state, catalog)
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	var reward: float = ProgressionRules.enemy_reward(
		state.stage, catalog.balance, float(modifiers.bits)
	)
	if ProgressionRules.is_boss_stage(state.stage):
		reward *= catalog.balance.boss_health_multiplier
	var bits_per_second: float = 0.0 if estimated_ttk <= 0.0 else reward / estimated_ttk
	var wait_seconds: float = (
		INF
		if bits_per_second <= 0.0
		else maxf(0.0, next_cost - state.bits) / bits_per_second
	)
	if wait_seconds >= 60.0:
		return _diagnosis(
			"reward_leak",
			"보상 누수",
			"다음 유효 강화까지 약 %.0f초가 필요합니다." % wait_seconds,
			"warning"
		)

	return _diagnosis(
		"stable",
		"운영 안정",
		"현재 처리량과 보상 흐름이 목표 범위 안에 있습니다.",
		"info"
	)


static func _cheapest_upgrade_cost(state: GameState, catalog: ContentCatalog) -> float:
	var cheapest: float = INF
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
	return cheapest


static func _diagnosis(kind: String, title: String, evidence: String, severity: String) -> Dictionary:
	return {
		"kind": kind,
		"title": title,
		"evidence": evidence,
		"severity": severity,
	}
