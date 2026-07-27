class_name ProductV2SaveMigrator
extends RefCounted

const SaveRepository := preload(
	"res://game/persistence/save_repository.gd"
)
const GameSession := preload(
	"res://game/app/game_session.gd"
)
const ProductLoopSession := preload(
	"res://game/app/product_v2/product_loop_session.gd"
)
const ProductV2Catalog := preload(
	"res://game/content/product_v2/product_v2_catalog.gd"
)
const ProductLoopStateDto := preload(
	"res://game/app/product_v2/product_loop_state_dto.gd"
)


class MigrationResult:
	extends RefCounted

	var candidate: ProductLoopSession
	var session_data: Dictionary = {}
	var errors: PackedStringArray = PackedStringArray()
	var source_schema: int = 0
	var migrated: bool = false


	func is_valid() -> bool:
		return candidate != null and errors.is_empty()


static func migrate(
	schema_version: int,
	session_data: Dictionary,
	saved_at_unix: int,
	catalog_override: ProductV2Catalog = null
) -> MigrationResult:
	var result := MigrationResult.new()
	result.source_schema = schema_version
	if saved_at_unix < 0:
		result.errors.append("saved_at_unix: non-negative integer is required")
		return result
	if schema_version == SaveRepository.CURRENT_SCHEMA_VERSION:
		return _validate_current(
			session_data, catalog_override, result
		)
	if schema_version not in [
		SaveRepository.LEGACY_SCHEMA_VERSION,
		SaveRepository.PREVIOUS_SCHEMA_VERSION,
	]:
		result.errors.append(
			"schema_version: unsupported Product V2 migration source %d"
			% schema_version
		)
		return result
	return _migrate_legacy(
		schema_version,
		session_data,
		saved_at_unix,
		catalog_override,
		result
	)


static func _validate_current(
	session_data: Dictionary,
	catalog_override: ProductV2Catalog,
	result: MigrationResult
) -> MigrationResult:
	var candidate := ProductLoopSession.new(catalog_override)
	var restore_errors := candidate.restore_state(session_data)
	_append_errors(result.errors, "schema 3 session", restore_errors)
	if not result.errors.is_empty():
		return result
	result.candidate = candidate
	result.session_data = candidate.export_state()
	return result


static func _migrate_legacy(
	schema_version: int,
	session_data: Dictionary,
	saved_at_unix: int,
	catalog_override: ProductV2Catalog,
	result: MigrationResult
) -> MigrationResult:
	var legacy_candidate := GameSession.new()
	var legacy_errors := (
		legacy_candidate.restore_schema1_state(session_data)
		if schema_version == SaveRepository.LEGACY_SCHEMA_VERSION
		else legacy_candidate.restore_state(session_data)
	)
	_append_errors(result.errors, "legacy session", legacy_errors)
	if not result.errors.is_empty():
		return result

	var legacy := legacy_candidate.export_state()
	var run_count := int(legacy["run_count"])
	if run_count >= ProductLoopStateDto.MAX_JSON_SAFE_INTEGER:
		result.errors.append(
			"legacy session.run_count: cannot map safely to Product V2 version"
		)
		return result

	var candidate := ProductLoopSession.new(catalog_override)
	var candidate_export := candidate.export_state()
	var loop_data := (
		candidate_export["product_loop"] as Dictionary
	).duplicate(true)
	loop_data["version"] = run_count + 1
	loop_data["bits"] = floori(float(legacy["bits"]))
	loop_data["patch_notes"] = int(legacy["patch_notes"])
	loop_data["legacy_cache_level"] = int(legacy["legacy_cache_level"])
	loop_data["operator_levels"] = (
		legacy["operator_levels"] as Dictionary
	).duplicate(true)
	loop_data["unlocked_operator_ids"] = (
		legacy["unlocked_operator_ids"] as Array
	).duplicate(true)
	loop_data["discovered_patch_ids"] = (
		legacy["discovered_patch_ids"] as Array
	).duplicate(true)
	loop_data["unlocked_patch_slots"] = int(legacy["unlocked_patch_slots"])
	loop_data["equipped_patch_ids"] = ["", "", ""]
	loop_data["day_income_anchor_unix"] = saved_at_unix
	loop_data["day_income_remainder_seconds"] = 0
	loop_data["last_day_income_elapsed_seconds"] = 0
	loop_data["last_day_income_bits"] = 0
	loop_data["day_income_report_available"] = false
	loop_data["migration_source_schema"] = schema_version
	loop_data["migration_source_run_count"] = run_count
	loop_data["migration_saved_at_unix"] = saved_at_unix

	var migration_errors := candidate.restore_migrated_day_state(loop_data)
	_append_errors(result.errors, "Product V2 candidate", migration_errors)
	if not result.errors.is_empty():
		return result
	result.candidate = candidate
	result.session_data = candidate.export_state()
	result.migrated = true
	return result


static func _append_errors(
	destination: PackedStringArray,
	prefix: String,
	source: PackedStringArray
) -> void:
	for error_message: String in source:
		destination.append("%s: %s" % [prefix, error_message])
