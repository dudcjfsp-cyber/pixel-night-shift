class_name AppSettings
extends RefCounted

const REQUIRED_KEYS: PackedStringArray = [
	"music_volume",
	"sfx_volume",
	"vibration_enabled",
	"screen_shake_enabled",
	"reduced_flashing",
	"reduced_motion",
	"onboarding_completed",
]

var music_volume: float = 0.8
var sfx_volume: float = 0.7
var vibration_enabled: bool = true
var screen_shake_enabled: bool = true
var reduced_flashing: bool = true
var reduced_motion: bool = false
var onboarding_completed: bool = false


func to_dictionary() -> Dictionary:
	return {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"vibration_enabled": vibration_enabled,
		"screen_shake_enabled": screen_shake_enabled,
		"reduced_flashing": reduced_flashing,
		"reduced_motion": reduced_motion,
		"onboarding_completed": onboarding_completed,
	}


func validation_errors() -> PackedStringArray:
	return validate_dictionary(to_dictionary())


static func from_dictionary(data: Dictionary) -> AppSettings:
	if not validate_dictionary(data).is_empty():
		return null
	var settings := AppSettings.new()
	settings.music_volume = float(data["music_volume"])
	settings.sfx_volume = float(data["sfx_volume"])
	settings.vibration_enabled = bool(data["vibration_enabled"])
	settings.screen_shake_enabled = bool(data["screen_shake_enabled"])
	settings.reduced_flashing = bool(data["reduced_flashing"])
	settings.reduced_motion = bool(data["reduced_motion"])
	settings.onboarding_completed = bool(data["onboarding_completed"])
	return settings


static func validate_dictionary(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for required_key: String in REQUIRED_KEYS:
		if not data.has(required_key):
			errors.append("settings.%s: required field is missing" % required_key)
	for key_value: Variant in data.keys():
		var key := String(key_value)
		if not REQUIRED_KEYS.has(key):
			errors.append("settings.%s: unexpected field" % key)
	if not errors.is_empty():
		return errors

	_validate_volume(data, "music_volume", errors)
	_validate_volume(data, "sfx_volume", errors)
	_validate_bool(data, "vibration_enabled", errors)
	_validate_bool(data, "screen_shake_enabled", errors)
	_validate_bool(data, "reduced_flashing", errors)
	_validate_bool(data, "reduced_motion", errors)
	_validate_bool(data, "onboarding_completed", errors)
	return errors


static func _validate_volume(
	data: Dictionary,
	key: String,
	errors: PackedStringArray
) -> void:
	var value: Variant = data[key]
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		errors.append("settings.%s: number in the range 0..1 is required" % key)
		return
	var numeric := float(value)
	if not is_finite(numeric) or numeric < 0.0 or numeric > 1.0:
		errors.append("settings.%s: finite number in the range 0..1 is required" % key)


static func _validate_bool(
	data: Dictionary,
	key: String,
	errors: PackedStringArray
) -> void:
	if typeof(data[key]) != TYPE_BOOL:
		errors.append("settings.%s: boolean is required" % key)
