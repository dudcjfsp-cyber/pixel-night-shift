class_name PresentationAssets
extends RefCounted

const OPERATOR_TEXTURES: Dictionary = {
	&"debugger": preload("res://game/assets/generated/operators/debugger.png"),
	&"build_engineer": preload("res://game/assets/generated/operators/build_engineer.png"),
	&"sprite_artist": preload("res://game/assets/generated/operators/sprite_artist.png"),
	&"qa_imp": preload("res://game/assets/generated/operators/qa_imp.png"),
}

const PATCH_TEXTURES: Dictionary = {
	&"frame_skip": preload("res://game/assets/generated/patches/frame_skip.png"),
	&"unsafe_build": preload("res://game/assets/generated/patches/unsafe_build.png"),
	&"reward_bypass": preload("res://game/assets/generated/patches/reward_bypass.png"),
	&"rollback_lock": preload("res://game/assets/generated/patches/rollback_lock.png"),
	&"safe_mode": preload("res://game/assets/generated/patches/safe_mode.png"),
}

const ENEMY_TEXTURES: Dictionary = {
	&"broken_pixel": preload("res://game/assets/generated/enemies/broken_pixel.png"),
	&"infinite_loop": preload("res://game/assets/generated/enemies/infinite_loop.png"),
	&"missing_resource": preload("res://game/assets/generated/enemies/missing_resource.png"),
	&"maintenance_error": preload("res://game/assets/generated/enemies/maintenance_error.png"),
	&"watchdog_process": preload("res://game/assets/generated/enemies/watchdog_process.png"),
}

const UI_TEXTURES: Dictionary = {
	&"bit": preload("res://game/assets/generated/ui/bit.png"),
	&"patch_note": preload("res://game/assets/generated/ui/patch_note.png"),
	&"stage": preload("res://game/assets/generated/ui/stage.png"),
	&"diagnosis": preload("res://game/assets/generated/ui/diagnosis.png"),
	&"combat": preload("res://game/assets/generated/ui/combat.png"),
	&"boss": preload("res://game/assets/generated/ui/boss.png"),
	&"maintenance": preload("res://game/assets/generated/ui/maintenance.png"),
	&"complete": preload("res://game/assets/generated/ui/complete.png"),
}

const BATTLE_BACKGROUND: Texture2D = preload(
	"res://game/assets/generated/backgrounds/battle_server_room.png"
)


static func operator_texture(operator_id: StringName) -> Texture2D:
	return OPERATOR_TEXTURES[operator_id] as Texture2D


static func patch_texture(patch_id: StringName) -> Texture2D:
	return PATCH_TEXTURES[patch_id] as Texture2D


static func ui_texture(icon_id: StringName) -> Texture2D:
	return UI_TEXTURES[icon_id] as Texture2D


static func enemy_texture(stage: int, is_boss: bool, mode: String) -> Texture2D:
	if is_boss:
		return ENEMY_TEXTURES[&"watchdog_process"] as Texture2D
	if mode == "maintenance":
		return ENEMY_TEXTURES[&"maintenance_error"] as Texture2D
	var normal_ids: Array[StringName] = [
		&"broken_pixel",
		&"infinite_loop",
		&"missing_resource",
	]
	var enemy_id: StringName = normal_ids[posmod(stage - 1, normal_ids.size())]
	return ENEMY_TEXTURES[enemy_id] as Texture2D


static func mode_texture(mode: String) -> Texture2D:
	var mode_id: StringName = StringName(mode)
	assert(UI_TEXTURES.has(mode_id), "Unknown presentation mode: %s" % mode)
	return UI_TEXTURES[mode_id] as Texture2D
