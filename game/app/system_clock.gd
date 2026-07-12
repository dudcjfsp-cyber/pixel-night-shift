class_name SystemClock
extends RefCounted


func now_unix() -> int:
	return int(Time.get_unix_time_from_system())
