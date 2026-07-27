class_name ProductLoopState
extends RefCounted

const SHIFT_COUNT := 2


enum Phase {
	DAY_PREP,
	NIGHT_ACTIVE,
	SHIFT_RESULT,
}


class ShiftRecord:
	extends RefCounted

	var shift_index: int
	var attempts: int = 0
	var highest_completed_waves: int = 0
	var best_stars: int = 0
	var claimed_reward_stars: int = 0


	func _init(index: int = 1) -> void:
		shift_index = index


	func deep_clone() -> ShiftRecord:
		var copy := ShiftRecord.new(shift_index)
		copy.attempts = attempts
		copy.highest_completed_waves = highest_completed_waves
		copy.best_stars = best_stars
		copy.claimed_reward_stars = claimed_reward_stars
		return copy


var phase: int = Phase.DAY_PREP
var version: int = 1
var bits: int = 0
var active_shift_index: int = 0
var result_serial: int = 0

var shift_records: Array[ShiftRecord] = []
var shift_2_unlocked: bool = false
var version_update_available: bool = false

var last_result: Dictionary = {}
var report_key := ""
var report_rows: Array[Dictionary] = []
var report_read: bool = true


func _init() -> void:
	for shift_index: int in range(1, SHIFT_COUNT + 1):
		shift_records.append(ShiftRecord.new(shift_index))


func get_shift_record(shift_index: int) -> ShiftRecord:
	for record: ShiftRecord in shift_records:
		if record.shift_index == shift_index:
			return record
	return null


func deep_clone() -> ProductLoopState:
	var copy := ProductLoopState.new()
	copy.phase = phase
	copy.version = version
	copy.bits = bits
	copy.active_shift_index = active_shift_index
	copy.result_serial = result_serial
	copy.shift_records.clear()
	for record: ShiftRecord in shift_records:
		copy.shift_records.append(record.deep_clone())
	copy.shift_2_unlocked = shift_2_unlocked
	copy.version_update_available = version_update_available
	copy.last_result = last_result.duplicate(true)
	copy.report_key = report_key
	for row: Dictionary in report_rows:
		copy.report_rows.append(row.duplicate(true))
	copy.report_read = report_read
	return copy
