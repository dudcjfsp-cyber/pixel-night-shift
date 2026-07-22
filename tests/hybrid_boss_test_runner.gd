extends SceneTree

const ContentLoaderScript := preload("res://game/content/content_loader.gd")
const GameStateScript := preload("res://game/domain/game_state.gd")
const HybridBossSimulatorScript := preload("res://game/domain/hybrid_boss_simulator.gd")
const ProgressionRulesScript := preload("res://game/domain/progression_rules.gd")

var _failures := 0


func _init() -> void:
	var load_result := ContentLoaderScript.load_default()
	_check(load_result.is_valid(), "hybrid boss contract requires valid content")
	if not load_result.is_valid():
		_finish()
		return
	var catalog: ContentCatalog = load_result.catalog
	var state: GameState = GameStateScript.new()
	state.stage = 10
	state.highest_stage = 10
	for definition: OperatorDefinition in catalog.operators:
		state.operator_levels[definition.id] = 10
	ProgressionRulesScript.refresh_unlocks(state, catalog)
	state.boss_attempt_serial = 1
	HybridBossSimulatorScript.reset_attempt(state, catalog)

	var debugger_runtime := state.get_operator_combat_state(&"debugger")
	debugger_runtime.current_hp = 1.0
	state.enemy_attack_remaining = 0.0
	state.boss_special_remaining = INF
	state.boss_rollback_remaining = INF
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF
	HybridBossSimulatorScript.advance(state, catalog, 0.01)
	_check(not debugger_runtime.is_active(), "POLL must put the selected operator process-down")
	_check(
		state.qa_rescue_target_id == &"debugger",
		"an active QA operator must schedule one automatic rescue"
	)

	state.enemy_attack_remaining = INF
	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.attack_remaining = INF
	HybridBossSimulatorScript.advance(state, catalog, catalog.balance.qa_rescue_delay)
	_check(debugger_runtime.is_active(), "QA rescue must restore the scheduled operator")
	_check(state.qa_rescue_count == 1, "QA rescue must be counted exactly once")

	for runtime: OperatorCombatState in state.operator_combat_states:
		runtime.current_hp = 0.0
	HybridBossSimulatorScript.advance(state, catalog, 0.01)
	_check(
		state.last_boss_failure_reason == &"boss_all_down",
		"all process-down operators must end the attempt with a factual reason"
	)
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("FAIL  %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("PASS  hybrid boss durability and QA recovery")
	quit(0 if _failures == 0 else 1)
