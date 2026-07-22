class_name CombatV2TestSaveRepository
extends RefCounted

const CURRENT_SCHEMA_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1
const DEFAULT_BASE_DIR := "user://pixel_night_shift_combat_v2_test"
const REQUIRED_PAYLOAD_KEYS: PackedStringArray = ["v2_schema_version", "state"]
const LEGACY_STATE_KEYS: PackedStringArray = ["combat", "diagnosis_history", "patch_history"]
const APPEAL_STATE_DTO: GDScript = preload(
	"res://game/persistence/combat_v2_appeal_state_dto.gd"
)

var _storage: SaveRepository


func _init(base_dir: String = DEFAULT_BASE_DIR) -> void:
	assert(not base_dir.strip_edges().is_empty(), "Combat V2 test base_dir must not be empty.")
	_storage = SaveRepository.new(base_dir)


func load() -> SaveLoadResult:
	return _unwrap(_storage.load())


func load_backup() -> SaveLoadResult:
	return _unwrap(_storage.load_backup())


func save(state_data: Dictionary, saved_at_unix: int, last_gameplay_tab: int) -> Error:
	var payload := {
		"v2_schema_version": CURRENT_SCHEMA_VERSION,
		"state": state_data.duplicate(true),
	}
	if not _validate_payload(payload).is_empty():
		return ERR_INVALID_PARAMETER
	return _storage.save(payload, saved_at_unix, last_gameplay_tab)


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
	if payload.has("v2_schema_version") and _is_integer_number(payload["v2_schema_version"]):
		var version := int(payload["v2_schema_version"])
		if version > CURRENT_SCHEMA_VERSION:
			return _error_result(
				SaveLoadResult.Status.NEWER_SCHEMA,
				stored,
				PackedStringArray([
					"Combat V2 test schema %d is newer than supported schema %d."
					% [version, CURRENT_SCHEMA_VERSION],
				])
			)
		if version == LEGACY_SCHEMA_VERSION:
			var migration_errors := _validate_legacy_payload(payload)
			if not migration_errors.is_empty():
				return _error_result(SaveLoadResult.Status.CORRUPT, stored, migration_errors)
			payload = _migrate_v1_payload(payload)
	var errors := _validate_payload(payload)
	if not errors.is_empty():
		return _error_result(SaveLoadResult.Status.CORRUPT, stored, errors)
	var result := SaveLoadResult.new()
	result.status = stored.status
	result.schema_version = stored.schema_version
	result.saved_at_unix = stored.saved_at_unix
	result.last_gameplay_tab = stored.last_gameplay_tab
	result.source_path = stored.source_path
	result.errors = stored.errors.duplicate()
	result.session_data = (payload["state"] as Dictionary).duplicate(true)
	return result


func _validate_legacy_payload(payload: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in REQUIRED_PAYLOAD_KEYS:
		if not payload.has(key):
			errors.append("%s: required Combat V2 payload field is missing" % key)
	for raw_key: Variant in payload.keys():
		if typeof(raw_key) != TYPE_STRING or not REQUIRED_PAYLOAD_KEYS.has(String(raw_key)):
			errors.append("%s: unexpected Combat V2 payload field" % String(raw_key))
	if not errors.is_empty():
		return errors
	if not _is_integer_number(payload["v2_schema_version"]) or int(payload["v2_schema_version"]) != 1:
		errors.append("v2_schema_version must equal legacy schema 1")
	if typeof(payload["state"]) != TYPE_DICTIONARY:
		errors.append("state must be an object")
		return errors
	var state := payload["state"] as Dictionary
	for key: String in LEGACY_STATE_KEYS:
		if not state.has(key):
			errors.append("state.%s: required legacy field is missing" % key)
	for raw_key: Variant in state.keys():
		if typeof(raw_key) != TYPE_STRING or not LEGACY_STATE_KEYS.has(String(raw_key)):
			errors.append("state.%s: unexpected legacy field" % String(raw_key))
	return errors


func _migrate_v1_payload(payload: Dictionary) -> Dictionary:
	var migrated_state := (payload["state"] as Dictionary).duplicate(true)
	migrated_state["appeals"] = APPEAL_STATE_DTO.default_state()
	return {
		"v2_schema_version": CURRENT_SCHEMA_VERSION,
		"state": migrated_state,
	}


func _validate_payload(payload: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in REQUIRED_PAYLOAD_KEYS:
		if not payload.has(key):
			errors.append("%s: required Combat V2 payload field is missing" % key)
	for raw_key: Variant in payload.keys():
		if typeof(raw_key) != TYPE_STRING or not REQUIRED_PAYLOAD_KEYS.has(String(raw_key)):
			errors.append("%s: unexpected Combat V2 payload field" % String(raw_key))
	if not errors.is_empty():
		return errors
	if not _is_integer_number(payload["v2_schema_version"]):
		errors.append("v2_schema_version must be an integer")
	elif int(payload["v2_schema_version"]) != CURRENT_SCHEMA_VERSION:
		errors.append("v2_schema_version must equal %d" % CURRENT_SCHEMA_VERSION)
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
	result.last_gameplay_tab = stored.last_gameplay_tab
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
