class_name ProductV2Forecast
extends RefCounted

const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const NightShiftSimulator := preload(
	"res://game/domain/product_v2/night_shift_simulator.gd"
)

const FORECAST_SECONDS := 300.0


static func evaluate(
	catalog: ProductV2Catalog,
	shift_index: int,
	operator_levels: Dictionary,
	unlocked_operator_ids: Array[StringName],
	equipped_patch_ids: Array[StringName],
	legacy_cache_level: int
) -> Dictionary:
	var state := NightShiftSimulator.create_state(
		catalog,
		shift_index,
		operator_levels,
		unlocked_operator_ids,
		equipped_patch_ids,
		legacy_cache_level
	)
	NightShiftSimulator.advance(state, catalog, FORECAST_SECONDS)
	var modifiers := ProgressionRules.patch_modifiers(
		equipped_patch_ids, catalog.base_catalog
	)
	var completed_waves := clampi(state.completed_waves, 0, 10)
	var stability_steps := floori(
		float(state.stability * 100)
		/ float(
			maxi(1, catalog.balance.max_stability)
			* catalog.balance.stability_step_percent
		)
	)
	var performance_raw := (
		completed_waves * catalog.balance.completed_wave_salary_bits
		+ (catalog.balance.boss_defeat_salary_bits if state.is_success() else 0)
		+ stability_steps * catalog.balance.stability_step_salary_bits
	)
	var repeat_salary := (
		catalog.balance.base_salary_bits
		+ floori(float(performance_raw) * float(modifiers.bits))
	)
	var expected_clear_seconds := state.total_elapsed
	return {
		"shift_index": shift_index,
		"kill_time": expected_clear_seconds,
		"expected_clear_seconds": expected_clear_seconds,
		"combat_time": state.combat_elapsed,
		"enemies_leaked": state.total_enemies_leaked,
		"expected_leaks": state.total_enemies_leaked,
		"leak_damage": state.total_leak_damage,
		"stability": state.stability,
		"boss_risk": _boss_risk(String(state.terminal_reason)),
		"terminal_reason": String(state.terminal_reason),
		"success": state.is_success(),
		"stars": state.star_count(catalog.balance.star_thresholds),
		"bit_multiplier": float(modifiers.bits),
		"repeat_salary": repeat_salary,
	}


static func _boss_risk(terminal_reason: String) -> String:
	match terminal_reason:
		"boss_defeated":
			return "low"
		"boss_timeout":
			return "timeout"
		"boss_all_down":
			return "process_down"
		"stability_depleted":
			return "server_breach"
	return "unknown"
