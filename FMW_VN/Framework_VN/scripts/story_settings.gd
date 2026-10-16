class_name StorySettings
extends RefCounted

## The player's own settings - how fast lines are read, how fast fast-forward
## goes, how long auto-forward holds a line, how loud the game is, and how the
## window is displayed.
##
## These are the player's, not the story's: a story says how fast its own lines
## *want* to be read ([code]text_speed[/code]), and the writing speeds here
## multiply that. Nothing in a story file can change what is in this one.
##
## Kept in a file of its own, in the user's data directory:
##
## [codeblock]
## {
##   "version": 1,
##   "writing_speed": 1.0,            # x every line's own text_speed
##   "fast_writing_speed": 4.0,       # x while fast-forwarding (Tab / held Ctrl)
##   "auto_forward_seconds": 0.05,    # per drawn character, the auto-forward formula
##   "master_volume": 0.8,            # x every story's own music and sound levels
##   "screen_mode": "maximize"        # "windowed" / "maximize" / "full_screen"
## }
## [/codeblock]
##
## [member master_volume] is the odd one out: the writing speeds and the
## auto-forward formula change how a story *reads*, while this one scales what it
## *sounds* like. A story names its own music and sound levels (and a save can
## carry them), so this is the player's overall dial on top of them.
##
## Writing speeds are multipliers rather than characters a second, so a line the
## writer deliberately gave its own speed - or set to [code]0[/code] to print at
## once - keeps its shape however the player sets the dial.
##
## Nothing here needs a story to be loaded, and none of it is part of a save:
## the settings are the same for every story, and loading an old save does not
## put them back to what they were.

const VERSION := 1

## How the window is displayed. The three the settings page offers - Godot's own
## [enum DisplayServer.WindowMode] has more, and [method window_mode_of] maps
## between them.
enum ScreenMode { WINDOWED, MAXIMIZED, FULLSCREEN }

## The names the settings page shows and the file stores, in [enum ScreenMode]
## order. [method screen_mode_of_name] reads them back.
const SCREEN_MODE_NAMES: PackedStringArray = ["windowed", "maximize", "full_screen"]
const SCREEN_MODE_LABELS: PackedStringArray = ["Windowed", "Maximize", "Full screen"]

## The writing-speed multiplier: [constant TEXT_SPEED_MIN] to
## [constant TEXT_SPEED_MAX], stepped by [constant TEXT_SPEED_STEP] - the same
## step the Ctrl + Right key uses.
const TEXT_SPEED_DEFAULT := 1.0
const TEXT_SPEED_MIN := 0.25
const TEXT_SPEED_MAX := 8.0
const TEXT_SPEED_STEP := 0.25

## The fast-forward multiplier. It has to be at least 1x, or "fast" would read
## slower than normal.
const FAST_SPEED_DEFAULT := 4.0
const FAST_SPEED_MIN := 1.0
const FAST_SPEED_MAX := 16.0
const FAST_SPEED_STEP := 1.0

## How long auto-forward holds a finished line, in seconds for every drawn
## character (spaces included). [code]0[/code] moves on as soon as a line is
## complete, ignoring the count. The line's own [code]{w=...}[/code] pauses are
## added on top and are not affected by this.
const AUTO_FORWARD_DEFAULT := 0.05
const AUTO_FORWARD_MIN := 0.0
const AUTO_FORWARD_MAX := 0.5
const AUTO_FORWARD_STEP := 0.01

## The player's overall volume, 0 to 1: every story's music and sound effects
## are played at their own level multiplied by this. [code]0[/code] is silence
## and [code]1[/code] leaves the story's own mix exactly as written.
const MASTER_VOLUME_DEFAULT := 1.0
const MASTER_VOLUME_MIN := 0.0
const MASTER_VOLUME_MAX := 1.0
const MASTER_VOLUME_STEP := 0.05

## Where the settings live, outside every save slot.
var path: String = "user://fmw_vn_settings.json"

## x the speed of every line - [method set_text_speed] keeps it in range.
var text_speed: float = TEXT_SPEED_DEFAULT
## x the speed while fast-forwarding - [method set_fast_speed] keeps it in range.
var fast_speed: float = FAST_SPEED_DEFAULT
## Seconds a drawn character is held by auto-forward.
var auto_forward_seconds: float = AUTO_FORWARD_DEFAULT
## The overall volume, 0 to 1 - [method set_master_volume] keeps it in range.
var master_volume: float = MASTER_VOLUME_DEFAULT
## One of [enum ScreenMode].
var screen_mode: int = ScreenMode.WINDOWED
## The language the player wants a story read in: one of that story's own codes.
## Empty means "whatever the story is written in", which is what a story that
## declares no languages is read in.
var language: String = ""

var _loaded: bool = false
## True when something has changed since the last write.
var _dirty: bool = false


static func default_path() -> String:
	return "user://fmw_vn_settings.json"


# --- disk ---------------------------------------------------------------------

## Reads the settings from disk. Returns false when there was nothing to read,
## which leaves the defaults in place - a player who has never opened the
## settings page has no file, and that is not a problem. A file that cannot be
## read or decoded is reported and then treated as a fresh one.
func load_from_disk() -> bool:
	_loaded = true
	_dirty = false
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("FMW_VN: %s is not a readable settings file; using the defaults." % path)
		return false
	from_dict(json.data)
	return true


## True once [method load_from_disk] has run.
func is_loaded() -> bool:
	return _loaded


## True when there are changes that have not been written yet.
func is_dirty() -> bool:
	return _dirty


func has_file() -> bool:
	return FileAccess.file_exists(path)


## Writes the settings, so a later run picks them up. Returns true when the file
## was written. Unlike the progress record this always writes - a settings file
## that says "the defaults" is a real thing to remember.
func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FMW_VN: could not write the settings file %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dict(), "  "))
	file.close()
	_dirty = false
	return true


## Writes only when something has changed since the last write.
func save_if_dirty() -> bool:
	return save() if _dirty else false


## The settings, as they are written to disk.
func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"writing_speed": text_speed,
		"fast_writing_speed": fast_speed,
		"auto_forward_seconds": auto_forward_seconds,
		"master_volume": master_volume,
		"screen_mode": screen_mode_name(),
		"language": language,
	}


## Replaces the settings from a decoded dictionary. Unknown keys are dropped and
## anything malformed, missing or out of range falls back to the default for that
## setting rather than being refused, so a hand-edited or older file still loads -
## at worst the player has to set that one setting again.
func from_dict(data: Dictionary) -> void:
	text_speed = _number_in_range(data.get("writing_speed"), TEXT_SPEED_DEFAULT, TEXT_SPEED_MIN, TEXT_SPEED_MAX)
	fast_speed = _number_in_range(data.get("fast_writing_speed"), FAST_SPEED_DEFAULT, FAST_SPEED_MIN, FAST_SPEED_MAX)
	auto_forward_seconds = _number_in_range(data.get("auto_forward_seconds"), AUTO_FORWARD_DEFAULT, AUTO_FORWARD_MIN, AUTO_FORWARD_MAX)
	master_volume = _number_in_range(data.get("master_volume"), MASTER_VOLUME_DEFAULT, MASTER_VOLUME_MIN, MASTER_VOLUME_MAX)
	screen_mode = screen_mode_of_name(data.get("screen_mode"))
	# A code the story does not have is simply ignored when the story is read, so
	# there is nothing to refuse here.
	language = str(data.get("language", "")).strip_edges().to_lower() if typeof(data.get("language")) == TYPE_STRING else ""
	_dirty = false


## Back to the defaults, in memory only - [method save] makes it stick.
func reset() -> void:
	text_speed = TEXT_SPEED_DEFAULT
	fast_speed = FAST_SPEED_DEFAULT
	auto_forward_seconds = AUTO_FORWARD_DEFAULT
	master_volume = MASTER_VOLUME_DEFAULT
	screen_mode = ScreenMode.WINDOWED
	language = ""
	_dirty = true


# --- the settings themselves -------------------------------------------------

## Sets the writing-speed multiplier, clamped to the range. Returns true when
## that changed something.
func set_text_speed(value: float) -> bool:
	return _set_in_range(&"text_speed", value, TEXT_SPEED_MIN, TEXT_SPEED_MAX)


## Sets the fast-forward multiplier, clamped to the range.
func set_fast_speed(value: float) -> bool:
	return _set_in_range(&"fast_speed", value, FAST_SPEED_MIN, FAST_SPEED_MAX)


## Sets the auto-forward formula's per-character hold, clamped to the range.
func set_auto_forward_seconds(value: float) -> bool:
	return _set_in_range(&"auto_forward_seconds", value, AUTO_FORWARD_MIN, AUTO_FORWARD_MAX)


## Sets the overall volume, clamped to the range. Returns true when that changed
## something.
func set_master_volume(value: float) -> bool:
	return _set_in_range(&"master_volume", value, MASTER_VOLUME_MIN, MASTER_VOLUME_MAX)


## Sets the screen mode, ignoring a value that is not one of [enum ScreenMode].
func set_screen_mode(value: int) -> bool:
	if value < 0 or value >= SCREEN_MODE_NAMES.size():
		return false
	if screen_mode == value:
		return false
	screen_mode = value
	_dirty = true
	return true


## Sets the language to read in. Returns true when that changed something.
func set_language(code: String) -> bool:
	var wanted := code.strip_edges().to_lower()
	if language == wanted:
		return false
	language = wanted
	_dirty = true
	return true


## The file name for the current screen mode, one of [constant SCREEN_MODE_NAMES].
func screen_mode_name() -> String:
	return SCREEN_MODE_NAMES[clampi(screen_mode, 0, SCREEN_MODE_NAMES.size() - 1)]


## What the settings page shows for the current screen mode.
func screen_mode_label() -> String:
	return SCREEN_MODE_LABELS[clampi(screen_mode, 0, SCREEN_MODE_LABELS.size() - 1)]


## Everything, for a menu line or a log.
func describe() -> String:
	return "%.2fx writing, %.2fx fast, %.3f s/char auto-forward, master volume %d%%, %s%s" % [
		text_speed, fast_speed, auto_forward_seconds, roundi(master_volume * 100.0), screen_mode_label(),
		(", language \"%s\"" % language) if not language.is_empty() else "",
	]


# --- the screen mode ---------------------------------------------------------

## The Godot window mode for one of [enum ScreenMode].
static func window_mode_of(mode: int) -> DisplayServer.WindowMode:
	match mode:
		ScreenMode.MAXIMIZED:
			return DisplayServer.WINDOW_MODE_MAXIMIZED
		ScreenMode.FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_WINDOWED


## The [enum ScreenMode] behind a Godot window mode. Godot has more than three;
## the ones this does not offer are folded onto the nearest of them - exclusive
## full screen is full screen, and a minimised or unknown window is windowed.
static func screen_mode_of(window_mode: int) -> int:
	match window_mode:
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return ScreenMode.MAXIMIZED
		DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return ScreenMode.FULLSCREEN
		_:
			return ScreenMode.WINDOWED


## The [enum ScreenMode] a stored name means, or the default when the name is
## missing or unrecognised.
static func screen_mode_of_name(name: Variant) -> int:
	if typeof(name) != TYPE_STRING:
		return ScreenMode.WINDOWED
	var wanted := (name as String).strip_edges().to_lower()
	for i in SCREEN_MODE_NAMES.size():
		if SCREEN_MODE_NAMES[i] == wanted:
			return i
	return ScreenMode.WINDOWED


# --- helpers ------------------------------------------------------------------

## A stored number, clamped into range. Anything that is not a number - a
## missing key, a string, a null - falls back to the default.
static func _number_in_range(value: Variant, fallback: float, low: float, high: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	return clampf(float(value), low, high)


func _set_in_range(property: StringName, value: float, low: float, high: float) -> bool:
	var wanted := clampf(value, low, high)
	if is_equal_approx(wanted, float(get(property))):
		return false
	set(property, wanted)
	_dirty = true
	return true
