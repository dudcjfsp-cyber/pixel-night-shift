class_name GameSession
extends RefCounted

const PROTOTYPE_MAX_STAGE := 20
const EQUIPPED_PATCH_SLOT_COUNT := 3
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const SAVE_COMPARISON_EPSILON := 0.000001
const SAVE_STATE_KEYS: Array[String] = [
	"stage",
	"highest_stage",
	"bits",
	"patch_notes",
	"run_count",
	"legacy_cache_level",
	"operator_levels",
	"unlocked_operator_ids",
	"discovered_patch_ids",
	"equipped_patch_ids",
	"unlocked_patch_slots",
	"enemy_index",
	"enemy_health",
	"boss_elapsed",
	"boss_recovery_count",
	"boss_recovered_health",
	"boss_debuff_applied",
	"boss_failure_count",
	"is_maintenance",
	"maintenance_cycles_remaining",
	"can_prestige",
	"free_patch_swaps",
	"status_message",
]

var _catalog: ContentCatalog
var _state: GameState
var _last_error: String = ""
var _hybrid_boss_enabled := false


func _init(
	catalog_override: ContentCatalog = null,
	hybrid_boss_enabled: bool = false
) -> void:
	_hybrid_boss_enabled = hybrid_boss_enabled
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
	BattleSimulator.advance(_state, _catalog, delta_seconds, _hybrid_boss_enabled)


func upgrade_operator(operator_id: StringName) -> bool:
	if not _catalog.has_operator(operator_id):
		return _reject("존재하지 않는 요원입니다.")
	if not _state.is_operator_unlocked(operator_id):
		return _reject("아직 해금되지 않은 요원입니다.")
	var definition := _catalog.get_operator(operator_id)
	var level := int(_state.operator_levels.get(operator_id, 0))
	var runtime := _state.get_operator_combat_state(operator_id)
	var hybrid_boss_active := (
		_hybrid_boss_enabled
		and ProgressionRules.is_boss_stage(_state.stage)
		and not _state.is_maintenance
	)
	var previous_hp_ratio := 0.0
	if hybrid_boss_active and runtime != null and runtime.is_active():
		var previous_max_hp := HybridBossSimulator.operator_max_hp(
			_state, _catalog, operator_id
		)
		if previous_max_hp > SAVE_COMPARISON_EPSILON:
			previous_hp_ratio = clampf(runtime.current_hp / previous_max_hp, 0.0, 1.0)
	var cost := ProgressionRules.operator_upgrade_cost(
		level, definition.base_cost, definition.cost_growth
	)
	if _state.bits + 0.000001 < cost:
		return _reject("비트가 부족합니다.")
	_state.bits = maxf(0.0, _state.bits - cost)
	_state.operator_levels[operator_id] = level + 1
	if hybrid_boss_active and runtime != null and runtime.is_active():
		runtime.current_hp = (
			HybridBossSimulator.operator_max_hp(_state, _catalog, operator_id)
			* previous_hp_ratio
		)
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
	_state.operator_combat_states.clear()
	_state.enemy_attack_remaining = INF
	_state.boss_special_remaining = INF
	_state.boss_rollback_remaining = INF
	_state.boss_attempt_serial = 0
	_state.last_boss_failure_reason = &""
	_state.qa_rescue_consumed = false
	_state.qa_rescue_target_id = &""
	_state.qa_rescue_remaining = 0.0
	_state.qa_rescue_count = 0
	_state.boss_event_serial = 0
	_state.recent_boss_events.clear()
	_state.total_operator_down_count = 0
	_state.total_operator_down_time = 0.0
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
		var runtime := _state.get_operator_combat_state(definition.id)
		var max_operator_hp := 0.0
		if boss and _hybrid_boss_enabled and runtime != null and _state.is_operator_unlocked(definition.id):
			max_operator_hp = HybridBossSimulator.operator_max_hp(
				_state, _catalog, definition.id
			)
		operator_rows.append({
			"id": String(definition.id),
			"name": definition.display_name,
			"role": definition.role_name,
			"level": level,
			"unlocked": _state.is_operator_unlocked(definition.id),
			"dps": ProgressionRules.operator_dps(definition, level),
			"effective_dps": (
				HybridBossSimulator.operator_effective_dps(_state, _catalog, definition.id)
				if boss and _hybrid_boss_enabled and runtime != null
				else ProgressionRules.operator_dps(definition, level)
			),
			"hp": runtime.current_hp if boss and _hybrid_boss_enabled and runtime != null else 0.0,
			"max_hp": max_operator_hp,
			"down": boss and _hybrid_boss_enabled and runtime != null and _state.is_operator_unlocked(definition.id) and not runtime.is_active(),
			"process_down": boss and _hybrid_boss_enabled and runtime != null and _state.is_operator_unlocked(definition.id) and not runtime.is_active(),
			"attack_remaining": runtime.attack_remaining if boss and _hybrid_boss_enabled and runtime != null else INF,
			"damage_dealt": runtime.damage_dealt if runtime != null else 0.0,
			"damage_taken": runtime.damage_taken if runtime != null else 0.0,
			"down_count": runtime.down_count if runtime != null else 0,
			"active_time": runtime.active_time if runtime != null else 0.0,
			"down_time": runtime.down_time if runtime != null else 0.0,
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

	var next_action := {"label": "", "seconds": 0.0}
	if boss and _hybrid_boss_enabled:
		next_action = HybridBossSimulator.next_action(_state)
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
			"next_action": String(next_action["label"]),
			"next_action_in": float(next_action["seconds"]),
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
		"hybrid_combat_enabled": _hybrid_boss_enabled,
		"boss_failure_count": _state.boss_failure_count,
		"last_failure_reason": String(_state.last_boss_failure_reason),
		"qa_rescue": {
			"available": boss and not _state.qa_rescue_consumed,
			"pending": _state.qa_rescue_target_id != &"",
			"target_id": String(_state.qa_rescue_target_id),
			"remaining": _state.qa_rescue_remaining,
			"count": _state.qa_rescue_count,
		},
		"recent_boss_events": _state.recent_boss_events.duplicate(true),
		"combat_v2_test_mode": false,
		"combat_v2_complete": false,
		"offline_progress_supported": true,
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


func export_state() -> Dictionary:
	var operator_levels: Dictionary = {}
	for definition: OperatorDefinition in _catalog.operators:
		operator_levels[String(definition.id)] = int(
			_state.operator_levels.get(definition.id, 0)
		)

	var unlocked_operator_ids: Array[String] = []
	for operator_id: StringName in _state.unlocked_operator_ids:
		unlocked_operator_ids.append(String(operator_id))
	var discovered_patch_ids: Array[String] = []
	for patch_id: StringName in _state.discovered_patch_ids:
		discovered_patch_ids.append(String(patch_id))
	var equipped_patch_ids: Array[String] = []
	for patch_id: StringName in _state.equipped_patch_ids:
		equipped_patch_ids.append(String(patch_id))

	return {
		"stage": _state.stage,
		"highest_stage": _state.highest_stage,
		"bits": _state.bits,
		"patch_notes": _state.patch_notes,
		"run_count": _state.run_count,
		"legacy_cache_level": _state.legacy_cache_level,
		"operator_levels": operator_levels,
		"unlocked_operator_ids": unlocked_operator_ids,
		"discovered_patch_ids": discovered_patch_ids,
		"equipped_patch_ids": equipped_patch_ids,
		"unlocked_patch_slots": _state.unlocked_patch_slots,
		"enemy_index": _state.enemy_index,
		"enemy_health": _state.enemy_health,
		"boss_elapsed": _state.boss_elapsed,
		"boss_recovery_count": _state.boss_recovery_count,
		"boss_recovered_health": _state.boss_recovered_health,
		"boss_debuff_applied": _state.boss_debuff_applied,
		"boss_failure_count": _state.boss_failure_count,
		"is_maintenance": _state.is_maintenance,
		"maintenance_cycles_remaining": _state.maintenance_cycles_remaining,
		"can_prestige": _state.can_prestige,
		"free_patch_swaps": _state.free_patch_swaps,
		"status_message": _state.status_message,
	}


func restore_state(data: Dictionary) -> PackedStringArray:
	var errors: Array[String] = []
	_validate_save_keys(data, errors)

	var candidate := GameState.new()
	candidate.stage = _read_save_int(
		data, "stage", 1, PROTOTYPE_MAX_STAGE, errors
	)
	candidate.highest_stage = _read_save_int(
		data, "highest_stage", 1, PROTOTYPE_MAX_STAGE, errors
	)
	candidate.bits = _read_save_float(data, "bits", 0.0, -1.0, errors)
	candidate.patch_notes = _read_save_int(data, "patch_notes", 0, -1, errors)
	candidate.run_count = _read_save_int(data, "run_count", 0, -1, errors)
	candidate.legacy_cache_level = _read_save_int(
		data,
		"legacy_cache_level",
		0,
		_catalog.balance.max_legacy_cache_level,
		errors
	)
	candidate.operator_levels = _read_operator_levels(data, errors)
	candidate.unlocked_operator_ids = _read_unlocked_operator_ids(data, errors)
	candidate.discovered_patch_ids = _read_discovered_patch_ids(data, errors)
	candidate.equipped_patch_ids = _read_equipped_patch_ids(data, errors)
	candidate.unlocked_patch_slots = _read_save_int(
		data, "unlocked_patch_slots", 0, EQUIPPED_PATCH_SLOT_COUNT, errors
	)
	candidate.enemy_index = _read_save_int(
		data, "enemy_index", 1, _catalog.balance.normal_enemy_count, errors
	)
	candidate.enemy_health = _read_save_float(
		data, "enemy_health", 0.0, -1.0, errors
	)
	candidate.boss_elapsed = _read_save_float(
		data, "boss_elapsed", 0.0, _catalog.balance.boss_time_limit, errors
	)
	candidate.boss_recovery_count = _read_save_int(
		data, "boss_recovery_count", 0, -1, errors
	)
	candidate.boss_recovered_health = _read_save_float(
		data, "boss_recovered_health", 0.0, -1.0, errors
	)
	candidate.boss_debuff_applied = _read_save_bool(
		data, "boss_debuff_applied", errors
	)
	candidate.boss_failure_count = _read_save_int(
		data, "boss_failure_count", 0, -1, errors
	)
	candidate.is_maintenance = _read_save_bool(data, "is_maintenance", errors)
	candidate.maintenance_cycles_remaining = _read_save_int(
		data,
		"maintenance_cycles_remaining",
		0,
		_catalog.balance.maintenance_cycles,
		errors
	)
	candidate.can_prestige = _read_save_bool(data, "can_prestige", errors)
	candidate.free_patch_swaps = _read_save_int(
		data, "free_patch_swaps", 0, 1, errors
	)
	candidate.status_message = _read_save_string(
		data, "status_message", false, errors
	)

	if not errors.is_empty():
		return PackedStringArray(errors)

	_validate_save_candidate(candidate, errors)
	if not errors.is_empty():
		return PackedStringArray(errors)

	_state = candidate
	_last_error = ""
	return PackedStringArray()


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


func _validate_save_keys(data: Dictionary, errors: Array[String]) -> void:
	for key: String in SAVE_STATE_KEYS:
		if not data.has(key):
			errors.append("session.%s: required field is missing" % key)
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING:
			errors.append("session: save field names must be strings")
			continue
		var key := String(raw_key)
		if not SAVE_STATE_KEYS.has(key):
			errors.append("session.%s: unexpected field" % key)


func _read_save_int(
	data: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	errors: Array[String]
) -> int:
	if not data.has(key):
		return minimum
	var raw_value: Variant = data[key]
	if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
		errors.append("session.%s: integer is required" % key)
		return minimum
	var numeric_value := float(raw_value)
	if (
		not is_finite(numeric_value)
		or floor(numeric_value) != numeric_value
		or numeric_value > float(MAX_SAFE_JSON_INTEGER)
	):
		errors.append("session.%s: JSON-safe integer is required" % key)
		return minimum
	var value := int(numeric_value)
	if value < minimum or (maximum >= minimum and value > maximum):
		var range_text := "%d or greater" % minimum
		if maximum >= minimum:
			range_text = "%d..%d" % [minimum, maximum]
		errors.append("session.%s: value must be within %s" % [key, range_text])
	return value


func _read_save_float(
	data: Dictionary,
	key: String,
	minimum: float,
	maximum: float,
	errors: Array[String]
) -> float:
	if not data.has(key):
		return minimum
	var raw_value: Variant = data[key]
	if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
		errors.append("session.%s: finite number is required" % key)
		return minimum
	var value := float(raw_value)
	if not is_finite(value):
		errors.append("session.%s: finite number is required" % key)
		return minimum
	if value < minimum or (maximum >= minimum and value > maximum):
		var range_text := "%s or greater" % minimum
		if maximum >= minimum:
			range_text = "%s..%s" % [minimum, maximum]
		errors.append("session.%s: value must be within %s" % [key, range_text])
	return value


func _read_save_bool(
	data: Dictionary,
	key: String,
	errors: Array[String]
) -> bool:
	if not data.has(key):
		return false
	if typeof(data[key]) != TYPE_BOOL:
		errors.append("session.%s: boolean is required" % key)
		return false
	return bool(data[key])


func _read_save_string(
	data: Dictionary,
	key: String,
	allow_empty: bool,
	errors: Array[String]
) -> String:
	if not data.has(key):
		return ""
	if typeof(data[key]) != TYPE_STRING:
		errors.append("session.%s: string is required" % key)
		return ""
	var value := String(data[key])
	if not allow_empty and value.strip_edges().is_empty():
		errors.append("session.%s: non-empty string is required" % key)
	return value


func _read_operator_levels(data: Dictionary, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if not data.has("operator_levels"):
		return result
	if typeof(data["operator_levels"]) != TYPE_DICTIONARY:
		errors.append("session.operator_levels: object is required")
		return result

	var raw_levels := data["operator_levels"] as Dictionary
	var seen_ids: Dictionary = {}
	for raw_key: Variant in raw_levels.keys():
		if typeof(raw_key) != TYPE_STRING:
			errors.append("session.operator_levels: operator ids must be strings")
			continue
		var operator_text := String(raw_key)
		var operator_id := StringName(operator_text)
		if not _catalog.has_operator(operator_id):
			errors.append(
				"session.operator_levels.%s: unknown operator id" % operator_text
			)
			continue
		seen_ids[operator_text] = true
		var raw_level: Variant = raw_levels[raw_key]
		if typeof(raw_level) != TYPE_INT and typeof(raw_level) != TYPE_FLOAT:
			errors.append(
				"session.operator_levels.%s: non-negative integer is required"
				% operator_text
			)
			continue
		var numeric_level := float(raw_level)
		if (
			not is_finite(numeric_level)
			or floor(numeric_level) != numeric_level
			or numeric_level < 0.0
			or numeric_level > float(MAX_SAFE_JSON_INTEGER)
		):
			errors.append(
				"session.operator_levels.%s: non-negative JSON-safe integer is required"
				% operator_text
			)
			continue
		var level := int(numeric_level)
		result[operator_id] = level

	for definition: OperatorDefinition in _catalog.operators:
		var operator_text := String(definition.id)
		if not seen_ids.has(operator_text):
			errors.append(
				"session.operator_levels.%s: required operator is missing"
				% operator_text
			)
	return result


func _read_unlocked_operator_ids(
	data: Dictionary,
	errors: Array[String]
) -> Array[StringName]:
	var result: Array[StringName] = []
	if not data.has("unlocked_operator_ids"):
		return result
	if typeof(data["unlocked_operator_ids"]) != TYPE_ARRAY:
		errors.append("session.unlocked_operator_ids: array is required")
		return result

	var seen_ids: Dictionary = {}
	for index: int in (data["unlocked_operator_ids"] as Array).size():
		var raw_id: Variant = (data["unlocked_operator_ids"] as Array)[index]
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty():
			errors.append(
				"session.unlocked_operator_ids[%d]: non-empty string is required"
				% index
			)
			continue
		var operator_text := String(raw_id)
		var operator_id := StringName(operator_text)
		if not _catalog.has_operator(operator_id):
			errors.append(
				"session.unlocked_operator_ids[%d]: unknown operator id '%s'"
				% [index, operator_text]
			)
			continue
		if seen_ids.has(operator_text):
			errors.append(
				"session.unlocked_operator_ids[%d]: duplicate operator id '%s'"
				% [index, operator_text]
			)
			continue
		seen_ids[operator_text] = true
		result.append(operator_id)
	return result


func _read_discovered_patch_ids(
	data: Dictionary,
	errors: Array[String]
) -> Array[StringName]:
	var result: Array[StringName] = []
	if not data.has("discovered_patch_ids"):
		return result
	if typeof(data["discovered_patch_ids"]) != TYPE_ARRAY:
		errors.append("session.discovered_patch_ids: array is required")
		return result

	var seen_ids: Dictionary = {}
	for index: int in (data["discovered_patch_ids"] as Array).size():
		var raw_id: Variant = (data["discovered_patch_ids"] as Array)[index]
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty():
			errors.append(
				"session.discovered_patch_ids[%d]: non-empty string is required"
				% index
			)
			continue
		var patch_text := String(raw_id)
		var patch_id := StringName(patch_text)
		if not _catalog.has_patch(patch_id):
			errors.append(
				"session.discovered_patch_ids[%d]: unknown patch id '%s'"
				% [index, patch_text]
			)
			continue
		if seen_ids.has(patch_text):
			errors.append(
				"session.discovered_patch_ids[%d]: duplicate patch id '%s'"
				% [index, patch_text]
			)
			continue
		seen_ids[patch_text] = true
		result.append(patch_id)
	return result


func _read_equipped_patch_ids(
	data: Dictionary,
	errors: Array[String]
) -> Array[StringName]:
	var result: Array[StringName] = []
	if not data.has("equipped_patch_ids"):
		return result
	if typeof(data["equipped_patch_ids"]) != TYPE_ARRAY:
		errors.append("session.equipped_patch_ids: array is required")
		return result

	var raw_ids := data["equipped_patch_ids"] as Array
	if raw_ids.size() != EQUIPPED_PATCH_SLOT_COUNT:
		errors.append(
			"session.equipped_patch_ids: exactly %d slots are required"
			% EQUIPPED_PATCH_SLOT_COUNT
		)
	var seen_ids: Dictionary = {}
	for index: int in raw_ids.size():
		var raw_id: Variant = raw_ids[index]
		if typeof(raw_id) != TYPE_STRING:
			errors.append(
				"session.equipped_patch_ids[%d]: string is required" % index
			)
			continue
		var patch_text := String(raw_id)
		if patch_text.is_empty():
			result.append(&"")
			continue
		var patch_id := StringName(patch_text)
		if not _catalog.has_patch(patch_id):
			errors.append(
				"session.equipped_patch_ids[%d]: unknown patch id '%s'"
				% [index, patch_text]
			)
			continue
		if seen_ids.has(patch_text):
			errors.append(
				"session.equipped_patch_ids[%d]: duplicate patch id '%s'"
				% [index, patch_text]
			)
			continue
		seen_ids[patch_text] = true
		result.append(patch_id)
	return result


func _validate_save_candidate(state: GameState, errors: Array[String]) -> void:
	_validate_progression_save_state(state, errors)
	_validate_equipped_patch_save_state(state, errors)
	_validate_combat_save_state(state, errors)


func _validate_progression_save_state(
	state: GameState,
	errors: Array[String]
) -> void:
	if state.highest_stage < state.stage:
		errors.append("session.highest_stage: cannot be lower than current stage")
	if state.run_count == 0 and state.highest_stage != state.stage:
		errors.append(
			"session.highest_stage: first-run highest stage must equal current stage"
		)
	if state.run_count > 0 and state.highest_stage != PROTOTYPE_MAX_STAGE:
		errors.append(
			"session.highest_stage: a later run requires a completed stage 20"
		)

	var expected_patch_notes := (
		state.run_count
		- state.legacy_cache_level * _catalog.balance.legacy_cache_cost
	)
	if state.patch_notes != expected_patch_notes:
		errors.append(
			"session.patch_notes: value is inconsistent with runs and legacy cache"
		)

	for definition: OperatorDefinition in _catalog.operators:
		var should_be_unlocked := (
			state.run_count > 0 or state.stage >= definition.unlock_stage
		)
		var is_unlocked := state.unlocked_operator_ids.has(definition.id)
		if is_unlocked != should_be_unlocked:
			errors.append(
				"session.unlocked_operator_ids: '%s' has an inconsistent unlock state"
				% definition.id
			)
		var level := int(state.operator_levels[definition.id])
		if (is_unlocked and level < 1) or (not is_unlocked and level != 0):
			errors.append(
				"session.operator_levels.%s: level is inconsistent with unlock state"
				% definition.id
			)
		var dps := ProgressionRules.operator_dps(definition, level)
		var upgrade_cost := ProgressionRules.operator_upgrade_cost(
			level, definition.base_cost, definition.cost_growth
		)
		if not is_finite(dps) or not is_finite(upgrade_cost):
			errors.append(
				"session.operator_levels.%s: derived values must remain finite"
				% definition.id
			)

	for definition: PatchDefinition in _catalog.patches:
		var should_be_discovered := state.highest_stage >= definition.unlock_stage
		if state.discovered_patch_ids.has(definition.id) != should_be_discovered:
			errors.append(
				"session.discovered_patch_ids: '%s' has an inconsistent discovery state"
				% definition.id
			)

	var expected_unlocked_slots := 0
	for unlock_stage: int in _catalog.balance.patch_slot_unlock_stages:
		if state.highest_stage >= unlock_stage:
			expected_unlocked_slots += 1
	if state.unlocked_patch_slots != expected_unlocked_slots:
		errors.append(
			"session.unlocked_patch_slots: value is inconsistent with highest stage"
		)


func _validate_equipped_patch_save_state(
	state: GameState,
	errors: Array[String]
) -> void:
	for slot_index: int in state.equipped_patch_ids.size():
		var patch_id := state.equipped_patch_ids[slot_index]
		if slot_index >= state.unlocked_patch_slots and patch_id != &"":
			errors.append(
				"session.equipped_patch_ids[%d]: locked slots must be empty"
				% slot_index
			)
		if patch_id != &"" and not state.discovered_patch_ids.has(patch_id):
			errors.append(
				"session.equipped_patch_ids[%d]: patch must be discovered"
				% slot_index
			)


func _validate_combat_save_state(state: GameState, errors: Array[String]) -> void:
	var is_boss_stage := ProgressionRules.is_boss_stage(state.stage)
	if state.is_maintenance:
		if not is_boss_stage:
			errors.append("session.is_maintenance: maintenance requires a boss stage")
		if state.maintenance_cycles_remaining < 1:
			errors.append(
				"session.maintenance_cycles_remaining: active maintenance needs a cycle"
			)
		if state.boss_failure_count < 1:
			errors.append(
				"session.boss_failure_count: maintenance requires a boss failure"
			)
		if state.can_prestige:
			errors.append("session.can_prestige: maintenance cannot be complete")
	elif state.maintenance_cycles_remaining != 0:
		errors.append(
			"session.maintenance_cycles_remaining: inactive maintenance must be zero"
		)

	if state.can_prestige:
		if state.stage != PROTOTYPE_MAX_STAGE:
			errors.append("session.can_prestige: only stage 20 can be complete")
		if not is_zero_approx(state.enemy_health):
			errors.append("session.enemy_health: completed stage 20 must have zero health")
	elif state.enemy_health <= 0.0:
		errors.append("session.enemy_health: active combat requires positive health")

	if is_boss_stage and not state.is_maintenance and state.enemy_index != 1:
		errors.append("session.enemy_index: active boss stages use enemy index 1")
	if not is_boss_stage:
		if not is_zero_approx(state.boss_elapsed):
			errors.append("session.boss_elapsed: non-boss stages must reset boss time")
		if state.boss_recovery_count != 0:
			errors.append(
				"session.boss_recovery_count: non-boss stages must reset recoveries"
			)
		if not is_zero_approx(state.boss_recovered_health):
			errors.append(
				"session.boss_recovered_health: non-boss stages must reset recovery"
			)
		if state.boss_debuff_applied:
			errors.append("session.boss_debuff_applied: non-boss stage cannot be debuffed")

	if state.stage != PROTOTYPE_MAX_STAGE and state.boss_debuff_applied:
		errors.append("session.boss_debuff_applied: only stage 20 uses the debuff")
	if (
		state.boss_debuff_applied
		and state.boss_elapsed + SAVE_COMPARISON_EPSILON
		< _catalog.balance.stage_20_debuff_time
	):
		errors.append(
			"session.boss_debuff_applied: debuff cannot precede its trigger time"
		)
	if state.boss_recovered_health > 0.0 and state.boss_recovery_count == 0:
		errors.append(
			"session.boss_recovered_health: recovered health requires a recovery event"
		)
	if state.free_patch_swaps > 0 and state.boss_failure_count == 0:
		errors.append("session.free_patch_swaps: free swaps require a boss failure")

	var max_health := ProgressionRules.current_enemy_max_hp(state, _catalog)
	if not is_finite(max_health) or max_health <= 0.0:
		errors.append("session: current enemy maximum health must remain finite")
	elif state.enemy_health > max_health + SAVE_COMPARISON_EPSILON:
		errors.append("session.enemy_health: value exceeds current maximum health")
	var total_dps := ProgressionRules.total_dps(state, _catalog)
	if not is_finite(total_dps):
		errors.append("session.operator_levels: total damage must remain finite")
