class_name OfflineReportViewData
extends RefCounted

var absence_seconds: int
var recovered_bits: float
var stage_from: int
var stage_to: int
var has_bottleneck: bool
var bottleneck_stage: int
var bottleneck_cause: String
var reached_cap: bool


func _init(
	p_absence_seconds: int,
	p_recovered_bits: float,
	p_stage_from: int,
	p_stage_to: int,
	p_has_bottleneck: bool,
	p_bottleneck_stage: int,
	p_bottleneck_cause: String,
	p_reached_cap: bool
) -> void:
	absence_seconds = p_absence_seconds
	recovered_bits = p_recovered_bits
	stage_from = p_stage_from
	stage_to = p_stage_to
	has_bottleneck = p_has_bottleneck
	bottleneck_stage = p_bottleneck_stage
	bottleneck_cause = p_bottleneck_cause
	reached_cap = p_reached_cap
	var errors := validation_errors()
	if not errors.is_empty():
		push_error("Invalid OfflineReportViewData: %s" % "; ".join(errors))
	assert(errors.is_empty(), "Invalid OfflineReportViewData: %s" % "; ".join(errors))


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if absence_seconds < 0:
		errors.append("absence_seconds cannot be negative")
	if not is_finite(recovered_bits):
		errors.append("recovered_bits must be finite")
	elif recovered_bits < 0.0:
		errors.append("recovered_bits cannot be negative")
	if stage_from < 1 or stage_to < stage_from:
		errors.append("stage range must be monotonic and start at 1 or later")
	if has_bottleneck:
		if bottleneck_stage < 1:
			errors.append("bottleneck_stage is required when has_bottleneck is true")
		if bottleneck_cause.is_empty():
			errors.append("bottleneck_cause is required when has_bottleneck is true")
	elif bottleneck_stage != 0 or not bottleneck_cause.is_empty():
		errors.append("non-bottleneck reports cannot carry bottleneck details")
	return errors
