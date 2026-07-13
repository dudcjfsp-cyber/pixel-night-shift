class_name CombatV2Simulator
extends RefCounted

const EPSILON := 0.000001
const MAX_EVENTS_PER_ADVANCE := 2000000
const QA_OPERATOR_ID := &"qa_imp"
const WATCHDOG_ID := &"watchdog_process"
const RECOVERY_SOURCE_QA := &"qa"
const RECOVERY_SOURCE_EMERGENCY := &"emergency"
const RECOVERY_SOURCE_PRIORITY: Array[StringName] = [
	RECOVERY_SOURCE_QA,
	RECOVERY_SOURCE_EMERGENCY,
]


static func initialize_new_run(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	assert(state != null, "Combat V2 state is required")
	assert(catalog != null and catalog.base_catalog != null, "Combat V2 catalog is incomplete")
	state.progression = GameState.new()
	state.operators.clear()
	state.recent_events.clear()
	state.encounter_serial = 1
	state.total_elapsed = 0.0
	state.total_enemies_defeated = 0
	state.total_stages_cleared = 0
	state.total_damage_taken = 0.0
	state.total_down_count = 0
	state.total_down_time = 0.0
	state.total_boss_healed = 0.0
	state.attempt_serial = 1
	state.maintenance_remaining = 0.0
	state.normal_failure_count = 0
	state.last_failure_reason = &""
	state.qa_rescue_count = 0
	state.paid_redeploy_count = 0
	state.emergency_spent_bits = 0.0
	state.total_bits_earned = 0.0
	state.reset_stage_metrics()
	ProgressionRules.refresh_unlocks(state.progression, catalog.base_catalog)
	for profile: CombatV2Catalog.OperatorProfile in catalog.operators:
		state.operators.append(CombatV2State.OperatorRuntime.new(profile.id))
	_reset_boss_attempt(state)
	_reset_stage_recovery_state(state)
	reset_team_full(state, catalog)
	_initialize_encounter(state, catalog)
	state.progression.status_message = "Combat V2 shift started."
	state.record_event(&"run_started")


static func advance(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	delta_seconds: float,
	stop_after_encounter_change: bool = false
) -> int:
	if delta_seconds <= 0.0 or state.progression.can_prestige:
		return 0
	assert(not state.operators.is_empty(), "Combat V2 state must be initialized before advance")
	var remaining := delta_seconds
	var processed_events := 0
	var initial_encounter_serial := state.encounter_serial
	while remaining > 0.0:
		assert(
			processed_events <= MAX_EVENTS_PER_ADVANCE,
			"Combat V2 event loop exceeded its safety limit"
		)
		var next_event := _next_event_time(state, catalog)
		if is_inf(next_event) or next_event > remaining + EPSILON:
			_advance_time(state, catalog, remaining)
			remaining = 0.0
			break
		var step := minf(maxf(0.0, next_event), remaining)
		if step > 0.0:
			_advance_time(state, catalog, step)
			remaining = maxf(0.0, remaining - step)
		var batch_events := _process_due_events(state, catalog)
		assert(batch_events > 0, "Combat V2 reached a zero-time event loop")
		processed_events += batch_events
		if stop_after_encounter_change and state.encounter_serial != initial_encounter_serial:
			break
		if state.progression.can_prestige:
			break
	return processed_events


static func operator_max_hp(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName
) -> float:
	var profile: CombatV2Catalog.OperatorProfile = catalog.get_operator(operator_id)
	assert(profile != null, "Unknown Combat V2 operator: %s" % operator_id)
	var level := int(state.progression.operator_levels.get(operator_id, 0))
	if level <= 0:
		return 0.0
	return profile.base_hp * (1.0 + catalog.balance.hp_per_level * float(level - 1))


static func emergency_redeploy_cost(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> float:
	var cheapest := INF
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		if not _is_unlocked(state, definition.id):
			continue
		var level := int(state.progression.operator_levels.get(definition.id, 0))
		var next_cost := ProgressionRules.operator_upgrade_cost(
			level, definition.base_cost, definition.cost_growth
		)
		cheapest = minf(cheapest, next_cost)
	assert(is_finite(cheapest), "Emergency redeploy requires an unlocked operator")
	return maxf(1.0, ceilf(cheapest * catalog.balance.emergency_cost_fraction))


static func emergency_redeploy_status(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName
) -> Dictionary:
	var cost := emergency_redeploy_cost(state, catalog)
	var status := {
		"available": false,
		"eligible": false,
		"affordable": state.progression.bits + EPSILON >= cost,
		"remaining": 0 if state.emergency_redeploy_used else 1,
		"cost": cost,
		"target_id": operator_id,
		"error": "",
	}
	if state.progression.can_prestige or state.progression.is_maintenance:
		status.error = "Combat is not accepting emergency redeploy commands."
		return status
	if state.progression.enemy_health <= EPSILON or all_down(state):
		status.error = "The encounter attempt has already ended."
		return status
	if state.emergency_redeploy_used:
		status.error = "Emergency redeploy has already been used this attempt."
		return status
	var runtime := state.get_operator(operator_id)
	if runtime == null:
		status.error = "Unknown Combat V2 operator."
		return status
	if not _is_unlocked(state, operator_id):
		status.error = "Operator is not unlocked."
		return status
	if runtime.current_hp > EPSILON:
		status.error = "Operator is not down."
		return status
	if runtime.recovery_source != &"" or runtime.recovery_remaining > EPSILON:
		status.error = "Operator already has a recovery scheduled."
		return status
	status.eligible = true
	if not bool(status.affordable):
		status.error = "Not enough bits for emergency redeploy."
		return status
	status.available = true
	return status


static func emergency_redeploy_overview(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> Dictionary:
	var cost := emergency_redeploy_cost(state, catalog)
	var available := false
	var eligible_targets: Array[String] = []
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		var status := emergency_redeploy_status(state, catalog, operator_id)
		if bool(status.eligible):
			eligible_targets.append(String(operator_id))
		available = available or bool(status.available)
	return {
		"cost": cost,
		"available": available,
		"affordable": state.progression.bits + EPSILON >= cost,
		"remaining": 0 if state.emergency_redeploy_used else 1,
		"reserved_operator_id": String(state.emergency_redeploy_target_id),
		"eligible_targets": eligible_targets,
	}


static func request_emergency_redeploy(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName
) -> Dictionary:
	var result := emergency_redeploy_status(state, catalog, operator_id)
	result["succeeded"] = false
	if not bool(result.available):
		return result
	var runtime := state.get_operator(operator_id)
	assert(runtime != null, "Validated emergency redeploy target must exist")
	var cost := float(result.cost)
	state.progression.bits -= cost
	state.emergency_spent_bits += cost
	state.emergency_redeploy_used = true
	state.emergency_redeploy_target_id = operator_id
	state.paid_redeploy_count += 1
	runtime.recovery_source = RECOVERY_SOURCE_EMERGENCY
	runtime.recovery_remaining = catalog.balance.emergency_redeploy_delay
	state.record_event(&"emergency_redeploy_requested", {
		"target_id": operator_id,
		"cost": cost,
		"delay": catalog.balance.emergency_redeploy_delay,
	})
	result.succeeded = true
	result.remaining = 0
	result.available = false
	result.error = ""
	return result


static func operator_attack_interval(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName
) -> float:
	var profile: CombatV2Catalog.OperatorProfile = catalog.get_operator(operator_id)
	assert(profile != null, "Unknown Combat V2 operator: %s" % operator_id)
	var modifiers := ProgressionRules.patch_modifiers(
		state.progression.equipped_patch_ids, catalog.base_catalog
	)
	var attack_speed := float(modifiers.attack_speed)
	assert(attack_speed > EPSILON, "Operator attack speed must stay positive")
	var interval := profile.attack_interval / attack_speed
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if not runtime.is_active():
			continue
		var ally_profile: CombatV2Catalog.OperatorProfile = catalog.get_operator(runtime.operator_id)
		assert(ally_profile != null, "Runtime has an unknown operator id")
		interval *= ally_profile.team_interval_multiplier
	return interval


static func operator_attack_damage(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName
) -> float:
	var profile: CombatV2Catalog.OperatorProfile = catalog.get_operator(operator_id)
	var base_definition: OperatorDefinition = catalog.base_catalog.get_operator(operator_id)
	assert(profile != null and base_definition != null, "Unknown Combat V2 operator: %s" % operator_id)
	var level := int(state.progression.operator_levels.get(operator_id, 0))
	if level <= 0:
		return 0.0
	var modifiers := ProgressionRules.patch_modifiers(
		state.progression.equipped_patch_ids, catalog.base_catalog
	)
	var legacy_multiplier := 1.0 + (
		catalog.base_catalog.balance.legacy_cache_bonus
		* float(state.progression.legacy_cache_level)
	)
	var boss_multiplier := profile.boss_multiplier if _is_boss_combat(state, catalog) else 1.0
	var role_scaled_dps := base_definition.base_dps * pow(
		float(level),
		base_definition.dps_exponent * profile.damage_exponent_multiplier
	)
	return (
		role_scaled_dps
		* profile.outgoing_multiplier
		* boss_multiplier
		* float(modifiers.damage)
		* legacy_multiplier
		* profile.attack_interval
	)


static func operator_effective_dps(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName
) -> float:
	var runtime := state.get_operator(operator_id)
	if runtime == null or not runtime.is_active():
		return 0.0
	return operator_attack_damage(state, catalog, operator_id) / operator_attack_interval(
		state, catalog, operator_id
	)


static func team_max_hp(state: CombatV2State, catalog: CombatV2Catalog) -> float:
	var total := 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if _is_unlocked(state, runtime.operator_id):
			total += operator_max_hp(state, catalog, runtime.operator_id)
	return total


static func team_current_hp(state: CombatV2State) -> float:
	var total := 0.0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		total += runtime.current_hp
	return total


static func active_operator_count(state: CombatV2State) -> int:
	var count := 0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if runtime.is_active():
			count += 1
	return count


static func unlocked_operator_count(state: CombatV2State) -> int:
	var count := 0
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if _is_unlocked(state, runtime.operator_id):
			count += 1
	return count


static func all_active(state: CombatV2State) -> bool:
	var unlocked := unlocked_operator_count(state)
	return unlocked > 0 and active_operator_count(state) == unlocked


static func all_down(state: CombatV2State) -> bool:
	return unlocked_operator_count(state) > 0 and active_operator_count(state) == 0


static func reset_team_full(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if not _is_unlocked(state, runtime.operator_id):
			runtime.current_hp = 0.0
			runtime.attack_remaining = INF
			runtime.recovery_remaining = 0.0
			runtime.recovery_source = &""
			continue
		runtime.current_hp = operator_max_hp(state, catalog, runtime.operator_id)
		runtime.recovery_remaining = 0.0
		runtime.recovery_source = &""
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if runtime.is_active():
			runtime.attack_remaining = operator_attack_interval(
				state, catalog, runtime.operator_id
			)


static func preserve_operator_health_ratio(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	operator_id: StringName,
	previous_max_hp: float
) -> void:
	var runtime := state.get_operator(operator_id)
	assert(runtime != null, "Unknown operator runtime: %s" % operator_id)
	if not runtime.is_active() or previous_max_hp <= EPSILON:
		return
	var ratio := clampf(runtime.current_hp / previous_max_hp, 0.0, 1.0)
	runtime.current_hp = operator_max_hp(state, catalog, operator_id) * ratio


static func preserve_enemy_health_ratio(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	previous_max_hp: float
) -> void:
	if previous_max_hp <= EPSILON or state.progression.enemy_health <= EPSILON:
		return
	var ratio := clampf(state.progression.enemy_health / previous_max_hp, 0.0, 1.0)
	state.progression.enemy_health = _current_enemy_max_hp(state, catalog) * ratio


static func current_enemy_profile(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> CombatV2Catalog.EnemyProfile:
	if _is_boss_combat(state, catalog):
		var watchdog: CombatV2Catalog.EnemyProfile = catalog.get_enemy(WATCHDOG_ID)
		assert(watchdog != null, "Combat V2 watchdog profile is missing")
		return watchdog
	var combat_stage := state.progression.stage
	var normal_index := posmod(combat_stage - 1, 3)
	assert(catalog.enemies.size() > normal_index, "Combat V2 normal enemy profiles are incomplete")
	return catalog.enemies[normal_index]


static func _next_event_time(state: CombatV2State, catalog: CombatV2Catalog) -> float:
	if state.progression.is_maintenance:
		return maxf(0.0, state.maintenance_remaining)
	if state.progression.enemy_health <= EPSILON:
		return 0.0
	var next_event := INF
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if runtime.is_active():
			next_event = minf(next_event, runtime.attack_remaining)
		elif _is_unlocked(state, runtime.operator_id) and runtime.recovery_remaining > 0.0:
			next_event = minf(next_event, runtime.recovery_remaining)
	if _is_boss_combat(state, catalog):
		next_event = minf(next_event, state.enemy_attack_remaining)
		next_event = minf(next_event, state.boss_special_remaining)
		next_event = minf(next_event, state.boss_rollback_remaining)
		var timeout_remaining := maxf(
			0.0,
			catalog.base_catalog.balance.boss_time_limit - state.progression.boss_elapsed
		)
		next_event = minf(next_event, timeout_remaining)
	else:
		next_event = minf(next_event, state.enemy_attack_remaining)
	return maxf(0.0, next_event)


static func _advance_time(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	seconds: float
) -> void:
	state.total_elapsed += seconds
	state.stage_elapsed += seconds
	if state.progression.is_maintenance:
		state.maintenance_remaining = maxf(0.0, state.maintenance_remaining - seconds)
		for runtime: CombatV2State.OperatorRuntime in state.operators:
			if _is_unlocked(state, runtime.operator_id) and not runtime.is_active():
				runtime.down_time += seconds
				state.total_down_time += seconds
				state.stage_down_time += seconds
		return
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		if runtime.is_active():
			runtime.attack_remaining = maxf(0.0, runtime.attack_remaining - seconds)
			runtime.active_time += seconds
		elif _is_unlocked(state, runtime.operator_id):
			if runtime.recovery_remaining > 0.0:
				runtime.recovery_remaining = maxf(0.0, runtime.recovery_remaining - seconds)
			runtime.down_time += seconds
			state.total_down_time += seconds
			state.stage_down_time += seconds
	state.enemy_attack_remaining = maxf(0.0, state.enemy_attack_remaining - seconds)
	if not _is_boss_combat(state, catalog):
		return
	state.boss_special_remaining = maxf(0.0, state.boss_special_remaining - seconds)
	state.boss_rollback_remaining = maxf(0.0, state.boss_rollback_remaining - seconds)
	state.progression.boss_elapsed += seconds


static func _process_due_events(state: CombatV2State, catalog: CombatV2Catalog) -> int:
	if state.progression.is_maintenance:
		if state.maintenance_remaining > EPSILON:
			return 0
		_retry_attempt(state, catalog)
		return 1
	var processed := _process_operator_attacks(state, catalog)
	if state.progression.enemy_health <= EPSILON:
		_complete_enemy(state, catalog)
		processed += 1
		if state.progression.can_prestige:
			return processed
	processed += _process_recoveries(state, catalog)
	if _is_boss_combat(state, catalog):
		processed += _process_boss_attacks(state, catalog)
		if state.progression.is_maintenance:
			return processed
		processed += _process_boss_rollback(state, catalog)
		if (
			state.progression.boss_elapsed + EPSILON
			>= catalog.base_catalog.balance.boss_time_limit
			and state.progression.enemy_health > EPSILON
		):
			_fail_attempt(state, catalog, &"boss_timeout")
			processed += 1
	else:
		processed += _process_normal_enemy_attack(state, catalog)
		if all_down(state):
			_fail_attempt(state, catalog, &"normal_all_down")
			processed += 1
	return processed


static func _process_operator_attacks(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> int:
	var processed := 0
	for runtime: CombatV2State.OperatorRuntime in _stable_runtimes(state):
		if not runtime.is_active() or runtime.attack_remaining > EPSILON:
			continue
		var damage := operator_attack_damage(state, catalog, runtime.operator_id)
		state.progression.enemy_health = maxf(0.0, state.progression.enemy_health - damage)
		runtime.damage_dealt += damage
		runtime.attack_remaining = operator_attack_interval(state, catalog, runtime.operator_id)
		state.record_event(&"operator_attack", {
			"operator_id": runtime.operator_id,
			"damage": damage,
		})
		processed += 1
	return processed


static func _process_recoveries(state: CombatV2State, catalog: CombatV2Catalog) -> int:
	var processed := 0
	# Recovery ordering is target stable ID first, then RECOVERY_SOURCE_PRIORITY.
	# A target owns exactly one source; the rank assertion keeps that contract explicit.
	for runtime: CombatV2State.OperatorRuntime in _stable_runtimes(state):
		if (
			_recovery_source_rank(runtime.recovery_source) < 0
			or runtime.recovery_remaining > EPSILON
		):
			continue
		_revive_operator(state, catalog, runtime, runtime.recovery_source)
		processed += 1
	return processed


static func _process_normal_enemy_attack(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> int:
	if state.enemy_attack_remaining > EPSILON:
		return 0
	var profile := current_enemy_profile(state, catalog)
	var damage := profile.attack_damage * _enemy_damage_scale(state, catalog)
	match profile.pattern:
		&"focused":
			_attack_target(state, catalog, _highest_threat_target(state, catalog), damage, &"focused")
			state.enemy_attack_remaining = profile.attack_interval
		&"burst":
			_process_burst_hit(state, catalog, profile, damage)
		&"aoe":
			var hit_count := 0
			for runtime: CombatV2State.OperatorRuntime in _stable_runtimes(state):
				if runtime.is_active():
					_apply_damage(state, catalog, runtime, damage, &"aoe")
					hit_count += 1
			state.record_event(&"enemy_aoe", {"damage": damage, "targets": hit_count})
			state.enemy_attack_remaining = profile.attack_interval
		_:
			assert(false, "Unsupported Combat V2 enemy pattern: %s" % profile.pattern)
	return 1


static func _process_burst_hit(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	profile: CombatV2Catalog.EnemyProfile,
	damage: float
) -> void:
	var target: CombatV2State.OperatorRuntime = null
	if state.enemy_pattern_step == 0:
		target = _highest_dps_target(state, catalog)
		state.enemy_locked_target_id = target.operator_id if target != null else &""
	else:
		target = state.get_operator(state.enemy_locked_target_id)
	_attack_target(state, catalog, target, damage, &"burst")
	var next_step := state.enemy_pattern_step + 1
	if next_step < profile.burst_count:
		state.enemy_pattern_step = next_step
		state.enemy_attack_remaining = profile.burst_gap
		return
	state.enemy_pattern_step = 0
	state.enemy_locked_target_id = &""
	state.enemy_attack_remaining = maxf(
		EPSILON,
		profile.attack_interval - profile.burst_gap * float(profile.burst_count - 1)
	)


static func _process_boss_attacks(state: CombatV2State, catalog: CombatV2Catalog) -> int:
	var profile := current_enemy_profile(state, catalog)
	var processed := 0
	var damage_scale := _enemy_damage_scale(state, catalog)
	if state.enemy_attack_remaining <= EPSILON:
		_attack_target(
			state,
			catalog,
			_highest_threat_target(state, catalog),
			profile.poll_damage * damage_scale,
			&"boss_poll"
		)
		state.enemy_attack_remaining = profile.poll_interval
		processed += 1
		if all_down(state):
			_fail_attempt(state, catalog, &"boss_all_down")
			return processed + 1
	if state.boss_special_remaining <= EPSILON:
		_attack_target(
			state,
			catalog,
			_highest_dps_target(state, catalog),
			profile.special_damage * damage_scale,
			&"boss_special"
		)
		state.boss_special_remaining = profile.special_interval * _boss_interval_multiplier(
			state, catalog
		)
		processed += 1
		if all_down(state):
			_fail_attempt(state, catalog, &"boss_all_down")
			return processed + 1
	return processed


static func _process_boss_rollback(state: CombatV2State, catalog: CombatV2Catalog) -> int:
	if state.boss_rollback_remaining > EPSILON:
		return 0
	var profile := current_enemy_profile(state, catalog)
	var modifiers := ProgressionRules.patch_modifiers(
		state.progression.equipped_patch_ids, catalog.base_catalog
	)
	var max_hp := _current_enemy_max_hp(state, catalog)
	var requested := max_hp * profile.rollback_fraction * float(modifiers.boss_recovery)
	var previous_hp := state.progression.enemy_health
	state.progression.enemy_health = minf(max_hp, previous_hp + requested)
	var healed := state.progression.enemy_health - previous_hp
	state.progression.boss_recovery_count += 1
	state.progression.boss_recovered_health += healed
	state.total_boss_healed += healed
	state.stage_boss_healed += healed
	state.boss_rollback_remaining = profile.rollback_interval * _boss_interval_multiplier(
		state, catalog
	)
	state.record_event(&"boss_rollback", {"healed": healed})
	return 1


static func _attack_target(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	target: CombatV2State.OperatorRuntime,
	damage: float,
	attack_kind: StringName
) -> void:
	if target == null or not target.is_active():
		state.record_event(&"enemy_attack_missed", {"attack": attack_kind})
		return
	_apply_damage(state, catalog, target, damage, attack_kind)


static func _apply_damage(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	target: CombatV2State.OperatorRuntime,
	base_damage: float,
	attack_kind: StringName
) -> void:
	var profile: CombatV2Catalog.OperatorProfile = catalog.get_operator(target.operator_id)
	assert(profile != null, "Enemy attack targeted an unknown operator")
	var incoming := base_damage * profile.incoming_multiplier
	var applied := minf(target.current_hp, incoming)
	target.current_hp = maxf(0.0, target.current_hp - incoming)
	target.damage_taken += applied
	state.total_damage_taken += applied
	state.stage_damage_taken += applied
	state.record_event(&"operator_damaged", {
		"operator_id": target.operator_id,
		"attack": attack_kind,
		"damage": applied,
	})
	if target.current_hp > EPSILON:
		return
	target.current_hp = 0.0
	target.attack_remaining = INF
	target.recovery_remaining = 0.0
	target.recovery_source = &""
	target.down_count += 1
	state.total_down_count += 1
	state.stage_down_count += 1
	if target.operator_id == QA_OPERATOR_ID:
		if not state.qa_rescue_consumed:
			state.qa_rescue_consumed = true
		_cancel_qa_recovery(state)
	else:
		_schedule_qa_recovery_if_available(state, catalog, target)
	state.record_event(&"operator_down", {
		"operator_id": target.operator_id,
		"recovery_source": target.recovery_source,
		"recovery": target.recovery_remaining,
	})
	if all_down(state):
		state.progression.status_message = "All operators are down. Attempt failed."
		state.record_event(&"team_all_down")


static func _revive_operator(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	runtime: CombatV2State.OperatorRuntime,
	source: StringName
) -> void:
	runtime.recovery_remaining = 0.0
	runtime.recovery_source = &""
	runtime.current_hp = operator_max_hp(
		state, catalog, runtime.operator_id
	) * catalog.balance.revive_fraction
	runtime.attack_remaining = operator_attack_interval(state, catalog, runtime.operator_id)
	if source == RECOVERY_SOURCE_QA:
		state.qa_recovery_target_id = &""
		state.qa_rescue_count += 1
	elif source == RECOVERY_SOURCE_EMERGENCY:
		state.emergency_redeploy_target_id = &""
	state.record_event(&"operator_recovered", {
		"operator_id": runtime.operator_id,
		"hp": runtime.current_hp,
		"source": source,
	})


static func _highest_threat_target(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> CombatV2State.OperatorRuntime:
	var best: CombatV2State.OperatorRuntime = null
	var best_threat := -INF
	for runtime: CombatV2State.OperatorRuntime in _stable_runtimes(state):
		if not runtime.is_active():
			continue
		var profile: CombatV2Catalog.OperatorProfile = catalog.get_operator(runtime.operator_id)
		if (
			profile.threat_weight > best_threat + EPSILON
			or (
				is_equal_approx(profile.threat_weight, best_threat)
				and (best == null or _stable_rank(runtime.operator_id) < _stable_rank(best.operator_id))
			)
		):
			best = runtime
			best_threat = profile.threat_weight
	return best


static func _highest_dps_target(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> CombatV2State.OperatorRuntime:
	var best: CombatV2State.OperatorRuntime = null
	var best_dps := -INF
	for runtime: CombatV2State.OperatorRuntime in _stable_runtimes(state):
		if not runtime.is_active():
			continue
		var dps := operator_effective_dps(state, catalog, runtime.operator_id)
		if (
			dps > best_dps + EPSILON
			or (
				is_equal_approx(dps, best_dps)
				and (best == null or _stable_rank(runtime.operator_id) < _stable_rank(best.operator_id))
			)
		):
			best = runtime
			best_dps = dps
	return best


static func _complete_enemy(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	if _is_boss_combat(state, catalog):
		_complete_boss(state, catalog)
	else:
		_complete_normal_enemy(state, catalog)


static func _complete_normal_enemy(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	var combat_stage := state.progression.stage
	var modifiers := ProgressionRules.patch_modifiers(
		state.progression.equipped_patch_ids, catalog.base_catalog
	)
	var reward := ProgressionRules.enemy_reward(
		combat_stage, catalog.base_catalog.balance, float(modifiers.bits)
	)
	state.progression.bits += reward
	state.total_bits_earned += reward
	state.total_enemies_defeated += 1
	state.record_event(&"enemy_defeated", {"maintenance": false})
	state.progression.enemy_index += 1
	if state.progression.enemy_index <= catalog.balance.normal_enemy_count:
		state.encounter_serial += 1
		_initialize_encounter(state, catalog)
		return
	state.total_stages_cleared += 1
	state.progression.stage += 1
	state.progression.highest_stage = maxi(
		state.progression.highest_stage, state.progression.stage
	)
	state.progression.enemy_index = 1
	ProgressionRules.refresh_unlocks(state.progression, catalog.base_catalog)
	state.reset_stage_metrics()
	_reset_boss_attempt(state)
	state.attempt_serial += 1
	_reset_stage_recovery_state(state)
	reset_team_full(state, catalog)
	state.encounter_serial += 1
	_initialize_encounter(state, catalog)
	state.progression.status_message = "Entered stage %d." % state.progression.stage
	state.record_event(&"stage_entered")


static func _complete_boss(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	var modifiers := ProgressionRules.patch_modifiers(
		state.progression.equipped_patch_ids, catalog.base_catalog
	)
	var reward := ProgressionRules.enemy_reward(
		state.progression.stage,
		catalog.base_catalog.balance,
		float(modifiers.bits)
	) * catalog.base_catalog.balance.boss_health_multiplier
	state.progression.bits += reward
	state.total_bits_earned += reward
	state.total_enemies_defeated += 1
	state.total_stages_cleared += 1
	state.progression.enemy_health = 0.0
	state.progression.can_prestige = true
	_reset_stage_recovery_state(state)
	reset_team_full(state, catalog)
	state.encounter_serial += 1
	state.progression.status_message = "Combat V2 stage 10 cleared."
	state.record_event(&"boss_defeated")


static func _fail_attempt(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	reason: StringName
) -> void:
	assert(not state.progression.is_maintenance, "Cannot fail an inactive attempt")
	var was_boss := _is_boss_combat(state, catalog)
	var reset_enemy_hp := _current_enemy_max_hp(state, catalog)
	state.last_failure_reason = reason
	if was_boss:
		state.progression.boss_failure_count += 1
		if state.progression.boss_failure_count == 1:
			state.progression.free_patch_swaps += 1
	else:
		state.normal_failure_count += 1
	state.progression.is_maintenance = true
	state.maintenance_remaining = catalog.balance.maintenance_seconds
	state.progression.enemy_index = 1
	state.progression.enemy_health = reset_enemy_hp
	state.enemy_attack_remaining = INF
	state.boss_special_remaining = INF
	state.boss_rollback_remaining = INF
	state.enemy_pattern_step = 0
	state.enemy_locked_target_id = &""
	_cancel_all_recoveries(state)
	_reset_boss_attempt(state)
	state.encounter_serial += 1
	state.progression.status_message = "Attempt failed. Automatic retry in %.0f seconds." % (
		catalog.balance.maintenance_seconds
	)
	state.record_event(&"attempt_failed", {
		"reason": reason,
		"failure_count": state.total_failure_count(),
		"maintenance_seconds": state.maintenance_remaining,
	})


static func _retry_attempt(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	state.progression.is_maintenance = false
	state.maintenance_remaining = 0.0
	state.progression.enemy_index = 1
	_reset_boss_attempt(state)
	state.reset_stage_metrics()
	state.attempt_serial += 1
	_reset_attempt_recovery_state(state)
	reset_team_full(state, catalog)
	state.encounter_serial += 1
	_initialize_encounter(state, catalog)
	state.progression.status_message = "Maintenance complete. Stage retry started."
	state.record_event(&"attempt_retry", {
		"attempt_serial": state.attempt_serial,
		"failure_reason": state.last_failure_reason,
	})


static func _initialize_encounter(state: CombatV2State, catalog: CombatV2Catalog) -> void:
	state.progression.enemy_health = _current_enemy_max_hp(state, catalog)
	state.enemy_pattern_step = 0
	state.enemy_locked_target_id = &""
	if state.progression.is_maintenance:
		state.enemy_attack_remaining = INF
		state.boss_special_remaining = INF
		state.boss_rollback_remaining = INF
		return
	var profile := current_enemy_profile(state, catalog)
	if profile.pattern == &"watchdog":
		state.enemy_attack_remaining = profile.poll_interval
		state.boss_special_remaining = profile.special_interval * _boss_interval_multiplier(
			state, catalog
		)
		state.boss_rollback_remaining = profile.rollback_interval * _boss_interval_multiplier(
			state, catalog
		)
	else:
		state.enemy_attack_remaining = profile.attack_interval
		state.boss_special_remaining = INF
		state.boss_rollback_remaining = INF


static func _reset_boss_attempt(state: CombatV2State) -> void:
	state.progression.boss_elapsed = 0.0
	state.progression.boss_recovery_count = 0
	state.progression.boss_recovered_health = 0.0
	state.progression.boss_debuff_applied = false


static func _schedule_qa_recovery_if_available(
	state: CombatV2State,
	catalog: CombatV2Catalog,
	target: CombatV2State.OperatorRuntime
) -> void:
	if state.qa_rescue_consumed:
		return
	var qa_runtime := state.get_operator(QA_OPERATOR_ID)
	if (
		qa_runtime == null
		or not _is_unlocked(state, QA_OPERATOR_ID)
		or not qa_runtime.is_active()
	):
		return
	state.qa_rescue_consumed = true
	state.qa_recovery_target_id = target.operator_id
	target.recovery_source = RECOVERY_SOURCE_QA
	target.recovery_remaining = catalog.balance.qa_recovery_delay
	state.record_event(&"qa_recovery_scheduled", {
		"target_id": target.operator_id,
		"delay": target.recovery_remaining,
	})


static func _cancel_qa_recovery(state: CombatV2State) -> void:
	if state.qa_recovery_target_id == &"":
		return
	var target := state.get_operator(state.qa_recovery_target_id)
	if target != null and target.recovery_source == RECOVERY_SOURCE_QA:
		target.recovery_source = &""
		target.recovery_remaining = 0.0
		state.record_event(&"qa_recovery_cancelled", {"target_id": target.operator_id})
	state.qa_recovery_target_id = &""


static func _cancel_all_recoveries(state: CombatV2State) -> void:
	for runtime: CombatV2State.OperatorRuntime in state.operators:
		runtime.recovery_source = &""
		runtime.recovery_remaining = 0.0
	state.qa_recovery_target_id = &""
	state.emergency_redeploy_target_id = &""


static func _reset_attempt_recovery_state(state: CombatV2State) -> void:
	_cancel_all_recoveries(state)
	state.emergency_redeploy_used = false


static func _reset_stage_recovery_state(state: CombatV2State) -> void:
	_reset_attempt_recovery_state(state)
	state.qa_rescue_consumed = false


static func _current_enemy_max_hp(state: CombatV2State, catalog: CombatV2Catalog) -> float:
	return ProgressionRules.current_enemy_max_hp(state.progression, catalog.base_catalog)


static func _enemy_damage_scale(state: CombatV2State, catalog: CombatV2Catalog) -> float:
	return pow(
		catalog.balance.damage_growth,
		float(maxi(state.progression.stage - 1, 0))
	)


static func _boss_interval_multiplier(
	state: CombatV2State,
	catalog: CombatV2Catalog
) -> float:
	var modifiers := ProgressionRules.patch_modifiers(
		state.progression.equipped_patch_ids, catalog.base_catalog
	)
	return float(modifiers.boss_special_interval)


static func _is_boss_combat(state: CombatV2State, catalog: CombatV2Catalog) -> bool:
	return (
		not state.progression.is_maintenance
		and state.progression.stage == catalog.balance.max_stage
	)


static func _is_unlocked(state: CombatV2State, operator_id: StringName) -> bool:
	return (
		state.progression.is_operator_unlocked(operator_id)
		and int(state.progression.operator_levels.get(operator_id, 0)) > 0
	)


static func _stable_runtimes(state: CombatV2State) -> Array[CombatV2State.OperatorRuntime]:
	var ordered: Array[CombatV2State.OperatorRuntime] = []
	for operator_id: StringName in CombatV2Catalog.STABLE_OPERATOR_IDS:
		var runtime := state.get_operator(operator_id)
		if runtime != null:
			ordered.append(runtime)
	return ordered


static func _stable_rank(operator_id: StringName) -> int:
	var rank := CombatV2Catalog.STABLE_OPERATOR_IDS.find(operator_id)
	assert(rank >= 0, "Unknown operator id in stable Combat V2 ordering: %s" % operator_id)
	return rank


static func _recovery_source_rank(source: StringName) -> int:
	return RECOVERY_SOURCE_PRIORITY.find(source)
