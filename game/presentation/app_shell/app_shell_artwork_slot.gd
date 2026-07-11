class_name AppShellArtworkSlot
extends Control

const UI: GDScript = preload("res://game/presentation/app_shell/app_shell_ui.gd")

const FIRST_SHIFT: StringName = &"first_shift"
const OPERATIONS_ROOM: StringName = &"operations_room"

var _fallback_kind: StringName = FIRST_SHIFT
var _artwork: Texture2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	queue_redraw()


func set_fallback_kind(kind: StringName) -> void:
	if kind not in [FIRST_SHIFT, OPERATIONS_ROOM]:
		push_error("Unknown app-shell artwork kind: %s" % kind)
		return
	_fallback_kind = kind
	queue_redraw()


func set_artwork(texture: Texture2D) -> void:
	_artwork = texture
	queue_redraw()


func artwork_display_rect() -> Rect2:
	if _artwork == null:
		return Rect2()
	return integer_fit_rect(_artwork.get_size(), size)


static func integer_fit_rect(source_size: Vector2, destination_size: Vector2) -> Rect2:
	assert(source_size.x > 0.0 and source_size.y > 0.0, "Artwork source size must be positive.")
	assert(
		destination_size.x > 0.0 and destination_size.y > 0.0,
		"Artwork destination size must be positive."
	)
	var available_scale := minf(
		destination_size.x / source_size.x,
		destination_size.y / source_size.y
	)
	var integer_scale := maxi(1, int(floorf(available_scale)))
	var target_size := (source_size * float(integer_scale)).floor()
	var target_position := ((destination_size - target_size) * 0.5).floor()
	return Rect2(target_position, target_size)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.COLOR_DEEP, true)
	if _artwork != null:
		draw_texture_rect(_artwork, artwork_display_rect(), false)
		draw_rect(Rect2(Vector2.ZERO, size), UI.COLOR_BORDER, false, 1.0)
		return

	_draw_grid()
	if _fallback_kind == OPERATIONS_ROOM:
		_draw_operations_room()
	else:
		_draw_first_shift()
	draw_rect(Rect2(Vector2.ZERO, size), UI.COLOR_BORDER, false, 1.0)


func _draw_grid() -> void:
	var grid_color := Color(UI.COLOR_BORDER, 0.22)
	for x: int in range(0, int(size.x), 16):
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0, false)
	for y: int in range(0, int(size.y), 16):
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0, false)


func _draw_first_shift() -> void:
	var center_x := floorf(size.x * 0.5)
	var server_rect := Rect2(center_x - 50.0, 22.0, 100.0, 78.0)
	draw_rect(server_rect, UI.COLOR_PANEL, true)
	draw_rect(server_rect, UI.COLOR_INFO, false, 2.0)
	for row: int in range(4):
		var row_rect := Rect2(server_rect.position + Vector2(10.0, 9.0 + row * 16.0), Vector2(80.0, 9.0))
		draw_rect(row_rect, UI.COLOR_PANEL_RAISED, true)
		draw_rect(Rect2(row_rect.position + Vector2(6.0, 3.0), Vector2(3.0, 3.0)), UI.COLOR_SAFE, true)
		draw_rect(Rect2(row_rect.position + Vector2(14.0, 3.0), Vector2(3.0, 3.0)), UI.COLOR_INFO, true)

	var operator_colors: Array[Color] = [
		UI.COLOR_INFO, UI.COLOR_WARNING, UI.COLOR_SPECIAL, UI.COLOR_SAFE,
	]
	var base_y := size.y - 24.0
	var spacing := size.x / 5.0
	for index: int in range(4):
		var x := floorf(spacing * float(index + 1))
		var body := Rect2(x - 9.0, base_y - 30.0, 18.0, 24.0)
		draw_rect(body, UI.COLOR_PANEL_RAISED, true)
		draw_rect(body, operator_colors[index], false, 2.0)
		draw_rect(Rect2(x - 6.0, base_y - 39.0, 12.0, 10.0), operator_colors[index], true)
		draw_line(Vector2(x - 8.0, base_y), Vector2(x - 2.0, base_y - 6.0), operator_colors[index], 2.0, false)
		draw_line(Vector2(x + 8.0, base_y), Vector2(x + 2.0, base_y - 6.0), operator_colors[index], 2.0, false)


func _draw_operations_room() -> void:
	var rack_width := 72.0
	var rack_gap := 14.0
	var total_width := rack_width * 3.0 + rack_gap * 2.0
	var start_x := floorf((size.x - total_width) * 0.5)
	for rack_index: int in range(3):
		var rack_x := start_x + float(rack_index) * (rack_width + rack_gap)
		var rack := Rect2(rack_x, 22.0, rack_width, size.y - 44.0)
		draw_rect(rack, UI.COLOR_PANEL, true)
		draw_rect(rack, UI.COLOR_BORDER, false, 2.0)
		for unit_index: int in range(5):
			var unit := Rect2(rack_x + 8.0, 32.0 + unit_index * 27.0, rack_width - 16.0, 18.0)
			draw_rect(unit, UI.COLOR_PANEL_RAISED, true)
			var light_color := UI.COLOR_SAFE if (unit_index + rack_index) % 3 != 0 else UI.COLOR_WARNING
			draw_rect(Rect2(unit.position + Vector2(6.0, 6.0), Vector2(5.0, 5.0)), light_color, true)
			draw_line(
				unit.position + Vector2(18.0, 8.0),
				unit.position + Vector2(unit.size.x - 7.0, 8.0),
				Color(UI.COLOR_MUTED, 0.55),
				2.0,
				false
			)

	var console := Rect2(size.x * 0.5 - 54.0, size.y - 39.0, 108.0, 22.0)
	draw_rect(console, UI.COLOR_PANEL_INFO, true)
	draw_rect(console, UI.COLOR_INFO, false, 2.0)
	draw_line(console.position + Vector2(13.0, 11.0), console.position + Vector2(95.0, 11.0), UI.COLOR_INFO, 2.0, false)
