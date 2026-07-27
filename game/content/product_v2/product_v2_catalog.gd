class_name ProductV2Catalog
extends RefCounted

const STABLE_OPERATOR_IDS: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]
const STABLE_PATCH_IDS: Array[StringName] = [
	&"frame_skip", &"unsafe_build", &"reward_bypass", &"rollback_lock", &"safe_mode",
]
const STABLE_ENEMY_IDS: Array[StringName] = [
	&"small", &"standard", &"surge",
]
const STABLE_ENEMY_ASSET_IDS: Array[StringName] = [
	&"broken_pixel", &"missing_resource", &"infinite_loop",
]
const BOSS_ID := &"watchdog_process"
const BOSS_ASSET_ID := &"watchdog_process"


class BalanceProfile:
	extends RefCounted

	var countdown_seconds: float
	var normal_wave_seconds: float
	var transition_seconds: float
	var boss_warning_seconds: float
	var boss_seconds: float
	var max_stability: int
	var wave_leak_cap: int
	var danger_stability: int
	var star_thresholds: PackedInt32Array = PackedInt32Array()
	var first_star_reward_bits: PackedInt32Array = PackedInt32Array()
	var operator_hp_growth: float
	var qa_rescue_delay: float
	var qa_rescue_hp_fraction: float


class EnemyArchetype:
	extends RefCounted

	var id: StringName
	var display_name: String
	var asset_id: StringName
	var base_hp: float
	var leak_damage: int


class WaveEntry:
	extends RefCounted

	var enemy_id: StringName
	var count: int


class WaveProfile:
	extends RefCounted

	var number: int
	var hp_multiplier: float
	var entries: Array[WaveEntry] = []


class BossProfile:
	extends RefCounted

	var id: StringName
	var display_name: String
	var asset_id: StringName
	var max_hp: float
	var poll_interval: float
	var poll_damage: float
	var special_interval: float
	var special_damage: float
	var rollback_interval: float
	var rollback_fraction: float
	var debuff_start_seconds: float
	var debuff_multiplier: float


class ShiftProfile:
	extends RefCounted

	var index: int
	var health_multiplier: float
	var waves: Array[WaveProfile] = []
	var boss: BossProfile

	var _waves_by_number: Dictionary = {}


	func build_index() -> void:
		_waves_by_number.clear()
		for profile: WaveProfile in waves:
			_waves_by_number[profile.number] = profile


	func has_wave(wave_number: int) -> bool:
		return _waves_by_number.has(wave_number)


	func get_wave(wave_number: int) -> WaveProfile:
		return _waves_by_number.get(wave_number) as WaveProfile


var base_catalog: ContentCatalog
var balance: BalanceProfile
var enemy_archetypes: Array[EnemyArchetype] = []
var shifts: Array[ShiftProfile] = []

var _enemies_by_id: Dictionary = {}
var _shifts_by_index: Dictionary = {}


func build_indexes() -> void:
	_enemies_by_id.clear()
	_shifts_by_index.clear()
	for archetype: EnemyArchetype in enemy_archetypes:
		_enemies_by_id[archetype.id] = archetype
	for profile: ShiftProfile in shifts:
		profile.build_index()
		_shifts_by_index[profile.index] = profile


func has_enemy(enemy_id: StringName) -> bool:
	return _enemies_by_id.has(enemy_id)


func get_enemy(enemy_id: StringName) -> EnemyArchetype:
	return _enemies_by_id.get(enemy_id) as EnemyArchetype


func has_shift(shift_index: int) -> bool:
	return _shifts_by_index.has(shift_index)


func get_shift(shift_index: int) -> ShiftProfile:
	return _shifts_by_index.get(shift_index) as ShiftProfile
