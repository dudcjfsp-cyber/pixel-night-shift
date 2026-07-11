class_name GameSession
extends RefCounted

var _catalog: ContentCatalog
var _state: GameState
var _last_error: String = ""


func _init(catalog_override: ContentCatalog = null) -> void:
	if catalog_override != null:
		_catalog = catalog_override
	else:
		var load_result := ContentLoader.load_default()
		assert(
			load_result.is_valid(),
			"Content failed validation: %s" % "; ".join(load_result.errors)
		)
		_catalog = load_result.catalog
	_state = GameState.new()
	for definition: OperatorDefinition in _catalog.operators:
		_state.operator_levels[definition.id] = 0
	ProgressionRules.refresh_unlocks(_state, _catalog)
	_state.enemy_health = ProgressionRules.current_enemy_max_hp(_state, _catalog)


func tick(delta_seconds: float) -> void:
	if delta_seconds < 0.0 or not is_finite(delta_seconds):
		_reject("경과 시간은 0 이상의 유한한 값이어야 합니다.")
		return
	_last_error = ""
	BattleSimulator.advance(_state, _catalog, delta_seconds)


func upgrade_operator(operator_id: StringName) -> bool:
	if not _catalog.has_operator(operator_id):
		return _reject("존재하지 않는 요원입니다.")
	if not _state.is_operator_unlocked(operator_id):
		return _reject("아직 해금되지 않은 요원입니다.")
	var definition := _catalog.get_operator(operator_id)
	var level := int(_state.operator_levels.get(operator_id, 0))
	var cost := ProgressionRules.operator_upgrade_cost(
		level, definition.base_cost, definition.cost_growth
	)
	if _state.bits + 0.000001 < cost:
		return _reject("비트가 부족합니다.")
	_state.bits = maxf(0.0, _state.bits - cost)
	_state.operator_levels[operator_id] = level + 1
	_state.status_message = "%s 레벨 %d" % [definition.display_name, level + 1]
	return _accept()


func equip_patch(slot_index: int, patch_id: StringName) -> bool:
	if not _is_unlocked_slot(slot_index):
		return _reject("아직 사용할 수 없는 패치 슬롯입니다.")
	if not _catalog.has_patch(patch_id):
		return _reject("존재하지 않는 패치입니다.")
	if not _state.is_patch_discovered(patch_id):
		return _reject("아직 발견하지 않은 패치입니다.")
	if _state.equipped_patch_ids.has(patch_id):
		return _reject("같은 패치는 두 슬롯에 장착할 수 없습니다.")
	var replacing := _state.equipped_patch_ids[slot_index] != &""
	var cost := _patch_change_cost(replacing)
	if _state.bits + 0.000001 < cost:
		return _reject("패치 교체에 필요한 비트가 부족합니다.")

	var old_max_hp := ProgressionRules.current_enemy_max_hp(_state, _catalog)
	_state.bits = maxf(0.0, _state.bits - cost)
	if replacing and _state.free_patch_swaps > 0:
		_state.free_patch_swaps -= 1
	_state.equipped_patch_ids[slot_index] = patch_id
	_preserve_enemy_health_ratio(old_max_hp)
	_state.status_message = "%s 적용" % _catalog.get_patch(patch_id).display_name
	return _accept()


func remove_patch(slot_index: int) -> bool:
	if not _is_unlocked_slot(slot_index):
		return _reject("아직 사용할 수 없는 패치 슬롯입니다.")
	if _state.equipped_patch_ids[slot_index] == &"":
		return _reject("패치 슬롯이 이미 비어 있습니다.")
	var cost := _patch_change_cost(true)
	if _state.bits + 0.000001 < cost:
		return _reject("패치 제거에 필요한 비트가 부족합니다.")
	var old_max_hp := ProgressionRules.current_enemy_max_hp(_state, _catalog)
	_state.bits = maxf(0.0, _state.bits - cost)
	if _state.free_patch_swaps > 0:
		_state.free_patch_swaps -= 1
	_state.equipped_patch_ids[slot_index] = &""
	_preserve_enemy_health_ratio(old_max_hp)
	_state.status_message = "패치를 제거했습니다."
	return _accept()


func prestige() -> bool:
	if not _state.can_prestige:
		return _reject("아직 버전 업데이트를 실행할 수 없습니다.")
	_state.patch_notes += 1
	_state.run_count += 1
	_state.stage = 1
	_state.bits = 0.0
	_state.can_prestige = false
	_state.is_maintenance = false
	_state.maintenance_cycles_remaining = 0
	_state.enemy_index = 1
	_state.equipped_patch_ids = [&"", &"", &""]
	_state.free_patch_swaps = 0
	_state.boss_failure_count = 0
	_state.boss_elapsed = 0.0
	_state.boss_recovery_count = 0
	_state.boss_recovered_health = 0.0
	_state.boss_debuff_applied = false
	for definition: OperatorDefinition in _catalog.operators:
		_state.operator_levels[definition.id] = 0
	ProgressionRules.refresh_unlocks(_state, _catalog)
	_state.enemy_health = ProgressionRules.current_enemy_max_hp(_state, _catalog)
	_state.status_message = "새 버전의 야간 근무를 시작합니다."
	return _accept()


func buy_legacy_cache() -> bool:
	var balance := _catalog.balance
	if _state.legacy_cache_level >= balance.max_legacy_cache_level:
		return _reject("레거시 빌드 캐시는 이미 최대 단계입니다.")
	if _state.patch_notes < balance.legacy_cache_cost:
		return _reject("패치노트가 부족합니다.")
	_state.patch_notes -= balance.legacy_cache_cost
	_state.legacy_cache_level += 1
	_state.status_message = "레거시 빌드 캐시를 활성화했습니다."
	return _accept()


func snapshot() -> Dictionary:
	var boss := ProgressionRules.is_boss_stage(_state.stage) and not _state.is_maintenance
	var max_hp := ProgressionRules.current_enemy_max_hp(_state, _catalog)
	var operator_rows: Array[Dictionary] = []
	for definition: OperatorDefinition in _catalog.operators:
		var level := int(_state.operator_levels.get(definition.id, 0))
		operator_rows.append({
			"id": String(definition.id),
			"name": definition.display_name,
			"level": level,
			"unlocked": _state.is_operator_unlocked(definition.id),
			"dps": ProgressionRules.operator_dps(definition, level),
			"upgrade_cost": ProgressionRules.operator_upgrade_cost(
				level, definition.base_cost, definition.cost_growth
			),
		})

	var slot_rows: Array[String] = []
	for patch_id: StringName in _state.equipped_patch_ids:
		slot_rows.append(String(patch_id))
	var patch_rows: Array[Dictionary] = []
	for definition: PatchDefinition in _catalog.patches:
		patch_rows.append({
			"id": String(definition.id),
			"name": definition.display_name,
			"description": definition.description,
			"benefit": definition.benefit,
			"drawback": definition.drawback,
			"unlocked": _state.is_patch_discovered(definition.id),
			"equipped": _state.equipped_patch_ids.has(definition.id),
		})

	return {
		"stage": _state.stage,
		"stage_enemy_index": 1 if boss else _state.enemy_index,
		"stage_enemy_total": 1 if boss else _catalog.balance.normal_enemy_count,
		"bits": _state.bits,
		"patch_notes": _state.patch_notes,
		"run_count": _state.run_count,
		"mode": _mode(),
		"enemy": {
			"name": _enemy_name(boss),
			"hp": _state.enemy_health,
			"max_hp": max_hp,
			"is_boss": boss,
			"time_left": max(0.0, _catalog.balance.boss_time_limit - _state.boss_elapsed) if boss else 0.0,
		},
		"operators": operator_rows,
		"patch_slots": slot_rows,
		"patches": patch_rows,
		"unlocked_patch_slots": _state.unlocked_patch_slots,
		"diagnosis": get_diagnosis(),
		"prestige_available": _state.can_prestige,
		"legacy_cache_level": _state.legacy_cache_level,
		"legacy_cache_cost": (
			0
			if _state.legacy_cache_level >= _catalog.balance.max_legacy_cache_level
			else _catalog.balance.legacy_cache_cost
		),
		"maintenance_time_left": _estimated_maintenance_time(),
		"status_message": _state.status_message,
		"last_error": _last_error,
	}


func get_diagnosis() -> Dictionary:
	return DiagnosisRules.evaluate(_state, _catalog)


func get_patch_preview(slot_index: int, patch_id: StringName) -> Dictionary:
	var can_equip := (
		_is_unlocked_slot(slot_index)
		and _catalog.has_patch(patch_id)
		and _state.is_patch_discovered(patch_id)
		and not _state.equipped_patch_ids.has(patch_id)
	)
	var proposed: Array[StringName] = _state.equipped_patch_ids.duplicate()
	if slot_index >= 0 and slot_index < proposed.size():
		proposed[slot_index] = patch_id
	var before_modifiers := ProgressionRules.patch_modifiers(_state.equipped_patch_ids, _catalog)
	var after_modifiers := ProgressionRules.patch_modifiers(proposed, _catalog)
	var before_ttk := _estimated_ttk(_state.equipped_patch_ids)
	var after_ttk := _estimated_ttk(proposed)
	var replacing := (
		slot_index >= 0
		and slot_index < _state.equipped_patch_ids.size()
		and _state.equipped_patch_ids[slot_index] != &""
	)
	var cost := _patch_change_cost(replacing) if can_equip else 0.0
	var summary := "장착할 수 없는 패치입니다."
	if can_equip:
		summary = "예상 처치 %.1f초 → %.1f초, 비트 배율 %.2f → %.2f" % [
			before_ttk, after_ttk, before_modifiers.bits, after_modifiers.bits
		]
	return {
		"can_equip": can_equip,
		"cost": cost,
		"summary": summary,
		"before_ttk": before_ttk,
		"after_ttk": after_ttk,
		"before_bits_multiplier": float(before_modifiers.bits),
		"after_bits_multiplier": float(after_modifiers.bits),
	}


func _is_unlocked_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _state.unlocked_patch_slots


func _patch_change_cost(replacing: bool) -> float:
	if not replacing or _state.free_patch_swaps > 0:
		return 0.0
	return ProgressionRules.patch_swap_cost(_state, _catalog)


func _preserve_enemy_health_ratio(old_max_hp: float) -> void:
	if old_max_hp <= 0.0:
		return
	var health_ratio: float = clampf(_state.enemy_health / old_max_hp, 0.0, 1.0)
	var new_max_hp := ProgressionRules.current_enemy_max_hp(_state, _catalog)
	_state.enemy_health = new_max_hp * health_ratio


func _estimated_ttk(patch_ids: Array[StringName]) -> float:
	return ProgressionRules.estimated_time_to_kill(_state, _catalog, patch_ids)


func _estimated_maintenance_time() -> float:
	if not _state.is_maintenance:
		return 0.0
	var dps := ProgressionRules.total_dps(_state, _catalog)
	if dps <= 0.0:
		return INF
	var max_hp := ProgressionRules.current_enemy_max_hp(_state, _catalog)
	var enemies_after_current := (
		(_catalog.balance.normal_enemy_count - _state.enemy_index)
		+ ((_state.maintenance_cycles_remaining - 1) * _catalog.balance.normal_enemy_count)
	)
	return (_state.enemy_health + max_hp * enemies_after_current) / dps


func _mode() -> String:
	if _state.can_prestige:
		return "complete"
	if _state.is_maintenance:
		return "maintenance"
	if ProgressionRules.is_boss_stage(_state.stage):
		return "boss"
	return "combat"


func _enemy_name(boss: bool) -> String:
	if boss:
		return "감시견 프로세스"
	if _state.is_maintenance:
		return "유지보수 오류"
	var names: Array[String] = ["깨진 픽셀", "무한 루프", "누락 리소스"]
	return names[(_state.stage - 1) % names.size()]


func _accept() -> bool:
	_last_error = ""
	return true


func _reject(message: String) -> bool:
	_last_error = message
	return false
