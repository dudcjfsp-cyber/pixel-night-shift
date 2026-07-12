class_name OperatorUpgradeEffect
extends Control

const DURATION_SECONDS := 0.65
const COLOR_CYAN := Color("52d6c8")
const COLOR_TEXT := Color("edf4ff")
const COLOR_BUBBLE := Color("0b1119e8")
const SPARK_DIRECTIONS: Array[Vector2] = [
	Vector2(-0.85, -0.55),
	Vector2(-0.45, -1.0),
	Vector2(0.25, -1.0),
	Vector2(0.85, -0.55),
	Vector2(-0.75, 0.65),
	Vector2(0.75, 0.65),
]

var _panel: PanelContainer
var _portrait: TextureRect
var _normal_panel_style: StyleBox
var _time_left := 0.0
var _message := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false


func configure(panel: PanelContainer, portrait: TextureRect) -> void:
	_panel = panel
	_portrait = portrait
	_normal_panel_style = panel.get_theme_stylebox("panel").duplicate() as StyleBox
	assert(
		_normal_panel_style is StyleBoxFlat,
		"OperatorUpgradeEffect requires a StyleBoxFlat panel style."
	)


func play(dps_delta: float) -> void:
	assert(is_instance_valid(_panel), "OperatorUpgradeEffect requires a configured panel.")
	assert(is_instance_valid(_portrait), "OperatorUpgradeEffect requires a configured portrait.")
	assert(_normal_panel_style != null, "OperatorUpgradeEffect requires a normal panel style.")

	_time_left = DURATION_SECONDS
	_message = "LEVEL UP  ·  DPS +%s" % _format_number(maxf(0.0, dps_delta))
	visible = true
	set_process(true)
	_portrait.pivot_offset = Vector2(_portrait.size.x * 0.5, _portrait.size.y)
	_apply_highlight_style()
	queue_redraw()


func _process(delta_seconds: float) -> void:
	_time_left = maxf(0.0, _time_left - delta_seconds)
	var progress := clampf(1.0 - (_time_left / DURATION_SECONDS), 0.0, 1.0)
	var pulse := sin(progress * PI)
	_portrait.scale = Vector2.ONE * (1.0 + pulse * 0.16)
	_portrait.modulate = Color.WHITE.lerp(COLOR_CYAN, pulse * 0.8)
	queue_redraw()

	if _time_left > 0.0:
		return
	_finish()


func _draw() -> void:
	if _time_left <= 0.0:
		return
	var progress := clampf(1.0 - (_time_left / DURATION_SECONDS), 0.0, 1.0)
	var fade := minf(1.0, _time_left / 0.18)
	var origin := Vector2(26.0, 25.0)
	for direction: Vector2 in SPARK_DIRECTIONS:
		var spark_position := origin + direction * (7.0 + progress * 18.0)
		var spark_color := COLOR_CYAN
		spark_color.a = fade
		draw_rect(Rect2(spark_position.floor(), Vector2(3.0, 3.0)), spark_color)

	var bubble_width := clampf(size.x - 150.0, 108.0, 176.0)
	var bubble_y := 5.0 - progress * 3.0
	var bubble_color := COLOR_BUBBLE
	bubble_color.a *= fade
	draw_rect(Rect2(48.0, bubble_y, bubble_width, 22.0), bubble_color)
	var text_color := COLOR_TEXT
	text_color.a = fade
	draw_string(
		get_theme_default_font(),
		Vector2(54.0, bubble_y + 15.0),
		_message,
		HORIZONTAL_ALIGNMENT_LEFT,
		bubble_width - 10.0,
		9,
		text_color
	)


func _apply_highlight_style() -> void:
	var highlight := _normal_panel_style.duplicate() as StyleBoxFlat
	highlight.bg_color = Color("153d43")
	highlight.border_color = COLOR_CYAN
	highlight.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", highlight)


func _finish() -> void:
	_portrait.scale = Vector2.ONE
	_portrait.modulate = Color.WHITE
	_panel.add_theme_stylebox_override("panel", _normal_panel_style)
	visible = false
	set_process(false)
	queue_redraw()


func _format_number(value: float) -> String:
	if value >= 1_000_000.0:
		return "%.2fM" % (value / 1_000_000.0)
	if value >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
