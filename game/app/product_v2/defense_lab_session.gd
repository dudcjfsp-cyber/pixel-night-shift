class_name DefenseLabSession
extends RefCounted

const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const ProductV2Loader := preload(
	"res://game/content/product_v2/product_v2_loader.gd"
)
const NightShiftState := preload(
	"res://game/domain/product_v2/night_shift_state.gd"
)
const NightShiftSimulator := preload(
	"res://game/domain/product_v2/night_shift_simulator.gd"
)
const NightShiftStateDto := preload(
	"res://game/app/product_v2/night_shift_state_dto.gd"
)

const DEFAULT_PRESET := &"first_two"
const PRESET_IDS: Array[StringName] = [&"first_two", &"full_team"]
const SAVE_KEYS: PackedStringArray = ["preset", "night_shift"]

var _catalog: ProductV2Catalog
var _state: NightShiftState
var _preset_id: StringName = DEFAULT_PRESET
var _last_error := ""


func _init(
	catalog_override: ProductV2Catalog = null,
	preset_id: StringName = DEFAULT_PRESET,
	shift_index: int = 0
) -> void:
	if catalog_override != null:
		_catalog = catalog_override
	else:
		var load_result := ProductV2Loader.load_default()
		assert(
			load_result.is_valid(),
			"Defense Lab content failed validation: %s" % "; ".join(load_result.errors)
		)
		_catalog = load_result.catalog
	assert(_catalog != null, "Defense Lab requires Product V2 content")
	assert(
		_restart_with_candidate(preset_id, shift_index),
		"Invalid Defense Lab initial preset or shift"
	)


func tick(delta_seconds: float) -> bool:
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		return _reject("경과 시간은 0 이상의 유한한 값이어야 합니다.")
	_last_error = ""
	NightShiftSimulator.advance(_state, _catalog, delta_seconds)
	return true


func restart(
	preset_id: StringName = DEFAULT_PRESET,
	shift_index: int = 0
) -> bool:
	return _restart_with_candidate(preset_id, shift_index)


func snapshot() -> Dictionary:
	var enemy_rows: Array[Dictionary] = []
	for enemy: NightShiftState.EnemyRuntime in _state.enemies:
		var archetype := _catalog.get_enemy(enemy.enemy_id)
		assert(archetype != null, "Defense Lab enemy runtime requires content")
		enemy_rows.append({
			"id": String(enemy.enemy_id),
			"name": archetype.display_name,
			"asset_id": String(archetype.asset_id),
			"hp": enemy.current_hp,
			"max_hp": enemy.max_hp,
			"leak_damage": enemy.leak_damage,
			"serial": enemy.serial,
			"alive": enemy.is_alive(),
		})

	var operator_rows: Array[Dictionary] = []
	for definition: OperatorDefinition in _catalog.base_catalog.operators:
		var runtime := _state.get_operator_combat_state(definition.id)
		assert(runtime != null, "Defense Lab snapshot requires every operator runtime")
		var unlocked := _state.unlocked_operator_ids.has(definition.id)
		var level := int(_state.operator_levels.get(definition.id, 0))
		var max_hp := (
			NightShiftSimulator.operator_max_hp(_state, _catalog, definition.id)
			if unlocked else 0.0
		)
		var attack_scheduled := runtime.is_active() and not is_inf(runtime.attack_remaining)
		operator_rows.append({
			"id": String(definition.id),
			"name": definition.display_name,
			"asset_id": String(definition.id),
			"role": definition.role_name,
			"ability": definition.ability_description,
			"level": level,
			"unlocked": unlocked,
			"hp": runtime.current_hp,
			"max_hp": max_hp,
			"dps": (
				NightShiftSimulator.operator_effective_dps(
					_state, _catalog, definition.id
				) if unlocked else 0.0
			),
			"down": unlocked and not runtime.is_active(),
			"attack": {
				"scheduled": attack_scheduled,
				"remaining": maxf(0.0, runtime.attack_remaining) if attack_scheduled else 0.0,
				"base_interval": definition.attack_interval,
			},
			"attack_remaining": (
				maxf(0.0, runtime.attack_remaining) if attack_scheduled else 0.0
			),
			"damage_dealt": runtime.damage_dealt,
			"damage_taken": runtime.damage_taken,
			"down_count": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		})

	var shift := _catalog.get_shift(_state.shift_index)
	assert(shift != null, "Defense Lab state requires known shift content")
	var boss_profile := shift.boss
	var recent_events: Array[Dictionary] = []
	for event: Dictionary in _state.recent_events:
		recent_events.append(_copy_dictionary_for_view(event))
	var down_rows: Array[Dictionary] = []
	for row: Dictionary in _state.operator_down_records:
		down_rows.append(_copy_dictionary_for_view(row))
	var star_thresholds: Array[int] = []
	for threshold: int in _catalog.balance.star_thresholds:
		star_thresholds.append(threshold)

	return {
		"prototype": "product_v2_defense_lab",
		"preset": String(_preset_id),
		"shift_index": _state.shift_index,
		"phase": _state.phase,
		"phase_name": _phase_name(_state.phase),
		"wave": _state.current_wave,
		"current_wave": _state.current_wave,
		"completed_waves": _state.completed_waves,
		"stars": _state.star_count(_catalog.balance.star_thresholds),
		"star_thresholds": star_thresholds,
		"stability": _state.stability,
		"max_stability": _catalog.balance.max_stability,
		"danger_stability": _catalog.balance.danger_stability,
		"timers": {
			"phase_remaining": _state.phase_remaining,
			"total_elapsed": _state.total_elapsed,
			"combat_elapsed": _state.combat_elapsed,
			"wave_elapsed": _state.wave_elapsed,
			"normal_wave_seconds": _catalog.balance.normal_wave_seconds,
			"boss_elapsed": _state.boss_elapsed,
			"boss_seconds": _catalog.balance.boss_seconds,
			"boss_time_left": maxf(
				0.0, _catalog.balance.boss_seconds - _state.boss_elapsed
			),
		},
		"enemies": enemy_rows,
		"operators": operator_rows,
		"boss": {
			"id": String(boss_profile.id),
			"name": boss_profile.display_name,
			"asset_id": String(boss_profile.asset_id),
			"active": _state.current_wave == 10,
			"hp": _state.boss_hp,
			"max_hp": _state.boss_max_hp,
			"time_limit": _catalog.balance.boss_seconds,
			"time_left": maxf(
				0.0, _catalog.balance.boss_seconds - _state.boss_elapsed
			),
			"poll_remaining": _visible_timer(_state.boss_poll_remaining),
			"special_remaining": _visible_timer(_state.boss_special_remaining),
			"rollback_remaining": _visible_timer(_state.boss_rollback_remaining),
			"debuff_applied": _state.boss_debuff_applied,
			"recovery_count": _state.boss_recovery_count,
			"recovered_health": _state.boss_recovered_health,
		},
		"next_wave": _next_wave_preview(),
		"recent_events": recent_events,
		"down_evidence": {
			"total_count": _state.total_operator_down_count,
			"total_time": _state.total_operator_down_time,
			"records": down_rows,
		},
		"qa_outcome": {
			"consumed": _state.qa_rescue_consumed,
			"pending_target_id": String(_state.qa_rescue_target_id),
			"remaining": _state.qa_rescue_remaining,
			"rescue_count": _state.qa_rescue_count,
			"outcome": String(_state.qa_rescue_outcome),
			"target_id": String(_state.qa_rescue_outcome_target_id),
			"reason": String(_state.qa_rescue_outcome_reason),
			"time": _state.qa_rescue_outcome_time,
		},
		"combat_metrics": {
			"enemies_defeated": _state.total_enemies_defeated,
			"enemies_leaked": _state.total_enemies_leaked,
			"leak_damage": _state.total_leak_damage,
			"largest_wave_leak_damage": _state.largest_wave_leak_damage,
			"last_wave_leak_damage": _state.last_wave_leak_damage,
		},
		"terminal": _state.is_terminal(),
		"success": _state.is_success(),
		"terminal_reason": String(_state.terminal_reason),
		"last_error": _last_error,
	}


func export_state() -> Dictionary:
	return {
		"preset": String(_preset_id),
		"night_shift": NightShiftStateDto.export_state(_state),
	}


func restore_state(data: Dictionary) -> PackedStringArray:
	var errors := _validate_restore_wrapper(data)
	if not errors.is_empty():
		return errors
	var preset_id := StringName(String(data["preset"]))
	if not PRESET_IDS.has(preset_id):
		errors.append("preset: unknown Defense Lab preset '%s'" % preset_id)
		return errors
	var restore_result := NightShiftStateDto.restore_candidate(
		data["night_shift"] as Dictionary, _catalog
	)
	for error_message: String in restore_result.errors:
		errors.append("night_shift: %s" % error_message)
	if not errors.is_empty():
		return errors
	assert(restore_result.state != null, "Validated Defense Lab restore requires a state")
	if not _candidate_matches_preset(restore_result.state, preset_id):
		errors.append("night_shift: loadout does not match preset '%s'" % preset_id)
		return errors
	_state = restore_result.state
	_preset_id = preset_id
	_last_error = ""
	return PackedStringArray()


func _restart_with_candidate(preset_id: StringName, shift_index: int) -> bool:
	if not PRESET_IDS.has(preset_id):
		return _reject("알 수 없는 Defense Lab 프리셋입니다: %s" % preset_id)
	var config := _preset_config(preset_id)
	var selected_shift := int(config["shift_index"]) if shift_index == 0 else shift_index
	if not _catalog.has_shift(selected_shift):
		return _reject("알 수 없는 Product V2 근무 차수입니다: %d" % selected_shift)
	var levels := (config["operator_levels"] as Dictionary).duplicate(true)
	var unlocked: Array[StringName] = []
	for raw_id: Variant in config["unlocked_operator_ids"] as Array:
		unlocked.append(StringName(String(raw_id)))
	var patches: Array[StringName] = []
	for raw_id: Variant in config["equipped_patch_ids"] as Array:
		patches.append(StringName(String(raw_id)))
	var candidate := NightShiftSimulator.create_state(
		_catalog,
		selected_shift,
		levels,
		unlocked,
		patches,
		int(config["legacy_cache_level"])
	)
	_state = candidate
	_preset_id = preset_id
	_last_error = ""
	return true


func _next_wave_preview() -> Dictionary:
	var next_number := 0
	match _state.phase:
		NightShiftState.Phase.COUNTDOWN:
			next_number = 1
		NightShiftState.Phase.NORMAL_ACTIVE:
			next_number = _state.current_wave + 1
		NightShiftState.Phase.INTER_WAVE:
			next_number = _state.completed_waves + 1
		NightShiftState.Phase.BOSS_WARNING:
			next_number = 10
		_:
			next_number = 0
	if next_number <= 0 or next_number > 10:
		return {"available": false}
	var shift := _catalog.get_shift(_state.shift_index)
	if next_number == 10:
		return {
			"available": true,
			"wave": 10,
			"is_boss": true,
			"id": String(shift.boss.id),
			"name": shift.boss.display_name,
			"asset_id": String(shift.boss.asset_id),
			"max_hp": shift.boss.max_hp,
		}
	var wave := shift.get_wave(next_number)
	assert(wave != null, "Defense Lab preview requires wave content")
	var modifiers := ProgressionRules.patch_modifiers(
		_state.equipped_patch_ids, _catalog.base_catalog
	)
	var rows: Array[Dictionary] = []
	var total_count := 0
	var total_leak_damage := 0
	for entry: ProductV2Catalog.WaveEntry in wave.entries:
		var archetype := _catalog.get_enemy(entry.enemy_id)
		assert(archetype != null, "Defense Lab preview enemy requires content")
		var hp := (
			archetype.base_hp
			* wave.hp_multiplier
			* shift.health_multiplier
			* float(modifiers.enemy_health)
		)
		rows.append({
			"id": String(archetype.id),
			"name": archetype.display_name,
			"asset_id": String(archetype.asset_id),
			"count": entry.count,
			"hp": hp,
			"leak_damage": archetype.leak_damage,
		})
		total_count += entry.count
		total_leak_damage += entry.count * archetype.leak_damage
	return {
		"available": true,
		"wave": next_number,
		"is_boss": false,
		"enemies": rows,
		"total_count": total_count,
		"potential_leak_damage": mini(
			total_leak_damage, _catalog.balance.wave_leak_cap
		),
	}


func _candidate_matches_preset(
	candidate: NightShiftState,
	preset_id: StringName
) -> bool:
	var config := _preset_config(preset_id)
	var expected_levels := config["operator_levels"] as Dictionary
	if candidate.operator_levels.size() != expected_levels.size():
		return false
	for raw_id: Variant in expected_levels.keys():
		var operator_id := StringName(String(raw_id))
		if int(candidate.operator_levels.get(operator_id, 0)) != int(expected_levels[raw_id]):
			return false
	var expected_unlocked: Array = config["unlocked_operator_ids"]
	if candidate.unlocked_operator_ids.size() != expected_unlocked.size():
		return false
	for index: int in range(expected_unlocked.size()):
		if candidate.unlocked_operator_ids[index] != expected_unlocked[index]:
			return false
	return (
		candidate.equipped_patch_ids.is_empty()
		and candidate.legacy_cache_level == int(config["legacy_cache_level"])
	)


func _validate_restore_wrapper(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in SAVE_KEYS:
		if not data.has(key):
			errors.append("%s: required Defense Lab state field is missing" % key)
	for raw_key: Variant in data.keys():
		if typeof(raw_key) != TYPE_STRING or not SAVE_KEYS.has(String(raw_key)):
			errors.append("%s: unexpected Defense Lab state field" % String(raw_key))
	if not errors.is_empty():
		return errors
	if typeof(data["preset"]) != TYPE_STRING or String(data["preset"]).is_empty():
		errors.append("preset must be a non-empty string")
	if typeof(data["night_shift"]) != TYPE_DICTIONARY:
		errors.append("night_shift must be an object")
	return errors


func _preset_config(preset_id: StringName) -> Dictionary:
	match preset_id:
		&"first_two":
			return {
				"shift_index": 1,
				"operator_levels": {
					&"debugger": 2,
					&"build_engineer": 2,
				},
				"unlocked_operator_ids": [&"debugger", &"build_engineer"],
				"equipped_patch_ids": [],
				"legacy_cache_level": 0,
			}
		&"full_team":
			return {
				"shift_index": 1,
				"operator_levels": {
					&"debugger": 3,
					&"build_engineer": 3,
					&"sprite_artist": 3,
					&"qa_imp": 3,
				},
				"unlocked_operator_ids": [
					&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
				],
				"equipped_patch_ids": [],
				"legacy_cache_level": 0,
			}
	assert(false, "Unknown Defense Lab preset")
	return {}


func _phase_name(phase: int) -> String:
	match phase:
		NightShiftState.Phase.COUNTDOWN:
			return "countdown"
		NightShiftState.Phase.NORMAL_ACTIVE:
			return "normal_active"
		NightShiftState.Phase.INTER_WAVE:
			return "inter_wave"
		NightShiftState.Phase.BOSS_WARNING:
			return "boss_warning"
		NightShiftState.Phase.BOSS_ACTIVE:
			return "boss_active"
		NightShiftState.Phase.SUCCESS:
			return "success"
		NightShiftState.Phase.FAILURE:
			return "failure"
	assert(false, "Unknown Product V2 phase: %d" % phase)
	return "unknown"


func _copy_dictionary_for_view(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in source.keys():
		var value: Variant = source[raw_key]
		result[String(raw_key)] = String(value) if value is StringName else value
	return result


func _visible_timer(value: float) -> float:
	return 0.0 if is_inf(value) else maxf(0.0, value)


func _reject(message: String) -> bool:
	_last_error = message
	return false
