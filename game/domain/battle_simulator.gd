class_name BattleSimulator
extends RefCounted

const EPSILON := 0.000001
const MAX_EVENTS_PER_TICK := 100000


static func advance(state: GameState, catalog: ContentCatalog, delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or state.can_prestige:
		return
	var remaining := delta_seconds
	var event_count := 0
	while remaining > EPSILON and not state.can_prestige:
		event_count += 1
		assert(event_count <= MAX_EVENTS_PER_TICK, "Combat event loop exceeded its safety limit")
		var consumed := 0.0
		if state.is_maintenance:
			consumed = _advance_normal_enemy(state, catalog, remaining, true)
		elif ProgressionRules.is_boss_stage(state.stage):
			consumed = _advance_boss(state, catalog, remaining)
		else:
			consumed = _advance_normal_enemy(state, catalog, remaining, false)
		if consumed > EPSILON:
			remaining -= consumed


static func _advance_normal_enemy(
	state: GameState,
	catalog: ContentCatalog,
	available_seconds: float,
	maintenance: bool
) -> float:
	var dps := ProgressionRules.total_dps(state, catalog)
	if dps <= EPSILON:
		return available_seconds
	if state.enemy_health <= EPSILON:
		state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
	var time_to_kill: float = state.enemy_health / dps
	var consumed: float = minf(available_seconds, time_to_kill)
	state.enemy_health = maxf(0.0, state.enemy_health - dps * consumed)
	if state.enemy_health <= EPSILON:
		_complete_normal_enemy(state, catalog, maintenance)
	return consumed


static func _complete_normal_enemy(
	state: GameState,
	catalog: ContentCatalog,
	maintenance: bool
) -> void:
	var combat_stage := state.stage - 1 if maintenance else state.stage
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	state.bits += ProgressionRules.enemy_reward(
		combat_stage, catalog.balance, float(modifiers.bits)
	)
	state.enemy_index += 1
	if state.enemy_index <= catalog.balance.normal_enemy_count:
		state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
		return

	if maintenance:
		state.maintenance_cycles_remaining -= 1
		if state.maintenance_cycles_remaining > 0:
			state.enemy_index = 1
			state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
			return
		_retry_boss(state, catalog)
		return

	state.stage += 1
	state.highest_stage = maxi(state.highest_stage, state.stage)
	state.enemy_index = 1
	ProgressionRules.refresh_unlocks(state, catalog)
	state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
	state.status_message = "스테이지 %d 진입" % state.stage


static func _advance_boss(
	state: GameState,
	catalog: ContentCatalog,
	available_seconds: float
) -> float:
	var balance := catalog.balance
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	var dps := ProgressionRules.total_dps(state, catalog)
	if state.stage == 20 and state.boss_debuff_applied:
		dps *= balance.stage_20_debuff_multiplier
	var max_hp := ProgressionRules.current_enemy_max_hp(state, catalog)
	if state.enemy_health <= EPSILON:
		state.enemy_health = max_hp

	var recovery_interval := ProgressionRules.boss_recovery_interval(state.stage, balance)
	recovery_interval *= float(modifiers.boss_special_interval)
	var next_recovery_at := recovery_interval * float(state.boss_recovery_count + 1)
	var until_recovery: float = maxf(0.0, next_recovery_at - state.boss_elapsed)
	var until_timeout: float = maxf(0.0, balance.boss_time_limit - state.boss_elapsed)
	var until_debuff: float = INF
	if state.stage == 20 and not state.boss_debuff_applied:
		until_debuff = maxf(0.0, balance.stage_20_debuff_time - state.boss_elapsed)
	var until_kill: float = INF if dps <= EPSILON else state.enemy_health / dps
	var consumed: float = minf(
		available_seconds,
		minf(until_kill, minf(until_recovery, minf(until_timeout, until_debuff)))
	)
	state.enemy_health = maxf(0.0, state.enemy_health - dps * consumed)
	state.boss_elapsed += consumed

	if state.enemy_health <= EPSILON:
		_complete_boss(state, catalog)
		return consumed

	if state.stage == 20 and not state.boss_debuff_applied:
		if state.boss_elapsed + EPSILON >= balance.stage_20_debuff_time:
			state.boss_debuff_applied = true
			state.status_message = "감시견이 공격 처리량을 제한합니다."

	if state.boss_elapsed + EPSILON >= next_recovery_at:
		var recovery_fraction := ProgressionRules.boss_recovery_fraction(state.stage, balance)
		var requested_heal := max_hp * recovery_fraction * float(modifiers.boss_recovery)
		var previous_health := state.enemy_health
		state.enemy_health = minf(max_hp, state.enemy_health + requested_heal)
		state.boss_recovered_health += state.enemy_health - previous_health
		state.boss_recovery_count += 1
		state.status_message = "감시견이 이전 상태로 롤백했습니다."

	if state.boss_elapsed + EPSILON >= balance.boss_time_limit:
		_fail_boss(state, catalog)
	return consumed


static func _complete_boss(state: GameState, catalog: ContentCatalog) -> void:
	var modifiers := ProgressionRules.patch_modifiers(state.equipped_patch_ids, catalog)
	state.bits += ProgressionRules.enemy_reward(
		state.stage, catalog.balance, float(modifiers.bits)
	) * catalog.balance.boss_health_multiplier
	if state.stage == 20:
		state.can_prestige = true
		state.enemy_health = 0.0
		state.status_message = "버전 업데이트를 실행할 수 있습니다."
		return
	state.stage += 1
	state.highest_stage = maxi(state.highest_stage, state.stage)
	state.enemy_index = 1
	_reset_boss_attempt(state)
	ProgressionRules.refresh_unlocks(state, catalog)
	state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
	state.status_message = "감시견 프로세스를 격리했습니다."


static func _fail_boss(state: GameState, catalog: ContentCatalog) -> void:
	state.boss_failure_count += 1
	if state.boss_failure_count == 1:
		state.free_patch_swaps += 1
	state.is_maintenance = true
	state.maintenance_cycles_remaining = catalog.balance.maintenance_cycles
	state.enemy_index = 1
	state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
	state.status_message = "보스 실패: 유지보수 파밍 후 자동 재시도합니다."


static func _retry_boss(state: GameState, catalog: ContentCatalog) -> void:
	state.is_maintenance = false
	state.enemy_index = 1
	_reset_boss_attempt(state)
	state.enemy_health = ProgressionRules.current_enemy_max_hp(state, catalog)
	state.status_message = "유지보수 완료: 감시견에 자동 재접속합니다."


static func _reset_boss_attempt(state: GameState) -> void:
	state.boss_elapsed = 0.0
	state.boss_recovery_count = 0
	state.boss_recovered_health = 0.0
	state.boss_debuff_applied = false
