extends SceneTree

## Plays a story from the first slide to the ending without opening a window,
## so you can tell whether a change broke playback:
##
##     godot --headless --path . --script res://Framework_VN/tools/smoke_test.gd
##     godot --headless --path . --script res://Framework_VN/tools/smoke_test.gd -- res://VN/Story/other.json
##
## It works out the expected path by following every slide's "next" - taking a
## slide's own "branch" where it has one, and the first available choice
## wherever the story asks the player to pick one - then checks that the player
## showed exactly that and that the right picture was on screen the whole way.
## Slides whose own "if" does not hold are passed over, and the variables are
## carried along the way the player carries them, so a conditional story is
## still expected exactly. Exits with 0 when it all matches, 1 otherwise.

const StoryLib := preload("res://Framework_VN/scripts/story_parser.gd")
const VNScreen := preload("res://Framework_VN/scenes/vn_screen.tscn")

var _player: Control = null
var _story: StoryLib.Story = null
var _expected: Array[int] = []
## Expected background path per expected slide index, carried over when a slide
## does not mention one. Keyed by slide index, because a story that skips a
## slide no longer runs through its slides in a row.
var _backgrounds: Dictionary = {}
var _seen: Array[int] = []
var _picture_issues := PackedStringArray()
var _choices_taken: int = 0
var _finished: bool = false
var _started: bool = false
var _guard: int = 0
var _final_code: int = 0
var _leaving: bool = false


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var path := arguments[0] if arguments.size() > 0 else "res://VN/Story/story.json"

	var result: StoryLib.Result = StoryLib.parse_file(path)
	for message in result.warnings:
		printerr("smoke test: warning: " + message)
	if not result.ok:
		printerr("smoke test: story did not parse:")
		for message in result.errors:
			printerr("  " + message)
		_finish_with(1)
		return
	_story = result.story
	_expected = _walk()
	if _expected.is_empty():
		printerr("smoke test: the story has no reachable slides.")
		_finish_with(1)
		return
	print("smoke test: %s -> %d slide(s) to play" % [_story.describe(), _expected.size()])


## Follows the story the way a player who always takes the first available answer
## would: a slide its own "if" hides is passed over, a "branch" picks its first
## matching entry, a choice only counts when its own "if" holds, and every "set"
## along the way is applied to the variables the next condition reads.
func _walk() -> Array[int]:
	var path: Array[int] = []
	var background := ""
	var variables: StoryVars = _story.new_vars()
	var cursor := _story.start_index
	var guard := 0
	var limit := _story.slide_count() * 2 + 8
	while cursor >= 0 and cursor < _story.slide_count() and path.size() <= _story.slide_count() and guard < limit:
		guard += 1
		if not _story.is_visible(cursor, variables):
			cursor = _story.next_after(cursor, variables)
			continue
		path.append(cursor)
		var slide: Dictionary = _story.slides[cursor]
		if slide.has("background"):
			background = str(slide["background"])
		_backgrounds[cursor] = background
		# The player runs a slide's own "set" when the slide appears.
		_story.apply_set(cursor, variables)
		var choices: Array = _story.visible_choices(cursor, variables)
		if choices.is_empty():
			cursor = _story.next_after(cursor, variables)
		else:
			cursor = int((choices[0] as Dictionary).get("next_index", -1))
	return path


func _process(_delta: float) -> bool:
	# The tree is only fully up once the first frame runs, so the scene goes in
	# here rather than in _initialize().
	if not _started:
		_started = true
		if _story == null:
			# _initialize() already queued the failure exit.
			return false
		_player = VNScreen.instantiate()
		_player.track_progress = false   # a smoke test is not a player
		_player.remember_settings = false   # and not the player settings file either
		# This test drives playback itself instead of letting _ready start it.
		_player.play_on_start = false
		root.add_child(_player)
		_player.slide_shown.connect(_on_slide_shown)
		_player.choice_made.connect(_on_choice_made)
		_player.story_finished.connect(_on_story_finished)
		_player.begin(_story)
		return false

	if _leaving:
		# _cleanup() quits at the end of this frame.
		return false
	_guard += 1
	if _guard > 10000:
		printerr("smoke test: gave up after %d frames, playback is stuck." % _guard)
		_finish_with(1)
		return false

	if _player.is_choosing():
		# Pick the first option, like the expected path above does.
		_player.choose(0)
	elif _player.is_playing():
		# One nudge per frame: the first fills in a running text block, the next
		# one moves on, which walks the whole story.
		_player.advance()
	return false


func _on_slide_shown(index: int) -> void:
	_seen.append(index)
	if not _backgrounds.has(index):
		return
	var want := str(_backgrounds[index])
	if want.is_empty():
		if _showing_picture("BgA") or _showing_picture("BgB"):
			_picture_issues.append("slide %d should have no background picture" % index)
	elif not _showing_picture_path(want):
		_picture_issues.append("slide %d shows %s, expected %s" % [index, _pictures_on_screen(), want])


func _showing_picture(node_name: String) -> bool:
	return _player.get_node("%" + node_name).texture != null


func _showing_picture_path(path: String) -> bool:
	for node_name in ["BgA", "BgB"]:
		var node = _player.get_node("%" + node_name)
		if node.texture != null and str(node.texture.resource_path) == path:
			return true
	return false


func _pictures_on_screen() -> String:
	var paths := PackedStringArray()
	for node_name in ["BgA", "BgB"]:
		var node = _player.get_node("%" + node_name)
		paths.append("none" if node.texture == null else str(node.texture.resource_path).get_file())
	return " + ".join(paths)


func _on_choice_made(_index: int) -> void:
	_choices_taken += 1


func _on_story_finished() -> void:
	_finished = true
	var failures := PackedStringArray()
	if _seen != _expected:
		failures.append("played slides %s, expected %s" % [str(_seen), str(_expected)])
	for issue in _picture_issues:
		failures.append(issue)
	var last_index: int = _player.current_slide_index()
	if last_index != _expected[-1]:
		failures.append("stopped on slide %d, expected %d" % [last_index, _expected[-1]])

	if failures.is_empty():
		print("smoke test: OK - played %d slide(s), %d choice(s), backgrounds correct, reached the ending." % [_seen.size(), _choices_taken])
		_finish_with(0)
	else:
		for message in failures:
			printerr("smoke test: " + message)
		_finish_with(1)


## Drops the scene and quits. Deferred, because this usually runs from inside
## the player's own signal, and freeing a node mid-call is not safe.
func _finish_with(code: int) -> void:
	_final_code = code
	_leaving = true
	_cleanup.call_deferred()


func _cleanup() -> void:
	if _player != null and is_instance_valid(_player):
		_player.free()
	# Let go of the parsed story too, so the engine's exit check stays quiet.
	_player = null
	_story = null
	quit(_final_code)
