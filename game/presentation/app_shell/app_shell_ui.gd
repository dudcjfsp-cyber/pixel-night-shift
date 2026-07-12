class_name AppShellUI
extends RefCounted

const LOGICAL_SIZE := Vector2(360.0, 640.0)

const COLOR_DEEP := Color("050914")
const COLOR_BACKGROUND := Color("10151f")
const COLOR_PANEL := Color("182232")
const COLOR_PANEL_RAISED := Color("213047")
const COLOR_PANEL_INFO := Color("15383b")
const COLOR_PANEL_SAFE := Color("18302d")
const COLOR_BORDER := Color("40526c")
const COLOR_TEXT := Color("edf4ff")
const COLOR_MUTED := Color("9dafc7")
const COLOR_INFO := Color("52d6c8")
const COLOR_SAFE := Color("7be495")
const COLOR_WARNING := Color("f4c95d")
const COLOR_DANGER := Color("ff6b72")
const COLOR_SPECIAL := Color("8a78e6")
const COLOR_DEV := Color("f06adf")
const COLOR_DEV_PANEL := Color("1d1020")
const COLOR_MODAL_SHADE := Color(0.01, 0.02, 0.05, 0.84)

const CONTENT_MARGIN := 8
const GAP_SMALL := 4
const GAP_MEDIUM := 8
const GAP_LARGE := 12
const TOUCH_MIN := 48
const PRIMARY_HEIGHT := 52
const BODY_SIZE := 12
const SUPPORT_SIZE := 10
const TITLE_SIZE := 20


static func attach_screen_frame(owner: Control, separation: int = GAP_MEDIUM) -> VBoxContainer:
	owner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var background := ColorRect.new()
	background.name = "ScreenBackground"
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe_margin := MarginContainer.new()
	safe_margin.name = "SafeContent"
	add_margins(
		safe_margin,
		CONTENT_MARGIN,
		CONTENT_MARGIN,
		CONTENT_MARGIN,
		CONTENT_MARGIN
	)
	owner.add_child(safe_margin)
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.name = "ScreenColumn"
	column.add_theme_constant_override("separation", separation)
	safe_margin.add_child(column)
	return column


static func attach_scrollable_screen_frame(
	owner: Control,
	separation: int = GAP_MEDIUM
) -> VBoxContainer:
	owner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var background := ColorRect.new()
	background.name = "ScreenBackground"
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe_margin := MarginContainer.new()
	safe_margin.name = "SafeContent"
	add_margins(safe_margin, CONTENT_MARGIN, CONTENT_MARGIN, CONTENT_MARGIN, CONTENT_MARGIN)
	owner.add_child(safe_margin)
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var scroll := ScrollContainer.new()
	scroll.name = "ScreenScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe_margin.add_child(scroll)

	var column := VBoxContainer.new()
	column.name = "ScreenColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", separation)
	scroll.add_child(column)
	return column


static func make_label(
	text_value: String,
	font_size: int = BODY_SIZE,
	text_color: Color = COLOR_TEXT,
	wrap: bool = false
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


static func make_button(
	text_value: String,
	role: StringName = &"secondary",
	minimum_height: int = TOUCH_MIN
) -> Button:
	var palette := _button_palette(role)
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(TOUCH_MIN, minimum_height)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", BODY_SIZE)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color("66758a"))
	button.add_theme_stylebox_override(
		"normal", make_style(palette["normal"], palette["border"], int(palette["width"]), 4, 6)
	)
	button.add_theme_stylebox_override(
		"hover", make_style(palette["hover"], palette["accent"], 2, 4, 6)
	)
	button.add_theme_stylebox_override(
		"pressed", make_style(palette["pressed"], palette["accent"], 2, 4, 6)
	)
	button.add_theme_stylebox_override(
		"focus", make_style(palette["normal"], palette["accent"], 2, 4, 6)
	)
	button.add_theme_stylebox_override(
		"disabled", make_style(Color("161d28"), Color("293545"), 1, 4, 6)
	)
	return button


static func make_panel(
	background_color: Color = COLOR_PANEL,
	border_color: Color = COLOR_BORDER,
	border_width: int = 1,
	padding: int = CONTENT_MARGIN
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", make_style(background_color, border_color, border_width, 4, padding)
	)
	return panel


static func make_style(
	background_color: Color,
	border_color: Color,
	border_width: int,
	corner_radius: int = 4,
	padding: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.content_margin_left = float(padding)
	style.content_margin_right = float(padding)
	style.content_margin_top = float(padding)
	style.content_margin_bottom = float(padding)
	return style


static func make_value_row(
	caption: String,
	value: String,
	value_color: Color = COLOR_TEXT
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 24.0
	row.add_theme_constant_override("separation", GAP_MEDIUM)
	var caption_label := make_label(caption, SUPPORT_SIZE, COLOR_MUTED)
	caption_label.custom_minimum_size.x = 92.0
	row.add_child(caption_label)
	var value_label := make_label(value, BODY_SIZE, value_color)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	return row


static func make_spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


static func make_rule(color: Color = COLOR_BORDER) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


static func add_margins(
	container: MarginContainer,
	left: int,
	right: int,
	top: int,
	bottom: int
) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_bottom", bottom)


static func format_compact_number(value: float) -> String:
	var absolute := absf(value)
	if absolute >= 1_000_000_000.0:
		return "%.2fB" % (value / 1_000_000_000.0)
	if absolute >= 1_000_000.0:
		return "%.2fM" % (value / 1_000_000.0)
	if absolute >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


static func format_duration(total_seconds: int) -> String:
	assert(total_seconds >= 0, "Duration cannot be negative.")
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	if hours > 0:
		return "%d시간 %d분" % [hours, minutes]
	if minutes > 0:
		return "%d분 %d초" % [minutes, seconds]
	return "%d초" % seconds


static func _button_palette(role: StringName) -> Dictionary:
	match role:
		&"primary":
			return {
				"normal": COLOR_PANEL_INFO,
				"hover": Color("1b4a4e"),
				"pressed": Color("102d30"),
				"border": COLOR_INFO,
				"accent": COLOR_INFO,
				"width": 2,
			}
		&"danger":
			return {
				"normal": Color("3a2028"),
				"hover": Color("502832"),
				"pressed": Color("2c1820"),
				"border": COLOR_DANGER,
				"accent": COLOR_DANGER,
				"width": 2,
			}
		&"quiet":
			return {
				"normal": COLOR_BACKGROUND,
				"hover": COLOR_PANEL_RAISED,
				"pressed": COLOR_PANEL,
				"border": COLOR_BORDER,
				"accent": COLOR_INFO,
				"width": 1,
			}
		&"dev":
			return {
				"normal": Color("32182f"),
				"hover": Color("482044"),
				"pressed": Color("251222"),
				"border": COLOR_DEV,
				"accent": COLOR_DEV,
				"width": 2,
			}
		&"secondary":
			return {
				"normal": COLOR_PANEL_RAISED,
				"hover": Color("2b405c"),
				"pressed": Color("183f44"),
				"border": COLOR_BORDER,
				"accent": COLOR_INFO,
				"width": 1,
			}
		_:
			assert(false, "Unknown app-shell button role: %s" % role)
			return {}
