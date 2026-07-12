class_name SettingsRepository
extends RefCounted

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_BASE_DIR := SaveRepository.DEFAULT_BASE_DIR
const SETTINGS_FILE_NAME := "settings.json"
const TEMP_FILE_NAME := "settings.tmp.json"
const ROLLBACK_FILE_NAME := "settings.previous.json"
const REQUIRED_ENVELOPE_KEYS: PackedStringArray = ["schema_version", "settings"]

enum LoadStatus {
	NOT_FOUND,
	LOADED,
	CORRUPT,
	NEWER_SCHEMA,
}

enum EnvelopeKind {
	CURRENT,
	NEWER,
	INVALID,
}

class SettingsLoadResult extends RefCounted:
	var status: LoadStatus = LoadStatus.NOT_FOUND
	var settings: AppSettings = null
	var errors: PackedStringArray = PackedStringArray()
	var source_path: String = ""

	func is_loaded() -> bool:
		return status == LoadStatus.LOADED and settings != null and errors.is_empty()


class EnvelopeReadResult extends RefCounted:
	var kind: EnvelopeKind = EnvelopeKind.INVALID
	var settings_data: Dictionary = {}
	var errors: PackedStringArray = PackedStringArray()


var _base_dir: String


func _init(base_dir: String = DEFAULT_BASE_DIR) -> void:
	assert(not base_dir.strip_edges().is_empty(), "SettingsRepository base_dir must not be empty.")
	_base_dir = base_dir.trim_suffix("/").trim_suffix("\\")


func load() -> SettingsLoadResult:
	var result := SettingsLoadResult.new()
	result.source_path = settings_path()
	var absolute_path := _absolute_path(SETTINGS_FILE_NAME)
	if not FileAccess.file_exists(absolute_path):
		var rollback_absolute := _absolute_path(ROLLBACK_FILE_NAME)
		if FileAccess.file_exists(rollback_absolute):
			return _recover_interrupted_replace(rollback_absolute, absolute_path)
		return result

	var read_result := _read_envelope(absolute_path)
	result.errors = read_result.errors.duplicate()
	if read_result.kind == EnvelopeKind.NEWER:
		result.status = LoadStatus.NEWER_SCHEMA
		return result
	if read_result.kind != EnvelopeKind.CURRENT:
		var rollback_absolute := _absolute_path(ROLLBACK_FILE_NAME)
		if FileAccess.file_exists(rollback_absolute):
			var recovery := _recover_interrupted_replace(rollback_absolute, absolute_path)
			if recovery.is_loaded():
				push_warning(
					"Recovered settings from rollback after invalid primary: %s"
					% "; ".join(read_result.errors)
				)
				return recovery
			var combined_errors := PackedStringArray()
			_append_prefixed_errors(combined_errors, "primary", read_result.errors)
			_append_prefixed_errors(combined_errors, "rollback", recovery.errors)
			recovery.errors = combined_errors
			return recovery
		result.status = LoadStatus.CORRUPT
		if result.errors.is_empty():
			result.errors.append("Settings file is invalid.")
		return result

	var loaded_settings := AppSettings.from_dictionary(read_result.settings_data)
	if loaded_settings == null:
		result.status = LoadStatus.CORRUPT
		result.errors.append("Settings data failed validation after parsing.")
		return result
	result.status = LoadStatus.LOADED
	result.settings = loaded_settings
	return result


func save(settings: AppSettings) -> Error:
	if settings == null or not settings.validation_errors().is_empty():
		return ERR_INVALID_PARAMETER

	var existing_absolute := _absolute_path(SETTINGS_FILE_NAME)
	if FileAccess.file_exists(existing_absolute):
		var existing_read := _read_envelope(existing_absolute)
		if existing_read.kind == EnvelopeKind.NEWER:
			return ERR_FILE_UNRECOGNIZED
		if existing_read.kind != EnvelopeKind.CURRENT:
			return ERR_FILE_CORRUPT

	var directory_error := _ensure_base_directory()
	if directory_error != OK:
		return directory_error
	var temp_absolute := _absolute_path(TEMP_FILE_NAME)
	var stale_temp_error := _remove_if_exists(temp_absolute)
	if stale_temp_error != OK:
		return stale_temp_error
	var envelope := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"settings": settings.to_dictionary(),
	}
	var write_error := _write_json(temp_absolute, envelope)
	if write_error != OK:
		return write_error
	var temp_read := _read_envelope(temp_absolute)
	if temp_read.kind != EnvelopeKind.CURRENT:
		_remove_if_exists(temp_absolute)
		return ERR_FILE_CORRUPT

	var rollback_absolute := _absolute_path(ROLLBACK_FILE_NAME)
	var had_existing := FileAccess.file_exists(existing_absolute)
	if had_existing:
		var stale_rollback_error := _remove_if_exists(rollback_absolute)
		if stale_rollback_error != OK:
			_remove_if_exists(temp_absolute)
			return stale_rollback_error
		var backup_error := DirAccess.copy_absolute(existing_absolute, rollback_absolute)
		if backup_error != OK:
			_remove_if_exists(temp_absolute)
			return backup_error
		var rollback_read := _read_envelope(rollback_absolute)
		if rollback_read.kind != EnvelopeKind.CURRENT:
			_remove_if_exists(temp_absolute)
			_remove_if_exists(rollback_absolute)
			return ERR_FILE_CORRUPT
		var remove_existing_error := _remove_if_exists(existing_absolute)
		if remove_existing_error != OK:
			_remove_if_exists(temp_absolute)
			_remove_if_exists(rollback_absolute)
			return remove_existing_error
	var rename_error := DirAccess.rename_absolute(temp_absolute, existing_absolute)
	if rename_error != OK:
		if had_existing:
			var restore_error := DirAccess.copy_absolute(rollback_absolute, existing_absolute)
			if restore_error != OK:
				return restore_error
		return rename_error
	var cleanup_error := _remove_if_exists(rollback_absolute)
	if cleanup_error != OK:
		push_warning("Settings commit succeeded but rollback cleanup failed: %d" % cleanup_error)
	return OK


func create_defaults() -> Error:
	var load_result := self.load()
	match load_result.status:
		LoadStatus.NOT_FOUND:
			return save(AppSettings.new())
		LoadStatus.LOADED:
			return ERR_ALREADY_EXISTS
		LoadStatus.NEWER_SCHEMA:
			return ERR_FILE_UNRECOGNIZED
		LoadStatus.CORRUPT:
			return ERR_FILE_CORRUPT
	return FAILED


func base_dir() -> String:
	return _base_dir


func settings_path() -> String:
	return _base_dir.path_join(SETTINGS_FILE_NAME)


func temporary_path() -> String:
	return _base_dir.path_join(TEMP_FILE_NAME)


func rollback_path() -> String:
	return _base_dir.path_join(ROLLBACK_FILE_NAME)


func _recover_interrupted_replace(
	rollback_absolute: String,
	settings_absolute: String
) -> SettingsLoadResult:
	var result := SettingsLoadResult.new()
	result.source_path = settings_path()
	var rollback_read := _read_envelope(rollback_absolute)
	if rollback_read.kind == EnvelopeKind.NEWER:
		result.status = LoadStatus.NEWER_SCHEMA
		result.errors = rollback_read.errors.duplicate()
		return result
	if rollback_read.kind != EnvelopeKind.CURRENT:
		result.status = LoadStatus.CORRUPT
		result.errors = rollback_read.errors.duplicate()
		if result.errors.is_empty():
			result.errors.append("Interrupted settings rollback is invalid.")
		return result
	if FileAccess.file_exists(settings_absolute):
		var remove_error := _remove_if_exists(settings_absolute)
		if remove_error != OK:
			result.status = LoadStatus.CORRUPT
			result.errors.append(
				"Unable to remove invalid settings before rollback restore: error %d"
				% remove_error
			)
			return result
	var restore_error := DirAccess.copy_absolute(rollback_absolute, settings_absolute)
	if restore_error != OK:
		result.status = LoadStatus.CORRUPT
		result.errors.append("Unable to restore interrupted settings write: error %d" % restore_error)
		return result
	var restored_read := _read_envelope(settings_absolute)
	if restored_read.kind != EnvelopeKind.CURRENT:
		result.status = LoadStatus.CORRUPT
		result.errors.append("Restored settings failed validation.")
		return result
	var loaded_settings := AppSettings.from_dictionary(restored_read.settings_data)
	if loaded_settings == null:
		result.status = LoadStatus.CORRUPT
		result.errors.append("Restored settings data failed validation.")
		return result
	result.status = LoadStatus.LOADED
	result.settings = loaded_settings
	var cleanup_error := _remove_if_exists(rollback_absolute)
	if cleanup_error != OK:
		push_warning("Recovered settings but rollback cleanup failed: %d" % cleanup_error)
	return result


func _read_envelope(path: String) -> EnvelopeReadResult:
	var result := EnvelopeReadResult.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Unable to read settings: error %d" % FileAccess.get_open_error())
		return result
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		result.errors.append(
			"Settings JSON parse error at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return result
	if typeof(parser.data) != TYPE_DICTIONARY:
		result.errors.append("Settings root must be an object.")
		return result

	var envelope := parser.data as Dictionary
	if not envelope.has("schema_version") or not _is_integer_number(envelope["schema_version"]):
		result.errors.append("schema_version must be an integer.")
		return result
	var schema_version := int(envelope["schema_version"])
	if schema_version > CURRENT_SCHEMA_VERSION:
		result.kind = EnvelopeKind.NEWER
		result.errors.append(
			"Settings schema %d is newer than supported schema %d."
			% [schema_version, CURRENT_SCHEMA_VERSION]
		)
		return result

	for required_key: String in REQUIRED_ENVELOPE_KEYS:
		if not envelope.has(required_key):
			result.errors.append("%s: required settings envelope field is missing" % required_key)
	for key_value: Variant in envelope.keys():
		var key := String(key_value)
		if not REQUIRED_ENVELOPE_KEYS.has(key):
			result.errors.append("%s: unexpected settings envelope field" % key)
	if not result.errors.is_empty():
		return result
	if schema_version != CURRENT_SCHEMA_VERSION:
		result.errors.append("schema_version must equal %d." % CURRENT_SCHEMA_VERSION)
		return result
	if typeof(envelope["settings"]) != TYPE_DICTIONARY:
		result.errors.append("settings must be an object.")
		return result

	var settings_data := envelope["settings"] as Dictionary
	result.errors = AppSettings.validate_dictionary(settings_data)
	if result.errors.is_empty():
		result.kind = EnvelopeKind.CURRENT
		result.settings_data = settings_data.duplicate(true)
	return result


func _ensure_base_directory() -> Error:
	var absolute_base := ProjectSettings.globalize_path(_base_dir)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_base)
	if directory_error == OK or directory_error == ERR_ALREADY_EXISTS:
		return OK
	return directory_error


func _absolute_path(file_name: String) -> String:
	return ProjectSettings.globalize_path(_base_dir.path_join(file_name))


func _write_json(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		return OK
	return DirAccess.remove_absolute(path)


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == float(int(numeric))


func _append_prefixed_errors(
	target: PackedStringArray,
	prefix: String,
	source: PackedStringArray
) -> void:
	if source.is_empty():
		target.append("%s: settings file is invalid" % prefix)
		return
	for message: String in source:
		target.append("%s: %s" % [prefix, message])
