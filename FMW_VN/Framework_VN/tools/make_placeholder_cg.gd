extends SceneTree

## Writes the placeholder CG pictures the demo's gallery collects:
##
##     godot --headless --path . --script res://Framework_VN/tools/make_placeholder_cg.gd
##     godot --headless --path . --import
##
## Every one is a flat gradient with a couple of shapes - a rooftop at sunset, a
## classroom after the bell - so the gallery has something to show before you
## bring in real CG art. Plain, small pictures on purpose, like the flat coloured
## placeholder backgrounds. Replace them under the same names and the demo keeps
## working, or point the story's `assets.cg` aliases at your own files.
##
## Nothing here reads the story: the file names are the ones data/story.json
## points at.

const OUT_DIR := "res://VN/assets/cg"
const WIDTH := 1920
const HEIGHT := 1080
## Gradients are painted this small and scaled up, which smooths them and keeps
## the per-pixel loops to something GDScript finishes in a moment.
const SKETCH_WIDTH := 320
const SKETCH_HEIGHT := 180


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_write("cg_classroom.png", _classroom())
	_write("cg_rooftop.png", _rooftop())
	_write("cg_worth_it.png", _worth_it())
	_write("cg_rain.png", _rain())
	print("wrote 4 CGs to %s" % OUT_DIR)
	print("now run: godot --headless --path . --import")
	quit(0)


## The classroom after the bell: dusk light through the windows, desks in front.
func _classroom() -> Image:
	var image := _sky(Color("#2b3450"), Color("#101522"))
	for column in 3:
		var x := 210 + column * 540
		image.fill_rect(Rect2i(x, 250, 380, 460), Color("#f0b978"))
		for pane in 3:
			image.fill_rect(Rect2i(x, 250 + pane * 154, 380, 10), Color("#2b3450"))
		image.fill_rect(Rect2i(x + 184, 250, 12, 460), Color("#2b3450"))
	for desk in 5:
		var x := 90 + desk * 370
		image.fill_rect(Rect2i(x, 860, 300, 30), Color("#1b2033"))
		image.fill_rect(Rect2i(x + 130, 890, 40, 120), Color("#1b2033"))
	return image


## The rooftop at sunset: the sky chapter two is about, over a dark city.
func _rooftop() -> Image:
	var image := _sky(Color("#3a2b63"), Color("#f0a05a"))
	_disc(image, Vector2(1420, 620), 150, Color("#ffd39a"))
	for tower in 9:
		var x := 40 + tower * 215
		var height := 120 + (tower * 97) % 260
		image.fill_rect(Rect2i(x, 900 - height, 150, height), Color("#20182f"))
	image.fill_rect(Rect2i(0, 918, WIDTH, 14), Color("#3b2f55"))
	image.fill_rect(Rect2i(0, 930, WIDTH, HEIGHT - 930), Color("#150f24"))
	return image


## Worth it: the same sky closer up, with the light nearly gone.
func _worth_it() -> Image:
	var image := _sky(Color("#101026"), Color("#e07a4e"))
	_disc(image, Vector2(960, 700), 260, Color("#ffe0b0"))
	for band in 5:
		_rect(image, Rect2i(120 + band * 130, 300 + band * 80, 1500 - band * 220, 26), Color(1.0, 0.9, 0.8, 0.22))
	image.fill_rect(Rect2i(0, 980, WIDTH, 100), Color("#0d0a1a"))
	return image


## An umbrella, anyway: the other ending, in the rain.
func _rain() -> Image:
	var image := _sky(Color("#232c44"), Color("#0d1220"))
	for drop in 150:
		var x := (drop * 137) % WIDTH
		var y := (drop * 331) % (HEIGHT + 300) - 150
		_streak(image, Vector2(x, y), Vector2(x - 26, y + 120), Color(0.75, 0.82, 1.0, 0.32), 3)
	_disc(image, Vector2(960, 520), 190, Color(0.9, 0.94, 1.0, 0.12))
	image.fill_rect(Rect2i(0, 1010, WIDTH, 70), Color("#0a0e18"))
	return image


# --- painting ----------------------------------------------------------------

## A sky: a vertical gradient, painted small and scaled up so it comes out
## smooth instead of banded.
func _sky(top: Color, bottom: Color) -> Image:
	var small := Image.create_empty(SKETCH_WIDTH, SKETCH_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in SKETCH_HEIGHT:
		var color := top.lerp(bottom, float(y) / float(SKETCH_HEIGHT - 1))
		for x in SKETCH_WIDTH:
			small.set_pixel(x, y, color)
	small.resize(WIDTH, HEIGHT, Image.INTERPOLATE_CUBIC)
	return small


## A filled circle, mixed into what is under it rather than punched through, so
## a translucent sun still leaves an opaque picture.
func _disc(image: Image, centre: Vector2, radius: float, color: Color) -> void:
	var r2 := radius * radius
	for y in range(maxi(0, int(centre.y - radius)), mini(HEIGHT, int(centre.y + radius) + 1)):
		for x in range(maxi(0, int(centre.x - radius)), mini(WIDTH, int(centre.x + radius) + 1)):
			var dx := x - centre.x
			var dy := y - centre.y
			if dx * dx + dy * dy <= r2:
				_blend(image, x, y, color)


func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(maxi(0, rect.position.y), mini(HEIGHT, rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(WIDTH, rect.end.x)):
			_blend(image, x, y, color)


## A line, pixel by pixel - enough for a rain streak.
func _streak(image: Image, from: Vector2, to: Vector2, color: Color, thickness: int = 1) -> void:
	var steps := maxi(int(maxf(absf(to.x - from.x), absf(to.y - from.y))) + 1, 2)
	for i in steps:
		var point := from.lerp(to, float(i) / float(steps - 1))
		for dy in thickness:
			for dx in thickness:
				_blend(image, int(point.x) + dx, int(point.y) + dy, color)


## Paints over a pixel, mixing with what is already there. The pictures come out
## fully opaque, so a CG never shows the menu through itself.
func _blend(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return
	var under := image.get_pixel(x, y)
	image.set_pixel(x, y, under.lerp(Color(color.r, color.g, color.b, under.a), color.a))


func _write(name: String, image: Image) -> void:
	var path := OUT_DIR.path_join(name)
	var error := image.save_png(path)
	if error != OK:
		push_error("could not write %s (%s)" % [path, error_string(error)])
		return
	print("  %s  (%d x %d)" % [path, image.get_width(), image.get_height()])
