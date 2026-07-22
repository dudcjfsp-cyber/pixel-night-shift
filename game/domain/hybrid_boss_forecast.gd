class_name HybridBossForecast
extends RefCounted

const EPSILON := 0.000001


static func estimate(state: GameState, catalog: ContentCatalog) -> Dictionary:
	assert(state != null, "Hybrid boss forecast requires a state")
	assert(
		catalog != null and catalog.balance != null,
		"Hybrid boss forecast requires content"
	)
	assert(
		ProgressionRules.is_boss_stage(state.stage) and not state.is_maintenance,
		"Hybrid boss forecast only evaluates an active boss attempt"
	)

	var forecast_state := state.deep_clone()
	if (
		forecast_state.operator_combat_states.is_empty()
		or not is_finite(forecast_state.enemy_attack_remaining)
	) and forecast_state.last_boss_failure_reason.is_empty():
		forecast_state.boss_attempt_serial += 1
		HybridBossSimulator.reset_attempt(forecast_state, catalog)

	var initial_elapsed := forecast_state.boss_elapsed
	var initial_healed := forecast_state.boss_recovered_health
	var initial_downs := forecast_state.total_operator_down_count
	var initial_qa_rescues := forecast_state.qa_rescue_count
	var initial_event_serial := forecast_state.boss_event_serial
	var initial_team_hp := _team_hp(forecast_state)
	var initial_metrics := _operator_metrics(forecast_state)
	var qa_available := _qa_rescue_available(forecast_state, catalog)

	if (
		forecast_state.enemy_health > EPSILON
		and forecast_state.last_boss_failure_reason.is_empty()
	):
		var remaining_limit := maxf(
			0.0,
			catalog.balance.boss_time_limit - forecast_state.boss_elapsed
		)
		# The epsilon lets a state exactly on the deadline process its zero-time
		# timeout event. A successful attack tied with the deadline still wins
		# because HybridBossSimulator owns the event ordering.
		HybridBossSimulator.advance(
			forecast_state,
			catalog,
			remaining_limit + EPSILON
		)

	var resolved := forecast_state.enemy_health <= EPSILON
	var failed := not forecast_state.last_boss_failure_reason.is_empty()
	var operator_results := _operator_results(
		forecast_state,
		catalog,
		initial_metrics
	)
	var ending_down_count := _down_count(forecast_state)
	var unlocked_count := _unlocked_count(forecast_state)
	var future_downs := forecast_state.total_operator_down_count - initial_downs
	var future_events := _events_after(forecast_state, initial_event_serial)
	var max_enemy_hp := ProgressionRules.current_enemy_max_hp(forecast_state, catalog)
	assert(max_enemy_hp > EPSILON, "Hybrid boss forecast requires positive boss HP")
	var healed := forecast_state.boss_recovered_health - initial_healed
	var seconds := maxf(0.0, forecast_state.boss_elapsed - initial_elapsed)

	return {
		"resolved": resolved,
		"failed": failed,
		"attempt_ended": resolved or failed,
		"seconds": seconds,
		"remaining_limit": maxf(
			0.0,
			catalog.balance.boss_time_limit - initial_elapsed
		),
		"failure_reason": String(forecast_state.last_boss_failure_reason),
		"enemy_health": forecast_state.enemy_health,
		"enemy_max_hp": max_enemy_hp,
		"downs": future_downs,
		"ending_down_count": ending_down_count,
		"unlocked_operator_count": unlocked_count,
		"all_down": unlocked_count > 0 and ending_down_count == unlocked_count,
		"wipe_risk": _wipe_risk(
			failed,
			forecast_state.last_boss_failure_reason,
			future_downs,
			ending_down_count,
			unlocked_count
		),
		"team_hp": initial_team_hp,
		"team_max_hp": _team_max_hp(forecast_state, catalog),
		"ending_team_hp": _team_hp(forecast_state),
		"boss_healed": healed,
		"boss_healed_ratio": healed / max_enemy_hp,
		"attempt_boss_healed_ratio": (
			forecast_state.boss_recovered_health / max_enemy_hp
		),
		"qa_rescue_available": qa_available,
		"qa_rescue_pending": state.qa_rescue_target_id != &"",
		"qa_rescues": forecast_state.qa_rescue_count - initial_qa_rescues,
		"operator_results": operator_results,
		"events": future_events,
	}


static func _operator_metrics(state: GameState) -> Dictionary:
	var metrics: Dictionary = {}
	for runtime: OperatorCombatState in state.operator_combat_states:
		metrics[runtime.operator_id] = {
			"hp": runtime.current_hp,
			"damage_dealt": runtime.damage_dealt,
			"damage_taken": runtime.damage_taken,
			"down_count": runtime.down_count,
			"active_time": runtime.active_time,
			"down_time": runtime.down_time,
		}
	return metrics


static func _operator_results(
	state: GameState,
	catalog: ContentCatalog,
	initial_metrics: Dictionary
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for definition: OperatorDefinition in catalog.operators:
		if not _is_unlocked(state, definition.id):
			continue
		var runtime := state.get_operator_combat_state(definition.id)
		assert(runtime != null, "Forecast operator runtime must exist")
		var initial: Dictionary = initial_metrics.get(definition.id, {})
		results.append({
			"operator_id": String(definition.id),
			"start_hp": float(initial.get("hp", runtime.current_hp)),
			"ending_hp": runtime.current_hp,
			"max_hp": HybridBossSimulator.operator_max_hp(
				state, catalog, definition.id
			),
			"down": not runtime.is_active(),
			"downs": runtime.down_count - int(initial.get("down_count", 0)),
			"damage_dealt": (
				runtime.damage_dealt - float(initial.get("damage_dealt", 0.0))
			),
			"damage_taken": (
				runtime.damage_taken - float(initial.get("damage_taken", 0.0))
			),
			"active_seconds": (
				runtime.active_time - float(initial.get("active_time", 0.0))
			),
			"down_seconds": (
				runtime.down_time - float(initial.get("down_time", 0.0))
			),
		})
	return results


static func _events_after(state: GameState, serial: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event: Dictionary in state.recent_boss_events:
		if int(event.get("serial", 0)) > serial:
			events.append(event.duplicate(true))
	return events


static func _qa_rescue_available(state: GameState, catalog: ContentCatalog) -> bool:
	if state.qa_rescue_consumed:
		return false
	for definition: OperatorDefinition in catalog.operators:
		if not definition.qa_rescue_enabled:
			continue
		var runtime := state.get_operator_combat_state(definition.id)
		return runtime != null and runtime.is_active()
	return false


static func _team_hp(state: GameState) -> float:
	var total := 0.0
	for runtime: OperatorCombatState in state.operator_combat_states:
		if state.is_operator_unlocked(runtime.operator_id):
			total += runtime.current_hp
	return total


static func _team_max_hp(state: GameState, catalog: ContentCatalog) -> float:
	var total := 0.0
	for definition: OperatorDefinition in catalog.operators:
		if _is_unlocked(state, definition.id):
			total += HybridBossSimulator.operator_max_hp(state, catalog, definition.id)
	return total


static func _down_count(state: GameState) -> int:
	var count := 0
	for runtime: OperatorCombatState in state.operator_combat_states:
		if state.is_operator_unlocked(runtime.operator_id) and not runtime.is_active():
			count += 1
	return count


static func _unlocked_count(state: GameState) -> int:
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


static func _wipe_risk(
	failed: bool,
	failure_reason: StringName,
	future_downs: int,
	ending_down_count: int,
	unlocked_count: int
) -> String:
	if failed and failure_reason == &"boss_all_down":
		return "high"
	if unlocked_count > 0 and ending_down_count >= unlocked_count - 1:
		return "medium"
	if future_downs > 0 or ending_down_count > 0:
		return "medium"
	return "low"
