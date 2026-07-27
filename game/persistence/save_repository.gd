class_name SaveRepository
extends RefCounted

const CURRENT_SCHEMA_VERSION := 3
const LEGACY_SCHEMA_VERSION := 1
const PREVIOUS_SCHEMA_VERSION := 2
const SUPPORTED_SCHEMA_VERSIONS: PackedInt32Array = [1, 2, 3]
const DEFAULT_BASE_DIR := "user://pixel_night_shift"
const PRIMARY_FILE_NAME := "work_record.json"
const BACKUP_FILE_NAME := "work_record.backup.json"
const TEMP_FILE_NAME := "work_record.tmp.json"
const BACKUP_ROTATION_FILE_NAME := "work_record.backup.tmp.json"
const REQUIRED_ENVELOPE_KEYS: PackedStringArray = [
	"schema_version",
	"saved_at_unix",
	"last_gameplay_tab",
	"session",
]

enum EnvelopeKind {
	CURRENT,
	NEWER,
	INVALID,
}

class EnvelopeReadResult extends RefCounted:
	var kind: EnvelopeKind = EnvelopeKind.INVALID
	var envelope: Dictionary = {}
	var errors: PackedStringArray = PackedStringArray()


var _base_dir: String


func _init(base_dir: String = DEFAULT_BASE_DIR) -> void:
	assert(not base_dir.strip_edges().is_empty(), "SaveRepository base_dir must not be empty.")
	_base_dir = base_dir.trim_suffix("/").trim_suffix("\\")


func load() -> SaveLoadResult:
	var primary_exists := FileAccess.file_exists(_absolute_path(PRIMARY_FILE_NAME))
	var backup_exists := FileAccess.file_exists(_absolute_path(BACKUP_FILE_NAME))
	if not primary_exists and not backup_exists:
		return SaveLoadResult.new()

	if primary_exists:
		var primary_read := _read_envelope(_absolute_path(PRIMARY_FILE_NAME))
		if primary_read.kind == EnvelopeKind.CURRENT:
			return _make_load_result(
				SaveLoadResult.Status.LOADED,
				primary_read,
				primary_path()
			)
		if primary_read.kind == EnvelopeKind.NEWER:
			return _make_load_result(
				SaveLoadResult.Status.NEWER_SCHEMA,
				primary_read,
				primary_path()
			)
		if not backup_exists:
			return _make_corrupt_result(primary_read.errors)

		var backup_after_primary_failure := _read_envelope(_absolute_path(BACKUP_FILE_NAME))
		if backup_after_primary_failure.kind == EnvelopeKind.CURRENT:
			var recovered := _make_load_result(
				SaveLoadResult.Status.RECOVERED_BACKUP,
				backup_after_primary_failure,
				backup_path()
			)
			recovered.errors.append("Primary work record is invalid; backup recovery is available.")
			_append_prefixed_errors(recovered.errors, "primary", primary_read.errors)
			return recovered
		if backup_after_primary_failure.kind == EnvelopeKind.NEWER:
			var newer_backup := _make_load_result(
				SaveLoadResult.Status.NEWER_SCHEMA,
				backup_after_primary_failure,
				backup_path()
			)
			_append_prefixed_errors(newer_backup.errors, "primary", primary_read.errors)
			return newer_backup
		var combined_errors := PackedStringArray()
		_append_prefixed_errors(combined_errors, "primary", primary_read.errors)
		_append_prefixed_errors(combined_errors, "backup", backup_after_primary_failure.errors)
		return _make_corrupt_result(combined_errors)

	var backup_read := _read_envelope(_absolute_path(BACKUP_FILE_NAME))
	if backup_read.kind == EnvelopeKind.CURRENT:
		var missing_primary := _make_load_result(
			SaveLoadResult.Status.RECOVERED_BACKUP,
			backup_read,
			backup_path()
		)
		missing_primary.errors.append("Primary work record is missing; backup recovery is available.")
		return missing_primary
	if backup_read.kind == EnvelopeKind.NEWER:
		return _make_load_result(
			SaveLoadResult.Status.NEWER_SCHEMA,
			backup_read,
			backup_path()
		)
	return _make_corrupt_result(backup_read.errors)


func load_backup() -> SaveLoadResult:
	var backup_absolute := _absolute_path(BACKUP_FILE_NAME)
	if not FileAccess.file_exists(backup_absolute):
		var missing_result := SaveLoadResult.new()
		missing_result.errors.append("Backup work record was not found.")
		missing_result.source_path = backup_path()
		return missing_result
	var backup_read := _read_envelope(backup_absolute)
	if backup_read.kind == EnvelopeKind.CURRENT:
		return _make_load_result(
			SaveLoadResult.Status.RECOVERED_BACKUP,
			backup_read,
			backup_path()
		)
	if backup_read.kind == EnvelopeKind.NEWER:
		return _make_load_result(
			SaveLoadResult.Status.NEWER_SCHEMA,
			backup_read,
			backup_path()
		)
	var corrupt_result := _make_corrupt_result(backup_read.errors)
	corrupt_result.source_path = backup_path()
	return corrupt_result


func save(
	session_data: Dictionary,
	saved_at_unix: int,
	last_gameplay_tab: int
) -> Error:
	var envelope := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"saved_at_unix": saved_at_unix,
		"last_gameplay_tab": last_gameplay_tab,
		"session": session_data.duplicate(true),
	}
	if not _validate_supported_envelope(envelope).is_empty():
		return ERR_INVALID_PARAMETER

	var directory_error := _ensure_base_directory()
	if directory_error != OK:
		return directory_error
	var stale_temp_error := _remove_if_exists(_absolute_path(TEMP_FILE_NAME))
	if stale_temp_error != OK:
		return stale_temp_error
	var write_error := _write_json(_absolute_path(TEMP_FILE_NAME), envelope)
	if write_error != OK:
		return write_error
	var temp_read := _read_envelope(_absolute_path(TEMP_FILE_NAME))
	if temp_read.kind != EnvelopeKind.CURRENT:
		_remove_if_exists(_absolute_path(TEMP_FILE_NAME))
		return ERR_FILE_CORRUPT

	var primary_absolute := _absolute_path(PRIMARY_FILE_NAME)
	if FileAccess.file_exists(primary_absolute):
		var primary_read := _read_envelope(primary_absolute)
		if primary_read.kind == EnvelopeKind.NEWER:
			_remove_if_exists(_absolute_path(TEMP_FILE_NAME))
			return ERR_FILE_UNRECOGNIZED
		if primary_read.kind != EnvelopeKind.CURRENT:
			_remove_if_exists(_absolute_path(TEMP_FILE_NAME))
			return ERR_FILE_CORRUPT
		var rotation_error := _rotate_valid_primary_to_backup()
		if rotation_error != OK:
			_remove_if_exists(_absolute_path(TEMP_FILE_NAME))
			return rotation_error

	var replace_error := _replace_primary_with_temp()
	if replace_error != OK:
		return replace_error
	return OK


func promote_backup() -> Error:
	var backup_absolute := _absolute_path(BACKUP_FILE_NAME)
	if not FileAccess.file_exists(backup_absolute):
		return ERR_FILE_NOT_FOUND
	var backup_read := _read_envelope(backup_absolute)
	if backup_read.kind == EnvelopeKind.NEWER:
		return ERR_FILE_UNRECOGNIZED
	if backup_read.kind != EnvelopeKind.CURRENT:
		return ERR_FILE_CORRUPT

	var directory_error := _ensure_base_directory()
	if directory_error != OK:
		return directory_error
	var temp_absolute := _absolute_path(TEMP_FILE_NAME)
	var stale_temp_error := _remove_if_exists(temp_absolute)
	if stale_temp_error != OK:
		return stale_temp_error
	var copy_error := DirAccess.copy_absolute(backup_absolute, temp_absolute)
	if copy_error != OK:
		return copy_error
	var copied_read := _read_envelope(temp_absolute)
	if copied_read.kind != EnvelopeKind.CURRENT:
		_remove_if_exists(temp_absolute)
		return ERR_FILE_CORRUPT
	return _replace_primary_with_temp()


func clear_records() -> Error:
	var first_error: Error = OK
	for file_name: String in [
		PRIMARY_FILE_NAME,
		BACKUP_FILE_NAME,
		TEMP_FILE_NAME,
		BACKUP_ROTATION_FILE_NAME,
	]:
		var remove_error := _remove_if_exists(_absolute_path(file_name))
		if first_error == OK and remove_error != OK:
			first_error = remove_error
	return first_error


func base_dir() -> String:
	return _base_dir


func primary_path() -> String:
	return _base_dir.path_join(PRIMARY_FILE_NAME)


func backup_path() -> String:
	return _base_dir.path_join(BACKUP_FILE_NAME)


func temporary_path() -> String:
	return _base_dir.path_join(TEMP_FILE_NAME)


func _rotate_valid_primary_to_backup() -> Error:
	var primary_absolute := _absolute_path(PRIMARY_FILE_NAME)
	var rotation_absolute := _absolute_path(BACKUP_ROTATION_FILE_NAME)
	var backup_absolute := _absolute_path(BACKUP_FILE_NAME)
	var stale_rotation_error := _remove_if_exists(rotation_absolute)
	if stale_rotation_error != OK:
		return stale_rotation_error
	var copy_error := DirAccess.copy_absolute(primary_absolute, rotation_absolute)
	if copy_error != OK:
		return copy_error
	var copied_read := _read_envelope(rotation_absolute)
	if copied_read.kind != EnvelopeKind.CURRENT:
		_remove_if_exists(rotation_absolute)
		return ERR_FILE_CORRUPT
	var remove_backup_error := _remove_if_exists(backup_absolute)
	if remove_backup_error != OK:
		_remove_if_exists(rotation_absolute)
		return remove_backup_error
	var promote_rotation_error := DirAccess.rename_absolute(rotation_absolute, backup_absolute)
	if promote_rotation_error != OK:
		return promote_rotation_error
	return OK


func _replace_primary_with_temp() -> Error:
	var primary_absolute := _absolute_path(PRIMARY_FILE_NAME)
	var temp_absolute := _absolute_path(TEMP_FILE_NAME)
	var had_primary := FileAccess.file_exists(primary_absolute)
	var remove_primary_error := _remove_if_exists(primary_absolute)
	if remove_primary_error != OK:
		_remove_if_exists(temp_absolute)
		return remove_primary_error
	var rename_error := DirAccess.rename_absolute(temp_absolute, primary_absolute)
	if rename_error != OK:
		if had_primary:
			var rollback_error := DirAccess.copy_absolute(
				_absolute_path(BACKUP_FILE_NAME),
				primary_absolute
			)
			if rollback_error != OK:
				push_error(
					"Work record replacement and primary rollback both failed: %d, %d"
					% [rename_error, rollback_error]
				)
		return rename_error
	return OK


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


func _read_envelope(path: String) -> EnvelopeReadResult:
	var result := EnvelopeReadResult.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Unable to read work record: error %d" % FileAccess.get_open_error())
		return result
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		result.errors.append(
			"Work record JSON parse error at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return result
	if typeof(parser.data) != TYPE_DICTIONARY:
		result.errors.append("Work record root must be an object.")
		return result

	var envelope := parser.data as Dictionary
	if not envelope.has("schema_version") or not _is_integer_number(envelope["schema_version"]):
		result.errors.append("schema_version must be an integer.")
		return result
	var schema_version := int(envelope["schema_version"])
	if schema_version > CURRENT_SCHEMA_VERSION:
		result.kind = EnvelopeKind.NEWER
		result.envelope = envelope.duplicate(true)
		result.errors.append(
			"Work record schema %d is newer than supported schema %d."
			% [schema_version, CURRENT_SCHEMA_VERSION]
		)
		return result

	result.errors = _validate_supported_envelope(envelope)
	if result.errors.is_empty():
		result.kind = EnvelopeKind.CURRENT
		result.envelope = envelope.duplicate(true)
	return result


func _validate_supported_envelope(envelope: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for required_key: String in REQUIRED_ENVELOPE_KEYS:
		if not envelope.has(required_key):
			errors.append("%s: required envelope field is missing" % required_key)
	for key_value: Variant in envelope.keys():
		var key := String(key_value)
		if not REQUIRED_ENVELOPE_KEYS.has(key):
			errors.append("%s: unexpected envelope field" % key)
	if not errors.is_empty():
		return errors

	if not _is_integer_number(envelope["schema_version"]):
		errors.append("schema_version must be an integer.")
	elif not SUPPORTED_SCHEMA_VERSIONS.has(int(envelope["schema_version"])):
		errors.append(
			"schema_version must equal supported schema 1, 2, or 3."
		)

	if not _is_integer_number(envelope["saved_at_unix"]):
		errors.append("saved_at_unix must be an integer.")
	elif int(envelope["saved_at_unix"]) < 0:
		errors.append("saved_at_unix must be zero or greater.")

	if not _is_integer_number(envelope["last_gameplay_tab"]):
		errors.append("last_gameplay_tab must be an integer.")
	else:
		var tab := int(envelope["last_gameplay_tab"])
		if tab < 0 or tab > 2:
			errors.append("last_gameplay_tab must be in the range 0..2.")

	if typeof(envelope["session"]) != TYPE_DICTIONARY:
		errors.append("session must be an object.")
	return errors


func _make_load_result(
	status: SaveLoadResult.Status,
	read_result: EnvelopeReadResult,
	source_path: String
) -> SaveLoadResult:
	var result := SaveLoadResult.new()
	result.status = status
	result.errors = read_result.errors.duplicate()
	result.source_path = source_path
	if (
		read_result.envelope.has("schema_version")
		and _is_integer_number(read_result.envelope["schema_version"])
	):
		result.schema_version = int(read_result.envelope["schema_version"])
	if read_result.kind == EnvelopeKind.CURRENT:
		result.saved_at_unix = int(read_result.envelope["saved_at_unix"])
		result.last_gameplay_tab = int(read_result.envelope["last_gameplay_tab"])
		result.session_data = (read_result.envelope["session"] as Dictionary).duplicate(true)
	return result


func _make_corrupt_result(errors: PackedStringArray) -> SaveLoadResult:
	var result := SaveLoadResult.new()
	result.status = SaveLoadResult.Status.CORRUPT
	result.errors = errors.duplicate()
	if result.errors.is_empty():
		result.errors.append("Work record is invalid.")
	return result


func _append_prefixed_errors(
	destination: PackedStringArray,
	prefix: String,
	source: PackedStringArray
) -> void:
	for error_message: String in source:
		destination.append("%s: %s" % [prefix, error_message])


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		return OK
	return DirAccess.remove_absolute(path)


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == float(int(numeric))
