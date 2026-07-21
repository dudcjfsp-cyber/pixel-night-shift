class_name AppealCatalog
extends RefCounted

var definitions: Array[AppealDefinition] = []
var _by_id: Dictionary = {}
var _by_trigger: Dictionary = {}


func build_indexes() -> void:
	_by_id.clear()
	_by_trigger.clear()
	for definition: AppealDefinition in definitions:
		_by_id[definition.id] = definition
		if not _by_trigger.has(definition.trigger):
			_by_trigger[definition.trigger] = []
		(_by_trigger[definition.trigger] as Array).append(definition)


func has_definition(definition_id: StringName) -> bool:
	return _by_id.has(definition_id)


func get_definition(definition_id: StringName) -> AppealDefinition:
	return _by_id.get(definition_id) as AppealDefinition


func definitions_for_trigger(trigger: StringName) -> Array[AppealDefinition]:
	var result: Array[AppealDefinition] = []
	if not _by_trigger.has(trigger):
		return result
	for raw_definition: Variant in _by_trigger[trigger] as Array:
		result.append(raw_definition as AppealDefinition)
	return result
