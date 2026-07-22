class_name CombatV2Forecast
extends RefCounted

const MAX_FORECAST_SECONDS := 30.0
const EPSILON := 0.000001


static func estimate(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	patch_ids_override: Variant = null
) -> Dictionary:
	assert(state != null, "Combat V2 forecast requires a state")
	assert(catalog != null and catalog.base_catalog != null, "Combat V2 forecast requires a catalog")

	var forecast_state: CombatV2State = state.deep_clone()
	if patch_ids_override != null:
		_apply_patch_override(forecast_state, catalog, patch_ids_override)

	var initial_encounter_serial := forecast_state.encounter_serial
	var initial_stage := forecast_state.progression.stage
	var initial_enemy_index := forecast_state.progression.enemy_index
	var initial_maintenance := forecast_state.progression.is_maintenance
	var initial_elapsed := forecast_state.total_elapsed
	var initial_bits := forecast_state.progression.bits
	var initial_boss_healed := forecast_state.total_boss_healed
	var initial_downs := forecast_state.total_down_count
	var initial_damage_taken := forecast_state.total_damage_taken
	var initial_failures := forecast_state.total_failure_count()
	var initial_normal_failures := forecast_state.normal_failure_count
	var initial_boss_failures := forecast_state.progression.boss_failure_count
	var initial_qa_rescues := forecast_state.qa_rescue_count
	var initial_paid_redeploys := forecast_state.paid_redeploy_count
	var initial_emergency_spent := forecast_state.emergency_spent_bits
	var initial_active_time := _total_active_time(forecast_state)
	var observed_operator_count := CombatV2Simulator.unlocked_operator_count(forecast_state)

	CombatV2Simulator.advance(
		forecast_state,
		catalog,
		MAX_FORECAST_SECONDS,
		true
	)

	var seconds: float = forecast_state.total_elapsed - initial_elapsed
	var encounter_changed := forecast_state.encounter_serial != initial_encounter_serial
	var active_time := _total_active_time(forecast_state) - initial_active_time
	var uptime := _uptime(
		active_time,
		seconds,
		observed_operator_count,
		forecast_state
	)
	return {
		"resolved": _was_resolved(
			forecast_state,
			catalog,
			initial_stage,
			initial_enemy_index,
			initial_maintenance,
			encounter_changed
		),
		"seconds": seconds,
		"downs": forecast_state.total_down_count - initial_downs,
		"ending_down_count": (
			CombatV2Simulator.unlocked_operator_count(forecast_state)
			- CombatV2Simulator.active_operator_count(forecast_state)
		),
		"damage_taken": forecast_state.total_damage_taken - initial_damage_taken,
		"uptime": uptime,
		"boss_healed": forecast_state.total_boss_healed - initial_boss_healed,
		"bits_earned": forecast_state.progression.bits - initial_bits,
		"failures": forecast_state.total_failure_count() - initial_failures,
		"normal_failures": forecast_state.normal_failure_count - initial_normal_failures,
		"boss_failures": (
			forecast_state.progression.boss_failure_count - initial_boss_failures
		),
		"qa_rescues": forecast_state.qa_rescue_count - initial_qa_rescues,
		"paid_redeploys": forecast_state.paid_redeploy_count - initial_paid_redeploys,
		"emergency_spent_bits": (
			forecast_state.emergency_spent_bits - initial_emergency_spent
		),
		"maintenance": forecast_state.progression.is_maintenance,
		"maintenance_remaining": forecast_state.maintenance_remaining,
		"last_failure_reason": String(forecast_state.last_failure_reason),
		"encounter_changed": encounter_changed,
	}


static func enemy_max_hp(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	patch_ids_override: Variant = null
) -> float:
	var patch_ids: Array[StringName] = state.progression.equipped_patch_ids
	if patch_ids_override != null:
		patch_ids = _validated_patch_ids(patch_ids_override, catalog)
	# Maintenance preserves the failed stage and its enemy HP for the retry.
	var combat_stage := state.progression.stage
	var is_boss := (
		combat_stage <= catalog.balance.max_stage
		and ProgressionRules.is_boss_stage(combat_stage)
	)
	var modifiers := ProgressionRules.patch_modifiers(patch_ids, catalog.base_catalog)
	return ProgressionRules.enemy_max_hp(
		combat_stage,
		is_boss,
		catalog.base_catalog.balance,
		float(modifiers.enemy_health)
	)


static func _apply_patch_override(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	patch_ids_override: Variant
) -> void:
	var patch_ids := _validated_patch_ids(patch_ids_override, catalog)
	var previous_max_hp := enemy_max_hp(state, catalog)
	assert(previous_max_hp > EPSILON, "Combat V2 enemy max HP must be positive")
	assert(
		state.progression.enemy_health >= -EPSILON
		and state.progression.enemy_health <= previous_max_hp + EPSILON,
		"Combat V2 enemy HP is outside its valid range"
	)
	var health_ratio := clampf(state.progression.enemy_health / previous_max_hp, 0.0, 1.0)
	state.progression.equipped_patch_ids = patch_ids.duplicate()
	state.progression.enemy_health = enemy_max_hp(state, catalog, patch_ids) * health_ratio


static func _validated_patch_ids(value: Variant, catalog: CombatV2Catalog) -> Array[StringName]:
	assert(value is Array, "Combat V2 patch override must be an Array")
	var patch_ids: Array[StringName] = []
	for raw_patch_id: Variant in value:
		assert(
			raw_patch_id is String or raw_patch_id is StringName,
			"Combat V2 patch override contains a non-string id"
		)
		var patch_id := StringName(raw_patch_id)
		if patch_id == &"":
			patch_ids.append(patch_id)
			continue
		assert(
			catalog.base_catalog.has_patch(patch_id),
			"Unknown patch id in Combat V2 forecast: %s" % patch_id
		)
		patch_ids.append(patch_id)
	return patch_ids


static func _was_resolved(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	initial_stage: int,
	initial_enemy_index: int,
	initial_maintenance: bool,
	encounter_changed: bool
) -> bool:
	if not encounter_changed:
		return false
	if not initial_maintenance and state.progression.is_maintenance:
		return false
	var was_boss := (
		initial_stage <= catalog.balance.max_stage
		and ProgressionRules.is_boss_stage(initial_stage)
		and not initial_maintenance
	)
	if was_boss:
		return not state.progression.is_maintenance
	if initial_maintenance:
		return (
			state.progression.enemy_index != initial_enemy_index
			or not state.progression.is_maintenance
		)
	return (
		state.progression.stage != initial_stage
		or state.progression.enemy_index != initial_enemy_index
	)


static func _uptime(
	active_time: float,
	seconds: float,
	operator_count: int,
	state: CombatV2State
) -> float:
	if seconds > EPSILON and operator_count > 0:
		return clampf(active_time / (seconds * float(operator_count)), 0.0, 1.0)
	if operator_count <= 0:
		return 0.0
	return (
		1.0
		if CombatV2Simulator.all_active(state)
		else float(CombatV2Simulator.active_operator_count(state)) / float(operator_count)
	)


static func _total_active_time(state: CombatV2State) -> float:
	var total := 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		total += runtime.active_time
	return total
