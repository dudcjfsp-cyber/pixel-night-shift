class_name AppRoot
extends Control

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")
const KOREAN_FALLBACK_FONT: Font = preload(
	"res://game/assets/fonts/Galmuri11-Bold.ttf"
)
const POLICY: GDScript = preload("res://game/app/app_policy.gd")
const MAIN_VIEW_SCRIPT: GDScript = preload("res://game/presentation/main_view.gd")
const MAIN_VIEW_SCENE: PackedScene = preload("res://game/presentation/main.tscn")
const PRODUCT_LOOP_SESSION_SCRIPT: GDScript = preload(
	"res://game/app/product_v2/product_loop_session.gd"
)
const PRODUCT_V2_SAVE_MIGRATOR_SCRIPT: GDScript = preload(
	"res://game/app/product_v2/product_v2_save_migrator.gd"
)
const PRODUCT_DAY_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/day_prep_view.tscn"
)
const PRODUCT_NIGHT_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/night_shift_view.tscn"
)
const PRODUCT_RESULT_SCENE: PackedScene = preload(
	"res://game/presentation/product_v2/shift_result_view.tscn"
)
const BOOT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/boot_view.tscn"
)
const TITLE_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/title_view.tscn"
)
const PROLOGUE_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/prologue_view.tscn"
)
const OPERATIONS_ROOM_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/operations_room_view.tscn"
)
const OFFLINE_REPORT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/offline_report_view.tscn"
)
const SETTINGS_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/settings_view.tscn"
)
const SAVE_RECOVERY_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/save_recovery_view.tscn"
)
const VERSION_UPDATE_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/version_update_confirm_view.tscn"
)
const RUN_SUMMARY_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/run_summary_view.tscn"
)
const ONBOARDING_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/onboarding_view.tscn"
)
const COMBAT_V2_RESULT_SCENE: PackedScene = preload(
	"res://game/presentation/app_shell/views/combat_v2_result_view.tscn"
)
const OPERATIONS_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/operations_room_view_data.gd"
)
const OFFLINE_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/offline_report_view_data.gd"
)
const COMBAT_V2_RESULT_DATA_SCRIPT: GDScript = preload(
	"res://game/presentation/app_shell/view_data/combat_v2_result_view_data.gd"
)
const COMBAT_V2_LAUNCH_OPTION := "--combat-v2-test"

const SCREEN_NONE: StringName = &"none"
const SCREEN_BOOT: StringName = &"boot"
const SCREEN_TITLE: StringName = &"title"
const SCREEN_PROLOGUE: StringName = &"prologue"
const SCREEN_OPERATIONS_ROOM: StringName = &"operations_room"
const SCREEN_GAMEPLAY: StringName = &"gameplay"
const SCREEN_SAVE_RECOVERY: StringName = &"save_recovery"
const SCREEN_COMBAT_V2_RESULT: StringName = &"combat_v2_result"
const SCREEN_DAY_PREP: StringName = &"day_prep"
const SCREEN_NIGHT_ACTIVE: StringName = &"night_active"
const SCREEN_SHIFT_RESULT: StringName = &"shift_result"

const OVERLAY_NONE: StringName = &"none"
const OVERLAY_OFFLINE_REPORT: StringName = &"offline_report"
const OVERLAY_SETTINGS: StringName = &"settings"
const OVERLAY_VERSION_UPDATE_CONFIRM: StringName = &"version_update_confirm"
const OVERLAY_RUN_SUMMARY: StringName = &"run_summary"
const OVERLAY_ONBOARDING: StringName = &"onboarding"

const AUDIO_REFRESH_SECONDS := 0.12
const OPERATIONS_REFRESH_SECONDS := 0.25
const PRODUCT_VIEW_REFRESH_SECONDS := 0.05

var _save_repository: SaveRepository
var _combat_v2_save_repository: CombatV2TestSaveRepository
var _settings_repository: SettingsRepository
var _clock: Variant = null
var _services_configured := false
var _session: Variant = null
var _pending_session: Variant = null
var _combat_v2_test_mode := false
var _audio_director: AudioDirector
var _settings: AppSettings

var _safe_margin: MarginContainer
var _screen_host: Control
var _overlay_host: Control
var _screen_id: StringName = SCREEN_NONE
var _overlay_id: StringName = OVERLAY_NONE
var _gameplay_view: MAIN_VIEW_SCRIPT
var _product_day_view: DayPrepView
var _product_night_view: DefenseLabView
var _product_result_view: ShiftResultView
var _recovery_result: SaveLoadResult

var _started := false
var _backgrounded := false
var _background_started_at_unix := 0
var _last_saved_at_unix := 0
var _last_gameplay_tab := 0
var _save_has_error := false
var _save_status := "저장 전"
var _settings_has_error := false
var _settings_status := "설정 저장 전"
var _pending_offline_report: Dictionary = {}
var _onboarding_step := 0
var _pending_resume_saved_at_unix := 0
var _title_has_saved_shift := false
var _prologue_step := 0
var _prologue_is_replay := false
var _run_summary_data: Dictionary = {}
var _save_elapsed := 0.0
var _audio_refresh_left := 0.0
var _operations_refresh_left := 0.0
var _audio_snapshot: Dictionary = {}
var _field_report_key := ""
var _field_report_read_key := ""
var _field_report_rows: Array = []
var _field_report_is_v2 := false
var _product_night_paused := false
var _product_night_overlay_paused := false
var _product_night_resume_guard := false
var _product_refresh_left := 0.0


func configure_services(
	save_repository: SaveRepository,
	settings_repository: SettingsRepository,
	clock: Variant,
	combat_v2_save_repository: CombatV2TestSaveRepository = null,
	combat_v2_test_mode: bool = false
) -> bool:
	if is_inside_tree() or _services_configured:
		push_error("AppRoot services must be configured once before entering the tree.")
		return false
	if save_repository == null or settings_repository == null:
		push_error("AppRoot repositories cannot be null.")
		return false
	if clock == null or not clock.has_method("now_unix"):
		push_error("AppRoot clock must expose now_unix().")
		return false
	_save_repository = save_repository
	_combat_v2_save_repository = combat_v2_save_repository
	_settings_repository = settings_repository
	_clock = clock
	_combat_v2_test_mode = combat_v2_test_mode
	_services_configured = true
	return true


func current_screen_id() -> StringName:
	return _screen_id


func current_overlay_id() -> StringName:
	return _overlay_id


func session_snapshot() -> Dictionary:
	return {} if _session == null else _session.snapshot().duplicate(true)


func field_report_state() -> Dictionary:
	return {
		"key": _field_report_key,
		"rows": _field_report_rows.duplicate(true),
		"is_v2": _field_report_is_v2,
		"unread": (
			not _field_report_rows.is_empty()
			and _field_report_key != _field_report_read_key
		),
	}


func session_instance_id() -> int:
	return 0 if _session == null else int(_session.get_instance_id())


func last_gameplay_tab() -> int:
	return _last_gameplay_tab


func save_has_error() -> bool:
	return _save_has_error


func is_combat_v2_test_mode() -> bool:
	return _combat_v2_test_mode


func active_save_base_dir() -> String:
	return String(_active_save_repository().base_dir())


func handle_back_request() -> bool:
	if _overlay_id != OVERLAY_NONE:
		_close_overlay()
		return false
	if _screen_id == SCREEN_SAVE_RECOVERY and _screen_host.get_child_count() > 0:
		var recovery_view := _screen_host.get_child(0) as AppShellSaveRecoveryView
		if recovery_view != null and recovery_view.is_confirming_new_shift():
			recovery_view.show_new_shift_confirmation(false)
			return false
	if _screen_id == SCREEN_PROLOGUE:
		_show_title(_title_has_saved_shift)
		return false
	if _screen_id in [
		SCREEN_DAY_PREP,
		SCREEN_NIGHT_ACTIVE,
		SCREEN_SHIFT_RESULT,
	]:
		_save_progress("앱 이탈", false)
		return true
	if _screen_id in [SCREEN_GAMEPLAY, SCREEN_COMBAT_V2_RESULT]:
		_show_operations_room()
		_save_progress("현장에서 운영실로 이동")
		return false
	var should_exit := _screen_id in [
		SCREEN_OPERATIONS_ROOM, SCREEN_TITLE, SCREEN_SAVE_RECOVERY,
	]
	if should_exit and _session != null:
		_save_progress("앱 이탈", false)
	return should_exit


func handle_application_paused() -> void:
	if _backgrounded:
		return
	_background_started_at_unix = _now_unix()
	_save_progress("앱 일시정지", false)
	_backgrounded = true


func handle_application_resumed() -> void:
	if not _backgrounded:
		return
	_backgrounded = false
	_close_overlay()
	if _session != null:
		if _combat_v2_test_mode:
			_save_status = "Combat V2 오프라인 진행 미지원 · 상태 보존"
			_refresh_save_status_views()
		else:
			_apply_product_offline_progress(_background_started_at_unix)


func apply_safe_area(safe_rect: Rect2i, window_size: Vector2i) -> void:
	_apply_safe_area(safe_rect, window_size)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_ui_theme()
	if not _services_configured:
		_save_repository = SaveRepository.new()
		_settings_repository = SettingsRepository.new()
		_clock = SystemClock.new()
		_combat_v2_test_mode = _launch_option_enabled()
	if _combat_v2_test_mode and _combat_v2_save_repository == null:
		_combat_v2_save_repository = CombatV2TestSaveRepository.new()
	_build_hosts()
	_load_settings()
	_audio_director = AudioDirector.new()
	_audio_director.name = "AudioDirector"
	add_child(_audio_director)
	_apply_audio_settings()
	get_tree().auto_accept_quit = false
	get_window().size_changed.connect(_update_safe_area)
	_update_safe_area()
	call_deferred("_start_boot")


func _install_ui_theme() -> void:
	var default_ui_font := FontVariation.new()
	var fallback_fonts: Array[Font] = [KOREAN_FALLBACK_FONT]
	default_ui_font.fallbacks = fallback_fonts
	var app_theme := Theme.new()
	app_theme.default_font = default_ui_font
	theme = app_theme


func _process(delta_seconds: float) -> void:
	if not _started or _backgrounded or _session == null:
		return
	if not _combat_v2_test_mode:
		_process_product(delta_seconds)
		return
	_session.tick(delta_seconds)
	if _combat_v2_test_mode and _screen_id == SCREEN_GAMEPLAY and _session.is_complete():
		_save_progress("Combat V2 테스트 완료", false)
		_show_combat_v2_result()
		return
	_save_elapsed += delta_seconds
	_audio_refresh_left -= delta_seconds
	_operations_refresh_left -= delta_seconds
	if _audio_refresh_left <= 0.0:
		_audio_refresh_left = AUDIO_REFRESH_SECONDS
		_sync_audio()
	if _screen_id == SCREEN_OPERATIONS_ROOM and _operations_refresh_left <= 0.0:
		_operations_refresh_left = OPERATIONS_REFRESH_SECONDS
		_refresh_operations_room()
	if _save_elapsed >= POLICY.PERIODIC_SAVE_SECONDS:
		_save_elapsed = 0.0
		_save_progress("주기 저장")


func _process_product(delta_seconds: float) -> void:
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		push_error("Product V2 frame delta must be a non-negative finite value.")
		return
	var before_snapshot: Dictionary = _session.snapshot()
	var phase_name := String(before_snapshot.get("phase_name", ""))
	var skip_resume_tick := _product_night_resume_guard
	_product_night_resume_guard = false
	if (
		phase_name == "night_active"
		and _overlay_id == OVERLAY_NONE
		and not _product_night_paused
		and not _product_night_overlay_paused
		and not skip_resume_tick
	):
		var before_state: Dictionary = _session.export_state()
		if not _session.tick(_product_tick_delta(before_snapshot, delta_seconds)):
			_report_product_error("야간근무 진행이 거부되었습니다.")
			_product_night_paused = true
		else:
			var after_snapshot: Dictionary = _session.snapshot()
			if String(after_snapshot.get("phase_name", "")) != phase_name:
				if _save_progress("근무 결과 확정", false) != OK:
					if not _restore_product_state(before_state, "근무 결과 저장 실패"):
						return
					_product_night_paused = true
					_refresh_product_surface()
					return
				_product_night_paused = false
				_show_product_surface()
				_sync_audio()
				return

	_product_refresh_left -= delta_seconds
	_save_elapsed += delta_seconds
	_audio_refresh_left -= delta_seconds
	if _product_refresh_left <= 0.0:
		_product_refresh_left = PRODUCT_VIEW_REFRESH_SECONDS
		_refresh_product_surface()
	if _audio_refresh_left <= 0.0:
		_audio_refresh_left = AUDIO_REFRESH_SECONDS
		_sync_audio()
	if _save_elapsed < POLICY.PERIODIC_SAVE_SECONDS:
		return
	_save_elapsed = 0.0
	if phase_name == "day_prep":
		_account_product_day_income(false)
	else:
		_save_progress("주기 저장")


func _product_tick_delta(snapshot: Dictionary, delta_seconds: float) -> float:
	var playback_speed := clampi(int(snapshot.get("playback_speed", 1)), 1, 2)
	if playback_speed == 1:
		return delta_seconds
	var night := snapshot.get("night", {}) as Dictionary
	var night_phase := String(night.get("phase_name", ""))
	return (
		delta_seconds * float(playback_speed)
		if night_phase in ["normal_active", "boss_active"]
		else delta_seconds
	)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			handle_application_paused()
		NOTIFICATION_APPLICATION_RESUMED:
			handle_application_resumed()
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			handle_application_paused()
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			handle_application_resumed()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if handle_back_request():
				get_tree().quit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _session != null:
				_save_progress("창 닫기", false)
			get_tree().quit()


func _build_hosts() -> void:
	var background := ColorRect.new()
	background.name = "AppBackground"
	background.color = UI.COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_safe_margin = MarginContainer.new()
	_safe_margin.name = "SafeArea"
	_safe_margin.unique_name_in_owner = true
	add_child(_safe_margin)
	_safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack := Control.new()
	stack.name = "AppStack"
	_safe_margin.add_child(stack)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_screen_host = Control.new()
	_screen_host.name = "ScreenHost"
	_screen_host.unique_name_in_owner = true
	stack.add_child(_screen_host)
	_screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_host = Control.new()
	_overlay_host.name = "OverlayHost"
	_overlay_host.unique_name_in_owner = true
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_overlay_host)
	_overlay_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _start_boot() -> void:
	_show_boot()
	var started_at_msec := Time.get_ticks_msec()
	var load_result: SaveLoadResult = _active_save_repository().load()
	var elapsed_msec := Time.get_ticks_msec() - started_at_msec
	if elapsed_msec >= POLICY.BOOT_STATUS_DELAY_MSEC:
		await get_tree().process_frame
	_route_from_load_result(load_result)
	_started = true


func _route_from_load_result(load_result: SaveLoadResult) -> void:
	match load_result.status:
		SaveLoadResult.Status.NOT_FOUND:
			_session = null
			_pending_session = null
			_pending_resume_saved_at_unix = 0
			_reset_field_report_state()
			_show_title(false)
		SaveLoadResult.Status.LOADED:
			_restore_primary(load_result)
		SaveLoadResult.Status.RECOVERED_BACKUP, SaveLoadResult.Status.CORRUPT, SaveLoadResult.Status.NEWER_SCHEMA, SaveLoadResult.Status.MIGRATION_FAILED:
			_recovery_result = load_result
			_session = null
			_pending_session = null
			_show_save_recovery()
		_:
			push_error("Unknown SaveLoadResult status: %s" % load_result.status)
			_recovery_result = load_result
			_session = null
			_pending_session = null
			_show_save_recovery()


func _restore_primary(load_result: SaveLoadResult) -> void:
	var candidate: Variant = _make_session()
	var restore_errors := _restore_candidate(candidate, load_result)
	if not restore_errors.is_empty():
		var backup_result: SaveLoadResult = _active_save_repository().load_backup()
		if backup_result.has_session_candidate():
			var backup_candidate: Variant = _make_session()
			var backup_errors := _restore_candidate(backup_candidate, backup_result)
			if backup_errors.is_empty():
				backup_result.errors.append("Primary session data failed validation.")
				for error_message: String in restore_errors:
					backup_result.errors.append("primary session: %s" % error_message)
				_recovery_result = backup_result
				_show_save_recovery()
				return
			for error_message: String in backup_errors:
				backup_result.errors.append("backup session: %s" % error_message)
		_recovery_result = backup_result
		if _recovery_result.status != SaveLoadResult.Status.NEWER_SCHEMA:
			_recovery_result.status = SaveLoadResult.Status.CORRUPT
		for error_message: String in restore_errors:
			_recovery_result.errors.append("primary session: %s" % error_message)
		_show_save_recovery()
		return

	if not _persist_schema_migration(candidate, load_result):
		return
	_session = null
	_pending_session = candidate
	_pending_resume_saved_at_unix = load_result.saved_at_unix
	_last_gameplay_tab = load_result.last_gameplay_tab
	_last_saved_at_unix = load_result.saved_at_unix
	_show_title(true)


func _restore_candidate(
	candidate: Variant,
	load_result: SaveLoadResult
) -> PackedStringArray:
	if not _combat_v2_test_mode:
		return _restore_product_candidate(candidate, load_result)
	if load_result.schema_version == SaveRepository.LEGACY_SCHEMA_VERSION:
		return candidate.restore_schema1_state(load_result.session_data)
	return candidate.restore_state(load_result.session_data)


func _restore_product_candidate(
	candidate: Variant,
	load_result: SaveLoadResult
) -> PackedStringArray:
	var migration_result: Variant = PRODUCT_V2_SAVE_MIGRATOR_SCRIPT.migrate(
		load_result.schema_version,
		load_result.session_data,
		load_result.saved_at_unix
	)
	if not migration_result.errors.is_empty():
		return migration_result.errors
	if not migration_result.is_valid():
		return PackedStringArray([
			"Product V2 migration did not produce a validated session.",
		])
	return candidate.restore_state(migration_result.session_data)


func _persist_schema_migration(
	candidate: Variant,
	load_result: SaveLoadResult
) -> bool:
	var requires_migration := (
		load_result.schema_version != SaveRepository.CURRENT_SCHEMA_VERSION
	)
	if _combat_v2_test_mode:
		requires_migration = (
			load_result.schema_version == SaveRepository.LEGACY_SCHEMA_VERSION
		)
	if not requires_migration:
		return true
	var save_error: Error = _active_save_repository().save(
		candidate.export_state(),
		load_result.saved_at_unix,
		load_result.last_gameplay_tab
	)
	if save_error == OK:
		return true
	_show_migration_failure(load_result, save_error)
	return false


func _show_migration_failure(
	load_result: SaveLoadResult,
	save_error: Error
) -> void:
	var failure := SaveLoadResult.new()
	failure.status = SaveLoadResult.Status.MIGRATION_FAILED
	failure.schema_version = load_result.schema_version
	failure.saved_at_unix = load_result.saved_at_unix
	failure.last_gameplay_tab = load_result.last_gameplay_tab
	failure.source_path = load_result.source_path
	failure.errors = load_result.errors.duplicate()
	failure.errors.append(
		"Schema %d migration save failed with error %d."
		% [load_result.schema_version, save_error]
	)
	_recovery_result = failure
	_session = null
	_pending_session = null
	_pending_resume_saved_at_unix = 0
	_save_has_error = true
	_save_status = "저장 전환 실패 (오류 %d)" % save_error
	_show_save_recovery()


func _show_boot() -> void:
	_close_overlay()
	var view := BOOT_SCENE.instantiate() as AppShellBootView
	assert(view != null, "Boot scene must instantiate as AppShellBootView.")
	view.configure("근무 기록 확인 중…")
	_set_screen(SCREEN_BOOT, view)


func _show_title(has_saved_shift: bool, error_message: String = "") -> void:
	_close_overlay()
	_title_has_saved_shift = has_saved_shift
	var view := TITLE_SCENE.instantiate() as AppShellTitleView
	assert(view != null, "Title scene must instantiate as AppShellTitleView.")
	view.configure(has_saved_shift, error_message)
	view.start_requested.connect(_on_title_start_requested)
	view.continue_requested.connect(_on_title_continue_requested)
	view.prologue_replay_requested.connect(_on_title_prologue_replay_requested)
	view.settings_requested.connect(_show_settings)
	view.audio_unlock_requested.connect(_on_title_audio_unlock_requested)
	_set_screen(SCREEN_TITLE, view)
	_audio_director.play_title_music()


func _show_first_start(error_message: String = "") -> void:
	_show_title(false, error_message)


func _show_prologue(step: int = 0, replay: bool = false) -> void:
	_close_overlay()
	_prologue_step = clampi(step, 0, AppShellPrologueView.STEP_COUNT - 1)
	_prologue_is_replay = replay
	var view := PROLOGUE_SCENE.instantiate() as AppShellPrologueView
	assert(view != null, "Prologue scene must instantiate as AppShellPrologueView.")
	view.configure(_prologue_step, replay, _settings.reduced_motion)
	view.advance_requested.connect(_on_prologue_advance_requested)
	view.skip_requested.connect(_on_prologue_skip_requested)
	_set_screen(SCREEN_PROLOGUE, view)
	_audio_director.play_title_music()


func _show_operations_room() -> void:
	if not _combat_v2_test_mode:
		_show_product_surface()
		return
	_close_overlay()
	var view := OPERATIONS_ROOM_SCENE.instantiate() as AppShellOperationsRoomView
	assert(view != null, "Operations scene must instantiate as AppShellOperationsRoomView.")
	view.configure(_make_operations_data())
	view.continue_requested.connect(_show_gameplay)
	view.manual_requested.connect(_show_manual)
	view.settings_requested.connect(_show_settings)
	_set_screen(SCREEN_OPERATIONS_ROOM, view)


func _show_gameplay() -> void:
	if _session == null:
		push_error("Gameplay cannot open without an active GameSession.")
		return
	if not _combat_v2_test_mode:
		_show_product_surface()
		return
	if _combat_v2_test_mode and _session.is_complete():
		_show_combat_v2_result()
		return
	_close_overlay()
	_capture_field_report(_session.snapshot())
	var view: MAIN_VIEW_SCRIPT = MAIN_VIEW_SCENE.instantiate() as MAIN_VIEW_SCRIPT
	assert(view != null, "Gameplay scene must instantiate as MainView.")
	view.apply_accessibility(
		_settings.screen_shake_enabled,
		_settings.reduced_flashing,
		_settings.reduced_motion
	)
	var configured: bool = view.configure(_session, _audio_director)
	if not configured:
		push_error("Gameplay view rejected its AppRoot configuration.")
		_show_save_recovery_for_runtime_error("현장 화면을 구성하지 못했습니다.")
		return
	if not view.set_field_report_state(field_report_state()):
		push_error("Gameplay view rejected its field report state.")
		_show_save_recovery_for_runtime_error("현장 보고서를 구성하지 못했습니다.")
		return
	view.set_active_tab(_last_gameplay_tab)
	view.operations_room_requested.connect(_on_gameplay_operations_requested)
	view.settings_requested.connect(_show_settings)
	if not _combat_v2_test_mode:
		view.version_update_requested.connect(_show_version_update_confirm)
	view.session_changed.connect(_on_session_changed)
	view.active_tab_changed.connect(_on_active_tab_changed)
	view.field_report_read.connect(_on_field_report_read)
	_gameplay_view = view
	_set_screen(SCREEN_GAMEPLAY, view)


func _show_product_surface() -> void:
	if _session == null:
		push_error("Product V2 surface cannot open without an active session.")
		return
	_close_overlay()
	var snapshot: Dictionary = _session.snapshot()
	match String(snapshot.get("phase_name", "")):
		"day_prep":
			_show_product_day(snapshot)
		"night_active":
			_show_product_night(snapshot)
		"shift_result":
			_show_product_result(snapshot)
		_:
			_show_save_recovery_for_runtime_error(
				"알 수 없는 Product V2 화면 상태입니다."
			)


func _show_product_day(snapshot: Dictionary) -> void:
	var view := PRODUCT_DAY_SCENE.instantiate() as DayPrepView
	assert(view != null, "Product V2 day scene must instantiate as DayPrepView.")
	view.start_shift_requested.connect(_on_product_start_shift)
	view.field_report_read_requested.connect(_on_product_report_read)
	view.upgrade_operator_requested.connect(_on_product_upgrade_operator)
	view.patch_preview_requested.connect(_on_product_patch_preview)
	view.patch_equip_requested.connect(_on_product_equip_patch)
	view.version_update_requested.connect(_on_product_version_update)
	view.legacy_cache_purchase_requested.connect(_on_product_buy_legacy_cache)
	view.settings_requested.connect(_show_settings)
	_set_screen(SCREEN_DAY_PREP, view)
	_product_day_view = view
	view.set_reduced_motion(
		_settings.reduced_motion or _settings.reduced_flashing
	)
	view.refresh(snapshot)
	_product_refresh_left = PRODUCT_VIEW_REFRESH_SECONDS


func _show_product_night(snapshot: Dictionary) -> void:
	var view := PRODUCT_NIGHT_SCENE.instantiate() as DefenseLabView
	assert(view != null, "Product V2 night scene must instantiate as DefenseLabView.")
	var shift_index := int(snapshot.get("active_shift_index", 1))
	var speed_unlocked := _is_product_double_speed_unlocked(
		snapshot,
		shift_index
	)
	view.pause_requested.connect(_on_product_pause)
	view.speed_requested.connect(_on_product_speed)
	view.settings_requested.connect(_show_settings)
	_set_screen(SCREEN_NIGHT_ACTIVE, view)
	_product_night_view = view
	view.set_product_mode(true, speed_unlocked)
	view.refresh(snapshot.get("night", {}) as Dictionary)
	view.configure(
		_product_night_paused,
		float(snapshot.get("playback_speed", 1)),
		&"first_two",
		shift_index,
		_save_status
	)
	_product_refresh_left = PRODUCT_VIEW_REFRESH_SECONDS


func _show_product_result(snapshot: Dictionary) -> void:
	var view := PRODUCT_RESULT_SCENE.instantiate() as ShiftResultView
	assert(view != null, "Product V2 result scene must instantiate as ShiftResultView.")
	view.continue_to_day_requested.connect(_on_product_continue_to_day)
	view.settings_requested.connect(_show_settings)
	_set_screen(SCREEN_SHIFT_RESULT, view)
	_product_result_view = view
	view.refresh(snapshot)
	_product_refresh_left = PRODUCT_VIEW_REFRESH_SECONDS


func _refresh_product_surface() -> void:
	if _session == null or _combat_v2_test_mode:
		return
	var snapshot: Dictionary = _session.snapshot()
	var phase_name := StringName(String(snapshot.get("phase_name", "")))
	if phase_name != _screen_id:
		_show_product_surface()
		return
	match _screen_id:
		SCREEN_DAY_PREP:
			if _product_day_view != null:
				_product_day_view.refresh(snapshot)
		SCREEN_NIGHT_ACTIVE:
			if _product_night_view != null:
				var shift_index := int(snapshot.get("active_shift_index", 1))
				_product_night_view.set_product_mode(
					true,
					_is_product_double_speed_unlocked(snapshot, shift_index)
				)
				_product_night_view.refresh(
					snapshot.get("night", {}) as Dictionary
				)
				_product_night_view.configure(
					_product_night_paused,
					float(snapshot.get("playback_speed", 1)),
					&"first_two",
					shift_index,
					_save_status
				)
		SCREEN_SHIFT_RESULT:
			if _product_result_view != null:
				_product_result_view.refresh(snapshot)


func _show_combat_v2_result() -> void:
	if not _combat_v2_test_mode or _session == null or not _session.is_complete():
		push_error("Combat V2 result requires a completed V2 test session.")
		return
	_close_overlay()
	var data: CombatV2ResultViewData = COMBAT_V2_RESULT_DATA_SCRIPT.new(_session.result_data())
	var view := COMBAT_V2_RESULT_SCENE.instantiate() as CombatV2ResultView
	assert(view != null, "Combat V2 result scene must instantiate with its product script.")
	if not view.configure(data):
		_show_save_recovery_for_runtime_error("Combat V2 결과 화면을 구성하지 못했습니다.")
		return
	view.operations_room_requested.connect(_show_operations_room)
	view.restart_requested.connect(_on_combat_v2_restart_requested)
	_set_screen(SCREEN_COMBAT_V2_RESULT, view)


func _show_save_recovery() -> void:
	_close_overlay()
	var view := SAVE_RECOVERY_SCENE.instantiate() as AppShellSaveRecoveryView
	assert(view != null, "Recovery scene must instantiate as AppShellSaveRecoveryView.")
	var newer := _recovery_result != null and (
		_recovery_result.status == SaveLoadResult.Status.NEWER_SCHEMA
	)
	var migration_failed := _recovery_result != null and (
		_recovery_result.status == SaveLoadResult.Status.MIGRATION_FAILED
	)
	var backup_available := _recovery_result != null and (
		_recovery_result.status == SaveLoadResult.Status.RECOVERED_BACKUP
	)
	var title_text := "[오류] 근무 기록에 문제가 있습니다."
	var detail_text := "현재 기록과 백업을 모두 읽을 수 없습니다."
	if newer:
		title_text = "[업데이트 필요] 근무 기록을 열 수 없습니다."
		detail_text = "이 기록을 만든 버전보다 현재 게임이 오래되었습니다. 게임 업데이트가 필요합니다."
	elif migration_failed:
		title_text = "[저장 전환 실패] 기존 기록을 열지 못했습니다."
		detail_text = "기존 기록은 활성화하지 않았습니다. 저장 공간을 확인한 뒤 다시 시도해 주세요."
	elif backup_available:
		detail_text = "가장 최근 기록을 읽을 수 없습니다. 이전 백업은 사용할 수 있습니다."
	var backup_label := ""
	if backup_available:
		backup_label = "복구 시점 · %s" % Time.get_datetime_string_from_unix_time(
			_recovery_result.saved_at_unix, true
		)
	view.configure(title_text, detail_text, backup_available, backup_label, newer)
	view.backup_restore_requested.connect(_on_backup_restore_requested)
	view.retry_requested.connect(_on_recovery_retry_requested)
	view.new_shift_requested.connect(_on_new_shift_requested)
	_set_screen(SCREEN_SAVE_RECOVERY, view)


func _show_save_recovery_for_runtime_error(message: String) -> void:
	_recovery_result = SaveLoadResult.new()
	_recovery_result.status = SaveLoadResult.Status.CORRUPT
	_recovery_result.errors.append(message)
	_session = null
	_pending_session = null
	_pending_resume_saved_at_unix = 0
	_show_save_recovery()


func _set_screen(screen_id: StringName, view: Control) -> void:
	assert(view != null, "Screen view cannot be null.")
	_replace_host_child(_screen_host, view)
	_screen_id = screen_id
	if screen_id != SCREEN_GAMEPLAY:
		_gameplay_view = null
	if screen_id != SCREEN_DAY_PREP:
		_product_day_view = null
	if screen_id != SCREEN_NIGHT_ACTIVE:
		_product_night_view = null
	if screen_id != SCREEN_SHIFT_RESULT:
		_product_result_view = null


func _show_overlay(overlay_id: StringName, view: Control) -> void:
	assert(view != null, "Overlay view cannot be null.")
	_replace_host_child(_overlay_host, view)
	_overlay_id = overlay_id
	if _screen_id == SCREEN_NIGHT_ACTIVE:
		_product_night_overlay_paused = true


func _close_overlay() -> void:
	var resumes_product_night := (
		_product_night_overlay_paused
		and _screen_id == SCREEN_NIGHT_ACTIVE
	)
	if _overlay_host != null:
		_clear_host(_overlay_host)
	_overlay_id = OVERLAY_NONE
	_product_night_overlay_paused = false
	if resumes_product_night:
		_product_night_resume_guard = true


func _replace_host_child(host: Control, child: Control) -> void:
	_clear_host(host)
	host.add_child(child)
	child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _clear_host(host: Control) -> void:
	for child: Node in host.get_children():
		host.remove_child(child)
		child.queue_free()


func _show_settings() -> void:
	var view := SETTINGS_SCENE.instantiate() as AppShellSettingsView
	assert(view != null, "Settings scene must instantiate as AppShellSettingsView.")
	view.configure(
		_settings_view_data(),
		_combined_save_status(),
		_save_has_error or _settings_has_error,
		_is_vibration_supported()
	)
	view.set_manual_available(_session != null and _combat_v2_test_mode)
	view.close_requested.connect(_close_overlay)
	view.music_volume_changed.connect(_on_music_volume_changed)
	view.sfx_volume_changed.connect(_on_sfx_volume_changed)
	view.vibration_changed.connect(_on_vibration_changed)
	view.screen_shake_changed.connect(_on_screen_shake_changed)
	view.reduced_flashes_changed.connect(_on_reduced_flashes_changed)
	view.reduced_motion_changed.connect(_on_reduced_motion_changed)
	view.save_retry_requested.connect(_on_save_retry_requested)
	view.manual_requested.connect(_show_manual)
	view.reset_records_requested.connect(_on_reset_records_requested)
	_show_overlay(OVERLAY_SETTINGS, view)


func _show_version_update_confirm() -> void:
	if _session == null or _combat_v2_test_mode:
		return
	var snapshot: Dictionary = _session.snapshot()
	if not bool(snapshot.get("prestige_available", false)):
		push_error("Version update was requested while it is locked.")
		return
	var view := VERSION_UPDATE_SCENE.instantiate() as AppShellVersionUpdateConfirmView
	assert(view != null, "Version update scene must instantiate with its product script.")
	view.confirm_requested.connect(_on_version_update_confirmed)
	view.cancel_requested.connect(_close_overlay)
	_show_overlay(OVERLAY_VERSION_UPDATE_CONFIRM, view)


func _show_run_summary() -> void:
	var view := RUN_SUMMARY_SCENE.instantiate() as AppShellRunSummaryView
	assert(view != null, "Run summary scene must instantiate with its product script.")
	if not view.configure(_run_summary_data):
		push_error("Run summary data failed product-view validation.")
		return
	view.continue_requested.connect(_on_run_summary_continue_requested)
	_show_overlay(OVERLAY_RUN_SUMMARY, view)


func _show_onboarding(step: int = 0) -> void:
	if _session == null or _combat_v2_test_mode:
		return
	if _screen_id != SCREEN_GAMEPLAY:
		_show_gameplay()
	_onboarding_step = clampi(step, 0, AppShellOnboardingView.STEP_COUNT - 1)
	var view := ONBOARDING_SCENE.instantiate() as AppShellOnboardingView
	assert(view != null, "Onboarding scene must instantiate with its product script.")
	view.configure(_onboarding_step)
	view.advance_requested.connect(_on_onboarding_advance_requested)
	view.diagnosis_requested.connect(_on_onboarding_diagnosis_requested)
	view.skip_requested.connect(_on_onboarding_skip_requested)
	_show_overlay(OVERLAY_ONBOARDING, view)


func _show_manual() -> void:
	_close_overlay()
	_show_onboarding(0)


func _show_offline_report() -> void:
	if _pending_offline_report.is_empty():
		return
	var data: OfflineReportViewData = OFFLINE_DATA_SCRIPT.new(
		int(_pending_offline_report["absence_seconds"]),
		float(_pending_offline_report["recovered_bits"]),
		int(_pending_offline_report["stage_from"]),
		int(_pending_offline_report["stage_to"]),
		bool(_pending_offline_report["has_bottleneck"]),
		int(_pending_offline_report["bottleneck_stage"]),
		String(_pending_offline_report["bottleneck_cause"]),
		bool(_pending_offline_report["reached_cap"])
	)
	var view := OFFLINE_REPORT_SCENE.instantiate() as AppShellOfflineReportView
	assert(view != null, "Offline report scene must instantiate with its product script.")
	view.configure(data)
	view.bottleneck_requested.connect(_on_offline_bottleneck_requested)
	view.continue_requested.connect(_on_offline_continue_requested)
	view.operations_room_requested.connect(_on_offline_operations_requested)
	_pending_offline_report = {}
	_show_overlay(OVERLAY_OFFLINE_REPORT, view)


func _on_title_audio_unlock_requested() -> void:
	_audio_director.retry_current_music_after_user_gesture()


func _on_title_start_requested() -> void:
	_on_title_audio_unlock_requested()
	_audio_director.play_cue(&"shift_authorized")
	if _combat_v2_test_mode:
		_on_first_shift_requested()
		return
	_show_prologue(0, false)


func _on_title_continue_requested() -> void:
	_on_title_audio_unlock_requested()
	if _pending_session == null:
		push_error("Continue was requested without a validated pending session.")
		_show_title(true, "근무 기록을 활성화하지 못했습니다. 다시 실행해 주세요.")
		return
	_audio_director.play_cue(&"shift_authorized")
	_session = _pending_session
	_pending_session = null
	var offline_baseline := _pending_resume_saved_at_unix
	_pending_resume_saved_at_unix = 0
	_show_operations_room()
	if _combat_v2_test_mode:
		_save_status = "Combat V2 테스트 저장 복구됨 · 오프라인 진행 미지원"
		_refresh_save_status_views()
	else:
		_apply_product_offline_progress(offline_baseline)
	_audio_snapshot = {}
	_sync_audio()


func _on_title_prologue_replay_requested() -> void:
	if _pending_session == null:
		push_error("Prologue replay requires a validated pending session.")
		return
	_show_prologue(0, true)


func _on_prologue_advance_requested() -> void:
	if _prologue_step >= AppShellPrologueView.STEP_COUNT - 1:
		_finish_prologue()
		return
	_show_prologue(_prologue_step + 1, _prologue_is_replay)


func _on_prologue_skip_requested() -> void:
	_finish_prologue()


func _finish_prologue() -> void:
	if _prologue_is_replay:
		_show_title(true)
		return
	_on_first_shift_requested()


func _on_first_shift_requested() -> void:
	var candidate: Variant = _make_session()
	if not _combat_v2_test_mode:
		candidate.account_day_income(_now_unix())
	_reset_field_report_state()
	_session = candidate
	_pending_session = null
	_pending_resume_saved_at_unix = 0
	_last_gameplay_tab = 0
	_last_saved_at_unix = 0
	var save_error := _save_progress("첫 근무 최초 저장", false)
	if save_error != OK:
		_session = null
		_show_first_start("최초 저장에 실패했습니다. 저장 공간을 확인한 뒤 다시 시도하세요.")
		return
	_audio_snapshot = {}
	_sync_audio()
	if _combat_v2_test_mode:
		_show_operations_room()
	else:
		_show_gameplay()


func _on_gameplay_operations_requested() -> void:
	_capture_gameplay_tab()
	_show_operations_room()
	_save_progress("운영실 진입")


func _on_session_changed() -> void:
	_save_progress("현장 상태 변경")


func _on_product_start_shift(shift_index: int) -> void:
	if _execute_product_command(
		func() -> bool: return _session.start_shift(shift_index),
		"야간근무 시작"
	):
		_product_night_paused = false
		_audio_director.play_cue(&"shift_authorized")


func _on_product_upgrade_operator(operator_id: StringName) -> void:
	if _execute_product_command(
		func() -> bool: return _session.upgrade_operator(operator_id),
		"요원 강화"
	):
		_audio_director.play_cue(&"operator_upgrade")


func _on_product_patch_preview(
	slot_index: int,
	patch_id: StringName
) -> void:
	if _session == null or _product_day_view == null:
		return
	_product_day_view.set_patch_preview(
		_session.get_patch_preview(slot_index, patch_id)
	)


func _on_product_equip_patch(
	slot_index: int,
	patch_id: StringName
) -> void:
	if _execute_product_command(
		func() -> bool: return _session.equip_patch(slot_index, patch_id),
		"패치 교체"
	):
		_audio_director.play_cue(&"patch_apply")
		if _product_day_view != null:
			_product_day_view.set_patch_preview(
				_session.get_patch_preview(slot_index, patch_id)
			)


func _on_product_report_read(report_key: String) -> void:
	_execute_product_command(
		func() -> bool: return _session.mark_report_read(report_key),
		"현장 보고서 확인"
	)


func _on_product_version_update() -> void:
	if _execute_product_command(
		func() -> bool: return _session.version_update(_now_unix()),
		"버전 업데이트"
	):
		_audio_director.play_cue(&"version_update")


func _on_product_buy_legacy_cache() -> void:
	_execute_product_command(
		func() -> bool: return _session.buy_legacy_cache(),
		"레거시 빌드 캐시"
	)


func _on_product_continue_to_day() -> void:
	if _execute_product_command(
		func() -> bool: return _session.continue_to_day(_now_unix()),
		"주간 정비 전환"
	):
		_product_night_paused = false


func _on_product_pause() -> void:
	if _screen_id != SCREEN_NIGHT_ACTIVE:
		return
	_product_night_paused = not _product_night_paused
	_refresh_product_surface()


func _on_product_speed() -> void:
	if _session == null or _screen_id != SCREEN_NIGHT_ACTIVE:
		return
	var snapshot: Dictionary = _session.snapshot()
	var current_speed := int(snapshot.get("playback_speed", 1))
	var next_speed := 2 if current_speed == 1 else 1
	_execute_product_command(
		func() -> bool: return _session.set_playback_speed(next_speed),
		"야간근무 배속"
	)


func _execute_product_command(
	command: Callable,
	save_reason: String
) -> bool:
	if _session == null or _combat_v2_test_mode:
		return false
	var before: Dictionary = _session.export_state()
	var phase_before := String(_session.snapshot().get("phase_name", ""))
	if not bool(command.call()):
		_report_product_error(
			String(_session.snapshot().get("last_error", "%s 실패" % save_reason))
		)
		_refresh_product_surface()
		return false
	if _save_progress(save_reason, false) != OK:
		_restore_product_state(before, "%s 저장 실패" % save_reason)
		_refresh_product_surface()
		return false
	var phase_after := String(_session.snapshot().get("phase_name", ""))
	if phase_after != phase_before:
		_show_product_surface()
	else:
		_refresh_product_surface()
	_sync_audio()
	return true


func _restore_product_state(before: Dictionary, context: String) -> bool:
	var restore_errors: PackedStringArray = _session.restore_state(before)
	if restore_errors.is_empty():
		return true
	push_error("%s: %s" % [context, "; ".join(restore_errors)])
	_show_save_recovery_for_runtime_error("%s 원복에 실패했습니다." % context)
	return false


func _report_product_error(message: String) -> void:
	push_error("Product V2 command failed: %s" % message)
	_save_status = "요청 거부 · %s" % message
	if _audio_director != null:
		_audio_director.play_cue(&"ui_error")


func _is_product_double_speed_unlocked(
	snapshot: Dictionary,
	shift_index: int
) -> bool:
	for raw_record: Variant in snapshot.get("shift_records", []) as Array:
		if (
			raw_record is Dictionary
			and int((raw_record as Dictionary).get("shift_index", 0)) == shift_index
		):
			return bool(
				(raw_record as Dictionary).get(
					"retry_speed_2x_unlocked",
					false
				)
			)
	return false


func _on_active_tab_changed(tab_index: int) -> void:
	if tab_index < POLICY.GAMEPLAY_TAB_MIN or tab_index > POLICY.GAMEPLAY_TAB_MAX:
		push_error("Gameplay emitted invalid tab index %d." % tab_index)
		return
	_last_gameplay_tab = tab_index
	_save_progress("현장 탭 변경")


func _on_field_report_read(report_key: String) -> void:
	if report_key.is_empty() or report_key != _field_report_key:
		push_error("Gameplay reported an unknown field report key: %s" % report_key)
		return
	_field_report_read_key = report_key
	_push_field_report_state_to_gameplay()


func _on_combat_v2_restart_requested() -> void:
	if not _combat_v2_test_mode:
		return
	var clear_error: Error = _active_save_repository().clear_records()
	if clear_error != OK:
		_show_save_recovery_for_runtime_error(
			"Combat V2 테스트 저장 초기화 실패 (오류 %d)" % clear_error
		)
		return
	_session = _make_session()
	_reset_field_report_state()
	_last_gameplay_tab = 0
	_last_saved_at_unix = 0
	if _save_progress("Combat V2 테스트 새로 시작", false) != OK:
		_show_save_recovery_for_runtime_error("Combat V2 새 테스트를 저장하지 못했습니다.")
		return
	_show_gameplay()


func _on_backup_restore_requested() -> void:
	if _recovery_result == null or not _recovery_result.has_session_candidate():
		_set_recovery_view_error("사용할 수 있는 백업 후보가 없습니다.")
		return
	var candidate: Variant = _make_session()
	var restore_errors := _restore_candidate(candidate, _recovery_result)
	if not restore_errors.is_empty():
		_set_recovery_view_error("백업 세션 검증 실패: %s" % "; ".join(restore_errors))
		return
	var promote_error: Error = _active_save_repository().promote_backup()
	if promote_error != OK:
		_set_recovery_view_error("백업 파일 복구 실패 (오류 %d)" % promote_error)
		return
	if not _persist_schema_migration(candidate, _recovery_result):
		return
	_session = candidate
	_pending_session = null
	_pending_resume_saved_at_unix = 0
	_last_gameplay_tab = _recovery_result.last_gameplay_tab
	_last_saved_at_unix = _recovery_result.saved_at_unix
	_show_operations_room()
	if not _combat_v2_test_mode:
		_apply_product_offline_progress(_recovery_result.saved_at_unix)


func _on_recovery_retry_requested() -> void:
	_route_from_load_result(_active_save_repository().load())


func _on_new_shift_requested() -> void:
	var clear_error: Error = _active_save_repository().clear_records()
	if clear_error != OK:
		_set_recovery_view_error("근무 기록 삭제 실패 (오류 %d)" % clear_error)
		return
	_session = null
	_pending_session = null
	_reset_field_report_state()
	_recovery_result = null
	_last_saved_at_unix = 0
	_pending_resume_saved_at_unix = 0
	_background_started_at_unix = 0
	_audio_snapshot = {}
	_save_has_error = false
	_save_status = "새 근무 저장 전"
	_show_first_start()


func _on_version_update_confirmed() -> void:
	if _session == null or _combat_v2_test_mode:
		return
	var before_state: Dictionary = _session.export_state()
	var before_snapshot: Dictionary = _session.snapshot()
	if not _session.prestige():
		_set_version_view_error(String(_session.snapshot().get("last_error", "업데이트 실행 실패")))
		return
	var save_error := _save_progress("버전 업데이트", false)
	if save_error != OK:
		var rollback_errors: PackedStringArray = _session.restore_state(before_state)
		if not rollback_errors.is_empty():
			push_error("Version update rollback failed: %s" % "; ".join(rollback_errors))
			_show_save_recovery_for_runtime_error("버전 업데이트 원복에 실패했습니다.")
			return
		_set_version_view_error("저장에 실패해 업데이트를 실행하지 않았습니다.")
		return
	_run_summary_data = _make_run_summary_data(before_snapshot, _session.snapshot())
	_audio_director.play_cue(&"version_update")
	_show_run_summary()


func _on_run_summary_continue_requested() -> void:
	_close_overlay()
	if _screen_id != SCREEN_GAMEPLAY:
		_show_gameplay()


func _on_offline_bottleneck_requested() -> void:
	_close_overlay()
	_show_gameplay()
	if _gameplay_view != null:
		_gameplay_view.set_active_tab(1)
		_last_gameplay_tab = 1
		_save_progress("정체 지점 확인")


func _on_offline_continue_requested() -> void:
	_close_overlay()
	_show_gameplay()


func _on_offline_operations_requested() -> void:
	_close_overlay()
	_show_operations_room()


func _on_onboarding_advance_requested() -> void:
	if _onboarding_step >= AppShellOnboardingView.STEP_COUNT - 1:
		_complete_onboarding()
		return
	_show_onboarding(_onboarding_step + 1)


func _on_onboarding_diagnosis_requested() -> void:
	if _gameplay_view != null:
		_gameplay_view.set_active_tab(0)
		_last_gameplay_tab = 0
		_save_progress("온보딩 요원 강화 보기")
	_show_onboarding(_onboarding_step + 1)


func _on_onboarding_skip_requested() -> void:
	_complete_onboarding()


func _complete_onboarding() -> void:
	_settings.onboarding_completed = true
	_save_settings("온보딩 완료")
	_close_overlay()


func _on_music_volume_changed(value: int) -> void:
	_settings.music_volume = float(value) / 100.0
	_audio_director.set_music_volume_percent(value)
	_save_settings("배경음악 설정")


func _on_sfx_volume_changed(value: int) -> void:
	_settings.sfx_volume = float(value) / 100.0
	_audio_director.set_sfx_volume_percent(value)
	_save_settings("효과음 설정")


func _on_vibration_changed(enabled: bool) -> void:
	if not _is_vibration_supported():
		return
	_settings.vibration_enabled = enabled
	_save_settings("진동 설정")


func _on_screen_shake_changed(enabled: bool) -> void:
	_settings.screen_shake_enabled = enabled
	_apply_gameplay_accessibility()
	_save_settings("화면 흔들림 설정")


func _on_reduced_flashes_changed(enabled: bool) -> void:
	_settings.reduced_flashing = enabled
	_apply_gameplay_accessibility()
	_save_settings("점멸 설정")


func _on_reduced_motion_changed(enabled: bool) -> void:
	_settings.reduced_motion = enabled
	_apply_gameplay_accessibility()
	_save_settings("동작 설정")


func _apply_gameplay_accessibility() -> void:
	if _gameplay_view != null:
		_gameplay_view.apply_accessibility(
			_settings.screen_shake_enabled,
			_settings.reduced_flashing,
			_settings.reduced_motion
		)
	if _product_day_view != null:
		_product_day_view.set_reduced_motion(
			_settings.reduced_motion or _settings.reduced_flashing
		)


func _on_save_retry_requested() -> void:
	if _session != null:
		_save_progress("사용자 저장 재시도")
	_save_settings("사용자 설정 저장 재시도")
	_refresh_settings_view()


func _on_reset_records_requested() -> void:
	var clear_error: Error = _active_save_repository().clear_records()
	if clear_error != OK:
		_save_has_error = true
		_save_status = "근무 기록 삭제 실패 (오류 %d)" % clear_error
		_refresh_settings_view()
		return
	_session = null
	_pending_session = null
	_reset_field_report_state()
	_pending_offline_report = {}
	_last_saved_at_unix = 0
	_pending_resume_saved_at_unix = 0
	_background_started_at_unix = 0
	_audio_snapshot = {}
	_save_has_error = false
	_save_status = "새 근무 저장 전"
	_close_overlay()
	_show_first_start()


func _set_recovery_view_error(message: String) -> void:
	var view := _screen_host.get_child(0) as AppShellSaveRecoveryView if _screen_host.get_child_count() > 0 else null
	if view != null:
		view.set_error(message)


func _set_version_view_error(message: String) -> void:
	var view := _overlay_host.get_child(0) as AppShellVersionUpdateConfirmView if _overlay_host.get_child_count() > 0 else null
	if view != null:
		view.set_error(message)


func _make_operations_data() -> OperationsRoomViewData:
	assert(_session != null, "Operations data requires an active session.")
	var snapshot: Dictionary = _session.snapshot()
	var diagnosis := snapshot.get("diagnosis", {}) as Dictionary
	var slots := snapshot.get("patch_slots", []) as Array
	var equipped_count := 0
	for slot_value: Variant in slots:
		if not String(slot_value).is_empty():
			equipped_count += 1
	var save_state := OperationsRoomViewData.SaveState.SAVED
	if _save_has_error:
		save_state = OperationsRoomViewData.SaveState.ERROR
	return OperationsRoomViewData.new(
		int(snapshot["run_count"]) + 1,
		true,
		_operations_status(snapshot),
		int(snapshot["stage"]),
		String(diagnosis.get("title", "진단 정보 없음")),
		equipped_count,
		int(snapshot["unlocked_patch_slots"]),
		_next_goal(snapshot),
		_save_status,
		save_state,
		(
			"V2 결과 보기"
			if _combat_v2_test_mode and bool(snapshot["combat_v2_complete"])
			else "Combat V2 테스트 진입" if _combat_v2_test_mode else "현장 복귀"
		)
	)


func _operations_status(snapshot: Dictionary) -> String:
	if _combat_v2_test_mode:
		return "Combat V2 테스트 · 자동 전투"
	match String(snapshot.get("mode", "combat")):
		"boss":
			return "보스 자동 대응 중"
		"maintenance":
			return "유지보수 후 자동 재시도"
		"complete":
			return "버전 업데이트 준비"
	return "자동 운영 중"


func _next_goal(snapshot: Dictionary) -> String:
	if _combat_v2_test_mode:
		return "테스트 결과 확인" if bool(snapshot["combat_v2_complete"]) else "Watchdog · ST 10"
	if bool(snapshot.get("prestige_available", false)):
		return "버전 업데이트 실행"
	var stage := int(snapshot.get("stage", 1))
	if stage < 10:
		return "감시견 · ST 10"
	return "최종 감시견 · ST 20"


func _refresh_operations_room() -> void:
	if _screen_id != SCREEN_OPERATIONS_ROOM or _session == null:
		return
	if _screen_host.get_child_count() == 0:
		return
	var view := _screen_host.get_child(0) as AppShellOperationsRoomView
	if view != null:
		view.configure(_make_operations_data())


func _make_run_summary_data(before: Dictionary, after: Dictionary) -> Dictionary:
	var slots := before.get("patch_slots", []) as Array
	var patch_count := 0
	for slot_value: Variant in slots:
		if not String(slot_value).is_empty():
			patch_count += 1
	var diagnosis := before.get("diagnosis", {}) as Dictionary
	return {
		"new_run_number": int(after["run_count"]) + 1,
		"patch_note_gain": int(after["patch_notes"]) - int(before["patch_notes"]),
		"previous_highest_stage": int(before["stage"]),
		"bottleneck": String(diagnosis.get("title", "운영 안정")),
		"used_patch_count": patch_count,
		"next_goal": "첫 보스 도달 시간 25% 단축",
	}


func _apply_product_offline_progress(baseline_unix: int) -> void:
	if _session == null or _combat_v2_test_mode:
		return
	var snapshot: Dictionary = _session.snapshot()
	var phase_name := String(snapshot.get("phase_name", ""))
	if phase_name != "day_prep":
		_save_status = (
			"야간근무는 저장 지점에서 재개됩니다."
			if phase_name == "night_active"
			else "근무 결과는 저장된 상태로 유지됩니다."
		)
		_refresh_save_status_views()
		return
	_account_product_day_income(true, baseline_unix)


func _account_product_day_income(
	show_report: bool,
	fallback_anchor_unix: int = 0
) -> bool:
	if _session == null or _combat_v2_test_mode:
		return false
	var snapshot: Dictionary = _session.snapshot()
	if String(snapshot.get("phase_name", "")) != "day_prep":
		return false
	var before: Dictionary = _session.export_state()
	var now_unix := _now_unix()
	var offline := snapshot.get("offline", {}) as Dictionary
	if (
		int(offline.get("anchor_unix", 0)) == 0
		and fallback_anchor_unix > 0
		and fallback_anchor_unix <= now_unix
	):
		_session.account_day_income(fallback_anchor_unix)
	var result: Dictionary = _session.account_day_income(now_unix)
	if _session.export_state() == before:
		_refresh_product_surface()
		return true
	if _save_progress("주간 방치 수입 반영", false) != OK:
		_restore_product_state(before, "주간 방치 수입 저장 실패")
		_refresh_product_surface()
		return false
	_refresh_product_surface()
	if (
		show_report
		and int(result.get("awarded_bits", 0)) > 0
		and _product_day_view != null
	):
		_product_day_view.show_offline_handoff(result)
	return true


func _apply_offline_progress(baseline_unix: int) -> void:
	if _session == null:
		return
	if _combat_v2_test_mode:
		push_error("Combat V2 test mode does not support offline progression.")
		return
	var now_unix := _now_unix()
	var raw_elapsed := maxi(0, now_unix - baseline_unix)
	var applied_seconds := mini(raw_elapsed, POLICY.OFFLINE_CAP_SECONDS)
	var reached_cap := raw_elapsed > POLICY.OFFLINE_CAP_SECONDS
	var before: Dictionary = _session.snapshot()
	var remaining := float(applied_seconds)
	while remaining > 0.0:
		var step := minf(remaining, POLICY.OFFLINE_TICK_CHUNK_SECONDS)
		_session.tick(step)
		remaining -= step
	var after: Dictionary = _session.snapshot()
	var stage_changed := int(after["stage"]) != int(before["stage"])
	var mode_changed := String(after["mode"]) != String(before["mode"])
	var recovered_bits := maxf(0.0, float(after["bits"]) - float(before["bits"]))
	var visible_progress := recovered_bits > 0.000001 or stage_changed or mode_changed
	var should_report := visible_progress and (
		raw_elapsed >= POLICY.OFFLINE_REPORT_THRESHOLD_SECONDS
		or stage_changed
		or mode_changed
		or reached_cap
	)
	var previous_pending := _pending_offline_report.duplicate(true)
	var next_report: Dictionary = {}
	if should_report:
		var diagnosis := after.get("diagnosis", {}) as Dictionary
		var severity := String(diagnosis.get("severity", "info"))
		var has_bottleneck := severity in ["warning", "critical"]
		next_report = {
			"absence_seconds": raw_elapsed,
			"recovered_bits": recovered_bits,
			"stage_from": int(before["stage"]),
			"stage_to": int(after["stage"]),
			"has_bottleneck": has_bottleneck,
			"bottleneck_stage": int(after["stage"]) if has_bottleneck else 0,
			"bottleneck_cause": String(diagnosis.get("evidence", "")) if has_bottleneck else "",
			"reached_cap": reached_cap,
		}
	_pending_offline_report = _merge_offline_reports(previous_pending, next_report)
	var save_error := _save_progress("오프라인 진행 반영", false)
	if save_error == OK and not _pending_offline_report.is_empty():
		_show_offline_report()


func _merge_offline_reports(previous: Dictionary, current: Dictionary) -> Dictionary:
	if previous.is_empty():
		return current
	if current.is_empty():
		return previous
	var current_has_bottleneck := bool(current["has_bottleneck"])
	return {
		"absence_seconds": int(previous["absence_seconds"]) + int(current["absence_seconds"]),
		"recovered_bits": float(previous["recovered_bits"]) + float(current["recovered_bits"]),
		"stage_from": int(previous["stage_from"]),
		"stage_to": int(current["stage_to"]),
		"has_bottleneck": current_has_bottleneck or bool(previous["has_bottleneck"]),
		"bottleneck_stage": (
			int(current["bottleneck_stage"])
			if current_has_bottleneck
			else int(previous["bottleneck_stage"])
		),
		"bottleneck_cause": (
			String(current["bottleneck_cause"])
			if current_has_bottleneck
			else String(previous["bottleneck_cause"])
		),
		"reached_cap": bool(previous["reached_cap"]) or bool(current["reached_cap"]),
	}


func _save_progress(reason: String, reveal_pending_report: bool = true) -> Error:
	if _session == null:
		return ERR_UNCONFIGURED
	var saved_at := maxi(_last_saved_at_unix, _now_unix())
	var save_error: Error = _active_save_repository().save(
		_session.export_state(),
		saved_at,
		_last_gameplay_tab
	)
	if save_error != OK:
		_save_has_error = true
		_save_status = "저장되지 않음 · %s (오류 %d)" % [reason, save_error]
		_refresh_save_status_views()
		return save_error
	_last_saved_at_unix = saved_at
	_save_has_error = false
	_save_status = "방금 저장됨 · %s" % reason
	_refresh_save_status_views()
	if reveal_pending_report and not _pending_offline_report.is_empty():
		_show_offline_report()
	return OK


func _refresh_save_status_views() -> void:
	_refresh_operations_room()
	_refresh_settings_view()
	if not _combat_v2_test_mode:
		_refresh_product_surface()
	if _screen_id == SCREEN_GAMEPLAY and _gameplay_view != null:
		_gameplay_view.set_save_warning(_save_status if _save_has_error else "")


func _capture_gameplay_tab() -> void:
	if _gameplay_view == null:
		return
	_last_gameplay_tab = clampi(
		_gameplay_view.get_active_tab(), POLICY.GAMEPLAY_TAB_MIN, POLICY.GAMEPLAY_TAB_MAX
	)


func _make_session() -> Variant:
	if _combat_v2_test_mode:
		return CombatV2IntegrationSession.new()
	return PRODUCT_LOOP_SESSION_SCRIPT.new()


func _active_save_repository() -> Variant:
	if _combat_v2_test_mode:
		assert(
			_combat_v2_save_repository != null,
			"Combat V2 test mode requires its isolated save repository."
		)
		return _combat_v2_save_repository
	assert(_save_repository != null, "Production mode requires the production save repository.")
	return _save_repository


func _launch_option_enabled() -> bool:
	return OS.get_cmdline_args().has(COMBAT_V2_LAUNCH_OPTION) or (
		OS.get_cmdline_user_args().has(COMBAT_V2_LAUNCH_OPTION)
	)


func _sync_audio() -> void:
	if _session == null or _audio_director == null:
		return
	var next_snapshot: Dictionary = _session.snapshot()
	_capture_field_report(next_snapshot)
	_audio_director.sync_snapshot(_audio_snapshot, next_snapshot)
	_audio_snapshot = next_snapshot


func _capture_field_report(snapshot: Dictionary) -> void:
	var raw_appeals: Variant = snapshot.get("appeals", [])
	if not (raw_appeals is Array) or (raw_appeals as Array).is_empty():
		return
	var is_v2 := bool(snapshot.get("combat_v2_test_mode", false))
	var report_rows: Array = []
	if is_v2:
		for raw_appeal: Variant in raw_appeals as Array:
			var appeal := raw_appeal as Dictionary
			if String(appeal.get("trigger", "")) in ["normal_failure", "boss_failure"]:
				report_rows.append(appeal.duplicate(true))
	else:
		if String(snapshot.get("mode", "")) != "maintenance":
			return
		report_rows = (raw_appeals as Array).duplicate(true)
	if report_rows.is_empty():
		return
	var failure_count := int(
		snapshot.get("failure_count", 0)
		if is_v2
		else snapshot.get("boss_failure_count", 0)
	)
	if failure_count <= 0:
		return
	var report_key := "%s:%d:%d" % [
		"v2" if is_v2 else "production",
		int(snapshot.get("run_count", 0)),
		failure_count,
	]
	if report_key == _field_report_key:
		return
	_field_report_key = report_key
	_field_report_rows = report_rows
	_field_report_is_v2 = is_v2
	_push_field_report_state_to_gameplay()


func _push_field_report_state_to_gameplay() -> void:
	if _gameplay_view == null:
		return
	if not _gameplay_view.set_field_report_state(field_report_state()):
		push_error("Gameplay view rejected an updated field report state.")


func _reset_field_report_state() -> void:
	_field_report_key = ""
	_field_report_read_key = ""
	_field_report_rows.clear()
	_field_report_is_v2 = false
	_push_field_report_state_to_gameplay()


func _load_settings() -> void:
	var load_result := _settings_repository.load()
	match load_result.status:
		SettingsRepository.LoadStatus.NOT_FOUND:
			_settings = AppSettings.new()
			var create_error := _settings_repository.create_defaults()
			if create_error != OK:
				_settings_has_error = true
				_settings_status = "기본 설정 저장 실패 (오류 %d)" % create_error
			else:
				_settings_status = "기본 설정 저장됨"
		SettingsRepository.LoadStatus.LOADED:
			_settings = load_result.settings
			_settings_status = "설정 저장 정상"
		SettingsRepository.LoadStatus.CORRUPT:
			_settings = AppSettings.new()
			_settings_has_error = true
			_settings_status = "설정 파일 손상 · 원본을 덮어쓰지 않음"
		SettingsRepository.LoadStatus.NEWER_SCHEMA:
			_settings = AppSettings.new()
			_settings_has_error = true
			_settings_status = "더 새로운 설정 파일 · 게임 업데이트 필요"
		_:
			_settings = AppSettings.new()
			_settings_has_error = true
			_settings_status = "알 수 없는 설정 로드 상태"


func _save_settings(reason: String) -> Error:
	var save_error := _settings_repository.save(_settings)
	if save_error != OK:
		_settings_has_error = true
		_settings_status = "%s 저장 실패 (오류 %d)" % [reason, save_error]
		_refresh_settings_view()
		return save_error
	_settings_has_error = false
	_settings_status = "%s 저장됨" % reason
	_refresh_settings_view()
	return OK


func _apply_audio_settings() -> void:
	_audio_director.set_music_enabled(true)
	_audio_director.set_sfx_enabled(true)
	_audio_director.set_music_volume_percent(int(round(_settings.music_volume * 100.0)))
	_audio_director.set_sfx_volume_percent(int(round(_settings.sfx_volume * 100.0)))


func _settings_view_data() -> Dictionary:
	return {
		"music_volume_percent": int(round(_settings.music_volume * 100.0)),
		"sfx_volume_percent": int(round(_settings.sfx_volume * 100.0)),
		"vibration_enabled": _settings.vibration_enabled,
		"screen_shake_enabled": _settings.screen_shake_enabled,
		"reduced_flashes": _settings.reduced_flashing,
		"reduced_motion": _settings.reduced_motion,
	}


func _combined_save_status() -> String:
	if _save_has_error and _settings_has_error:
		return "%s · %s" % [_save_status, _settings_status]
	if _save_has_error:
		return _save_status
	if _settings_has_error:
		return _settings_status
	return "%s · %s" % [_save_status, _settings_status]


func _refresh_settings_view() -> void:
	if _overlay_id != OVERLAY_SETTINGS or _overlay_host.get_child_count() == 0:
		return
	var view := _overlay_host.get_child(0) as AppShellSettingsView
	if view != null:
		view.configure(
			_settings_view_data(),
			_combined_save_status(),
			_save_has_error or _settings_has_error,
			_is_vibration_supported()
		)
		view.set_manual_available(_session != null and _combat_v2_test_mode)


func _is_vibration_supported() -> bool:
	return OS.get_name() == "Android"


func _update_safe_area() -> void:
	if OS.get_name() in ["Android", "iOS"]:
		_apply_safe_area(DisplayServer.get_display_safe_area(), get_window().size)
	else:
		_apply_safe_area(Rect2i(Vector2i.ZERO, get_window().size), get_window().size)


func _apply_safe_area(safe_rect: Rect2i, window_size: Vector2i) -> void:
	if _safe_margin == null:
		return
	if window_size.x <= 0 or window_size.y <= 0 or safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		UI.add_margins(_safe_margin, 0, 0, 0, 0)
		return
	var logical_per_pixel := maxf(
		UI.LOGICAL_SIZE.x / float(window_size.x),
		UI.LOGICAL_SIZE.y / float(window_size.y)
	)
	var logical_window_size := Vector2(window_size) * logical_per_pixel
	var safe_end := safe_rect.position + safe_rect.size
	var left := maxi(0, int(round(float(safe_rect.position.x) * logical_per_pixel)))
	var top := maxi(0, int(round(float(safe_rect.position.y) * logical_per_pixel)))
	var right := maxi(
		0,
		int(round(float(window_size.x - safe_end.x) * logical_per_pixel))
	)
	var bottom := maxi(
		0,
		int(round(float(window_size.y - safe_end.y) * logical_per_pixel))
	)
	var safe_logical_width := maxf(
		0.0,
		logical_window_size.x - float(left + right)
	)
	var centered_stage_margin := maxi(
		0,
		int(round((safe_logical_width - UI.LOGICAL_SIZE.x) * 0.5))
	)
	left = mini(left + centered_stage_margin, int(logical_window_size.x / 2.0))
	right = mini(right + centered_stage_margin, int(logical_window_size.x / 2.0))
	top = mini(top, int(logical_window_size.y / 2.0))
	bottom = mini(bottom, int(logical_window_size.y / 2.0))
	UI.add_margins(_safe_margin, left, right, top, bottom)


func _now_unix() -> int:
	var value: Variant = _clock.call("now_unix")
	assert(typeof(value) == TYPE_INT, "Clock now_unix() must return an int.")
	return int(value)
