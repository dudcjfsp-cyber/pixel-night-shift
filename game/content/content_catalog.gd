class_name ContentCatalog
extends RefCounted

var operators: Array[OperatorDefinition] = []
var patches: Array[PatchDefinition] = []
var balance: BalanceDefinition

var _operators_by_id: Dictionary = {}
var _patches_by_id: Dictionary = {}


func build_indexes() -> void:
	_operators_by_id.clear()
	_patches_by_id.clear()
	for definition: OperatorDefinition in operators:
		_operators_by_id[definition.id] = definition
	for definition: PatchDefinition in patches:
		_patches_by_id[definition.id] = definition


func has_operator(operator_id: StringName) -> bool:
	return _operators_by_id.has(operator_id)


func get_operator(operator_id: StringName) -> OperatorDefinition:
	return _operators_by_id.get(operator_id) as OperatorDefinition


func has_patch(patch_id: StringName) -> bool:
	return _patches_by_id.has(patch_id)


func get_patch(patch_id: StringName) -> PatchDefinition:
	return _patches_by_id.get(patch_id) as PatchDefinition
