extends SceneTree

const TEST_ROOT := "user://save_repository_schema_test"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var repository := SaveRepository.new(TEST_ROOT)
	repository.clear_records()
	_test_supported_envelopes(repository)
	_test_schema_rotation(repository)
	_test_newer_and_invalid(repository)
	repository.clear_records()
	print("SaveRepository schema test: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _test_supported_envelopes(repository: SaveRepository) -> void:
	_check(repository.save({"marker": "schema3"}, 3000, 2) == OK, "schema 3 save must succeed")
	var written := _read_json(repository.primary_path())
	_check(
		int(written.get("schema_version", 0)) == 3,
		"new saves must use schema 3"
	)
	var current := repository.load()
	_check(current.status == SaveLoadResult.Status.LOADED, "schema 3 envelope must load")
	_check(current.schema_version == 3, "load result must expose schema 3")

	_write_json(repository.primary_path(), _envelope(2, "schema2"))
	var previous := repository.load()
	_check(previous.status == SaveLoadResult.Status.LOADED, "schema 2 envelope must remain readable")
	_check(previous.schema_version == 2, "load result must expose schema 2")
	_check(previous.session_data.get("marker") == "schema2", "schema 2 payload must be preserved")
	_write_json(repository.primary_path(), _envelope(1, "schema1"))
	var legacy := repository.load()
	_check(legacy.status == SaveLoadResult.Status.LOADED, "schema 1 envelope must remain readable")
	_check(legacy.schema_version == 1, "load result must expose schema 1")
	_check(legacy.session_data.get("marker") == "schema1", "legacy session payload must be preserved")


func _test_schema_rotation(repository: SaveRepository) -> void:
	repository.clear_records()
	_write_json(repository.primary_path(), _envelope(2, "schema2"))
	_check(repository.save({"marker": "migrated"}, 3000, 1) == OK, "schema 2 primary must rotate safely")
	var migrated := repository.load()
	var backup := repository.load_backup()
	_check(migrated.schema_version == 3, "next save must promote the primary envelope to schema 3")
	_check(backup.schema_version == 2, "atomic rotation must preserve the schema 2 backup")
	_check(backup.session_data.get("marker") == "schema2", "rotated backup must retain old data")


func _test_newer_and_invalid(repository: SaveRepository) -> void:
	repository.clear_records()
	_write_json(repository.primary_path(), _envelope(4, "newer"))
	var newer := repository.load()
	_check(newer.status == SaveLoadResult.Status.NEWER_SCHEMA, "newer schema must be rejected explicitly")
	_check(newer.schema_version == 4, "newer result must expose its actual schema")

	repository.clear_records()
	_write_json(repository.primary_path(), _envelope(0, "invalid"))
	_check(repository.load().status == SaveLoadResult.Status.CORRUPT, "unsupported old schema must be invalid")


func _envelope(schema_version: int, marker: String) -> Dictionary:
	return {
		"schema_version": schema_version,
		"saved_at_unix": 1000,
		"last_gameplay_tab": 0,
		"session": {"marker": marker},
	}


func _write_json(path: String, value: Dictionary) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture file must open for writing")
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null:
		_check(false, "saved file must open for reading")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_check(false, "saved file must contain an object")
		return {}
	return parsed as Dictionary


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("  - %s" % message)
