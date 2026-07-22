class_name HybridBossSimulator
extends RefCounted

const EPSILON := 0.000001
const MAX_EVENTS_PER_ADVANCE := 100000
const MAX_RECENT_BOSS_EVENTS := 64


static func advance(
	state: GameState,
	catalog: ContentCatalog,
	available_seconds: float
) -> float:
	assert(state != null, "Hybrid boss simulation requires a state")
	assert(catalog != null and catalog.balance != null, "Hybrid boss simulation requires content")
	assert(
		ProgressionRules.is_boss_stage(state.stage) and not state.is_maintenance,
		"HybridBossSimulator only advances an active boss attempt"
	)
	assert(
		is_finite(available_seconds) and available_seconds >= 0.0,
		"Boss advance time must be a non-negative finite number"
	)
	if available_seconds <= 0.0 or _is_terminal(state):
		return 0.0
	if _all_down(state):
		_mark_failure(state, &"boss_all_down")
		return 0.0

	var remaining := available_seconds
	var consumed := 0.0
	var processed_events := 0
	while remaining > EPSILON and not _is_terminal(state):
		assert(
			processed_events <= MAX_EVENTS_PER_ADVANCE,
			"Hybrid boss event loop exceeded its safety limit"
		)
		var next_event := _next_event_time(state, catalog)
		if is_inf(next_event) or next_event > remaining + EPSILON:
			_advance_time(state, remaining)
			consumed += remaining
			break

		var step := minf(maxf(0.0, next_event), remaining)
		if step > 0.0:
			_advance_time(state, step)
			remaining = maxf(0.0, remaining - step)
			consumed += step
		var batch_events := _process_due_events(state, catalog)
		assert(batch_events > 0, "Hybrid boss simulation reached a zero-time event loop")
		processed_events += batch_events
	return consumed


static func reset_attempt(state: GameState, catalog: ContentCatalog) -> void:
	assert(state != null, "Hybrid boss attempt reset requires a state")
	assert(catalog != null and catalog.balance != null, "Hybrid boss attempt reset requires content")
	assert(
		ProgressionRules.is_boss_stage(state.stage) and not state.is_maintenance,
		"Only an active boss stage can reset a hybrid attempt"
	)

	var ordered_runtimes: Array[OperatorCombatState] = []
	for definition: OperatorDefinition in catalog.operators:
		var runtime := state.get_operator_combat_state(definition.id)
		if runtime == null:
			runtime = OperatorCombatState.new(definition.id)
		runtime.current_hp = (
			_operator_max_hp(state, catalog, definition)
			if _is_unlocked(state, definition.id)
			else 0.0
		)
		runtime.attack_remaining = INF
		ordered_runtimes.append(runtime)
	state.operator_combat_states = ordered_runtimes
	assert(_unlocked_operator_count(state) > 0, "A boss attempt requires an unlocked operator")

	state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
	state.boss_elapsed = 0.0
	state.boss_recovery_count = 0
	state.boss_recovered_health = 0.0
	state.boss_debuff_applied = false
	state.last_boss_failure_reason = &""
	state.qa_rescue_consumed = false
	state.qa_rescue_target_id = &""
	state.qa_rescue_remaining = 0.0

	for definition: OperatorDefinition in catalog.operators:
		var runtime := _runtime(state, definition.id)
		if runtime.is_active():
			runtime.attack_remaining = _operator_attack_interval(state, catalog, definition)
	state.enemy_attack_remaining = _poll_interval(state, catalog.balance)
	state.boss_special_remaining = _special_interval(state, catalog)
	state.boss_rollback_remaining = _rollback_interval(state, catalog)
	_record_event(state, &"boss_attempt_started")


static func clear_attempt(state: GameState) -> void:
	assert(state != null, "Hybrid boss attempt clear requires a state")
	if state.qa_rescue_target_id != &"":
		_cancel_qa_rescue(state, &"attempt_cleared")
	_stop_attempt_timers(state)
	_record_event(state, &"boss_attempt_cleared")


static func operator_max_hp(
	state: GameState,
	catalog: ContentCatalog,
	operator_id: StringName
) -> float:
	var definition := catalog.get_operator(operator_id)
	assert(definition != null, "Unknown hybrid operator: %s" % operator_id)
	return _operator_max_hp(state, catalog, definition)


static func operator_effective_dps(
	state: GameState,
	catalog: ContentCatalog,
	operator_id: StringName
) -> float:
	var definition := catalog.get_operator(operator_id)
	assert(definition != null, "Unknown hybrid operator: %s" % operator_id)
	return _operator_effective_dps(state, catalog, definition)


static func next_action(state: GameState) -> Dictionary:
	var label := "POLL"
	var seconds := state.enemy_attack_remaining
	if state.boss_special_remaining < seconds:
		label = "KILL SIGNAL"
		seconds = state.boss_special_remaining
	if state.boss_rollback_remaining < seconds:
		label = "ROLLBACK"
		seconds = state.boss_rollback_remaining
	return {"label": label, "seconds": maxf(0.0, seconds)}


static func _next_event_time(state: GameState, catalog: ContentCatalog) -> float:
	var next_event := INF
	if state.qa_rescue_target_id != &"":
		next_event = minf(next_event, state.qa_rescue_remaining)
	for runtime: OperatorCombatState in state.operator_combat_states:
		if runtime.is_active():
			next_event = minf(next_event, runtime.attack_remaining)
	next_event = minf(next_event, state.enemy_attack_remaining)
	next_event = minf(next_event, state.boss_special_remaining)
	next_event = minf(next_event, state.boss_rollback_remaining)
	if state.stage == 20 and not state.boss_debuff_applied:
		next_event = minf(
			next_event,
			maxf(0.0, catalog.balance.stage_20_debuff_time - state.boss_elapsed)
		)
	next_event = minf(
		next_event,
		maxf(0.0, catalog.balance.boss_time_limit - state.boss_elapsed)
	)
	return maxf(0.0, next_event)


static func _advance_time(state: GameState, seconds: float) -> void:
	if state.qa_rescue_target_id != &"":
		state.qa_rescue_remaining = maxf(0.0, state.qa_rescue_remaining - seconds)
	for runtime: OperatorCombatState in state.operator_combat_states:
		if not state.is_operator_unlocked(runtime.operator_id):
			continue
		if runtime.is_active():
			runtime.attack_remaining = maxf(0.0, runtime.attack_remaining - seconds)
			runtime.active_time += seconds
		else:
			runtime.down_time += seconds
			state.total_operator_down_time += seconds
	state.enemy_attack_remaining = maxf(0.0, state.enemy_attack_remaining - seconds)
	state.boss_special_remaining = maxf(0.0, state.boss_special_remaining - seconds)
	state.boss_rollback_remaining = maxf(0.0, state.boss_rollback_remaining - seconds)
	state.boss_elapsed += seconds


static func _process_due_events(state: GameState, catalog: ContentCatalog) -> int:
	var processed := _process_qa_rescue(state, catalog)
	processed += _process_operator_attacks(state, catalog)
	if state.enemy_health <= EPSILON:
		state.enemy_health = 0.0
		_record_event(state, &"boss_defeated")
		return processed + 1

	if state.enemy_attack_remaining <= EPSILON:
		_process_poll(state, catalog)
		processed += 1
		if not state.last_boss_failure_reason.is_empty():
			return processed
	if state.boss_special_remaining <= EPSILON:
		_process_special(state, catalog)
		processed += 1
		if not state.last_boss_failure_reason.is_empty():
			return processed
	if state.boss_rollback_remaining <= EPSILON:
		_process_rollback(state, catalog)
		processed += 1
	if (
		state.stage == 20
		and not state.boss_debuff_applied
		and state.boss_elapsed + EPSILON >= catalog.balance.stage_20_debuff_time
	):
		state.boss_debuff_applied = true
		_record_event(state, &"boss_debuff_applied", {
			"multiplier": catalog.balance.stage_20_debuff_multiplier,
		})
		processed += 1
	if (
		state.boss_elapsed + EPSILON >= catalog.balance.boss_time_limit
		and state.enemy_health > EPSILON
	):
		_mark_failure(state, &"boss_timeout")
		processed += 1
	return processed


static func _process_qa_rescue(state: GameState, catalog: ContentCatalog) -> int:
	if state.qa_rescue_target_id == &"" or state.qa_rescue_remaining > EPSILON:
		return 0
	var target := state.get_operator_combat_state(state.qa_rescue_target_id)
	assert(target != null, "QA rescue target must exist in operator combat state")
	var qa_runtime := _active_qa_runtime(state, catalog)
	if qa_runtime == null:
		_cancel_qa_rescue(state, &"qa_unavailable")
		return 1
	assert(not target.is_active(), "QA rescue target must still be process-down")
	var definition := catalog.get_operator(target.operator_id)
	assert(definition != null, "QA rescue target must have operator content")
	target.current_hp = (
		_operator_max_hp(state, catalog, definition)
		* catalog.balance.qa_rescue_hp_fraction
	)
	target.attack_remaining = _operator_attack_interval(state, catalog, definition)
	state.qa_rescue_target_id = &""
	state.qa_rescue_remaining = 0.0
	state.qa_rescue_count += 1
	_record_event(state, &"qa_rescue_succeeded", {
		"operator_id": target.operator_id,
		"hp": target.current_hp,
	})
	return 1


static func _process_operator_attacks(state: GameState, catalog: ContentCatalog) -> int:
	var processed := 0
	for definition: OperatorDefinition in catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not runtime.is_active() or runtime.attack_remaining > EPSILON:
			continue
		var damage := _operator_attack_damage(state, catalog, definition)
		var applied := minf(state.enemy_health, damage)
		state.enemy_health = maxf(0.0, state.enemy_health - damage)
		runtime.damage_dealt += applied
		runtime.attack_remaining = _operator_attack_interval(state, catalog, definition)
		processed += 1
		if state.enemy_health <= EPSILON:
			break
	return processed


static func _process_poll(state: GameState, catalog: ContentCatalog) -> void:
	var target := _highest_threat_target(state, catalog)
	_attack_target(
		state,
		catalog,
		target,
		_poll_damage(state, catalog.balance),
		&"boss_poll"
	)
	state.enemy_attack_remaining = _poll_interval(state, catalog.balance)
	if _all_down(state):
		_mark_failure(state, &"boss_all_down")


static func _process_special(state: GameState, catalog: ContentCatalog) -> void:
	var target := _highest_dps_target(state, catalog)
	_attack_target(
		state,
		catalog,
		target,
		_special_damage(state, catalog.balance),
		&"boss_special"
	)
	state.boss_special_remaining = _special_interval(state, catalog)
	if _all_down(state):
		_mark_failure(state, &"boss_all_down")


static func _process_rollback(state: GameState, catalog: ContentCatalog) -> void:
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	var max_hp := ProgressionRules.current_enemy_max_hp(state, catalog)
	var requested := (
		max_hp
		* ProgressionRules.boss_recovery_fraction(state.stage, catalog.balance)
		* float(modifiers.boss_recovery)
	)
	var previous_hp := state.enemy_health
	state.enemy_health = minf(max_hp, previous_hp + requested)
	var healed := state.enemy_health - previous_hp
	state.boss_recovery_count += 1
	state.boss_recovered_health += healed
	state.boss_rollback_remaining = _rollback_interval(state, catalog)
	_record_event(state, &"boss_rollback", {"healed": healed})


static func _attack_target(
	state: GameState,
	catalog: ContentCatalog,
	target: OperatorCombatState,
	damage: float,
	attack_kind: StringName
) -> void:
	if target == null or not target.is_active():
		_record_event(state, &"boss_attack_missed", {"attack": attack_kind})
		return
	_apply_damage(state, catalog, target, damage, attack_kind)


static func _apply_damage(
	state: GameState,
	catalog: ContentCatalog,
	target: OperatorCombatState,
	base_damage: float,
	attack_kind: StringName
) -> void:
	var definition := catalog.get_operator(target.operator_id)
	assert(definition != null, "Boss attack targeted an unknown operator")
	var incoming := base_damage * definition.incoming_multiplier
	var applied := minf(target.current_hp, incoming)
	target.current_hp = maxf(0.0, target.current_hp - incoming)
	target.damage_taken += applied
	_record_event(state, &"operator_damaged", {
		"operator_id": target.operator_id,
		"attack": attack_kind,
		"damage": applied,
	})
	if target.current_hp > EPSILON:
		return

	target.current_hp = 0.0
	target.attack_remaining = INF
	target.down_count += 1
	state.total_operator_down_count += 1
	_record_event(state, &"operator_down", {
		"operator_id": target.operator_id,
		"attack": attack_kind,
	})
	if definition.qa_rescue_enabled:
		state.qa_rescue_consumed = true
		if state.qa_rescue_target_id != &"":
			_cancel_qa_rescue(state, &"qa_process_down")
		return
	_schedule_qa_rescue(state, catalog, target)


static func _schedule_qa_rescue(
	state: GameState,
	catalog: ContentCatalog,
	target: OperatorCombatState
) -> void:
	if state.qa_rescue_consumed or _active_qa_runtime(state, catalog) == null:
		return
	state.qa_rescue_consumed = true
	state.qa_rescue_target_id = target.operator_id
	state.qa_rescue_remaining = catalog.balance.qa_rescue_delay
	_record_event(state, &"qa_rescue_scheduled", {
		"operator_id": target.operator_id,
		"delay": state.qa_rescue_remaining,
	})


static func _cancel_qa_rescue(state: GameState, reason: StringName) -> void:
	var target_id := state.qa_rescue_target_id
	state.qa_rescue_target_id = &""
	state.qa_rescue_remaining = 0.0
	_record_event(state, &"qa_rescue_cancelled", {
		"operator_id": target_id,
		"reason": reason,
	})


static func _mark_failure(state: GameState, reason: StringName) -> void:
	if not state.last_boss_failure_reason.is_empty():
		return
	state.last_boss_failure_reason = reason
	if state.qa_rescue_target_id != &"":
		_cancel_qa_rescue(state, &"attempt_failed")
	_stop_attempt_timers(state)
	_record_event(state, &"boss_attempt_failed", {"reason": reason})


static func _stop_attempt_timers(state: GameState) -> void:
	state.enemy_attack_remaining = INF
	state.boss_special_remaining = INF
	state.boss_rollback_remaining = INF
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF


static func _operator_max_hp(
	state: GameState,
	catalog: ContentCatalog,
	definition: OperatorDefinition
) -> float:
	var level := int(state.operator_levels.get(definition.id, 0))
	if level <= 0:
		return 0.0
	return definition.base_hp * pow(
		catalog.balance.operator_hp_growth,
		float(level - 1)
	)


static func _operator_attack_interval(
	state: GameState,
	catalog: ContentCatalog,
	definition: OperatorDefinition
) -> float:
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	var attack_speed := float(modifiers.attack_speed)
	assert(attack_speed > EPSILON, "Operator attack speed must stay positive")
	var interval := definition.attack_interval / attack_speed
	for ally_definition: OperatorDefinition in catalog.operators:
		var ally_runtime := _runtime(state, ally_definition.id)
		if ally_runtime.is_active():
			interval *= ally_definition.team_interval_multiplier
	return maxf(EPSILON, interval)


static func _operator_attack_damage(
	state: GameState,
	catalog: ContentCatalog,
	definition: OperatorDefinition
) -> float:
	var level := int(state.operator_levels.get(definition.id, 0))
	if level <= 0:
		return 0.0
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	var legacy_multiplier := 1.0 + (
		catalog.balance.legacy_cache_bonus * float(state.legacy_cache_level)
	)
	var damage := (
		ProgressionRules.operator_dps(definition, level)
		* definition.attack_interval
		* definition.outgoing_multiplier
		* definition.boss_multiplier
		* float(modifiers.damage)
		* legacy_multiplier
	)
	if state.stage == 20 and state.boss_debuff_applied:
		damage *= catalog.balance.stage_20_debuff_multiplier
	return damage


static func _operator_effective_dps(
	state: GameState,
	catalog: ContentCatalog,
	definition: OperatorDefinition
) -> float:
	var runtime := _runtime(state, definition.id)
	if not runtime.is_active():
		return 0.0
	return _operator_attack_damage(state, catalog, definition) / _operator_attack_interval(
		state, catalog, definition
	)


static func _highest_threat_target(
	state: GameState,
	catalog: ContentCatalog
) -> OperatorCombatState:
	var selected: OperatorCombatState = null
	var selected_threat := -INF
	for definition: OperatorDefinition in catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not runtime.is_active():
			continue
		if definition.threat_weight > selected_threat + EPSILON:
			selected = runtime
			selected_threat = definition.threat_weight
	return selected


static func _highest_dps_target(
	state: GameState,
	catalog: ContentCatalog
) -> OperatorCombatState:
	var selected: OperatorCombatState = null
	var selected_dps := -INF
	for definition: OperatorDefinition in catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not runtime.is_active():
			continue
		var dps := _operator_effective_dps(state, catalog, definition)
		if dps > selected_dps + EPSILON:
			selected = runtime
			selected_dps = dps
	return selected


static func _active_qa_runtime(
	state: GameState,
	catalog: ContentCatalog
) -> OperatorCombatState:
	for definition: OperatorDefinition in catalog.operators:
		if not definition.qa_rescue_enabled:
			continue
		var runtime := _runtime(state, definition.id)
		if runtime.is_active():
			return runtime
	return null


static func _all_down(state: GameState) -> bool:
	var unlocked := 0
	var active := 0
	for runtime: OperatorCombatState in state.operator_combat_states:
		if not state.is_operator_unlocked(runtime.operator_id):
			continue
		unlocked += 1
		if runtime.is_active():
			active += 1
	return unlocked > 0 and active == 0


static func _unlocked_operator_count(state: GameState) -> int:
	var count := 0
	for runtime: OperatorCombatState in state.operator_combat_states:
		if state.is_operator_unlocked(runtime.operator_id):
			count += 1
	return count


static func _is_unlocked(state: GameState, operator_id: StringName) -> bool:
	return (
		state.is_operator_unlocked(operator_id)
		and int(state.operator_levels.get(operator_id, 0)) > 0
	)


static func _runtime(state: GameState, operator_id: StringName) -> OperatorCombatState:
	var runtime := state.get_operator_combat_state(operator_id)
	assert(runtime != null, "Missing operator combat state: %s" % operator_id)
	return runtime


static func _poll_interval(state: GameState, balance: BalanceDefinition) -> float:
	return balance.stage_20_poll_interval if state.stage == 20 else balance.stage_10_poll_interval


static func _poll_damage(state: GameState, balance: BalanceDefinition) -> float:
	return balance.stage_20_poll_damage if state.stage == 20 else balance.stage_10_poll_damage


static func _special_interval(state: GameState, catalog: ContentCatalog) -> float:
	var base_interval := (
		catalog.balance.stage_20_special_interval
		if state.stage == 20
		else catalog.balance.stage_10_special_interval
	)
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	return base_interval * float(modifiers.boss_special_interval)


static func _special_damage(state: GameState, balance: BalanceDefinition) -> float:
	return (
		balance.stage_20_special_damage
		if state.stage == 20
		else balance.stage_10_special_damage
	)


static func _rollback_interval(state: GameState, catalog: ContentCatalog) -> float:
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	return (
		ProgressionRules.boss_recovery_interval(state.stage, catalog.balance)
		* float(modifiers.boss_special_interval)
	)


static func _record_event(
	state: GameState,
	kind: StringName,
	details: Dictionary = {}
) -> void:
	state.boss_event_serial += 1
	var event: Dictionary = {}
	for raw_key: Variant in details.keys():
		var value: Variant = details[raw_key]
		event[String(raw_key)] = String(value) if value is StringName else value
	event["serial"] = state.boss_event_serial
	event["kind"] = String(kind)
	event["time"] = state.boss_elapsed
	event["stage"] = state.stage
	event["attempt_serial"] = state.boss_attempt_serial
	state.recent_boss_events.append(event)
	if state.recent_boss_events.size() > MAX_RECENT_BOSS_EVENTS:
		state.recent_boss_events.pop_front()


static func _is_terminal(state: GameState) -> bool:
	return state.enemy_health <= EPSILON or not state.last_boss_failure_reason.is_empty()
