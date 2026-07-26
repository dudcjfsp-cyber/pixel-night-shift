class_name CombatEffectLayer
extends Control

signal impact(damage: float)

const PROJECTILE_DURATION := 0.18
const DAMAGE_NUMBER_DURATION := 0.62
const COLOR_DAMAGE := Color("fff1a8")
const COLOR_DAMAGE_REDUCED := Color("edf4ff")
const COLOR_OUTLINE := Color("10151f")


class ProjectileEffect extends RefCounted:
	var node: Control
	var start_position: Vector2
	var target_position: Vector2
	var damage: float
	var elapsed_seconds := 0.0
	var reduced_flashes := false


class DamageNumberEffect extends RefCounted:
	var label: Label
	var start_position: Vector2
	var elapsed_seconds := 0.0
	var moves := true


var _projectiles: Array[ProjectileEffect] = []
var _damage_numbers: Array[DamageNumberEffect] = []
var _effect_serial := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func play_attack(
	start_position: Vector2,
	target_position: Vector2,
	damage: float,
	accent: Color,
	reduced_motion: bool,
	reduced_flashes: bool
) -> bool:
	if damage <= 0.0 or not is_finite(damage):
		push_error("CombatEffectLayer damage must be a positive finite value.")
		return false
	if reduced_motion:
		_spawn_damage_number(target_position, damage, false, reduced_flashes)
		impact.emit(damage)
		return true

	_effect_serial += 1
	var projectile := Control.new()
	projectile.name = "CombatProjectile%d" % _effect_serial
	projectile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	projectile.size = Vector2(18.0, 9.0)
	projectile.pivot_offset = projectile.size * 0.5
	projectile.z_index = 20
	add_child(projectile)

	var visible_accent := accent if not reduced_flashes else COLOR_DAMAGE_REDUCED
	var trail := ColorRect.new()
	trail.color = Color(visible_accent, 0.42)
	trail.position = Vector2(0.0, 3.0)
	trail.size = Vector2(13.0, 3.0)
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	projectile.add_child(trail)
	var core := ColorRect.new()
	core.color = visible_accent
	core.position = Vector2(11.0, 1.0)
	core.size = Vector2(7.0, 7.0)
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	projectile.add_child(core)
	var highlight := ColorRect.new()
	highlight.color = Color.WHITE
	highlight.position = Vector2(13.0, 2.0)
	highlight.size = Vector2(3.0, 2.0)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	projectile.add_child(highlight)

	var effect := ProjectileEffect.new()
	effect.node = projectile
	effect.start_position = start_position
	effect.target_position = target_position
	effect.damage = damage
	effect.reduced_flashes = reduced_flashes
	_projectiles.append(effect)
	_apply_projectile_position(effect, 0.0)
	return true


func advance(delta_seconds: float) -> void:
	if delta_seconds < 0.0 or not is_finite(delta_seconds):
		push_error("CombatEffectLayer delta must be a non-negative finite value.")
		return
	for index: int in range(_projectiles.size() - 1, -1, -1):
		var projectile := _projectiles[index]
		projectile.elapsed_seconds += delta_seconds
		var progress := clampf(projectile.elapsed_seconds / PROJECTILE_DURATION, 0.0, 1.0)
		_apply_projectile_position(projectile, progress)
		if progress < 1.0:
			continue
		_spawn_damage_number(
			projectile.target_position,
			projectile.damage,
			true,
			projectile.reduced_flashes
		)
		impact.emit(projectile.damage)
		projectile.node.queue_free()
		_projectiles.remove_at(index)

	for index: int in range(_damage_numbers.size() - 1, -1, -1):
		var number := _damage_numbers[index]
		number.elapsed_seconds += delta_seconds
		var progress := clampf(number.elapsed_seconds / DAMAGE_NUMBER_DURATION, 0.0, 1.0)
		if number.moves:
			number.label.position = number.start_position + Vector2(0.0, -12.0 * progress)
		var label_color := number.label.modulate
		label_color.a = 1.0 - progress * progress
		number.label.modulate = label_color
		if progress < 1.0:
			continue
		number.label.queue_free()
		_damage_numbers.remove_at(index)


func clear() -> void:
	for projectile: ProjectileEffect in _projectiles:
		if is_instance_valid(projectile.node):
			projectile.node.queue_free()
	for number: DamageNumberEffect in _damage_numbers:
		if is_instance_valid(number.label):
			number.label.queue_free()
	_projectiles.clear()
	_damage_numbers.clear()


func _apply_projectile_position(effect: ProjectileEffect, progress: float) -> void:
	var arc := Vector2(0.0, -7.0 * sin(progress * PI))
	var center := effect.start_position.lerp(effect.target_position, progress) + arc
	effect.node.position = center - effect.node.size * 0.5
	effect.node.rotation = lerpf(-0.10, 0.10, progress)


func _spawn_damage_number(
	target_position: Vector2,
	damage: float,
	moves: bool,
	reduced_flashes: bool
) -> void:
	_effect_serial += 1
	var label := Label.new()
	label.name = "DamageNumber%d" % _effect_serial
	label.text = "-%s" % _format_number(damage)
	label.position = target_position + Vector2(-36.0, -29.0)
	label.size = Vector2(72.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 30
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override(
		"font_color", COLOR_DAMAGE_REDUCED if reduced_flashes else COLOR_DAMAGE
	)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)

	var effect := DamageNumberEffect.new()
	effect.label = label
	effect.start_position = label.position
	effect.moves = moves
	_damage_numbers.append(effect)


func _format_number(value: float) -> String:
	assert(is_finite(value), "Displayed damage values must be finite.")
	return str(int(floorf(value)))
