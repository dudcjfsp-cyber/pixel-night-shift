class_name ContentLoadResult
extends RefCounted

var catalog: ContentCatalog
var errors: PackedStringArray = PackedStringArray()


func is_valid() -> bool:
	return catalog != null and errors.is_empty()
