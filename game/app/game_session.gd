class_name GameSession
extends RefCounted

const PROTOTYPE_MAX_STAGE := 20
const EQUIPPED_PATCH_SLOT_COUNT := 3
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const SAVE_COMPARISON_EPSILON := 0.000001
const SCHEMA_1_STATE_KEYS: PackedStringArray = [
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
const SAVE_STATE_KEYS: PackedStringArray = GameSessionStateDto.ROOT_KEYS
const BOSS_FAILURE_REASONS: PackedStringArray = [
	"",
	"boss_all_down",
	"boss_timeout",
]
const BOSS_EVENT_REQUIRED_KEYS: PackedStringArray = [
	"serial",
	"kind",
	"time",
	"stage",
	"attempt_serial",
]
const BOSS_EVENT_KINDS: PackedStringArray = [
	"boss_attempt_started",
	"boss_attempt_cleared",
	"boss_defeated",
	"boss_debuff_applied",
	"qa_rescue_succeeded",
	"boss_rollback",
	"boss_attack_missed",
	"operator_damaged",
	"operator_down",
	"qa_rescue_scheduled",
	"qa_rescue_cancelled",
	"boss_attempt_failed",
]
const BOSS_ATTACK_KINDS: PackedStringArray = [
	"boss_poll",
	"boss_special",
]
const QA_RESCUE_CANCEL_REASONS: PackedStringArray = [
	"attempt_cleared",
	"attempt_failed",
	"qa_process_down",
	"qa_unavailable",
]

var _catalog: ContentCatalog
var _state: GameState
var _last_error: String = ""
var _hybrid_boss_enabled := true


func _init(
	catalog_override: ContentCatalog = null,
	hybrid_boss_enabled: bool = true
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
	var diagnosis := get_diagnosis()
	var appeals: Array[Dictionary] = []
	if _hybrid_boss_enabled and not _state.can_prestige and (boss or _state.is_maintenance):
		appeals = HybridOperatorAppealRules.evaluate(
			diagnosis,
			_current_stage_boss_events(),
			operator_rows
		)
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
		"diagnosis": diagnosis,
		"appeals": appeals,
		"appeal_limit": HybridOperatorAppealRules.MAX_VISIBLE_APPEALS,
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
	if _hybrid_boss_enabled and ProgressionRules.is_boss_stage(_state.stage):
		return HybridBossDiagnosisRules.evaluate(_state, _catalog)
	return DiagnosisRules.evaluate(_state, _catalog)


func _current_stage_boss_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event: Dictionary in _state.recent_boss_events:
		if (
			int(event.get("stage", -1)) == _state.stage
			and int(event.get("attempt_serial", -1)) == _state.boss_attempt_serial
		):
			events.append(event.duplicate(true))
	return events


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
	return GameSessionStateDto.export_state(_state, _catalog)


func restore_state(data: Dictionary) -> PackedStringArray:
	var errors: Array[String] = []
	_validate_save_keys(data, SAVE_STATE_KEYS, errors)
	var candidate := _read_base_save_candidate(data, errors)
	_read_schema_2_combat_state(candidate, data, errors)

	if not errors.is_empty():
		return PackedStringArray(errors)

	_validate_save_candidate(candidate, errors)
	_validate_schema_2_combat_state(candidate, errors)
	if not errors.is_empty():
		return PackedStringArray(errors)

	_state = candidate
	_last_error = ""
	return PackedStringArray()


func restore_schema1_state(data: Dictionary) -> PackedStringArray:
	var errors: Array[String] = []
	_validate_save_keys(data, SCHEMA_1_STATE_KEYS, errors)
	var candidate := _read_base_save_candidate(data, errors)
	if not errors.is_empty():
		return PackedStringArray(errors)

	_validate_save_candidate(candidate, errors)
	if not errors.is_empty():
		return PackedStringArray(errors)

	if ProgressionRules.is_boss_stage(candidate.stage) and not candidate.can_prestige:
		_migrate_schema_1_boss_attempt(candidate)
	_validate_save_candidate(candidate, errors)
	_validate_schema_2_combat_state(candidate, errors)
	if not errors.is_empty():
		return PackedStringArray(errors)

	_state = candidate
	_last_error = ""
	return PackedStringArray()


func _read_base_save_candidate(
	data: Dictionary,
	errors: Array[String]
) -> GameState:
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
	return candidate


func _read_schema_2_combat_state(
	candidate: GameState,
	data: Dictionary,
	errors: Array[String]
) -> void:
	candidate.operator_combat_states = _read_operator_combat_states(data, errors)
	candidate.enemy_attack_remaining = _read_save_timer(
		data, "enemy_attack_remaining", errors
	)
	candidate.boss_special_remaining = _read_save_timer(
		data, "boss_special_remaining", errors
	)
	candidate.boss_rollback_remaining = _read_save_timer(
		data, "boss_rollback_remaining", errors
	)
	candidate.boss_attempt_serial = _read_save_int(
		data, "boss_attempt_serial", 0, -1, errors
	)
	candidate.last_boss_failure_reason = StringName(
		_read_save_string(data, "last_boss_failure_reason", true, errors)
	)
	candidate.qa_rescue_consumed = _read_save_bool(
		data, "qa_rescue_consumed", errors
	)
	candidate.qa_rescue_target_id = StringName(
		_read_save_string(data, "qa_rescue_target_id", true, errors)
	)
	candidate.qa_rescue_remaining = _read_save_float(
		data, "qa_rescue_remaining", 0.0, -1.0, errors
	)
	candidate.qa_rescue_count = _read_save_int(
		data, "qa_rescue_count", 0, -1, errors
	)
	candidate.boss_event_serial = _read_save_int(
		data, "boss_event_serial", 0, -1, errors
	)
	candidate.recent_boss_events = _read_recent_boss_events(data, errors)
	candidate.total_operator_down_count = _read_save_int(
		data, "total_operator_down_count", 0, -1, errors
	)
	candidate.total_operator_down_time = _read_save_float(
		data, "total_operator_down_time", 0.0, -1.0, errors
	)


func _migrate_schema_1_boss_attempt(candidate: GameState) -> void:
	candidate.is_maintenance = false
	candidate.maintenance_cycles_remaining = 0
	candidate.enemy_index = 1
	candidate.enemy_health = ProgressionRules.current_enemy_max_hp(candidate, _catalog)
	candidate.boss_elapsed = 0.0
	candidate.boss_recovery_count = 0
	candidate.boss_recovered_health = 0.0
	candidate.boss_debuff_applied = false
	candidate.operator_combat_states.clear()
	candidate.enemy_attack_remaining = INF
	candidate.boss_special_remaining = INF
	candidate.boss_rollback_remaining = INF
	candidate.boss_attempt_serial = 0
	candidate.last_boss_failure_reason = &""
	candidate.qa_rescue_consumed = false
	candidate.qa_rescue_target_id = &""
	candidate.qa_rescue_remaining = 0.0
	candidate.qa_rescue_count = 0
	candidate.boss_event_serial = 0
	candidate.recent_boss_events.clear()
	candidate.total_operator_down_count = 0
	candidate.total_operator_down_time = 0.0
	candidate.status_message = "저장 기록을 현재 보스 시도로 전환했습니다."
	if _hybrid_boss_enabled:
		candidate.boss_attempt_serial = 1
		HybridBossSimulator.reset_attempt(candidate, _catalog)


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


func _validate_save_keys(
	data: Dictionary,
	expected_keys: PackedStringArray,
	errors: Array[String]
) -> void:
	for key: String in expected_keys:
		if not data.has(key):
			errors.append("session.%s: required field is missing" % key)
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING:
			errors.append("session: save field names must be strings")
			continue
		var key := String(raw_key)
		if not expected_keys.has(key):
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


func _read_save_timer(
	data: Dictionary,
	key: String,
	errors: Array[String]
) -> float:
	if not data.has(key):
		return INF
	var value: Variant = data[key]
	if not GameSessionStateDto.is_timer_value(value):
		errors.append(
			"session.%s: null or a non-negative finite timer is required" % key
		)
		return INF
	return GameSessionStateDto.decode_timer(value)


func _read_operator_combat_states(
	data: Dictionary,
	errors: Array[String]
) -> Array[OperatorCombatState]:
	var result: Array[OperatorCombatState] = []
	if not data.has("operator_combat_states"):
		return result
	if typeof(data["operator_combat_states"]) != TYPE_ARRAY:
		errors.append("session.operator_combat_states: array is required")
		return result

	var rows := data["operator_combat_states"] as Array
	if not rows.is_empty() and rows.size() != _catalog.operators.size():
		errors.append(
			"session.operator_combat_states: must be empty or cover every operator"
		)
	for index: int in rows.size():
		var context := "session.operator_combat_states[%d]" % index
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("%s: object is required" % context)
			continue
		var row := rows[index] as Dictionary
		_validate_nested_keys(
			row, GameSessionStateDto.OPERATOR_RUNTIME_KEYS, context, errors
		)
		var operator_text := _read_nested_string(
			row, "operator_id", context, false, errors
		)
		var operator_id := StringName(operator_text)
		if not _catalog.has_operator(operator_id):
			errors.append("%s.operator_id: unknown operator id" % context)
		elif index >= _catalog.operators.size():
			errors.append("%s.operator_id: unexpected runtime row" % context)
		elif _catalog.operators[index].id != operator_id:
			errors.append("%s.operator_id: runtime order is not canonical" % context)

		var runtime := OperatorCombatState.new(operator_id)
		runtime.current_hp = _read_nested_float(
			row, "current_hp", context, errors
		)
		runtime.attack_remaining = _read_nested_timer(
			row, "attack_remaining", context, errors
		)
		runtime.damage_dealt = _read_nested_float(
			row, "damage_dealt", context, errors
		)
		runtime.damage_taken = _read_nested_float(
			row, "damage_taken", context, errors
		)
		runtime.down_count = _read_nested_int(
			row, "down_count", context, errors
		)
		runtime.active_time = _read_nested_float(
			row, "active_time", context, errors
		)
		runtime.down_time = _read_nested_float(
			row, "down_time", context, errors
		)
		result.append(runtime)
	return result


func _read_recent_boss_events(
	data: Dictionary,
	errors: Array[String]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not data.has("recent_boss_events"):
		return result
	if typeof(data["recent_boss_events"]) != TYPE_ARRAY:
		errors.append("session.recent_boss_events: array is required")
		return result

	var rows := data["recent_boss_events"] as Array
	if rows.size() > GameSessionStateDto.MAX_RECENT_BOSS_EVENTS:
		errors.append("session.recent_boss_events: bounded history exceeded")
	for index: int in rows.size():
		var context := "session.recent_boss_events[%d]" % index
		if typeof(rows[index]) != TYPE_DICTIONARY:
			errors.append("%s: object is required" % context)
			continue
		var source := rows[index] as Dictionary
		for key: String in BOSS_EVENT_REQUIRED_KEYS:
			if not source.has(key):
				errors.append("%s.%s: required field is missing" % [context, key])
		var event: Dictionary = {}
		for raw_key: Variant in source.keys():
			if typeof(raw_key) != TYPE_STRING:
				errors.append("%s: event field names must be strings" % context)
				continue
			var key := String(raw_key)
			var value: Variant = source[raw_key]
			if not _is_json_scalar(value):
				errors.append("%s.%s: finite JSON scalar is required" % [context, key])
				continue
			event[key] = value
		if source.has("serial"):
			event["serial"] = _read_nested_int(source, "serial", context, errors)
		if source.has("kind"):
			event["kind"] = _read_nested_string(source, "kind", context, false, errors)
		if source.has("time"):
			event["time"] = _read_nested_float(source, "time", context, errors)
		if source.has("stage"):
			event["stage"] = _read_nested_int(source, "stage", context, errors)
		if source.has("attempt_serial"):
			event["attempt_serial"] = _read_nested_int(
				source, "attempt_serial", context, errors
			)
		result.append(event)
	return result


func _validate_nested_keys(
	data: Dictionary,
	expected_keys: PackedStringArray,
	context: String,
	errors: Array[String]
) -> void:
	for key: String in expected_keys:
		if not data.has(key):
			errors.append("%s.%s: required field is missing" % [context, key])
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not expected_keys.has(String(raw_key)):
			errors.append("%s.%s: unexpected field" % [context, String(raw_key)])


func _read_nested_string(
	data: Dictionary,
	key: String,
	context: String,
	allow_empty: bool,
	errors: Array[String]
) -> String:
	if not data.has(key):
		return ""
	if typeof(data[key]) != TYPE_STRING:
		errors.append("%s.%s: string is required" % [context, key])
		return ""
	var value := String(data[key])
	if not allow_empty and value.is_empty():
		errors.append("%s.%s: non-empty string is required" % [context, key])
	return value


func _read_nested_float(
	data: Dictionary,
	key: String,
	context: String,
	errors: Array[String]
) -> float:
	if not data.has(key):
		return 0.0
	var value: Variant = data[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		errors.append("%s.%s: finite number is required" % [context, key])
		return 0.0
	var numeric := float(value)
	if numeric < 0.0:
		errors.append("%s.%s: non-negative number is required" % [context, key])
	return numeric


func _read_nested_int(
	data: Dictionary,
	key: String,
	context: String,
	errors: Array[String]
) -> int:
	if not data.has(key):
		return 0
	var value: Variant = data[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s.%s: non-negative integer is required" % [context, key])
		return 0
	var numeric := float(value)
	if (
		not is_finite(numeric)
		or floor(numeric) != numeric
		or numeric < 0.0
		or numeric > float(MAX_SAFE_JSON_INTEGER)
	):
		errors.append(
			"%s.%s: non-negative JSON-safe integer is required" % [context, key]
		)
		return 0
	return int(numeric)


func _read_nested_timer(
	data: Dictionary,
	key: String,
	context: String,
	errors: Array[String]
) -> float:
	if not data.has(key):
		return INF
	var value: Variant = data[key]
	if not GameSessionStateDto.is_timer_value(value):
		errors.append(
			"%s.%s: null or a non-negative finite timer is required"
			% [context, key]
		)
		return INF
	return GameSessionStateDto.decode_timer(value)


func _is_json_scalar(value: Variant) -> bool:
	if typeof(value) in [TYPE_STRING, TYPE_BOOL]:
		return true
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


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


func _validate_schema_2_combat_state(
	state: GameState,
	errors: Array[String]
) -> void:
	if not BOSS_FAILURE_REASONS.has(String(state.last_boss_failure_reason)):
		errors.append("session.last_boss_failure_reason: unknown failure reason")
	if (
		state.qa_rescue_target_id != &""
		and not _catalog.has_operator(state.qa_rescue_target_id)
	):
		errors.append("session.qa_rescue_target_id: unknown operator id")
	if state.qa_rescue_count > state.boss_attempt_serial:
		errors.append("session.qa_rescue_count: cannot exceed started boss attempts")

	var has_runtimes := not state.operator_combat_states.is_empty()
	if has_runtimes and state.operator_combat_states.size() != _catalog.operators.size():
		errors.append("session.operator_combat_states: incomplete runtime set")
	var seen_ids: Dictionary = {}
	var active_unlocked_count := 0
	var runtime_down_count := 0
	var runtime_down_time := 0.0
	for runtime: OperatorCombatState in state.operator_combat_states:
		if not _catalog.has_operator(runtime.operator_id):
			errors.append(
				"session.operator_combat_states: unknown operator '%s'"
				% runtime.operator_id
			)
			continue
		if seen_ids.has(runtime.operator_id):
			errors.append(
				"session.operator_combat_states: duplicate operator '%s'"
				% runtime.operator_id
			)
			continue
		seen_ids[runtime.operator_id] = true
		var unlocked := state.is_operator_unlocked(runtime.operator_id)
		var max_hp := HybridBossSimulator.operator_max_hp(
			state, _catalog, runtime.operator_id
		)
		if runtime.current_hp > max_hp + SAVE_COMPARISON_EPSILON:
			errors.append(
				"session.operator_combat_states.%s: HP exceeds current maximum"
				% runtime.operator_id
			)
		if not unlocked and runtime.current_hp > SAVE_COMPARISON_EPSILON:
			errors.append(
				"session.operator_combat_states.%s: locked operator cannot have HP"
				% runtime.operator_id
			)
		if unlocked and runtime.is_active():
			active_unlocked_count += 1
		runtime_down_count += runtime.down_count
		runtime_down_time += runtime.down_time

	if state.total_operator_down_count != runtime_down_count:
		errors.append(
			"session.total_operator_down_count: runtime counters are inconsistent"
		)
	if (
		absf(state.total_operator_down_time - runtime_down_time)
		> SAVE_COMPARISON_EPSILON
	):
		errors.append(
			"session.total_operator_down_time: runtime timers are inconsistent"
		)

	var active_boss := (
		ProgressionRules.is_boss_stage(state.stage)
		and not state.is_maintenance
		and not state.can_prestige
	)
	var hybrid_attempt := active_boss and has_runtimes
	if active_boss and _hybrid_boss_enabled and not has_runtimes:
		errors.append("session.operator_combat_states: active hybrid boss needs runtimes")
	if hybrid_attempt:
		if state.boss_attempt_serial < 1:
			errors.append("session.boss_attempt_serial: active boss needs an attempt")
		if active_unlocked_count < 1:
			errors.append("session.operator_combat_states: active boss cannot be all down")
		for pair: Array in [
			["enemy_attack_remaining", state.enemy_attack_remaining],
			["boss_special_remaining", state.boss_special_remaining],
			["boss_rollback_remaining", state.boss_rollback_remaining],
		]:
			if is_inf(float(pair[1])):
				errors.append("session.%s: active boss timer cannot be null" % pair[0])
		for runtime: OperatorCombatState in state.operator_combat_states:
			if runtime.is_active() and is_inf(runtime.attack_remaining):
				errors.append(
					"session.operator_combat_states.%s: active operator needs an attack timer"
					% runtime.operator_id
				)
			elif not runtime.is_active() and not is_inf(runtime.attack_remaining):
				errors.append(
					"session.operator_combat_states.%s: down operator timer must be null"
					% runtime.operator_id
				)
	else:
		for pair: Array in [
			["enemy_attack_remaining", state.enemy_attack_remaining],
			["boss_special_remaining", state.boss_special_remaining],
			["boss_rollback_remaining", state.boss_rollback_remaining],
		]:
			if not is_inf(float(pair[1])):
				errors.append("session.%s: inactive boss timer must be null" % pair[0])
		for runtime: OperatorCombatState in state.operator_combat_states:
			if not is_inf(runtime.attack_remaining):
				errors.append(
					"session.operator_combat_states.%s: inactive attack timer must be null"
					% runtime.operator_id
				)

	_validate_qa_rescue_save_state(state, hybrid_attempt, errors)
	_validate_boss_event_save_state(state, errors)
	if state.is_maintenance and state.last_boss_failure_reason == &"":
		errors.append("session.last_boss_failure_reason: maintenance needs a reason")


func _validate_qa_rescue_save_state(
	state: GameState,
	hybrid_attempt: bool,
	errors: Array[String]
) -> void:
	if state.qa_rescue_target_id == &"":
		if not is_zero_approx(state.qa_rescue_remaining):
			errors.append("session.qa_rescue_remaining: targetless rescue must be zero")
		return
	if not hybrid_attempt:
		errors.append("session.qa_rescue_target_id: rescue requires an active boss")
	if not state.qa_rescue_consumed:
		errors.append("session.qa_rescue_consumed: pending rescue must consume allowance")
	if state.qa_rescue_remaining <= 0.0:
		errors.append("session.qa_rescue_remaining: pending rescue needs positive time")
	var target := state.get_operator_combat_state(state.qa_rescue_target_id)
	if target == null:
		errors.append("session.qa_rescue_target_id: runtime target is missing")
	elif target.is_active():
		errors.append("session.qa_rescue_target_id: rescue target must be process-down")
	var qa_active := false
	for definition: OperatorDefinition in _catalog.operators:
		if not definition.qa_rescue_enabled:
			continue
		var qa_runtime := state.get_operator_combat_state(definition.id)
		qa_active = qa_runtime != null and qa_runtime.is_active()
		break
	if not qa_active:
		errors.append("session.qa_rescue_target_id: QA must be active")


func _validate_boss_event_save_state(
	state: GameState,
	errors: Array[String]
) -> void:
	if state.recent_boss_events.is_empty():
		if state.boss_event_serial != 0:
			errors.append("session.boss_event_serial: empty history must start at zero")
		return
	var previous_serial := 0
	for index: int in state.recent_boss_events.size():
		var event := state.recent_boss_events[index]
		if not event.has_all(BOSS_EVENT_REQUIRED_KEYS):
			continue
		var serial := int(event["serial"])
		var event_stage := int(event["stage"])
		var attempt_serial := int(event["attempt_serial"])
		var kind := String(event["kind"])
		if serial <= previous_serial:
			errors.append(
				"session.recent_boss_events[%d].serial: history must increase" % index
			)
		if event_stage not in [10, 20]:
			errors.append(
				"session.recent_boss_events[%d].stage: event requires a boss stage"
				% index
			)
		if attempt_serial < 1 or attempt_serial > state.boss_attempt_serial:
			errors.append(
				"session.recent_boss_events[%d].attempt_serial: invalid attempt"
				% index
			)
		if float(event["time"]) > _catalog.balance.boss_time_limit + SAVE_COMPARISON_EPSILON:
			errors.append(
				"session.recent_boss_events[%d].time: exceeds boss time limit" % index
			)
		if not BOSS_EVENT_KINDS.has(kind):
			errors.append(
				"session.recent_boss_events[%d].kind: unknown event kind" % index
			)
		else:
			_validate_boss_event_details(event, index, kind, errors)
		previous_serial = serial
	if previous_serial != state.boss_event_serial:
		errors.append("session.boss_event_serial: latest event serial is inconsistent")


func _validate_boss_event_details(
	event: Dictionary,
	index: int,
	kind: String,
	errors: Array[String]
) -> void:
	var detail_keys := _boss_event_detail_keys(kind)
	var context := "session.recent_boss_events[%d]" % index
	for key: String in detail_keys:
		if not event.has(key):
			errors.append("%s.%s: required field is missing" % [context, key])
	for raw_key: Variant in event.keys():
		var key := String(raw_key)
		if not BOSS_EVENT_REQUIRED_KEYS.has(key) and not detail_keys.has(key):
			errors.append("%s.%s: unexpected field" % [context, key])

	if "operator_id" in detail_keys and event.has("operator_id"):
		if typeof(event["operator_id"]) != TYPE_STRING:
			errors.append("%s.operator_id: string is required" % context)
		elif not _catalog.has_operator(StringName(String(event["operator_id"]))):
			errors.append("%s.operator_id: unknown operator" % context)
	if "attack" in detail_keys:
		_validate_event_enum(
			event, "attack", context, BOSS_ATTACK_KINDS, errors
		)
	if "reason" in detail_keys:
		var allowed_reasons := (
			QA_RESCUE_CANCEL_REASONS
			if kind == "qa_rescue_cancelled"
			else BOSS_FAILURE_REASONS
		)
		_validate_event_enum(event, "reason", context, allowed_reasons, errors)
		if kind == "boss_attempt_failed" and String(event.get("reason", "")).is_empty():
			errors.append("%s.reason: failure reason cannot be empty" % context)
	for numeric_key: String in ["multiplier", "hp", "healed", "damage", "delay"]:
		if numeric_key in detail_keys:
			_validate_event_number(event, numeric_key, context, errors)


func _boss_event_detail_keys(kind: String) -> PackedStringArray:
	match kind:
		"boss_debuff_applied":
			return PackedStringArray(["multiplier"])
		"qa_rescue_succeeded":
			return PackedStringArray(["operator_id", "hp"])
		"boss_rollback":
			return PackedStringArray(["healed"])
		"boss_attack_missed":
			return PackedStringArray(["attack"])
		"operator_damaged":
			return PackedStringArray(["operator_id", "attack", "damage"])
		"operator_down":
			return PackedStringArray(["operator_id", "attack"])
		"qa_rescue_scheduled":
			return PackedStringArray(["operator_id", "delay"])
		"qa_rescue_cancelled":
			return PackedStringArray(["operator_id", "reason"])
		"boss_attempt_failed":
			return PackedStringArray(["reason"])
	return PackedStringArray()


func _validate_event_enum(
	event: Dictionary,
	key: String,
	context: String,
	allowed: PackedStringArray,
	errors: Array[String]
) -> void:
	if not event.has(key):
		return
	if typeof(event[key]) != TYPE_STRING:
		errors.append("%s.%s: string is required" % [context, key])
		return
	if not allowed.has(String(event[key])):
		errors.append("%s.%s: unknown value" % [context, key])


func _validate_event_number(
	event: Dictionary,
	key: String,
	context: String,
	errors: Array[String]
) -> void:
	if not event.has(key):
		return
	var value: Variant = event[key]
	if (
		typeof(value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value))
		or float(value) < 0.0
	):
		errors.append("%s.%s: non-negative finite number is required" % [context, key])


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
