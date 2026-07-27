class_name NightShiftSimulator
extends RefCounted

const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const NightShiftState := preload(
	"res://game/domain/product_v2/night_shift_state.gd"
)
const EPSILON := 0.000001
const MAX_EVENTS_PER_ADVANCE := 100000


static func create_state(
	catalog: ProductV2Catalog,
	shift_index: int,
	operator_levels: Dictionary,
	unlocked_operator_ids: Array[StringName],
	equipped_patch_ids: Array[StringName] = [],
	legacy_cache_level: int = 0
) -> NightShiftState:
	_validate_creation_inputs(
		catalog,
		shift_index,
		operator_levels,
		unlocked_operator_ids,
		equipped_patch_ids,
		legacy_cache_level
	)

	var state := NightShiftState.new()
	state.shift_index = shift_index
	state.phase = NightShiftState.Phase.COUNTDOWN
	state.phase_remaining = catalog.balance.countdown_seconds
	state.stability = catalog.balance.max_stability
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var level := _input_operator_level(operator_levels, definition.id)
		if level > 0:
			state.operator_levels[definition.id] = level
	state.unlocked_operator_ids.assign(unlocked_operator_ids)
	state.equipped_patch_ids.assign(equipped_patch_ids)
	state.legacy_cache_level = legacy_cache_level

	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := OperatorCombatState.new(definition.id)
		if _is_unlocked(state, definition.id):
			runtime.current_hp = _operator_max_hp(state, catalog, definition)
		state.operator_combat_states.append(runtime)

	state.record_event(&"night_shift_started", {
		"countdown_seconds": catalog.balance.countdown_seconds,
	})
	return state


static func advance(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	available_seconds: float
) -> float:
	assert(state != null, "Night shift simulation requires a state")
	assert(catalog != null and catalog.base_catalog != null, "Night shift simulation requires content")
	assert(
		catalog.get_shift(state.shift_index) != null,
		"Night shift state refers to unknown shift %d" % state.shift_index
	)
	assert(
		is_finite(available_seconds) and available_seconds >= 0.0,
		"Night shift advance time must be a non-negative finite number"
	)
	if available_seconds <= 0.0 or state.is_terminal():
		return 0.0
	if state.phase == NightShiftState.Phase.BOSS_ACTIVE and _all_down(state):
		_mark_failure(state, &"boss_all_down")
		return 0.0

	var remaining := available_seconds
	var consumed := 0.0
	var processed_events := 0
	while remaining > 0.0 and not state.is_terminal():
		assert(
			processed_events <= MAX_EVENTS_PER_ADVANCE,
			"Night shift event loop exceeded its safety limit"
		)
		var next_event := _next_event_time(state, catalog)
		assert(
			not is_nan(next_event) and next_event >= 0.0,
			"Night shift produced an invalid next event time"
		)
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
		assert(batch_events > 0, "Night shift simulation reached a zero-time event loop")
		processed_events += batch_events
	return consumed


static func operator_max_hp(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	operator_id: StringName
) -> float:
	var definition := catalog.base_catalog.get_operator(operator_id)
	assert(definition != null, "Unknown Product V2 operator: %s" % operator_id)
	return _operator_max_hp(state, catalog, definition)


static func operator_effective_dps(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	operator_id: StringName
) -> float:
	var definition := catalog.base_catalog.get_operator(operator_id)
	assert(definition != null, "Unknown Product V2 operator: %s" % operator_id)
	var runtime := _runtime(state, operator_id)
	if not runtime.is_active():
		return 0.0
	var boss_target := state.phase == NightShiftState.Phase.BOSS_ACTIVE
	return _operator_attack_damage(state, catalog, definition, boss_target) / (
		_operator_attack_interval(state, catalog, definition)
	)


static func _validate_creation_inputs(
	catalog: ProductV2Catalog,
	shift_index: int,
	operator_levels: Dictionary,
	unlocked_operator_ids: Array[StringName],
	equipped_patch_ids: Array[StringName],
	legacy_cache_level: int
) -> void:
	assert(
		catalog != null and catalog.base_catalog != null and catalog.balance != null,
		"Night shift creation requires loaded Product V2 content"
	)
	assert(catalog.get_shift(shift_index) != null, "Unknown Product V2 shift: %d" % shift_index)
	assert(legacy_cache_level >= 0, "Legacy cache level cannot be negative")
	assert(not unlocked_operator_ids.is_empty(), "A night shift requires an unlocked operator")

	var seen_operators: Dictionary = {}
	var active_operator_count := 0
	for operator_id: StringName in unlocked_operator_ids:
		assert(operator_id != &"", "Unlocked operator id cannot be empty")
		assert(not seen_operators.has(operator_id), "Duplicate unlocked operator: %s" % operator_id)
		seen_operators[operator_id] = true
		var definition := catalog.base_catalog.get_operator(operator_id)
		assert(definition != null, "Unknown unlocked operator: %s" % operator_id)
		var level := _input_operator_level(operator_levels, operator_id)
		assert(level > 0, "Unlocked operator must have a positive level: %s" % operator_id)
		active_operator_count += 1
	assert(active_operator_count > 0, "A night shift requires an active operator")

	for raw_operator_id: Variant in operator_levels.keys():
		var operator_id := StringName(String(raw_operator_id))
		assert(
			catalog.base_catalog.has_operator(operator_id),
			"Unknown operator level entry: %s" % operator_id
		)
		var raw_level: Variant = operator_levels[raw_operator_id]
		assert(
			raw_level is int or raw_level is float,
			"Operator level must be numeric: %s" % operator_id
		)
		var level_number := float(raw_level)
		assert(
			is_finite(level_number)
			and level_number >= 0.0
			and is_equal_approx(level_number, floor(level_number)),
			"Operator level must be a non-negative integer: %s" % operator_id
		)

	var seen_patches: Dictionary = {}
	for patch_id: StringName in equipped_patch_ids:
		if patch_id == &"":
			continue
		assert(not seen_patches.has(patch_id), "Duplicate equipped patch: %s" % patch_id)
		seen_patches[patch_id] = true
		assert(catalog.base_catalog.has_patch(patch_id), "Unknown equipped patch: %s" % patch_id)


static func _input_operator_level(
	operator_levels: Dictionary,
	operator_id: StringName
) -> int:
	if operator_levels.has(operator_id):
		return int(operator_levels[operator_id])
	return int(operator_levels.get(String(operator_id), 0))


static func _next_event_time(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> float:
	match state.phase:
		NightShiftState.Phase.COUNTDOWN:
			return maxf(0.0, state.phase_remaining)
		NightShiftState.Phase.INTER_WAVE:
			return maxf(0.0, state.phase_remaining)
		NightShiftState.Phase.BOSS_WARNING:
			return maxf(0.0, state.phase_remaining)
		NightShiftState.Phase.NORMAL_ACTIVE:
			var next_normal := maxf(0.0, state.phase_remaining)
			for runtime: OperatorCombatState in state.operator_combat_states:
				if _is_active_for_normal(state, runtime):
					next_normal = minf(next_normal, runtime.attack_remaining)
			return maxf(0.0, next_normal)
		NightShiftState.Phase.BOSS_ACTIVE:
			var next_boss := maxf(0.0, state.phase_remaining)
			if state.qa_rescue_target_id != &"":
				next_boss = minf(next_boss, state.qa_rescue_remaining)
			for runtime: OperatorCombatState in state.operator_combat_states:
				if runtime.is_active():
					next_boss = minf(next_boss, runtime.attack_remaining)
			next_boss = minf(next_boss, state.boss_poll_remaining)
			next_boss = minf(next_boss, state.boss_special_remaining)
			next_boss = minf(next_boss, state.boss_rollback_remaining)
			var boss := catalog.get_shift(state.shift_index).boss
			if not state.boss_debuff_applied and boss.debuff_start_seconds > 0.0:
				next_boss = minf(
					next_boss,
					maxf(0.0, boss.debuff_start_seconds - state.boss_elapsed)
				)
			return maxf(0.0, next_boss)
	return INF


static func _advance_time(state: NightShiftState, seconds: float) -> void:
	state.total_elapsed += seconds
	state.phase_remaining = maxf(0.0, state.phase_remaining - seconds)
	match state.phase:
		NightShiftState.Phase.NORMAL_ACTIVE:
			state.combat_elapsed += seconds
			state.wave_elapsed += seconds
			for runtime: OperatorCombatState in state.operator_combat_states:
				if _is_active_for_normal(state, runtime):
					runtime.attack_remaining = maxf(0.0, runtime.attack_remaining - seconds)
		NightShiftState.Phase.BOSS_ACTIVE:
			state.combat_elapsed += seconds
			state.boss_elapsed += seconds
			if state.qa_rescue_target_id != &"":
				state.qa_rescue_remaining = maxf(0.0, state.qa_rescue_remaining - seconds)
			for runtime: OperatorCombatState in state.operator_combat_states:
				if not _is_unlocked(state, runtime.operator_id):
					continue
				if runtime.is_active():
					runtime.attack_remaining = maxf(0.0, runtime.attack_remaining - seconds)
					runtime.active_time += seconds
				else:
					runtime.down_time += seconds
					state.total_operator_down_time += seconds
			state.boss_poll_remaining = maxf(0.0, state.boss_poll_remaining - seconds)
			state.boss_special_remaining = maxf(0.0, state.boss_special_remaining - seconds)
			state.boss_rollback_remaining = maxf(0.0, state.boss_rollback_remaining - seconds)


static func _process_due_events(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> int:
	match state.phase:
		NightShiftState.Phase.COUNTDOWN:
			if state.phase_remaining > EPSILON:
				return 0
			_start_normal_wave(state, catalog, 1)
			return 1
		NightShiftState.Phase.INTER_WAVE:
			if state.phase_remaining > EPSILON:
				return 0
			_start_normal_wave(state, catalog, state.completed_waves + 1)
			return 1
		NightShiftState.Phase.BOSS_WARNING:
			if state.phase_remaining > EPSILON:
				return 0
			_start_boss(state, catalog)
			return 1
		NightShiftState.Phase.NORMAL_ACTIVE:
			return _process_normal_events(state, catalog)
		NightShiftState.Phase.BOSS_ACTIVE:
			return _process_boss_events(state, catalog)
	return 0


static func _start_normal_wave(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	wave_number: int
) -> void:
	var shift := catalog.get_shift(state.shift_index)
	var wave: ProductV2Catalog.WaveProfile = null
	for candidate: ProductV2Catalog.WaveProfile in shift.waves:
		if candidate.number == wave_number:
			wave = candidate
			break
	assert(wave != null, "Missing Product V2 wave %d" % wave_number)

	state.phase = NightShiftState.Phase.NORMAL_ACTIVE
	state.current_wave = wave_number
	state.wave_elapsed = 0.0
	state.phase_remaining = catalog.balance.normal_wave_seconds
	state.enemies.clear()
	state.last_wave_leak_damage = 0

	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids,
		catalog.base_catalog
	)
	for entry: ProductV2Catalog.WaveEntry in wave.entries:
		var archetype := catalog.get_enemy(entry.enemy_id)
		assert(archetype != null, "Wave refers to unknown enemy: %s" % entry.enemy_id)
		var max_hp := (
			archetype.base_hp
			* wave.hp_multiplier
			* shift.health_multiplier
			* float(modifiers.enemy_health)
		)
		for _enemy_index: int in range(entry.count):
			state.enemies.append(NightShiftState.EnemyRuntime.new(
				state.next_enemy_serial,
				entry.enemy_id,
				max_hp,
				archetype.leak_damage
			))
			state.next_enemy_serial += 1

	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := _runtime(state, definition.id)
		runtime.attack_remaining = (
			_operator_attack_interval(state, catalog, definition)
			if _is_active_for_normal(state, runtime)
			else INF
		)
	state.record_event(&"normal_wave_started", {
		"enemy_count": state.enemies.size(),
		"duration": state.phase_remaining,
	})


static func _process_normal_events(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> int:
	var processed := _process_normal_operator_attacks(state, catalog)
	if not _has_living_enemy(state):
		_complete_normal_wave(state, catalog, false)
		return processed + 1
	if state.phase_remaining <= EPSILON:
		_resolve_wave_leak(state, catalog)
		processed += 1
		if state.stability <= 0:
			_mark_failure(state, &"stability_depleted")
			return processed + 1
		_complete_normal_wave(state, catalog, true)
		return processed + 1
	return processed


static func _process_normal_operator_attacks(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> int:
	var processed := 0
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not _is_active_for_normal(state, runtime) or runtime.attack_remaining > EPSILON:
			continue
		var target := _first_living_enemy(state)
		if target == null:
			break
		var damage := _operator_attack_damage(state, catalog, definition, false)
		var applied := minf(target.current_hp, damage)
		target.current_hp = maxf(0.0, target.current_hp - damage)
		runtime.damage_dealt += applied
		runtime.attack_remaining = _operator_attack_interval(state, catalog, definition)
		processed += 1
		state.record_event(&"operator_attacked", {
			"operator_id": definition.id,
			"target_serial": target.serial,
			"damage": applied,
		})
		if target.current_hp <= EPSILON:
			target.current_hp = 0.0
			state.total_enemies_defeated += 1
			state.record_event(&"enemy_defeated", {
				"enemy_id": target.enemy_id,
				"enemy_serial": target.serial,
			})
	return processed


static func _resolve_wave_leak(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> void:
	var raw_damage := 0
	var leaked_count := 0
	for enemy: NightShiftState.EnemyRuntime in state.enemies:
		if not enemy.is_alive():
			continue
		raw_damage += enemy.leak_damage
		leaked_count += 1
	var applied_damage := mini(raw_damage, catalog.balance.wave_leak_cap)
	state.last_wave_leak_damage = applied_damage
	state.largest_wave_leak_damage = maxi(state.largest_wave_leak_damage, applied_damage)
	state.total_leak_damage += applied_damage
	state.total_enemies_leaked += leaked_count
	state.stability = maxi(0, state.stability - applied_damage)
	state.enemies.clear()
	state.record_event(&"wave_leak_resolved", {
		"enemy_count": leaked_count,
		"raw_damage": raw_damage,
		"applied_damage": applied_damage,
		"capped": raw_damage > applied_damage,
		"stability": state.stability,
	})


static func _complete_normal_wave(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	had_leak: bool
) -> void:
	state.completed_waves += 1
	state.enemies.clear()
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF
	state.record_event(&"normal_wave_completed", {
		"had_leak": had_leak,
		"completed_waves": state.completed_waves,
		"stability": state.stability,
	})

	if state.completed_waves >= 9:
		state.phase = NightShiftState.Phase.BOSS_WARNING
		state.phase_remaining = catalog.balance.boss_warning_seconds
		state.record_event(&"boss_warning_started", {
			"duration": state.phase_remaining,
		})
		return
	state.phase = NightShiftState.Phase.INTER_WAVE
	state.phase_remaining = catalog.balance.transition_seconds
	state.record_event(&"inter_wave_started", {
		"duration": state.phase_remaining,
	})


static func _start_boss(state: NightShiftState, catalog: ProductV2Catalog) -> void:
	var shift := catalog.get_shift(state.shift_index)
	var boss := shift.boss
	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids,
		catalog.base_catalog
	)

	state.phase = NightShiftState.Phase.BOSS_ACTIVE
	state.current_wave = 10
	state.phase_remaining = catalog.balance.boss_seconds
	state.boss_elapsed = 0.0
	state.boss_max_hp = boss.max_hp * float(modifiers.enemy_health)
	state.boss_hp = state.boss_max_hp
	state.boss_poll_remaining = boss.poll_interval
	state.boss_special_remaining = (
		boss.special_interval * float(modifiers.boss_special_interval)
	)
	state.boss_rollback_remaining = (
		boss.rollback_interval * float(modifiers.boss_special_interval)
	)
	state.boss_debuff_applied = false
	state.boss_recovery_count = 0
	state.boss_recovered_health = 0.0
	state.qa_rescue_consumed = false
	state.qa_rescue_target_id = &""
	state.qa_rescue_remaining = 0.0
	state.qa_rescue_count = 0
	state.operator_down_records.clear()
	state.qa_rescue_outcome = &"unused"
	state.qa_rescue_outcome_target_id = &""
	state.qa_rescue_outcome_reason = &""
	state.qa_rescue_outcome_time = 0.0

	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := _runtime(state, definition.id)
		runtime.current_hp = (
			_operator_max_hp(state, catalog, definition)
			if _is_unlocked(state, definition.id)
			else 0.0
		)
		runtime.attack_remaining = (
			_operator_attack_interval(state, catalog, definition)
			if runtime.is_active()
			else INF
		)
		runtime.damage_dealt = 0.0
		runtime.damage_taken = 0.0
		runtime.down_count = 0
		runtime.active_time = 0.0
		runtime.down_time = 0.0

	state.record_event(&"boss_started", {
		"boss_id": boss.id,
		"max_hp": state.boss_max_hp,
		"duration": state.phase_remaining,
	})


static func _process_boss_events(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> int:
	var processed := _process_qa_rescue(state, catalog)
	processed += _process_boss_operator_attacks(state, catalog)
	if state.boss_hp <= EPSILON:
		_mark_success(state)
		return processed + 1

	var boss := catalog.get_shift(state.shift_index).boss
	if state.boss_poll_remaining <= EPSILON:
		_process_boss_poll(state, catalog)
		processed += 1
		if state.is_terminal():
			return processed
	if state.boss_special_remaining <= EPSILON:
		_process_boss_special(state, catalog)
		processed += 1
		if state.is_terminal():
			return processed
	if state.boss_rollback_remaining <= EPSILON:
		_process_boss_rollback(state, catalog)
		processed += 1
	if (
		not state.boss_debuff_applied
		and boss.debuff_start_seconds > 0.0
		and state.boss_elapsed + EPSILON >= boss.debuff_start_seconds
	):
		state.boss_debuff_applied = true
		state.record_event(&"boss_debuff_applied", {
			"multiplier": boss.debuff_multiplier,
		})
		processed += 1
	if state.phase_remaining <= EPSILON and state.boss_hp > EPSILON:
		_mark_failure(state, &"boss_timeout")
		processed += 1
	return processed


static func _process_qa_rescue(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> int:
	if state.qa_rescue_target_id == &"" or state.qa_rescue_remaining > EPSILON:
		return 0
	var target := state.get_operator_combat_state(state.qa_rescue_target_id)
	assert(target != null, "QA rescue target must exist in Product V2 state")
	var qa_runtime := _active_qa_runtime(state, catalog)
	if qa_runtime == null:
		_cancel_qa_rescue(state, &"qa_unavailable")
		return 1
	if target.is_active():
		_cancel_qa_rescue(state, &"target_already_active")
		return 1
	var definition := catalog.base_catalog.get_operator(target.operator_id)
	assert(definition != null, "QA rescue target must have operator content")
	target.current_hp = (
		_operator_max_hp(state, catalog, definition)
		* catalog.balance.qa_rescue_hp_fraction
	)
	target.attack_remaining = _operator_attack_interval(state, catalog, definition)
	state.qa_rescue_target_id = &""
	state.qa_rescue_remaining = 0.0
	state.qa_rescue_count += 1
	state.record_qa_rescue_outcome(&"succeeded", target.operator_id)
	state.record_event(&"qa_rescue_succeeded", {
		"operator_id": target.operator_id,
		"hp": target.current_hp,
	})
	return 1


static func _process_boss_operator_attacks(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> int:
	var processed := 0
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not runtime.is_active() or runtime.attack_remaining > EPSILON:
			continue
		var damage := _operator_attack_damage(state, catalog, definition, true)
		var applied := minf(state.boss_hp, damage)
		state.boss_hp = maxf(0.0, state.boss_hp - damage)
		runtime.damage_dealt += applied
		runtime.attack_remaining = _operator_attack_interval(state, catalog, definition)
		processed += 1
		state.record_event(&"operator_attacked_boss", {
			"operator_id": definition.id,
			"damage": applied,
		})
		if state.boss_hp <= EPSILON:
			break
	return processed


static func _process_boss_poll(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> void:
	var boss := catalog.get_shift(state.shift_index).boss
	var target := _highest_threat_target(state, catalog)
	_attack_operator(state, catalog, target, boss.poll_damage, &"boss_poll")
	state.boss_poll_remaining = boss.poll_interval
	if _all_down(state):
		_mark_failure(state, &"boss_all_down")


static func _process_boss_special(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> void:
	var boss := catalog.get_shift(state.shift_index).boss
	var target := _highest_dps_target(state, catalog)
	_attack_operator(state, catalog, target, boss.special_damage, &"boss_special")
	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids,
		catalog.base_catalog
	)
	state.boss_special_remaining = (
		boss.special_interval * float(modifiers.boss_special_interval)
	)
	if _all_down(state):
		_mark_failure(state, &"boss_all_down")


static func _process_boss_rollback(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> void:
	var boss := catalog.get_shift(state.shift_index).boss
	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids,
		catalog.base_catalog
	)
	var requested := (
		state.boss_max_hp
		* boss.rollback_fraction
		* float(modifiers.boss_recovery)
	)
	var previous_hp := state.boss_hp
	state.boss_hp = minf(state.boss_max_hp, previous_hp + requested)
	var healed := state.boss_hp - previous_hp
	state.boss_recovery_count += 1
	state.boss_recovered_health += healed
	state.boss_rollback_remaining = (
		boss.rollback_interval * float(modifiers.boss_special_interval)
	)
	state.record_event(&"boss_rollback", {"healed": healed})


static func _attack_operator(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	target: OperatorCombatState,
	base_damage: float,
	attack_kind: StringName
) -> void:
	if target == null or not target.is_active():
		state.record_event(&"boss_attack_missed", {"attack": attack_kind})
		return
	var definition := catalog.base_catalog.get_operator(target.operator_id)
	assert(definition != null, "Boss attack targeted an unknown Product V2 operator")
	var incoming := base_damage * definition.incoming_multiplier
	var applied := minf(target.current_hp, incoming)
	target.current_hp = maxf(0.0, target.current_hp - incoming)
	target.damage_taken += applied
	state.record_event(&"operator_damaged", {
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
	state.record_operator_down(target.operator_id, attack_kind, state.boss_elapsed)
	state.record_event(&"operator_down", {
		"operator_id": target.operator_id,
		"attack": attack_kind,
		"boss_time": state.boss_elapsed,
	})
	if definition.qa_rescue_enabled:
		if state.qa_rescue_target_id != &"":
			_cancel_qa_rescue(state, &"qa_process_down")
		return
	_schedule_qa_rescue(state, catalog, target)


static func _schedule_qa_rescue(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	target: OperatorCombatState
) -> void:
	if state.qa_rescue_consumed or _active_qa_runtime(state, catalog) == null:
		return
	state.qa_rescue_consumed = true
	state.qa_rescue_target_id = target.operator_id
	state.qa_rescue_remaining = catalog.balance.qa_rescue_delay
	state.record_qa_rescue_outcome(&"scheduled", target.operator_id)
	state.record_event(&"qa_rescue_scheduled", {
		"operator_id": target.operator_id,
		"delay": state.qa_rescue_remaining,
	})


static func _cancel_qa_rescue(state: NightShiftState, reason: StringName) -> void:
	var target_id := state.qa_rescue_target_id
	state.qa_rescue_target_id = &""
	state.qa_rescue_remaining = 0.0
	state.record_qa_rescue_outcome(&"cancelled", target_id, reason)
	state.record_event(&"qa_rescue_cancelled", {
		"operator_id": target_id,
		"reason": reason,
	})


static func _mark_success(state: NightShiftState) -> void:
	if state.is_terminal():
		return
	state.boss_hp = 0.0
	state.completed_waves = 10
	state.phase = NightShiftState.Phase.SUCCESS
	state.phase_remaining = 0.0
	state.terminal_reason = &"boss_defeated"
	_stop_combat_timers(state)
	state.record_event(&"night_shift_succeeded")


static func _mark_failure(state: NightShiftState, reason: StringName) -> void:
	if state.is_terminal():
		return
	if state.qa_rescue_target_id != &"":
		_cancel_qa_rescue(state, &"night_shift_failed")
	state.phase = NightShiftState.Phase.FAILURE
	state.phase_remaining = 0.0
	state.terminal_reason = reason
	_stop_combat_timers(state)
	state.record_event(&"night_shift_failed", {"reason": reason})


static func _stop_combat_timers(state: NightShiftState) -> void:
	state.boss_poll_remaining = INF
	state.boss_special_remaining = INF
	state.boss_rollback_remaining = INF
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF


static func _operator_max_hp(
	state: NightShiftState,
	catalog: ProductV2Catalog,
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
	state: NightShiftState,
	catalog: ProductV2Catalog,
	definition: OperatorDefinition
) -> float:
	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids,
		catalog.base_catalog
	)
	var attack_speed := float(modifiers.attack_speed)
	assert(attack_speed > EPSILON, "Product V2 operator attack speed must stay positive")
	var interval := definition.attack_interval / attack_speed
	for ally_definition: OperatorDefinition in catalog.base_catalog.operators:
		var ally_runtime := _runtime(state, ally_definition.id)
		if (
			_is_unlocked(state, ally_definition.id)
			and ally_runtime.is_active()
		):
			interval *= ally_definition.team_interval_multiplier
	return maxf(EPSILON, interval)


static func _operator_attack_damage(
	state: NightShiftState,
	catalog: ProductV2Catalog,
	definition: OperatorDefinition,
	boss_target: bool
) -> float:
	var level := int(state.operator_levels.get(definition.id, 0))
	if level <= 0:
		return 0.0
	var modifiers := ProgressionRules.patch_modifiers(
		state.equipped_patch_ids,
		catalog.base_catalog
	)
	var legacy_multiplier := 1.0 + (
		catalog.base_catalog.balance.legacy_cache_bonus
		* float(state.legacy_cache_level)
	)
	var damage := (
		ProgressionRules.operator_dps(definition, level)
		* definition.attack_interval
		* definition.outgoing_multiplier
		* float(modifiers.damage)
		* legacy_multiplier
	)
	if boss_target:
		damage *= definition.boss_multiplier
		var boss := catalog.get_shift(state.shift_index).boss
		if state.boss_debuff_applied:
			damage *= boss.debuff_multiplier
	return damage


static func _highest_threat_target(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> OperatorCombatState:
	var selected: OperatorCombatState = null
	var selected_threat := -INF
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not runtime.is_active():
			continue
		if definition.threat_weight > selected_threat + EPSILON:
			selected = runtime
			selected_threat = definition.threat_weight
	return selected


static func _highest_dps_target(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> OperatorCombatState:
	var selected: OperatorCombatState = null
	var selected_dps := -INF
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var runtime := _runtime(state, definition.id)
		if not runtime.is_active():
			continue
		var dps := operator_effective_dps(state, catalog, definition.id)
		if dps > selected_dps + EPSILON:
			selected = runtime
			selected_dps = dps
	return selected


static func _active_qa_runtime(
	state: NightShiftState,
	catalog: ProductV2Catalog
) -> OperatorCombatState:
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		if not definition.qa_rescue_enabled:
			continue
		var runtime := _runtime(state, definition.id)
		if runtime.is_active():
			return runtime
	return null


static func _all_down(state: NightShiftState) -> bool:
	var unlocked := 0
	var active := 0
	for runtime: OperatorCombatState in state.operator_combat_states:
		if not _is_unlocked(state, runtime.operator_id):
			continue
		unlocked += 1
		if runtime.is_active():
			active += 1
	return unlocked > 0 and active == 0


static func _is_unlocked(state: NightShiftState, operator_id: StringName) -> bool:
	return (
		state.unlocked_operator_ids.has(operator_id)
		and int(state.operator_levels.get(operator_id, 0)) > 0
	)


static func _is_active_for_normal(
	state: NightShiftState,
	runtime: OperatorCombatState
) -> bool:
	return _is_unlocked(state, runtime.operator_id)


static func _runtime(
	state: NightShiftState,
	operator_id: StringName
) -> OperatorCombatState:
	var runtime := state.get_operator_combat_state(operator_id)
	assert(runtime != null, "Missing Product V2 operator runtime: %s" % operator_id)
	return runtime


static func _first_living_enemy(state: NightShiftState) -> NightShiftState.EnemyRuntime:
	for enemy: NightShiftState.EnemyRuntime in state.enemies:
		if enemy.is_alive():
			return enemy
	return null


static func _has_living_enemy(state: NightShiftState) -> bool:
	return _first_living_enemy(state) != null
