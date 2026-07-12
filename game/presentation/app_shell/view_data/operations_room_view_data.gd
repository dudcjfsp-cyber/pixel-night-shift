class_name OperationsRoomViewData
extends RefCounted

enum SaveState {
	SAVED,
	SAVING,
	ERROR,
}

var run_number: int
var automatic_running: bool
var automatic_status_label: String
var stage: int
var bottleneck: String
var equipped_patch_count: int
var patch_slot_count: int
var next_goal: String
var save_status_label: String
var save_state: int


func _init(
	p_run_number: int,
	p_automatic_running: bool,
	p_automatic_status_label: String,
	p_stage: int,
	p_bottleneck: String,
	p_equipped_patch_count: int,
	p_patch_slot_count: int,
	p_next_goal: String,
	p_save_status_label: String,
	p_save_state: int
) -> void:
	run_number = p_run_number
	automatic_running = p_automatic_running
	automatic_status_label = p_automatic_status_label
	stage = p_stage
	bottleneck = p_bottleneck
	equipped_patch_count = p_equipped_patch_count
	patch_slot_count = p_patch_slot_count
	next_goal = p_next_goal
	save_status_label = p_save_status_label
	save_state = p_save_state
	var errors := validation_errors()
	if not errors.is_empty():
		push_error("Invalid OperationsRoomViewData: %s" % "; ".join(errors))
	assert(errors.is_empty(), "Invalid OperationsRoomViewData: %s" % "; ".join(errors))


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if run_number < 1:
		errors.append("run_number must be at least 1")
	if automatic_status_label.is_empty():
		errors.append("automatic_status_label cannot be empty")
	if stage < 1:
		errors.append("stage must be at least 1")
	if bottleneck.is_empty():
		errors.append("bottleneck cannot be empty")
	if patch_slot_count < 0:
		errors.append("patch_slot_count cannot be negative")
	if equipped_patch_count < 0 or equipped_patch_count > patch_slot_count:
		errors.append("equipped_patch_count must fit within patch_slot_count")
	if next_goal.is_empty():
		errors.append("next_goal cannot be empty")
	if save_status_label.is_empty():
		errors.append("save_status_label cannot be empty")
	if save_state not in [SaveState.SAVED, SaveState.SAVING, SaveState.ERROR]:
		errors.append("save_state is unknown")
	return errors
