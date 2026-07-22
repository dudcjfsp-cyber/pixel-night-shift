class_name HybridOperatorAppealRules
extends RefCounted

const MAX_VISIBLE_APPEALS := 2
const OPERATOR_ORDER: Array[StringName] = [
	&"debugger", &"build_engineer", &"sprite_artist", &"qa_imp",
]


class Candidate:
	extends RefCounted

	var operator_id: StringName
	var message: String
	var evidence: String
	var diagnosis_kind: StringName
	var priority: int
	var event_serial: int


	func _init(
		id: StringName,
		text: String,
		fact: String,
		kind: StringName,
		rank: int,
		serial: int = 0
	) -> void:
		operator_id = id
		message = text
		evidence = fact
		diagnosis_kind = kind
		priority = rank
		event_serial = serial


	func to_snapshot() -> Dictionary:
		return {
			"operator_id": String(operator_id),
			"message": message,
			"evidence": evidence,
			"diagnosis_kind": String(diagnosis_kind),
		}


static func evaluate(
	diagnosis: Dictionary,
	recent_boss_events: Array[Dictionary],
	operators: Array[Dictionary]
) -> Array[Dictionary]:
	assert(diagnosis.has("kind"), "Hybrid appeals require a diagnosis kind")
	var kind := StringName(String(diagnosis["kind"]))
	var rows := _available_rows(operators)
	var candidates: Array[Candidate] = []
	for index: int in range(recent_boss_events.size() - 1, -1, -1):
		_add_event_candidate(candidates, kind, recent_boss_events[index], rows)
	_add_diagnosis_candidate(candidates, diagnosis, kind, rows)
	candidates.sort_custom(_precedes)

	var selected: Array[Dictionary] = []
	var selected_ids: Dictionary = {}
	for candidate: Candidate in candidates:
		if selected_ids.has(candidate.operator_id):
			continue
		selected.append(candidate.to_snapshot())
		selected_ids[candidate.operator_id] = true
		if selected.size() == MAX_VISIBLE_APPEALS:
			break
	return selected


static func _available_rows(operators: Array[Dictionary]) -> Dictionary:
	var rows: Dictionary = {}
	for row: Dictionary in operators:
		var id := StringName(String(row.get("id", row.get("operator_id", ""))))
		assert(not id.is_empty(), "Hybrid appeal operator rows require an id")
		if bool(row.get("unlocked", true)):
			rows[id] = row
	return rows


static func _add_event_candidate(
	candidates: Array[Candidate],
	diagnosis_kind: StringName,
	event: Dictionary,
	rows: Dictionary
) -> void:
	assert(event.has("kind"), "Hybrid appeal events require a kind")
	var event_kind := StringName(String(event["kind"]))
	var serial := int(event.get("serial", 0))
	var seconds := float(event.get("time", 0.0))
	match event_kind:
		&"boss_attempt_failed":
			var reason := StringName(String(event.get("reason", "")))
			if reason == &"boss_all_down" and rows.has(&"debugger"):
				var downs := _down_count(rows)
				var fact := "전원 PROCESS DOWN · %.1f초" % seconds
				if downs > 0:
					fact += " · 현재 DOWN %d명" % downs
				candidates.append(Candidate.new(
					&"debugger", "전원이 PROCESS DOWN됐습니다. 전열의 생존 여유를 점검해 주세요.",
					fact, diagnosis_kind, 110, serial
				))
			elif reason == &"boss_timeout" and rows.has(&"build_engineer"):
				candidates.append(Candidate.new(
					&"build_engineer", "제한 시간 안에 보스를 처리하지 못했습니다. 보스 대상 화력을 점검해 주세요.",
					"보스 제한 시간 초과 · %.1f초" % seconds, diagnosis_kind, 110, serial
				))
		&"qa_rescue_cancelled":
			if rows.has(&"qa_imp"):
				var target := String(event.get("operator_id", ""))
				var reason := _qa_reason(StringName(String(event.get("reason", ""))))
				candidates.append(Candidate.new(
					&"qa_imp", "예약했던 자동 구조가 취소됐습니다. QA 생존 상태를 점검해 주세요.",
					"%s 구조 예약 취소 · %s" % [target, reason], diagnosis_kind, 105, serial
				))
		&"qa_rescue_succeeded":
			if rows.has(&"qa_imp"):
				candidates.append(Candidate.new(
					&"qa_imp", "자동 구조가 작동했습니다. 구조 이후 팀 생존 상태를 확인해 주세요.",
					"%s 구조 성공 · 복구 HP %.1f" % [String(event.get("operator_id", "")), float(event.get("hp", 0.0))],
					diagnosis_kind, 100, serial
				))
		&"operator_down":
			var id := StringName(String(event.get("operator_id", "")))
			if rows.has(id):
				var row := rows[id] as Dictionary
				var fact := "%s로 PROCESS DOWN · %.1f초" % [
					_attack_name(StringName(String(event.get("attack", "")))), seconds,
				]
				if int(row.get("down_count", 0)) > 0:
					fact += " · 누적 DOWN %d회" % int(row["down_count"])
				candidates.append(Candidate.new(
					id, "이번 보스 시도에서 PROCESS DOWN됐습니다. 제 생존 여유를 확인해 주세요.",
					fact, diagnosis_kind, 90, serial
				))
		&"boss_rollback":
			var healed := float(event.get("healed", 0.0))
			if healed > 0.0 and rows.has(&"build_engineer"):
				candidates.append(Candidate.new(
					&"build_engineer", "ROLLBACK으로 보스 체력이 회복됐습니다. 보스 화력과 패치를 점검해 주세요.",
					"ROLLBACK 복구 HP %.1f · %.1f초" % [healed, seconds], diagnosis_kind, 75, serial
				))
		&"boss_debuff_applied":
			if rows.has(&"sprite_artist"):
				candidates.append(Candidate.new(
					&"sprite_artist", "처리량 저하가 적용됐습니다. 남은 전투 시간을 확인해 주세요.",
					"팀 DPS x%.2f · %.1f초" % [float(event.get("multiplier", 1.0)), seconds],
					diagnosis_kind, 80, serial
				))


static func _add_diagnosis_candidate(
	candidates: Array[Candidate],
	diagnosis: Dictionary,
	kind: StringName,
	rows: Dictionary
) -> void:
	var evidence := String(diagnosis.get("evidence", "")).strip_edges()
	if evidence.is_empty():
		return
	var title := String(diagnosis.get("title", "")).strip_edges()
	if not title.is_empty():
		evidence = "%s · %s" % [title, evidence]
	var preferred_ids: Array[StringName] = []
	var raw_recommended: Variant = diagnosis.get("recommended_operator_ids", [])
	if raw_recommended is Array:
		for raw_id: Variant in raw_recommended as Array:
			var recommended_id := StringName(String(raw_id))
			if not recommended_id.is_empty() and not preferred_ids.has(recommended_id):
				preferred_ids.append(recommended_id)
	var fallback_id := _operator_for_diagnosis(kind)
	if preferred_ids.is_empty() and not fallback_id.is_empty():
		preferred_ids.append(fallback_id)
	for index: int in preferred_ids.size():
		var id := preferred_ids[index]
		if not rows.has(id):
			continue
		candidates.append(Candidate.new(
			id, _diagnosis_message(kind, id), evidence, kind, 85 - index
		))


static func _operator_for_diagnosis(kind: StringName) -> StringName:
	match kind:
		&"incoming_damage", &"wipe_risk", &"survivability", &"boss_all_down", \
		&"process_down_risk", &"recent_failure_all_down":
			return &"debugger"
		&"throughput", &"firepower", &"boss_rollback", &"rule_response", \
		&"boss_timeout", &"timeout_risk", &"rollback_pressure", \
		&"recent_failure_timeout":
			return &"build_engineer"
		&"recovery_delay", &"qa_rescue", &"qa_unavailable", \
		&"qa_rescue_cancelled", &"qa_rescue_pending", &"qa_rescue_used":
			return &"qa_imp"
		&"cadence", &"stage_20_debuff":
			return &"sprite_artist"
	return &""


static func _diagnosis_message(kind: StringName, operator_id: StringName) -> String:
	match operator_id:
		&"debugger":
			return "진단에서 생존 위험이 확인됐습니다. 전열 상태를 점검해 주세요."
		&"build_engineer":
			return "진단에서 보스 처리 문제가 확인됐습니다. 보스 대상 화력과 패치를 점검해 주세요."
		&"qa_imp":
			return "진단에서 자동 구조 위험이 확인됐습니다. QA 생존 상태를 점검해 주세요."
		&"sprite_artist":
			return "진단에서 팀 공격 주기 영향이 확인됐습니다. 팀 템포를 점검해 주세요."
	return "진단 근거를 확인해 주세요."


static func _down_count(rows: Dictionary) -> int:
	var result := 0
	for raw_row: Variant in rows.values():
		var row := raw_row as Dictionary
		if bool(row.get("down", row.get("process_down", false))):
			result += 1
	return result


static func _attack_name(kind: StringName) -> String:
	if kind == &"boss_poll":
		return "POLL"
	if kind == &"boss_special":
		return "KILL SIGNAL"
	return String(kind) if not kind.is_empty() else "보스 공격"


static func _qa_reason(reason: StringName) -> String:
	match reason:
		&"qa_unavailable":
			return "QA 사용 불가"
		&"qa_process_down":
			return "QA PROCESS DOWN"
		&"attempt_failed":
			return "보스 시도 실패"
		&"attempt_cleared":
			return "보스 시도 종료"
	return String(reason)


static func _precedes(left: Candidate, right: Candidate) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	if left.event_serial != right.event_serial:
		return left.event_serial > right.event_serial
	return OPERATOR_ORDER.find(left.operator_id) < OPERATOR_ORDER.find(right.operator_id)
