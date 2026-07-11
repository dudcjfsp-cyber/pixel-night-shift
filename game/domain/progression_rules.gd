class_name ProgressionRules
extends RefCounted

const ESTIMATE_EPSILON := 0.000001
const MAX_ESTIMATE_EVENTS := 256
const MAX_ESTIMATE_SECONDS := 300.0


static func is_boss_stage(stage: int) -> bool:
	return stage == 10 or stage == 20


static func enemy_max_hp(
	stage: int,
	is_boss: bool,
	balance: BalanceDefinition,
	health_multiplier: float = 1.0
) -> float:
	var health: float = balance.enemy_base_health * pow(
		balance.enemy_health_growth, maxi(stage - 1, 0)
	)
	if stage > 10:
		health *= pow(balance.post_stage_10_health_growth, stage - 10)
	if is_boss:
		health *= balance.boss_health_multiplier
	return health * health_multiplier


static func enemy_reward(
	stage: int,
	balance: BalanceDefinition,
	reward_multiplier: float = 1.0
) -> float:
	return floor(
		balance.enemy_reward_base
		* pow(balance.enemy_reward_growth, maxi(stage - 1, 0))
		* reward_multiplier
	)


static func operator_upgrade_cost(
	level: int,
	base_cost: float,
	cost_growth: float
) -> float:
	return floor(base_cost * pow(cost_growth, maxi(level - 1, 0)))


static func operator_dps(definition: OperatorDefinition, level: int) -> float:
	if level <= 0:
		return 0.0
	return definition.base_dps * pow(float(level), definition.dps_exponent)


static func total_dps(
	state: GameState,
	catalog: ContentCatalog,
	patch_ids: Array[StringName] = []
) -> float:
	var base_total := 0.0
	for definition: OperatorDefinition in catalog.operators:
		var level := int(state.operator_levels.get(definition.id, 0))
		base_total += operator_dps(definition, level)
	var active_ids := state.equipped_patch_ids if patch_ids.is_empty() else patch_ids
	var modifiers := patch_modifiers(active_ids, catalog)
	var legacy_multiplier := 1.0 + (
		catalog.balance.legacy_cache_bonus * float(state.legacy_cache_level)
	)
	return (
		base_total
		* float(modifiers.damage)
		* float(modifiers.attack_speed)
		* legacy_multiplier
	)


static func patch_modifiers(patch_ids: Array[StringName], catalog: ContentCatalog) -> Dictionary:
	var modifiers := {
		"damage": 1.0,
		"attack_speed": 1.0,
		"bits": 1.0,
		"enemy_health": 1.0,
		"boss_recovery": 1.0,
		"boss_special_interval": 1.0,
	}
	for patch_id: StringName in patch_ids:
		if patch_id == &"":
			continue
		var definition: PatchDefinition = catalog.get_patch(patch_id)
		assert(definition != null, "Unknown patch id in domain state: %s" % patch_id)
		modifiers.damage *= definition.damage_multiplier
		modifiers.attack_speed *= definition.attack_speed_multiplier
		modifiers.bits *= definition.bit_multiplier
		modifiers.enemy_health *= definition.enemy_health_multiplier
		modifiers.boss_recovery *= definition.boss_recovery_multiplier
		modifiers.boss_special_interval *= definition.boss_special_interval_multiplier
	return modifiers


static func current_enemy_max_hp(
	state: GameState,
	catalog: ContentCatalog,
	patch_ids: Array[StringName] = []
) -> float:
	var combat_stage := state.stage - 1 if state.is_maintenance else state.stage
	var boss := is_boss_stage(combat_stage) and not state.is_maintenance
	var active_ids := state.equipped_patch_ids if patch_ids.is_empty() else patch_ids
	var modifiers := patch_modifiers(active_ids, catalog)
	return enemy_max_hp(
		combat_stage, boss, catalog.balance, float(modifiers.enemy_health)
	)


static func estimated_time_to_kill(
	state: GameState,
	catalog: ContentCatalog,
	patch_ids: Array[StringName] = []
) -> float:
	var active_ids := state.equipped_patch_ids if patch_ids.is_empty() else patch_ids
	var dps: float = total_dps(state, catalog, active_ids)
	if dps <= ESTIMATE_EPSILON:
		return INF
	var max_hp: float = current_enemy_max_hp(state, catalog, active_ids)
	if not is_boss_stage(state.stage) or state.is_maintenance:
		return max_hp / dps
	return _estimate_boss_time(state.stage, max_hp, dps, active_ids, catalog)


static func boss_recovery_interval(stage: int, balance: BalanceDefinition) -> float:
	return (
		balance.stage_20_recovery_interval
		if stage == 20
		else balance.stage_10_recovery_interval
	)


static func boss_recovery_fraction(stage: int, balance: BalanceDefinition) -> float:
	return (
		balance.stage_20_recovery_fraction
		if stage == 20
		else balance.stage_10_recovery_fraction
	)


static func _estimate_boss_time(
	stage: int,
	max_hp: float,
	base_dps: float,
	patch_ids: Array[StringName],
	catalog: ContentCatalog
) -> float:
	var modifiers := patch_modifiers(patch_ids, catalog)
	var recovery_interval: float = boss_recovery_interval(stage, catalog.balance)
	recovery_interval *= float(modifiers.boss_special_interval)
	var recovery_amount: float = max_hp * boss_recovery_fraction(stage, catalog.balance)
	recovery_amount *= float(modifiers.boss_recovery)
	var remaining_hp := max_hp
	var elapsed := 0.0
	var recovery_count := 0
	var debuff_applied := false

	for _event: int in range(MAX_ESTIMATE_EVENTS):
		var active_dps := base_dps
		if stage == 20 and debuff_applied:
			active_dps *= catalog.balance.stage_20_debuff_multiplier
		if active_dps <= ESTIMATE_EPSILON:
			return INF

		var until_kill: float = remaining_hp / active_dps
		var next_recovery_at := recovery_interval * float(recovery_count + 1)
		var until_recovery: float = maxf(0.0, next_recovery_at - elapsed)
		var until_debuff: float = INF
		if stage == 20 and not debuff_applied:
			until_debuff = maxf(0.0, catalog.balance.stage_20_debuff_time - elapsed)
		var step: float = minf(until_kill, minf(until_recovery, until_debuff))
		remaining_hp = maxf(0.0, remaining_hp - active_dps * step)
		elapsed += step
		if remaining_hp <= ESTIMATE_EPSILON:
			return elapsed
		if elapsed > MAX_ESTIMATE_SECONDS:
			return INF
		if stage == 20 and not debuff_applied:
			if elapsed + ESTIMATE_EPSILON >= catalog.balance.stage_20_debuff_time:
				debuff_applied = true
		if elapsed + ESTIMATE_EPSILON >= next_recovery_at:
			remaining_hp = minf(max_hp, remaining_hp + recovery_amount)
			recovery_count += 1
	return INF


static func patch_swap_cost(state: GameState, catalog: ContentCatalog) -> float:
	var reward_stage: int = maxi(state.stage - 1, 1)
	while is_boss_stage(reward_stage) and reward_stage > 1:
		reward_stage -= 1
	return enemy_reward(reward_stage, catalog.balance) * catalog.balance.normal_enemy_count


static func refresh_unlocks(state: GameState, catalog: ContentCatalog) -> void:
	for definition: OperatorDefinition in catalog.operators:
		var should_unlock := state.run_count > 0 or state.stage >= definition.unlock_stage
		if not should_unlock:
			continue
		if not state.unlocked_operator_ids.has(definition.id):
			state.unlocked_operator_ids.append(definition.id)
		state.operator_levels[definition.id] = maxi(
			int(state.operator_levels.get(definition.id, 0)), 1
		)

	for definition: PatchDefinition in catalog.patches:
		if state.highest_stage >= definition.unlock_stage:
			if not state.discovered_patch_ids.has(definition.id):
				state.discovered_patch_ids.append(definition.id)

	var unlocked_slots := 0
	for unlock_stage: int in catalog.balance.patch_slot_unlock_stages:
		if state.highest_stage >= unlock_stage:
			unlocked_slots += 1
	state.unlocked_patch_slots = maxi(state.unlocked_patch_slots, unlocked_slots)
