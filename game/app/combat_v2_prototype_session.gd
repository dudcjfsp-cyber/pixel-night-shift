class_name CombatV2PrototypeSession
extends RefCounted

const EQUIPPED_PATCH_SLOT_COUNT := 3
const EPSILON := 0.000001
const MAINTENANCE_ENEMY_NAME := "유지보수 오류"

var _catalog: CombatV2Catalog
var _state: CombatV2State
var _last_error := ""


func _init(catalog_override: CombatV2Catalog = null) -> void:
	if catalog_override != null:
		_catalog = catalog_override
	else:
		var load_result := CombatV2Loader.load_default()
		assert(
			load_result.is_valid(),
			"Combat V2 content failed validation: %s" % "; ".join(load_result.errors)
		)
		_catalog = load_result.catalog
	_state = CombatV2State.new()
	CombatV2Simulator.initialize_new_run(_state, _catalog)


func tick(delta_seconds: float) -> void:
	if delta_seconds < 0.0 or not is_finite(delta_seconds):
		_reject("경과 시간은 0 이상의 유한한 값이어야 합니다.")
		return
	_last_error = ""
	CombatV2Simulator.advance(_state, _catalog, delta_seconds)


func upgrade_operator(operator_id: StringName) -> bool:
	var base_catalog := _catalog.base_catalog
	if not base_catalog.has_operator(operator_id):
		return _reject("존재하지 않는 요원입니다.")
	if not _state.progression.is_operator_unlocked(operator_id):
		return _reject("아직 해금되지 않은 요원입니다.")
	var definition := base_catalog.get_operator(operator_id)
	var level := int(_state.progression.operator_levels.get(operator_id, 0))
	var cost := ProgressionRules.operator_upgrade_cost(
		level, definition.base_cost, definition.cost_growth
	)
	if _state.progression.bits + EPSILON < cost:
		return _reject("비트가 부족합니다.")

	var runtime := _state.get_operator(operator_id)
	assert(runtime != null, "Unlocked Combat V2 operator requires runtime state")
	var old_max_hp := CombatV2Simulator.operator_max_hp(_state, _catalog, operator_id)
	var health_ratio := 0.0
	if runtime.is_active() and old_max_hp > EPSILON:
		health_ratio = clampf(runtime.current_hp / old_max_hp, 0.0, 1.0)
	_state.progression.bits = maxf(0.0, _state.progression.bits - cost)
	_state.progression.operator_levels[operator_id] = level + 1
	if runtime.is_active():
		var new_max_hp := CombatV2Simulator.operator_max_hp(_state, _catalog, operator_id)
		runtime.current_hp = new_max_hp * health_ratio
	_state.progression.status_message = "%s 레벨 %d" % [definition.display_name, level + 1]
	_state.record_event(&"operator_upgrade", {
		"operator_id": operator_id,
		"level": level + 1,
		"cost": cost,
	})
	return _accept()


func equip_patch(slot_index: int, patch_id: StringName) -> bool:
	if not _is_unlocked_slot(slot_index):
		return _reject("아직 사용할 수 없는 패치 슬롯입니다.")
	if not _catalog.base_catalog.has_patch(patch_id):
		return _reject("존재하지 않는 패치입니다.")
	if not _state.progression.is_patch_discovered(patch_id):
		return _reject("아직 발견하지 않은 패치입니다.")
	if _state.progression.equipped_patch_ids.has(patch_id):
		return _reject("같은 패치를 여러 슬롯에 장착할 수 없습니다.")

	var replacing := _state.progression.equipped_patch_ids[slot_index] != &""
	var cost := _patch_change_cost(replacing)
	if _state.progression.bits + EPSILON < cost:
		return _reject("패치 교체에 필요한 비트가 부족합니다.")
	var old_max_hp := CombatV2Forecast.enemy_max_hp(_state, _catalog)
	var health_ratio := clampf(_state.progression.enemy_health / old_max_hp, 0.0, 1.0)
	_state.progression.bits = maxf(0.0, _state.progression.bits - cost)
	if replacing and _state.progression.free_patch_swaps > 0:
		_state.progression.free_patch_swaps -= 1
	_state.progression.equipped_patch_ids[slot_index] = patch_id
	_state.progression.enemy_health = CombatV2Forecast.enemy_max_hp(
		_state, _catalog
	) * health_ratio
	_state.progression.status_message = "%s 적용" % _catalog.base_catalog.get_patch(
		patch_id
	).display_name
	_state.record_event(&"patch_equipped", {"patch_id": patch_id, "cost": cost})
	return _accept()


func remove_patch(slot_index: int) -> bool:
	if not _is_unlocked_slot(slot_index):
		return _reject("아직 사용할 수 없는 패치 슬롯입니다.")
	if _state.progression.equipped_patch_ids[slot_index] == &"":
		return _reject("패치 슬롯이 이미 비어 있습니다.")
	var cost := _patch_change_cost(true)
	if _state.progression.bits + EPSILON < cost:
		return _reject("패치 제거에 필요한 비트가 부족합니다.")
	var old_max_hp := CombatV2Forecast.enemy_max_hp(_state, _catalog)
	var health_ratio := clampf(_state.progression.enemy_health / old_max_hp, 0.0, 1.0)
	var removed_id := _state.progression.equipped_patch_ids[slot_index]
	_state.progression.bits = maxf(0.0, _state.progression.bits - cost)
	if _state.progression.free_patch_swaps > 0:
		_state.progression.free_patch_swaps -= 1
	_state.progression.equipped_patch_ids[slot_index] = &""
	_state.progression.enemy_health = CombatV2Forecast.enemy_max_hp(
		_state, _catalog
	) * health_ratio
	_state.record_event(&"patch_removed", {"patch_id": removed_id, "cost": cost})
	_state.progression.status_message = "패치를 제거했습니다."
	return _accept()


func emergency_redeploy(operator_id: StringName) -> bool:
	var result := CombatV2Simulator.request_emergency_redeploy(
		_state, _catalog, operator_id
	)
	if not bool(result.succeeded):
		return _reject(String(result.error))
	_state.progression.status_message = "%s 긴급 재배포 예약 · %.0f bit" % [
		_catalog.base_catalog.get_operator(operator_id).display_name,
		float(result.cost),
	]
	return _accept()


func snapshot() -> Dictionary:
	var progression := _state.progression
	var is_boss := _is_boss()
	var max_enemy_hp := CombatV2Forecast.enemy_max_hp(_state, _catalog)
	var operator_rows: Array[Dictionary] = []
	for definition: OperatorDefinition in _catalog.base_catalog.operators:
		var runtime := _state.get_operator(definition.id)
		assert(runtime != null, "Combat V2 snapshot requires every operator runtime")
		var level := int(progression.operator_levels.get(definition.id, 0))
		var unlocked := progression.is_operator_unlocked(definition.id)
		var max_hp := (
			CombatV2Simulator.operator_max_hp(_state, _catalog, definition.id)
			if unlocked else 0.0
		)
		var redeploy_status := CombatV2Simulator.emergency_redeploy_status(
			_state, _catalog, definition.id
		)
		operator_rows.append({
			"id": String(definition.id),
			"name": definition.display_name,
			"role": _catalog.get_operator(definition.id).role_name,
			"ability": definition.ability_description,
			"level": level,
			"unlocked": unlocked,
			"dps": CombatV2Simulator.operator_effective_dps(
				_state, _catalog, definition.id
			) if unlocked else 0.0,
			"upgrade_cost": ProgressionRules.operator_upgrade_cost(
				level, definition.base_cost, definition.cost_growth
			),
			"hp": runtime.current_hp,
			"max_hp": max_hp,
			"down": unlocked and not runtime.is_active(),
			"process_down": unlocked and not runtime.is_active(),
			"attack_remaining": 0.0 if not runtime.is_active() else runtime.attack_remaining,
			"recovery_remaining": runtime.recovery_remaining,
			"recovery_source": String(runtime.recovery_source),
			"redeploy_eligible": bool(redeploy_status.eligible),
			"redeploy_available": bool(redeploy_status.available),
			"redeploy_error": String(redeploy_status.error),
			"damage_dealt": runtime.damage_dealt,
			"damage_taken": runtime.damage_taken,
			"down_count": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		})

	var patch_slots: Array[String] = []
	for patch_id: StringName in progression.equipped_patch_ids:
		patch_slots.append(String(patch_id))
	var patch_rows: Array[Dictionary] = []
	for definition: PatchDefinition in _catalog.base_catalog.patches:
		patch_rows.append({
			"id": String(definition.id),
			"name": definition.display_name,
			"description": definition.description,
			"benefit": definition.benefit,
			"drawback": definition.drawback,
			"unlocked": progression.is_patch_discovered(definition.id),
			"equipped": progression.equipped_patch_ids.has(definition.id),
		})

	var enemy_id := _enemy_id()
	var enemy_name := MAINTENANCE_ENEMY_NAME
	if enemy_id != &"maintenance_error":
		var enemy_profile := _catalog.get_enemy(enemy_id)
		assert(enemy_profile != null, "Combat V2 snapshot requires a known enemy profile")
		enemy_name = enemy_profile.display_name
	var next_action := _next_enemy_action()
	var emergency := CombatV2Simulator.emergency_redeploy_overview(_state, _catalog)
	var diagnosis := get_diagnosis()
	var enemy_row := {
		"id": String(enemy_id),
		"name": enemy_name,
		"hp": progression.enemy_health,
		"max_hp": max_enemy_hp,
		"is_boss": is_boss,
		"time_left": maxf(
			0.0,
			_catalog.base_catalog.balance.boss_time_limit - progression.boss_elapsed
		) if is_boss else 0.0,
		"next_action": String(next_action.label),
		"next_action_in": float(next_action.seconds),
	}
	return {
		"prototype": "combat_v2",
		"stage": progression.stage,
		"stage_enemy_index": 1 if is_boss else progression.enemy_index,
		"stage_enemy_total": 1 if is_boss else _catalog.balance.normal_enemy_count,
		"bits": progression.bits,
		"mode": _mode(),
		"enemy": enemy_row,
		"operators": operator_rows,
		"patch_slots": patch_slots,
		"patches": patch_rows,
		"unlocked_patch_slots": progression.unlocked_patch_slots,
		"diagnosis": diagnosis,
		"prestige_available": progression.can_prestige,
		"failure_count": _state.total_failure_count(),
		"normal_failure_count": _state.normal_failure_count,
		"boss_failure_count": progression.boss_failure_count,
		"last_failure_reason": String(_state.last_failure_reason),
		"maintenance_remaining": _state.maintenance_remaining,
		"maintenance_reason": String(_state.last_failure_reason),
		"qa_rescue_count": _state.qa_rescue_count,
		"paid_redeploy_count": _state.paid_redeploy_count,
		"emergency_spent_bits": _state.emergency_spent_bits,
		"gross_bits": _state.total_bits_earned,
		"net_bits": progression.bits,
		"emergency_redeploy": emergency,
		"emergency_redeploy_cost": float(emergency.cost),
		"emergency_redeploy_available": bool(emergency.available),
		"emergency_redeploy_remaining": int(emergency.remaining),
		"free_patch_swaps": progression.free_patch_swaps,
		"recent_events": _formatted_events(),
		"visible_appeal_events": _visible_appeal_events(),
		"appeal_evidence": _appeal_evidence(diagnosis, emergency, operator_rows, enemy_row),
		"combat_metrics": {
			"total_elapsed": _state.total_elapsed,
			"damage_taken": _state.total_damage_taken,
			"down_count": _state.total_down_count,
			"down_time": _state.total_down_time,
			"boss_healed": _state.total_boss_healed,
			"enemies_defeated": _state.total_enemies_defeated,
			"stages_cleared": _state.total_stages_cleared,
			"failure_count": _state.total_failure_count(),
			"normal_failure_count": _state.normal_failure_count,
			"boss_failure_count": progression.boss_failure_count,
			"qa_rescue_count": _state.qa_rescue_count,
			"paid_redeploy_count": _state.paid_redeploy_count,
			"emergency_spent_bits": _state.emergency_spent_bits,
		},
		"status_message": progression.status_message,
		"last_error": _last_error,
	}


func get_diagnosis() -> Dictionary:
	return CombatV2DiagnosisRules.evaluate(_state, _catalog)


func get_patch_preview(slot_index: int, patch_id: StringName) -> Dictionary:
	var can_equip := (
		_is_unlocked_slot(slot_index)
		and _catalog.base_catalog.has_patch(patch_id)
		and _state.progression.is_patch_discovered(patch_id)
		and not _state.progression.equipped_patch_ids.has(patch_id)
	)
	var proposed: Array[StringName] = _state.progression.equipped_patch_ids.duplicate()
	if slot_index >= 0 and slot_index < proposed.size():
		proposed[slot_index] = patch_id
	var before := CombatV2Forecast.estimate(_state, _catalog)
	var after := CombatV2Forecast.estimate(_state, _catalog, proposed)
	var before_modifiers := ProgressionRules.patch_modifiers(
		_state.progression.equipped_patch_ids, _catalog.base_catalog
	)
	var after_modifiers := ProgressionRules.patch_modifiers(proposed, _catalog.base_catalog)
	var replacing := (
		slot_index >= 0
		and slot_index < _state.progression.equipped_patch_ids.size()
		and _state.progression.equipped_patch_ids[slot_index] != &""
	)
	return {
		"can_equip": can_equip,
		"cost": _patch_change_cost(replacing) if can_equip else 0.0,
		"before_ttk": float(before.seconds),
		"after_ttk": float(after.seconds),
		"before_bits_multiplier": float(before_modifiers.bits),
		"after_bits_multiplier": float(after_modifiers.bits),
		"before_downs": int(before.downs),
		"after_downs": int(after.downs),
		"before_uptime": float(before.uptime),
		"after_uptime": float(after.uptime),
		"before_damage_taken": float(before.damage_taken),
		"after_damage_taken": float(after.damage_taken),
	}


func debug_state_copy() -> CombatV2State:
	return _state.deep_clone()


func export_state() -> Dictionary:
	return CombatV2StateDto.export_state(_state)


func restore_state(data: Dictionary) -> PackedStringArray:
	var restore_result := CombatV2StateDto.restore_candidate(data, _catalog)
	if not restore_result.errors.is_empty():
		return restore_result.errors.duplicate()
	assert(restore_result.state != null, "Validated Combat V2 restore must produce a state")
	_state = restore_result.state
	_last_error = ""
	return PackedStringArray()


func _is_unlocked_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _state.progression.unlocked_patch_slots


func _patch_change_cost(replacing: bool) -> float:
	if not replacing or _state.progression.free_patch_swaps > 0:
		return 0.0
	return ProgressionRules.patch_swap_cost(_state.progression, _catalog.base_catalog)


func _is_boss() -> bool:
	return (
		_state.progression.stage <= _catalog.balance.max_stage
		and ProgressionRules.is_boss_stage(_state.progression.stage)
		and not _state.progression.is_maintenance
	)


func _mode() -> String:
	if _state.progression.can_prestige:
		return "complete"
	if _state.progression.is_maintenance:
		return "maintenance"
	if _is_boss():
		return "boss"
	return "combat"


func _enemy_id() -> StringName:
	if _state.progression.is_maintenance:
		return &"maintenance_error"
	if _is_boss():
		return &"watchdog_process"
	var ids: Array[StringName] = [&"broken_pixel", &"infinite_loop", &"missing_resource"]
	return ids[(_state.progression.stage - 1) % ids.size()]


func _next_enemy_action() -> Dictionary:
	if _state.progression.is_maintenance:
		return {"label": "자동 재도전", "seconds": _state.maintenance_remaining}
	if _state.progression.can_prestige:
		return {"label": "공격 없음", "seconds": 0.0}
	if _is_boss():
		var candidates: Array[Dictionary] = [
			{"label": "POLL", "seconds": _state.enemy_attack_remaining},
			{"label": "KILL SIGNAL", "seconds": _state.boss_special_remaining},
			{"label": "ROLLBACK", "seconds": _state.boss_rollback_remaining},
		]
		var best := candidates[0]
		for candidate: Dictionary in candidates:
			if float(candidate.seconds) < float(best.seconds):
				best = candidate
		return best
	return {
		"label": "3연타" if _enemy_id() == &"infinite_loop" else "공격",
		"seconds": _state.enemy_attack_remaining,
	}


func _formatted_events() -> Array[String]:
	var rows: Array[String] = []
	var first_index := maxi(0, _state.recent_events.size() - 12)
	for index: int in range(first_index, _state.recent_events.size()):
		var event := _state.recent_events[index]
		var summary_parts: Array[String] = []
		for key_value: Variant in event.keys():
			var key := String(key_value)
			if key in ["kind", "time", "stage", "enemy_index", "encounter_serial"]:
				continue
			summary_parts.append("%s=%s" % [key, str(event[key_value])])
		rows.append("%6.1fs · %-18s · %s" % [
			float(event.time), String(event.kind), ", ".join(summary_parts),
		])
	return rows


func _appeal_evidence(
	diagnosis: Dictionary,
	emergency: Dictionary,
	operator_rows: Array[Dictionary],
	enemy: Dictionary
) -> Dictionary:
	var evidence_data := diagnosis["evidence_data"] as Dictionary
	var current_downs := 0
	var unlocked_count := 0
	var unlocked_operator_ids: Array[String] = []
	for operator: Dictionary in operator_rows:
		if not bool(operator["unlocked"]):
			continue
		unlocked_count += 1
		unlocked_operator_ids.append(String(operator["id"]))
		if bool(operator["process_down"]):
			current_downs += 1
	var max_enemy_hp := float(enemy["max_hp"])
	return {
		"diagnosis_kind": String(diagnosis["kind"]),
		"stage": int(_state.progression.stage),
		"is_boss": bool(enemy["is_boss"]),
		"current_downs": current_downs,
		"failure_count": _state.total_failure_count(),
		"normal_failure_count": _state.normal_failure_count,
		"boss_failure_count": _state.progression.boss_failure_count,
		"last_failure_reason": String(_state.last_failure_reason),
		"maintenance": _state.progression.is_maintenance,
		"emergency_available": bool(emergency["available"]),
		"emergency_affordable": bool(emergency["affordable"]),
		"emergency_remaining": int(emergency["remaining"]),
		"qa_rescue_available": bool(evidence_data["qa_rescue_available"]),
		"qa_rescue_pending": bool(evidence_data["qa_rescue_pending"]),
		"qa_rescue_count": _state.qa_rescue_count,
		"paid_redeploy_count": _state.paid_redeploy_count,
		"enemy_hp_ratio": 0.0 if max_enemy_hp <= EPSILON else float(enemy["hp"]) / max_enemy_hp,
		"boss_time_left": float(enemy["time_left"]),
		"next_action": String(enemy["next_action"]),
		"unlocked_operator_count": unlocked_count,
		"unlocked_operator_ids": unlocked_operator_ids,
		"event_operator_id": "",
		"event_target_id": "",
		"event_source": "",
		"event_attack": "",
		"event_reason": "",
	}


func _visible_appeal_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event: Dictionary in _state.recent_events:
		var visible := _to_visible_appeal_event(event)
		if not visible.is_empty():
			events.append(visible)
	return events


func _to_visible_appeal_event(event: Dictionary) -> Dictionary:
	var trigger := &""
	var event_source := ""
	var event_attack := String(event.get("attack", ""))
	var event_reason := String(event.get("reason", ""))
	match StringName(String(event["kind"])):
		&"operator_down":
			trigger = &"operator_down"
		&"attempt_failed":
			trigger = &"boss_failure" if event_reason.begins_with("boss_") else &"normal_failure"
		&"qa_recovery_cancelled":
			trigger = &"qa_rescue_cancelled"
		&"operator_recovered":
			event_source = String(event.get("source", ""))
			if event_source == "qa":
				trigger = &"qa_rescue_succeeded"
		&"emergency_redeploy_requested":
			trigger = &"emergency_redeploy_used"
			event_source = "emergency"
		&"boss_rollback":
			trigger = &"watchdog_rollback"
			event_source = "watchdog"
		&"operator_damaged":
			if event_attack == "boss_special":
				trigger = &"watchdog_kill_signal"
		_:
			pass
	if trigger == &"":
		return {}
	var operator_id := String(event.get("operator_id", ""))
	var target_id := String(event.get("target_id", operator_id))
	return {
		"id": _appeal_event_id(event, trigger, operator_id, target_id),
		"trigger": String(trigger),
		"time": float(event["time"]),
		"stage": int(event["stage"]),
		"event_operator_id": operator_id,
		"event_target_id": target_id,
		"event_source": event_source,
		"event_attack": event_attack,
		"event_reason": event_reason,
	}


func _appeal_event_id(
	event: Dictionary,
	trigger: StringName,
	operator_id: String,
	target_id: String
) -> String:
	return "%d|%d|%.6f|%s|%s|%s|%s|%s" % [
		int(event["encounter_serial"]),
		int(event["stage"]),
		float(event["time"]),
		String(trigger),
		operator_id,
		target_id,
		String(event.get("source", "")),
		String(event.get("reason", event.get("attack", ""))),
	]


func _accept() -> bool:
	_last_error = ""
	return true


func _reject(message: String) -> bool:
	_last_error = message
	return false
