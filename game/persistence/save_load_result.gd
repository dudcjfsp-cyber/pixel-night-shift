class_name SaveLoadResult
extends RefCounted

enum Status {
	NOT_FOUND,
	LOADED,
	RECOVERED_BACKUP,
	CORRUPT,
	NEWER_SCHEMA,
}

var status: Status = Status.NOT_FOUND
var session_data: Dictionary = {}
var saved_at_unix: int = 0
var last_gameplay_tab: int = 0
var errors: PackedStringArray = PackedStringArray()
var source_path: String = ""


func has_session_candidate() -> bool:
	return status == Status.LOADED or status == Status.RECOVERED_BACKUP
