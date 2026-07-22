extends SceneTree

const SOURCE_ROOT := "res://.godot/opening-art-sources"
const OUTPUT_ROOT := "res://game/assets/opening"
const SOURCE_GAMMA := 0.82

const PALETTE: Array[Color] = [
	Color("050914"),
	Color("081124"),
	Color("0c1930"),
	Color("10213b"),
	Color("15304d"),
	Color("1a3c5b"),
	Color("214e6d"),
	Color("2d6280"),
	Color("9dafc7"),
	Color("edf4ff"),
	Color("31d2c9"),
	Color("1a8e99"),
	Color("ffb34d"),
	Color("b66b2d"),
	Color("df4d67"),
	Color("8a78e6"),
]

const SPECS: Array[Dictionary] = [
	{
		"source": SOURCE_ROOT + "/title_background_source.png",
		"output": OUTPUT_ROOT + "/title_background.png",
		"target_size": Vector2i(360, 640),
	},
	{
		"source": SOURCE_ROOT + "/city_network_source.png",
		"output": OUTPUT_ROOT + "/city_network.png",
		"target_size": Vector2i(344, 224),
	},
]


func _init() -> void:
	var output_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_ROOT)
	)
	if output_error not in [OK, ERR_ALREADY_EXISTS]:
		push_error("Unable to create opening art directory: %s" % error_string(output_error))
		quit(1)
		return

	for spec: Dictionary in SPECS:
		if not _prepare(spec):
			quit(1)
			return
	quit(0)


func _prepare(spec: Dictionary) -> bool:
	var source_path := String(spec["source"])
	var output_path := String(spec["output"])
	var target_size: Vector2i = spec["target_size"]
	var source := Image.load_from_file(source_path)
	if source == null or source.is_empty():
		push_error("Unable to load opening art source: %s" % source_path)
		return false
	source.convert(Image.FORMAT_RGB8)

	var prepared := _center_crop(source, target_size)
	var working_size := Vector2i(target_size.x / 2, target_size.y / 2)
	prepared.resize(working_size.x, working_size.y, Image.INTERPOLATE_LANCZOS)
	_quantize(prepared)
	prepared.resize(target_size.x, target_size.y, Image.INTERPOLATE_NEAREST)
	var save_error := prepared.save_png(output_path)
	if save_error != OK:
		push_error("Unable to save opening art '%s': %s" % [output_path, error_string(save_error)])
		return false
	print(
		"Prepared %s (%dx%d, sha256 %s)"
		% [
			output_path,
			target_size.x,
			target_size.y,
			FileAccess.get_sha256(ProjectSettings.globalize_path(output_path)),
		]
	)
	return true


func _center_crop(source: Image, target_size: Vector2i) -> Image:
	var source_size := source.get_size()
	var source_aspect := float(source_size.x) / float(source_size.y)
	var target_aspect := float(target_size.x) / float(target_size.y)
	var crop_size := source_size
	if source_aspect > target_aspect:
		crop_size.x = int(round(float(source_size.y) * target_aspect))
	else:
		crop_size.y = int(round(float(source_size.x) / target_aspect))
	var origin := Vector2i(
		(source_size.x - crop_size.x) / 2,
		(source_size.y - crop_size.y) / 2
	)
	return source.get_region(Rect2i(origin, crop_size))


func _quantize(image: Image) -> void:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var source_color := image.get_pixel(x, y)
			source_color = Color(
				pow(source_color.r, SOURCE_GAMMA),
				pow(source_color.g, SOURCE_GAMMA),
				pow(source_color.b, SOURCE_GAMMA)
			)
			var nearest := PALETTE[0]
			var nearest_distance := INF
			for candidate: Color in PALETTE:
				var red := source_color.r - candidate.r
				var green := source_color.g - candidate.g
				var blue := source_color.b - candidate.b
				var distance := red * red + green * green + blue * blue
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = candidate
			image.set_pixel(x, y, nearest)
