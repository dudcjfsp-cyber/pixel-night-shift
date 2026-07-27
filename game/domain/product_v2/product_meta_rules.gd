class_name ProductMetaRules
extends RefCounted

const ProductLoopState := preload(
	"res://game/domain/product_v2/product_loop_state.gd"
)
const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)

const MAX_OPERATOR_LEVEL := 1000


static func initialize_new_game(
	state: ProductLoopState,
	catalog: ProductV2Catalog,
	full_team_fixture: bool = false
) -> void:
	state.bits = catalog.balance.starting_bits
	state.patch_notes = 0
	state.legacy_cache_level = 0
	state.operator_levels.clear()
	state.unlocked_operator_ids.clear()
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		var unlocked := (
			full_team_fixture
			or definition.id == &"debugger"
			or definition.id == &"build_engineer"
		)
		state.operator_levels[definition.id] = 3 if full_team_fixture else (1 if unlocked else 0)
		if unlocked:
			state.unlocked_operator_ids.append(definition.id)
	state.discovered_patch_ids.clear()
	state.unlocked_patch_slots = 0
	state.equipped_patch_ids = [&"", &"", &""]
	arm_day_income(state, 0)


static func refresh_unlocks(
	state: ProductLoopState,
	catalog: ProductV2Catalog
) -> Dictionary:
	var new_operator_ids: Array[String] = []
	var new_patch_ids: Array[String] = []
	var new_patch_slots: Array[int] = []
	var first := state.get_shift_record(1)
	var second := state.get_shift_record(2)
	assert(first != null and second != null, "Product V2 requires two shift records")

	if first.best_stars >= 1:
		_unlock_operator(state, &"sprite_artist", new_operator_ids)
		_discover_patch(state, &"frame_skip", new_patch_ids)
		_unlock_slots(state, 1, new_patch_slots)
	if first.highest_completed_waves >= 5:
		_discover_patch(state, &"unsafe_build", new_patch_ids)
	if first.best_stars >= 2:
		_unlock_operator(state, &"qa_imp", new_operator_ids)
	if first.highest_completed_waves >= 7:
		_discover_patch(state, &"reward_bypass", new_patch_ids)
	if first.highest_completed_waves >= 9:
		_discover_patch(state, &"rollback_lock", new_patch_ids)
	if first.best_stars >= 3:
		_unlock_slots(state, 2, new_patch_slots)
	if second.boss_encountered:
		_discover_patch(state, &"safe_mode", new_patch_ids)
	if second.best_stars >= 2:
		_unlock_slots(state, 3, new_patch_slots)

	for operator_id: StringName in state.unlocked_operator_ids:
		assert(
			catalog.base_catalog.has_operator(operator_id),
			"Unlocked Product V2 operator must exist in content"
		)
	for patch_id: StringName in state.discovered_patch_ids:
		assert(
			catalog.base_catalog.has_patch(patch_id),
			"Discovered Product V2 patch must exist in content"
		)
	return {
		"operator_ids": new_operator_ids,
		"patch_ids": new_patch_ids,
		"patch_slots": new_patch_slots,
	}


static func operator_upgrade_cost(
	level: int,
	definition: OperatorDefinition
) -> int:
	if level <= 0 or level >= MAX_OPERATOR_LEVEL:
		return -1
	var value: float = floor(
		definition.base_cost * pow(definition.cost_growth, float(level - 1))
	)
	if not is_finite(value) or value > 2_000_000_000.0:
		return -1
	return maxi(1, int(value))


static func apply_day_income(
	state: ProductLoopState,
	catalog: ProductV2Catalog,
	now_unix: int
) -> Dictionary:
	assert(
		state.phase == ProductLoopState.Phase.DAY_PREP,
		"Day income can only be applied during DAY_PREP"
	)
	assert(now_unix >= 0, "Day income requires a non-negative absolute time")
	if state.day_income_anchor_unix == 0:
		state.day_income_anchor_unix = now_unix
		return _income_result(state, 0, 0, false, true)
	if now_unix <= state.day_income_anchor_unix:
		return _income_result(state, 0, 0, false, false)

	var elapsed := now_unix - state.day_income_anchor_unix
	var total_seconds := state.day_income_remainder_seconds + elapsed
	var capped_seconds := mini(total_seconds, catalog.balance.day_income_cap_seconds)
	var award := mini(
		floori(
			float(capped_seconds)
			/ float(catalog.balance.day_income_interval_seconds)
		),
		catalog.balance.day_income_cap_bits
	)
	var reached_cap := total_seconds >= catalog.balance.day_income_cap_seconds
	state.day_income_anchor_unix = now_unix
	state.day_income_remainder_seconds = (
		0
		if reached_cap
		else total_seconds % catalog.balance.day_income_interval_seconds
	)
	state.bits += award
	state.last_day_income_elapsed_seconds = elapsed
	state.last_day_income_bits = award
	if award > 0:
		state.day_income_report_available = true
	return _income_result(state, elapsed, award, reached_cap, true)


static func arm_day_income(state: ProductLoopState, now_unix: int) -> void:
	assert(now_unix >= 0, "Day income anchor must be non-negative")
	state.day_income_anchor_unix = now_unix
	state.day_income_remainder_seconds = 0
	state.last_day_income_elapsed_seconds = 0
	state.last_day_income_bits = 0
	state.day_income_report_available = false


static func reset_for_version_update(
	state: ProductLoopState,
	catalog: ProductV2Catalog,
	now_unix: int
) -> void:
	assert(
		state.phase == ProductLoopState.Phase.DAY_PREP
		and state.version_update_available,
		"Version update requires an eligible DAY_PREP state"
	)
	state.version += 1
	state.bits = catalog.balance.starting_bits
	state.patch_notes += catalog.balance.version_patch_notes_reward
	state.active_shift_index = 0
	state.result_serial = 0
	state.shift_records.clear()
	for shift_index: int in range(1, ProductLoopState.SHIFT_COUNT + 1):
		state.shift_records.append(ProductLoopState.ShiftRecord.new(shift_index))
	state.shift_2_unlocked = false
	state.version_update_available = false
	state.last_result.clear()
	state.report_key = ""
	state.report_rows.clear()
	state.report_read = true
	for definition: OperatorDefinition in catalog.base_catalog.operators:
		state.operator_levels[definition.id] = (
			1 if state.unlocked_operator_ids.has(definition.id) else 0
		)
	state.equipped_patch_ids = [&"", &"", &""]
	arm_day_income(state, now_unix)


static func _unlock_operator(
	state: ProductLoopState,
	operator_id: StringName,
	new_ids: Array[String]
) -> void:
	if state.unlocked_operator_ids.has(operator_id):
		return
	state.unlocked_operator_ids.append(operator_id)
	state.operator_levels[operator_id] = 1
	new_ids.append(String(operator_id))


static func _discover_patch(
	state: ProductLoopState,
	patch_id: StringName,
	new_ids: Array[String]
) -> void:
	if state.discovered_patch_ids.has(patch_id):
		return
	state.discovered_patch_ids.append(patch_id)
	new_ids.append(String(patch_id))


static func _unlock_slots(
	state: ProductLoopState,
	target_count: int,
	new_slots: Array[int]
) -> void:
	while state.unlocked_patch_slots < target_count:
		state.unlocked_patch_slots += 1
		new_slots.append(state.unlocked_patch_slots - 1)


static func _income_result(
	state: ProductLoopState,
	elapsed_seconds: int,
	awarded_bits: int,
	reached_cap: bool,
	anchor_changed: bool
) -> Dictionary:
	return {
		"applied": anchor_changed,
		"elapsed_seconds": elapsed_seconds,
		"awarded_bits": awarded_bits,
		"remainder_seconds": state.day_income_remainder_seconds,
		"reached_cap": reached_cap,
		"bits_after": state.bits,
	}
