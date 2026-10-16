extends SceneTree

## Checks a story file without opening the editor:
##
##     godot --headless --path . --script res://Framework_VN/tools/validate_story.gd
##     godot --headless --path . --script res://Framework_VN/tools/validate_story.gd -- res://VN/Story/other.json -v
##
## Exits with code 0 when the story is clean, 1 when it is not. Add -v to also
## print every parsed slide. Chapters are followed, so validating the index file
## checks every chapter with it.

const StoryLib := preload("res://Framework_VN/scripts/story_parser.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var path := "res://VN/Story/story.json"
	var verbose := false
	for argument in arguments:
		if argument.begins_with("-"):
			verbose = true
		else:
			path = argument

	print("FMW_VN validating: %s" % path)
	var result: StoryLib.Result = StoryLib.parse_file(path)

	for message in result.warnings:
		print("  warning: " + message)
	for message in result.errors:
		print("  error:   " + message)

	if not result.ok:
		print("\nFAILED - %d error(s), %d warning(s)." % [result.errors.size(), result.warnings.size()])
		quit(1)
		return

	if verbose:
		var story: StoryLib.Story = result.story
		print("\n%s" % story.describe())
		print("  background=%s  fade=%.2fs  text=%.0fcps  music=%.2f  sound=%.2f  start=%d" % [
			"#" + story.background_color.to_html(false),
			story.default_fade,
			story.default_text_speed,
			story.music_volume,
			story.sound_volume,
			story.start_index,
		])
		for chapter in story.chapters:
			print("  chapter: %s -> slides %d..%d" % [chapter["path"], chapter["first_index"], chapter["last_index"]])
		for slide in story.slides:
			print("  " + StoryLib.describe_slide(slide))

	print("\nOK - %s, %d warning(s)." % [result.story.describe(), result.warnings.size()])
	quit(0)
