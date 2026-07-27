class_name DefenseLabSaveRepository
extends RefCounted

const SaveRepository := preload(
	"res://game/persistence/save_repository.gd"
)
const SaveLoadResult := preload(
	"res://game/persistence/save_load_result.gd"
)

const CURRENT_LAB_SCHEMA_VERSION := 1
const DEFAULT_BASE_DIR := "user://product_v2_defense_lab"
const PAYLOAD_KEYS: PackedStringArray = ["lab_schema_version", "state"]

var _storage: SaveRepository


func _init(base_dir: String = DEFAULT_BASE_DIR) -> void:
	assert(
		not base_dir.strip_edges().is_empty(),
		"Defense Lab save base_dir must not be empty"
	)
	_storage = SaveRepository.new(base_dir)


func load() -> SaveLoadResult:
	return _unwrap(_storage.load())


func load_backup() -> SaveLoadResult:
	return _unwrap(_storage.load_backup())


func save(state_data: Dictionary, saved_at_unix: int) -> Error:
	var payload := {
		"lab_schema_version": CURRENT_LAB_SCHEMA_VERSION,
		"state": state_data.duplicate(true),
	}
	if not _validate_payload(payload).is_empty():
		return ERR_INVALID_PARAMETER
	return _storage.save(payload, saved_at_unix, 0)


func promote_backup() -> Error:
	return _storage.promote_backup()


func clear_records() -> Error:
	return _storage.clear_records()


func base_dir() -> String:
	return _storage.base_dir()


func primary_path() -> String:
	return _storage.primary_path()


func backup_path() -> String:
	return _storage.backup_path()


func temporary_path() -> String:
	return _storage.temporary_path()


func _unwrap(stored: SaveLoadResult) -> SaveLoadResult:
	if not stored.has_session_candidate():
		return stored
	var payload := stored.session_data
	if (
		payload.has("lab_schema_version")
		and _is_integer_number(payload["lab_schema_version"])
		and int(payload["lab_schema_version"]) > CURRENT_LAB_SCHEMA_VERSION
	):
		return _error_result(
			SaveLoadResult.Status.NEWER_SCHEMA,
			stored,
			PackedStringArray([
				"Defense Lab schema %d is newer than supported schema %d."
				% [int(payload["lab_schema_version"]), CURRENT_LAB_SCHEMA_VERSION],
			])
		)
	var errors := _validate_payload(payload)
	if not errors.is_empty():
		return _error_result(SaveLoadResult.Status.CORRUPT, stored, errors)
	var result := SaveLoadResult.new()
	result.status = stored.status
	result.schema_version = stored.schema_version
	result.saved_at_unix = stored.saved_at_unix
	result.last_gameplay_tab = 0
	result.source_path = stored.source_path
	result.errors = stored.errors.duplicate()
	result.session_data = (payload["state"] as Dictionary).duplicate(true)
	return result


func _validate_payload(payload: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in PAYLOAD_KEYS:
		if not payload.has(key):
			errors.append("%s: required Defense Lab payload field is missing" % key)
	for raw_key: Variant in payload.keys():
		if typeof(raw_key) != TYPE_STRING or not PAYLOAD_KEYS.has(String(raw_key)):
			errors.append("%s: unexpected Defense Lab payload field" % String(raw_key))
	if not errors.is_empty():
		return errors
	if not _is_integer_number(payload["lab_schema_version"]):
		errors.append("lab_schema_version must be an integer")
	elif int(payload["lab_schema_version"]) != CURRENT_LAB_SCHEMA_VERSION:
		errors.append(
			"lab_schema_version must equal %d" % CURRENT_LAB_SCHEMA_VERSION
		)
	if typeof(payload["state"]) != TYPE_DICTIONARY:
		errors.append("state must be an object")
	return errors


func _error_result(
	status: SaveLoadResult.Status,
	stored: SaveLoadResult,
	errors: PackedStringArray
) -> SaveLoadResult:
	var result := SaveLoadResult.new()
	result.status = status
	result.schema_version = stored.schema_version
	result.saved_at_unix = stored.saved_at_unix
	result.last_gameplay_tab = 0
	result.source_path = stored.source_path
	result.errors = stored.errors.duplicate()
	for error_message: String in errors:
		result.errors.append(error_message)
	return result


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == float(int(numeric))
