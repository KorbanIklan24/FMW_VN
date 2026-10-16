class_name StoryParser
extends RefCounted

## FMW_VN story parser.
##
## Turns one or more JSON files into a validated [Story]: a flat list of slides
## that [VNPlayer] can play back without doing any data handling of its own.
## See GUIDE.md for the full JSON schema.
##
## The parser never crashes on bad input - every problem is collected, so you
## always get a [Result] to inspect:
## [codeblock]
## var result := StoryParser.parse_file("res://VN/Story/story.json")
## if result.ok:
##     player.begin(result.story)
## else:
##     for message in result.errors:
##         push_error(message)
## [/codeblock]
##
## A story file may list further files with "chapters", in which case all of
## them are merged into a single [Story]: slide ids, asset aliases and variables
## are shared, the last slide of one chapter flows into the first slide of the
## next.
##
## A story can also carry [b]variables[/b] - a `variables` block of starting
## values, `"set"` on a slide to write them, and `"if"` / `"branch"` (plus a
## choice's own `"if"`) to read them. Every condition is compiled here with
## Godot's [Expression] class against the declared variable names, so a typo or
## a slide id used as a variable is a parse error with a message, not silence.
## Variables live in their own dictionary ([member Story.variables]), which can
## never be confused with slide ids ([member Story.id_to_index]); `"next"` still
## takes a slide id or a plain index exactly as before.

const DEFAULT_TEXT_SPEED := 45.0
const DEFAULT_FADE := 0.35
const DEFAULT_MUSIC_VOLUME := 0.6
const DEFAULT_SOUND_VOLUME := 0.8

## Extensions tried when an asset is written without one.
const IMAGE_EXTENSIONS := [".png", ".svg", ".webp", ".jpg", ".jpeg", ".bmp"]
const AUDIO_EXTENSIONS := [".ogg", ".wav", ".mp3"]

## Audio formats whose first bytes can be recognised. Godot imports by
## extension rather than by contents, so a file whose bytes disagree with its
## name is silently imported as empty - worth a warning (see
## [method _audio_mismatch]).
const AUDIO_FORMATS := [".ogg", ".wav", ".mp3"]

## Audio formats that are recognisable as audio but that Godot 4 has no
## importer for (verified against Godot 4.7.2). They can never resolve, so
## naming one gets a pointed error instead of the generic "asset not found"
## (see [method _unsupported_audio_extension]).
const UNSUPPORTED_AUDIO_EXTENSIONS := [".flac", ".aac", ".m4a"]

const STORY_EXTENSIONS := [".json"]

## "position" takes one of these on its own, or a pair like "bottom-left".
const HORIZONTAL_POSITIONS := ["auto", "left", "center", "right"]
const VERTICAL_POSITIONS := ["top", "middle", "bottom"]
const HORIZONTAL_RATIOS := {"left": 0.22, "center": 0.5, "right": 0.78}
## Where the bottom edge of the picture sits, as a fraction of the screen height.
const VERTICAL_RATIOS := {"top": 0.55, "middle": 0.78, "bottom": 1.0}

const TOP_LEVEL_KEYS := ["settings", "assets", "slides", "chapters", "variables", "gallery", "languages", "default_language"]
const SETTINGS_KEYS := ["title", "start", "chapters", "background_color", "default_text_speed", "default_fade", "music_volume", "sound_volume", "variables", "languages", "default_language"]

## A language mirror is a file that carries one translated line per line of the
## script it mirrors, and nothing else: the structure - pictures, ids, choices,
## "next" - lives in the base script alone, which is what makes a language
## switch land on the same line. The mirror of `ch01.json` is `ch01.id.json`.
const MIRROR_KEYS := ["slides"]
const MIRROR_SLIDE_KEYS := ["id", "text", "speaker", "choices"]
const MIRROR_CHOICE_KEYS := ["text"]
## A language code names that file, so it has to be safe in a file name.
const LANGUAGE_CODE_MAX := 16
const ASSET_KEYS := ["backgrounds", "characters", "music", "sounds", "cg"]
## Keys a `gallery` entry understands.
const GALLERY_KEYS := ["id", "title", "caption", "image", "unlock"]
## Keys an `unlock` goal understands: the dialogue id the player has to reach,
## and/or the slide index they have to get to.
const UNLOCK_KEYS := ["seen", "index"]
## The alias groups a gallery `image` is looked up in, in this order.
const GALLERY_ALIAS_GROUPS := ["cg", "backgrounds", "characters"]
const SLIDE_KEYS := ["id", "background", "characters", "show", "hide", "with", "speaker", "portrait", "text", "next", "fade", "text_speed", "wait", "auto", "choices", "bgm", "sfx", "transition", "effects", "set", "if", "branch"]
const CHARACTER_KEYS := ["id", "image", "portrait", "position", "vertical", "x", "y", "scale", "flip", "offset_y", "tint"]
## The simple transitions a character can come or go with, taken from a "show"
## / "hide" entry's own "effect" or the slide-wide "with". "dissolve" (and its
## alias "fade") fades the picture in or out, "none" cuts.
const STAGE_EFFECTS := ["none", "dissolve", "fade"]
## Keys a "hide" entry understands.
const HIDE_KEYS := ["id", "image", "effect", "duration"]
## Keys a "show" entry takes on top of the usual character keys.
const SHOW_EXTRA_KEYS := ["effect", "duration"]
const CHOICE_KEYS := ["text", "next", "sfx", "if"]
## Keys a "branch" entry understands. An entry without "if" is the default.
const BRANCH_KEYS := ["if", "next"]
## The one key a computed "set" value takes: `{ "expr": "affection + 1" }`.
const SET_VALUE_KEYS := ["expr"]

## A "bgm" value that means "silence from here on".
const MUSIC_STOP_WORDS := ["", "stop", "none", "silence"]

## How a new background can come in, for a slide's "transition".
const TRANSITIONS := ["cut", "fade", "fade_black", "wipe_left", "wipe_right", "wipe_up", "wipe_down", "slide_left", "slide_right", "slide_up", "slide_down"]

## Screen effects a slide can ask for, with the parameters each one understands.
const EFFECTS := ["shake", "flash", "zoom", "pulse", "reset"]
const EFFECT_PARAMS := {
	"shake": ["strength", "duration", "delay"],
	"flash": ["color", "duration", "delay"],
	"zoom": ["from", "to", "duration", "delay"],
	"pulse": ["strength", "duration", "delay"],
	"reset": ["duration", "delay"],
}


## A parsed, playable story.
class Story:
	extends RefCounted

	var title: String = "Untitled"
	## Every language the story is told in: code -> the name to show the player.
	## In the order the story declares them, which is the order a menu offers them.
	## Empty for a story that is only in one language (the usual case).
	var languages: Dictionary = {}
	## The code of the language the story is written in, and the one every line
	## falls back to: `""` when the story declares no languages at all.
	var default_language: String = ""
	## code -> the story's title in that language, for a menu or a save. [member
	## title] is always the default language's, so code that ignores languages
	## still reads correctly.
	var titles: Dictionary = {}
	var source_path: String = ""
	var background_color: Color = Color(0.06, 0.06, 0.09)
	var default_text_speed: float = 45.0
	var default_fade: float = 0.35
	var music_volume: float = 0.6
	var sound_volume: float = 0.8
	var start_index: int = 0
	## One dictionary per slide. Always there: index, id, source, speaker, text,
	## fade, text_speed, wait, auto_advance, sfx and the resolved next_index.
	## Only there when the JSON had them: background, characters, next, bgm,
	## choices, transition, effects. A story told in more than one language also
	## carries the other languages' lines side by side - `texts`, `speakers` and
	## `pause_sets`, keyed by language code - which is what [method text_for] and
	## its siblings read. A slide's plain `text` and `speaker` stay the default
	## language's, so code that ignores languages still reads correctly.
	var slides: Array[Dictionary] = []
	var id_to_index: Dictionary = {}
	## The starting value of every declared variable. This dictionary is the
	## variable namespace, and it is deliberately separate from
	## [member id_to_index] - a name can be both a variable and a slide id without
	## either shadowing the other.
	var variables: Dictionary = {}
	## The declared names, sorted. Every condition was compiled with exactly
	## these, in this order, which is what an expression is handed at run time.
	var variable_names: PackedStringArray = PackedStringArray()
	## One entry per story file that went into this story:
	## { path, first_index, last_index }.
	var chapters: Array[Dictionary] = []
	## The CG gallery: one entry per collectable picture,
	## { id, title, caption, image, goal }. `goal` is { seen, index } - the progress
	## the player needs for it to unlock, checked against the global record rather
	## than a save, so loading an older save cannot take a CG back.
	var gallery: Array[Dictionary] = []

	# --- languages ---------------------------------------------------------------

	## Every language code, in declaration order, default first.
	func language_codes() -> PackedStringArray:
		var out := PackedStringArray()
		for code in languages.keys():
			out.append(str(code))
		return out


	func has_language(code: String) -> bool:
		return languages.has(code)


	## True when there is more than one language to choose between.
	func is_multilingual() -> bool:
		return languages.size() > 1


	## What to call a language, or the code itself if the story never named it.
	func language_name(code: String) -> String:
		if code.is_empty():
			return ""
		return str(languages.get(code, code))


	## The language to actually read in: [param code] when the story has it, and
	## the story's own default otherwise (including "", which means "no opinion").
	func resolve_language(code: String) -> String:
		if languages.has(code):
			return code
		return default_language


	## The story's title in [param code]. One language's title falls back to the
	## default language's, and to [member title], so a half-translated story still
	## has something to show.
	func title_for(code: String) -> String:
		var wanted := str(titles.get(code, ""))
		if not wanted.is_empty():
			return wanted
		return str(titles.get(default_language, title))


	## The line to show for a slide in [param code]. A line that language has not
	## translated falls back to the default language's.
	func text_for(slide: Dictionary, code: String) -> String:
		return _localized_string(slide.get("texts"), code, str(slide.get("text", "")))


	## Who is speaking in [param code] - the same fallback as a line.
	func speaker_for(slide: Dictionary, code: String) -> String:
		return _localized_string(slide.get("speakers"), code, str(slide.get("speaker", "")))


	## The `{w=...}` pauses of a slide in [param code]. A translation may put its
	## pauses somewhere else, so they travel with the text; a language without its
	## own keeps the default language's.
	func pauses_for(slide: Dictionary, code: String) -> Array:
		var sets: Variant = slide.get("pause_sets")
		if typeof(sets) == TYPE_DICTIONARY and (sets as Dictionary).has(code):
			return (sets as Dictionary)[code]
		return slide.get("pauses", [])


	## A choice's own text in [param code], with the same fallback.
	func choice_text_for(choice: Dictionary, code: String) -> String:
		return _localized_string(choice.get("texts"), code, str(choice.get("text", "")))


	## A CG's title in [param code], falling back the same way.
	func cg_title_for(entry: Dictionary, code: String) -> String:
		return _localized_string(entry.get("titles"), code, str(entry.get("title", "")))


	## A CG's caption in [param code].
	func cg_caption_for(entry: Dictionary, code: String) -> String:
		return _localized_string(entry.get("captions"), code, str(entry.get("caption", "")))


	## One string out of a `{ code: string }` table, with the fallback.
	func _localized_string(table: Variant, code: String, fallback: String) -> String:
		if typeof(table) != TYPE_DICTIONARY:
			return fallback
		var strings: Dictionary = table
		if strings.has(code) and not str(strings[code]).is_empty():
			return str(strings[code])
		if strings.has(default_language) and not str(strings[default_language]).is_empty():
			return str(strings[default_language])
		return fallback


	func cg_count() -> int:
		return gallery.size()

	func has_cg(id: String) -> bool:
		return not cg_entry(id).is_empty()

	func cg_entry(id: String) -> Dictionary:
		for entry in gallery:
			if str(entry.get("id", "")) == id:
				return entry
		return {}

	func cg_ids() -> PackedStringArray:
		var out := PackedStringArray()
		for entry in gallery:
			out.append(str(entry.get("id", "")))
		return out

	func slide_count() -> int:
		return slides.size()

	func has_slide(id: String) -> bool:
		return id_to_index.has(id)

	func index_of(id: String) -> int:
		return int(id_to_index.get(id, -1))

	func slide_at(index: int) -> Dictionary:
		if index < 0 or index >= slides.size():
			return {}
		return slides[index]

	func has_variable(name: String) -> bool:
		return variables.has(name)

	func variable_names_string() -> String:
		return ", ".join(variable_names) if not variable_names.is_empty() else "none"

	## A fresh [StoryVars] holding this story's declared starting values.
	func new_vars() -> StoryVars:
		return StoryVars.new(variables, variable_names)

	## False only when the slide has an `"if"` that does not hold. A slide with
	## no condition is always shown.
	func is_visible(index: int, vars: StoryVars) -> bool:
		if index < 0 or index >= slides.size():
			return false
		var condition: Expression = slides[index].get("if_expr")
		if condition == null:
			return true
		return vars != null and vars.is_true(condition)

	## Where a slide leads once it is left: the first "branch" entry whose "if"
	## holds (or that has no "if" at all), otherwise the slide's own "next".
	func next_after(index: int, vars: StoryVars) -> int:
		if index < 0 or index >= slides.size():
			return -1
		var slide := slides[index]
		for entry in (slide.get("branch", []) as Array):
			var condition: Expression = entry.get("if_expr")
			if condition == null or (vars != null and vars.is_true(condition)):
				return int(entry.get("next_index", -1))
		return int(slide.get("next_index", -1))

	## The choices of a slide that pass their own "if", in JSON order. This is
	## what the player puts on screen, and what its buttons are numbered by.
	func visible_choices(index: int, vars: StoryVars) -> Array:
		var out: Array = []
		if index < 0 or index >= slides.size():
			return out
		for choice in (slides[index].get("choices", []) as Array):
			var condition: Expression = choice.get("if_expr")
			if condition == null or (vars != null and vars.is_true(condition)):
				out.append(choice)
		return out

	## Runs a slide's "set" writes, in the order they were written. Called when
	## the slide is entered (and never for a slide its "if" skipped).
	func apply_set(index: int, vars: StoryVars) -> void:
		if vars == null or index < 0 or index >= slides.size():
			return
		for entry in (slides[index].get("sets", []) as Array):
			var name := str(entry.get("name", ""))
			if entry.has("expr"):
				vars.set_value(name, vars.evaluate(entry["expr"]))
			else:
				var value: Variant = entry.get("value")
				if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
					# A literal list or object is handed over fresh each time, so two
					# slides writing the same "[]" never end up sharing one array.
					value = (value as Variant).duplicate(true)
				vars.set_value(name, value)

	## The chapter a slide belongs to, or {} when nothing matches.
	func chapter_of(index: int) -> Dictionary:
		for chapter in chapters:
			if index >= int(chapter["first_index"]) and index <= int(chapter["last_index"]):
				return chapter
		return {}

	func describe() -> String:
		var parts := PackedStringArray(["%s (%d slides" % [title, slides.size()]])
		if chapters.size() > 1:
			parts.append(", %d chapters" % chapters.size())
		if gallery.size() > 0:
			parts.append(", %d CGs" % gallery.size())
		parts.append(")")
		return "".join(parts)


## Outcome of a parse. Always returned, never null.
class Result:
	extends RefCounted

	## True only when there are no errors.
	var ok: bool = false
	var errors: PackedStringArray = PackedStringArray()
	## Non-fatal notes (unknown keys, repeated aliases...).
	var warnings: PackedStringArray = PackedStringArray()
	var story: Story = null


## Parses a story from disk. `settings.chapters` (or a top level `chapters`)
## pulls in further files. Relative paths are resolved against the story file's
## own folder.
static func parse_file(path: String) -> Result:
	var result := Result.new()
	result.story = Story.new()
	result.story.source_path = path
	var errors := PackedStringArray()
	var data := _read_story_file(path, errors)
	if not errors.is_empty():
		result.errors = errors
		return result
	result = parse_dict(data, path)
	result.story.source_path = path
	return result


## Parses a story from a JSON string. [param source_path] is only used for error
## messages and for resolving relative paths.
static func parse_text(text: String, source_path: String = "<memory>") -> Result:
	var errors := PackedStringArray()
	var data := _decode(text, source_path, errors)
	if not errors.is_empty():
		var failed := Result.new()
		failed.errors = errors
		return failed
	return parse_dict(data, source_path)


## The languages a story file declares, without parsing the story itself:
## `{ "names": { code: name }, "default": code }`. The menu needs this before
## anything has been played, so it stays a cheap read of the one file.
static func languages_of(path: String) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var data := _read_story_file(path, errors)
	if data.is_empty():
		return {"names": {}, "default": ""}
	var languages := _parse_languages(data, _dict_of(data.get("settings")), path, errors, warnings)
	return {"names": languages["names"], "default": languages["default"]}


## Parses an already decoded story dictionary.
static func parse_dict(data: Dictionary, source_path: String = "<memory>") -> Result:
	if _lists_chapters(data):
		return _parse_chapters(data, source_path)

	var result := Result.new()
	var story := Story.new()
	story.source_path = source_path
	result.story = story

	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	_report_unknown_keys(data, TOP_LEVEL_KEYS, source_path, warnings)
	if data.has("chapters"):
		warnings.append("%s - \"chapters\" is empty, so this file is read as a single story." % source_path)

	var parsed := _parse_slides_and_settings(data, source_path, errors, warnings)
	var slides: Array[Dictionary] = parsed["slides"]
	if slides.is_empty():
		result.errors = errors
		result.warnings = warnings
		return result

	# The languages this file is told in, and their mirrors of it, before anything
	# reads a line: the fallback for a missing translation is the default
	# language's own line, which is the one this file carries.
	var languages := _parse_languages(data, parsed["settings"], source_path, errors, warnings)
	story.languages = languages["names"]
	story.default_language = languages["default"]
	_merge_language_mirrors(slides, source_path, languages, errors, warnings)

	if slides.size() > 0:
		story.chapters.append({"path": source_path, "first_index": 0, "last_index": slides.size() - 1})
	_resolve_slides(slides, parsed["assets"], errors, warnings)
	var gallery := _parse_gallery(data, parsed["assets"], source_path, errors, warnings, languages)
	_apply_settings(story, parsed["settings"], errors)
	_finalize(story, slides, parsed["settings"], parsed["variables"], errors, warnings)
	_finalize_gallery(story, gallery, errors, warnings)

	result.errors = errors
	result.warnings = warnings
	result.ok = errors.is_empty()
	return result


## The name a resolved branch / choice entry leads to.
static func _target_name(entry: Dictionary) -> String:
	var index := int(entry.get("next_index", -1))
	return "end" if index < 0 else "#%d" % index


## Human readable one-liner for a gallery entry, handy for debugging and for the
## validator's dump.
static func describe_cg(entry: Dictionary) -> String:
	var bits := PackedStringArray()
	bits.append("%s" % entry.get("id", "?"))
	bits.append("\"%s\"" % entry.get("title", ""))
	bits.append("image=%s" % str(entry.get("image", "")).get_file())
	bits.append("unlock=%s" % describe_cg_goal(entry.get("goal", {})))
	return "  ".join(bits)


## What a gallery goal asks for, as text: "seen id", "index >= 12", or both.
static func describe_cg_goal(goal: Dictionary) -> String:
	var bits := PackedStringArray()
	if not str(goal.get("seen", "")).is_empty():
		bits.append("seen %s" % goal["seen"])
	if int(goal.get("index", -1)) >= 0:
		bits.append("index >= %d" % int(goal["index"]))
	return " and ".join(bits) if bits.size() > 0 else "nothing"


## Human readable one-liner for a slide, handy for debugging and tooling.
static func describe_slide(slide: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("#%d" % int(slide.get("index", -1)))
	var id := str(slide.get("id", ""))
	if not id.is_empty():
		parts.append("(%s)" % id)
	if not str(slide.get("background", "")).is_empty():
		parts.append("bg=" + str(slide["background"]).get_file())
	if slide.get("characters") != null:
		parts.append("cast=%d" % (slide["characters"] as Array).size())
	if slide.has("portrait"):
		parts.append("portrait=%s" % ("off" if str(slide["portrait"]).is_empty() else str(slide["portrait"]).get_file()))
	var speaker := str(slide.get("speaker", ""))
	if not speaker.is_empty():
		parts.append("%s:" % speaker)
	var text := str(slide.get("text", ""))
	if not text.is_empty():
		parts.append("\"%s\"" % text.substr(0, 40))
	if slide.has("choices"):
		parts.append("choices=%d" % (slide["choices"] as Array).size())
	if slide.has("sets"):
		var writes := PackedStringArray()
		for entry in (slide["sets"] as Array):
			writes.append("%s=%s" % [entry["name"], "{expression}" if entry.has("expr") else StoryVars.describe_value(entry.get("value"))])
		parts.append("set(%s)" % ",".join(writes))
	if slide.has("if_text"):
		parts.append("if(%s)" % str(slide["if_text"]))
	if slide.has("branch"):
		var routes := PackedStringArray()
		for entry in (slide["branch"] as Array):
			routes.append("%s -> %s" % [str(entry.get("if_text", "else")), _target_name(entry)])
		parts.append("branch(%s)" % "; ".join(routes))
	if slide.has("transition"):
		parts.append("transition=%s" % str((slide["transition"] as Dictionary).get("type", "fade")))
	var effects: Array = slide.get("effects", [])
	if not effects.is_empty():
		var names := PackedStringArray()
		for effect in effects:
			names.append(str((effect as Dictionary).get("type", "?")))
		parts.append("effects=%s" % ",".join(names))
	if slide.has("bgm"):
		parts.append("bgm=%s" % ("stop" if str(slide["bgm"]).is_empty() else str(slide["bgm"]).get_file()))
	var sounds: Array = slide.get("sfx", [])
	if not sounds.is_empty():
		parts.append("sfx=%d" % sounds.size())
	if bool(slide.get("auto_advance", false)):
		parts.append("auto=%.2fs" % float(slide.get("wait", 0.0)))
	return " ".join(parts)


# --- chapter index -----------------------------------------------------------

static func _lists_chapters(data: Dictionary) -> bool:
	return not _chapter_list(data, _dict_of(data.get("settings"))).is_empty()


static func _chapter_list(data: Dictionary, settings: Dictionary) -> Array:
	if typeof(data.get("chapters")) == TYPE_ARRAY:
		return data["chapters"]
	if typeof(settings.get("chapters")) == TYPE_ARRAY:
		return settings["chapters"]
	return []


static func _parse_chapters(index_data: Dictionary, source_path: String) -> Result:
	var result := Result.new()
	var story := Story.new()
	story.source_path = source_path
	result.story = story

	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	_report_unknown_keys(index_data, TOP_LEVEL_KEYS, source_path, warnings)
	if index_data.has("slides"):
		warnings.append("%s - a file with \"chapters\" cannot have its own \"slides\"; they are ignored." % source_path)

	var index_settings := _dict_of(index_data.get("settings"))
	# The languages the whole story is told in, declared once, in the index.
	var languages := _parse_languages(index_data, index_settings, source_path, errors, warnings)
	story.languages = languages["names"]
	story.default_language = languages["default"]
	var base_dir := source_path.get_base_dir()
	var slides: Array[Dictionary] = []
	var chapter_settings: Array[Dictionary] = []
	var chapter_assets: Array[Dictionary] = []
	var chapter_variables_list: Array[Dictionary] = []

	for entry in _chapter_list(index_data, index_settings):
		var chapter_path := _resolve_story_path(entry, base_dir, errors, "%s chapters" % source_path)
		if chapter_path.is_empty():
			continue
		var chapter_data := _read_story_file(chapter_path, errors)
		if chapter_data.is_empty():
			continue
		if _lists_chapters(chapter_data):
			errors.append("%s - a chapter cannot list chapters of its own." % chapter_path)
			continue
		if chapter_data.has("gallery"):
			warnings.append("%s - only the story's first file declares a gallery; this one is ignored." % chapter_path)
		if chapter_data.has("languages") or chapter_data.has("default_language"):
			warnings.append("%s - only the story's first file declares the languages; this one is ignored." % chapter_path)
		var parsed := _parse_slides_and_settings(chapter_data, chapter_path, errors, warnings)
		if (parsed["slides"] as Array).is_empty():
			continue
		# Every other language's translated copy of these lines, merged in.
		_merge_language_mirrors(parsed["slides"], chapter_path, languages, errors, warnings)
		var first_index := slides.size()
		slides.append_array(parsed["slides"])
		chapter_settings.append(parsed["settings"])
		chapter_assets.append(parsed["assets"])
		chapter_variables_list.append(parsed["variables"])
		story.chapters.append({"path": chapter_path, "first_index": first_index, "last_index": slides.size() - 1})

	if slides.is_empty():
		result.errors = errors
		result.warnings = warnings
		return result

	# Aliases from the index file first, then from each chapter. Anything that is
	# already defined wins, and a repeated alias is worth a warning.
	var assets := _dict_of(index_data.get("assets"))
	_report_unknown_keys(assets, ASSET_KEYS, source_path + " assets", warnings)
	_merge_assets(assets, chapter_assets, warnings)

	# Variables work the same way: declared once, shared by every chapter, and
	# the index file gets the last word when both name the same variable.
	var variables := _parse_variables(index_data, index_settings, source_path, errors, warnings)
	for chapter_variables in chapter_variables_list:
		for key in chapter_variables.keys():
			if variables.has(key):
				warnings.append("variables already defines \"%s\"; the first definition wins." % key)
				continue
			variables[key] = chapter_variables[key]

	# Settings: the first chapter is the fallback, the index file overrides it.
	var settings := {}
	if chapter_settings.size() > 0:
		settings = chapter_settings[0].duplicate(true)
	for key in index_settings:
		settings[key] = index_settings[key]

	_resolve_slides(slides, assets, errors, warnings)
	# The gallery belongs to the story rather than to a chapter, so it is read
	# from the index file (and a chapter's own is reported above).
	var gallery := _parse_gallery(index_data, assets, source_path, errors, warnings, languages)
	_apply_settings(story, settings, errors)
	_finalize(story, slides, settings, variables, errors, warnings)
	_finalize_gallery(story, gallery, errors, warnings)

	result.errors = errors
	result.warnings = warnings
	result.ok = errors.is_empty()
	return result


# --- languages ---------------------------------------------------------------

## Reads a story's `languages` block - `{ "en": "English", "id": "Indonesian" }`
## - in the order it is declared, and the `default_language` naming the one the
## story is written in. Returns `{ codes, names, default }`. A story that
## declares none gets empty codes and `""`, and is told in its base scripts
## alone, exactly as before there were languages.
static func _parse_languages(data: Dictionary, settings: Dictionary, source_path: String, errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	var codes := PackedStringArray()
	var names := {}
	var block: Variant = data.get("languages")
	if block == null:
		block = settings.get("languages")
	if block != null and typeof(block) != TYPE_DICTIONARY:
		errors.append("%s - \"languages\" must be an object of code: name pairs, like { \"en\": \"English\", \"id\": \"Indonesian\" }." % source_path)
		block = null
	if typeof(block) == TYPE_DICTIONARY:
		for key in (block as Dictionary).keys():
			var code := str(key).strip_edges().to_lower()
			if names.has(code):
				warnings.append("%s - languages names \"%s\" twice; the first name wins." % [source_path, code])
				continue
			var problem := _language_code_problem(code)
			if not problem.is_empty():
				errors.append("%s - languages: %s" % [source_path, problem])
				continue
			var label := str((block as Dictionary)[key]).strip_edges()
			if label.is_empty():
				errors.append("%s - languages.\"%s\" needs a name to show the player, like \"Indonesian\" or \"English\"." % [source_path, code])
				continue
			names[code] = label
			codes.append(code)
	var declared := str(data.get("default_language", settings.get("default_language", ""))).strip_edges().to_lower()
	if codes.is_empty():
		if not declared.is_empty():
			warnings.append("%s - \"default_language\" is \"%s\" but the story declares no \"languages\"; it is ignored." % [source_path, declared])
		return {"codes": codes, "names": names, "default": ""}
	if declared.is_empty():
		# The first declared language is the one the base scripts are in.
		return {"codes": codes, "names": names, "default": codes[0]}
	if not names.has(declared):
		errors.append("%s - \"default_language\" is \"%s\", which is not one of the declared languages (%s)." % [source_path, declared, ", ".join(codes)])
		return {"codes": codes, "names": names, "default": codes[0]}
	return {"codes": codes, "names": names, "default": declared}


## A language code names the mirror file (`ch01.id.json`), so it has to be safe
## in a file name. Returns "" when it is, and why not when it is not.
static func _language_code_problem(code: String) -> String:
	if code.is_empty():
		return "a language code cannot be empty."
	if code.length() > LANGUAGE_CODE_MAX:
		return "keep a language code to %d characters or fewer - it names a file." % LANGUAGE_CODE_MAX
	for i in code.length():
		var c := code[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			continue
		return "a language code may only use a-z, 0-9, \"_\" and \"-\", because it names the mirror file (\"%s.json\"); \"%s\" is not one." % [code, c]
	return ""


## Where a language's mirror of a script lives: `ch01.json` -> `ch01.id.json`.
static func mirror_path(path: String, code: String) -> String:
	if code.is_empty():
		return path
	return "%s.%s.json" % [path.get_basename(), code]


## Merges every language's mirror of one script into its slides, so that a story
## carries every language's lines side by side and switching between them cannot
## move the story: it is the same slides, only told differently.
##
## The default language is the base script itself. Each other language has a
## mirror file beside it, which must carry the same lines in the same order -
## that is the whole contract - and may only carry the words. A language with no
## mirror keeps the default language's lines with a warning, so a story can be
## translated one chapter at a time.
static func _merge_language_mirrors(slides: Array[Dictionary], script_path: String, languages: Dictionary, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var codes: PackedStringArray = languages["codes"]
	var default_language: String = languages["default"]
	if codes.is_empty():
		# One language: the base script is all there is, and no slide gains a
		# translation table it has no use for.
		return
	for slide in slides:
		_store_line(slide, default_language, slide)
	for code in codes:
		if code == default_language:
			continue
		var mirror := mirror_path(script_path, code)
		if not FileAccess.file_exists(mirror):
			warnings.append("%s - no \"%s\" mirror (%s); those lines stay in \"%s\"." % [script_path, code, mirror, default_language])
			continue
		var lines := _read_mirror(mirror, slides.size(), errors)
		if lines.is_empty():
			continue
		_merge_mirror_lines(slides, lines, mirror, script_path, code, errors, warnings)


## Reads one language's mirror of a script: the same number of slides, each
## carrying translated words only.
static func _read_mirror(mirror: String, expected: int, errors: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data := _read_story_file(mirror, errors)
	if data.is_empty():
		return out
	for key in data.keys():
		if not MIRROR_KEYS.has(str(key)):
			errors.append("%s - a language mirror carries translated lines and nothing else; \"%s\" belongs in the base script." % [mirror, str(key)])
	var raw_slides: Variant = data.get("slides")
	if typeof(raw_slides) != TYPE_ARRAY:
		errors.append("%s - a language mirror needs a \"slides\" array with one entry per line of the base script." % mirror)
		return out
	if (raw_slides as Array).size() != expected:
		errors.append("%s - a mirror must carry the same %d line(s) as the script it mirrors; this one has %d, so a language switch could not land on the same line." % [mirror, expected, (raw_slides as Array).size()])
		return out
	for i in (raw_slides as Array).size():
		var raw: Variant = (raw_slides as Array)[i]
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("%s - slides[%d] must be an object, like { \"id\": \"opening\", \"text\": \"...\" }." % [mirror, i])
			continue
		out.append(_parse_mirror_slide(raw, i, mirror, errors))
	return out


## One line of a mirror: the words, and nothing else.
static func _parse_mirror_slide(raw: Dictionary, index: int, mirror: String, errors: PackedStringArray) -> Dictionary:
	var where := "slides[%d]" % index
	for key in raw.keys():
		if not MIRROR_SLIDE_KEYS.has(str(key)):
			errors.append("%s - %s.\"%s\" does not belong in a language mirror. A mirror carries the words (\"id\", \"text\", \"speaker\", an answer's \"text\"); the pictures, the pacing, \"next\" and the conditions stay in the base script." % [mirror, where, str(key)])
	var entry := {
		"id": str(raw.get("id", "")).strip_edges(),
		"text": "",
		"speaker": str(raw.get("speaker", "")),
		"pauses": [],
		"choices": [],
	}
	if raw.has("text"):
		if typeof(raw["text"]) != TYPE_STRING:
			errors.append("%s - %s.text must be a string." % [mirror, where])
		else:
			var timed := _extract_pauses(str(raw["text"]), mirror, errors, where)
			entry["text"] = timed["text"]
			entry["pauses"] = timed["pauses"]
	if raw.has("speaker") and typeof(raw["speaker"]) != TYPE_STRING:
		errors.append("%s - %s.speaker must be a string." % [mirror, where])
	if raw.has("choices"):
		entry["choices"] = _parse_mirror_choices(raw["choices"], index, mirror, errors)
	return entry


## The answers of one mirrored line: as many as the base script's, in its order,
## carrying their text only.
static func _parse_mirror_choices(value: Variant, index: int, mirror: String, errors: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s - slides[%d].choices must be an array of { \"text\": ... }, one per answer in the base script." % [mirror, index])
		return out
	for i in (value as Array).size():
		var raw: Variant = (value as Array)[i]
		var where := "slides[%d].choices[%d]" % [index, i]
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("%s - %s must be an object with a \"text\"." % [mirror, where])
			continue
		for key in (raw as Dictionary).keys():
			if not MIRROR_CHOICE_KEYS.has(str(key)):
				errors.append("%s - %s.\"%s\" does not belong in a language mirror; an answer's \"next\", \"if\" and \"sfx\" are the base script's." % [mirror, where, str(key)])
		out.append({"text": str((raw as Dictionary).get("text", "")).strip_edges()})
	return out


## Checks a mirror against the script it mirrors, line by line, and merges what
## it carries. A mirror that is out of step is reported and left out rather than
## merged, because merging one would be exactly the bug this is here to prevent.
static func _merge_mirror_lines(slides: Array[Dictionary], lines: Array[Dictionary], mirror: String, base_path: String, code: String, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	for i in lines.size():
		var base: Dictionary = slides[i]
		var line: Dictionary = lines[i]
		var base_id := str(base.get("id", ""))
		var line_id := str(line.get("id", ""))
		if not base_id.is_empty() and line_id != base_id:
			errors.append("%s - slides[%d] is %s, but %s has \"%s\" on that line (%s). A mirror keeps the same lines in the same order, so a language switch cannot move the story." % [mirror, i, ("\"%s\"" % line_id) if not line_id.is_empty() else "unnamed", base_path, base_id, code])
			return
		if line_id.is_empty() and not base_id.is_empty():
			warnings.append("%s - slides[%d] has no \"id\"; it is matched to \"%s\" by its position." % [mirror, i, base_id])
		var line_choices: Array = line.get("choices", [])
		if not line_choices.is_empty():
			var base_choices: Array = base.get("choices", [])
			if line_choices.size() != base_choices.size():
				errors.append("%s - slides[%d] translates %d answer(s), but %s has %d on that line. The answers line up one for one." % [mirror, i, line_choices.size(), base_path, base_choices.size()])
				return
			for j in line_choices.size():
				_store_choice(base_choices[j], code, line_choices[j])
		_store_line(base, code, line)


## Puts one translated line on a slide under its language code. A line is
## translated as a whole - its text, who says it, and its own pauses - or not at
## all, in which case the default language's line stands.
static func _store_line(slide: Dictionary, code: String, line: Dictionary) -> void:
	var text := str(line.get("text", ""))
	if text.is_empty():
		return
	var texts: Dictionary = slide.get("texts", {})
	texts[code] = text
	slide["texts"] = texts
	var speakers: Dictionary = slide.get("speakers", {})
	speakers[code] = str(line.get("speaker", ""))
	slide["speakers"] = speakers
	var sets: Dictionary = slide.get("pause_sets", {})
	sets[code] = line.get("pauses", [])
	slide["pause_sets"] = sets


static func _store_choice(choice: Dictionary, code: String, line: Dictionary) -> void:
	var text := str(line.get("text", ""))
	if text.is_empty():
		return
	var texts: Dictionary = choice.get("texts", {})
	texts[code] = text
	choice["texts"] = texts


## A string that may be written once for everybody, or once for each language:
## `"title": "..."` or `"title": { "id": "...", "en": "..." }`. Returns
## `{ "default": String, "by_language": { code: String } }`, where "default" is
## the default language's - falling back to the first language written, so a
## half-filled table still puts something on screen.
static func _localized_string(value: Variant, codes: PackedStringArray, default_language: String, source_path: String, where: String, errors: PackedStringArray) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		var plain := "" if value == null else str(value)
		var only := {}
		if not codes.is_empty():
			only[default_language] = plain
		return {"default": plain, "by_language": only}
	var by_language := {}
	for key in (value as Dictionary).keys():
		var code := str(key).strip_edges().to_lower()
		if not codes.has(code):
			if codes.is_empty():
				errors.append("%s - %s is written per language (\"%s\"), but the story declares no \"languages\" block." % [source_path, where, code])
			else:
				errors.append("%s - %s has a \"%s\" string, but \"%s\" is not one of the declared languages (%s)." % [source_path, where, code, code, ", ".join(codes)])
			continue
		by_language[code] = str((value as Dictionary)[key])
	var fallback := str(by_language.get(default_language, ""))
	if fallback.is_empty() and not by_language.is_empty():
		fallback = str(by_language.values()[0])
	return {"default": fallback, "by_language": by_language}


static func _merge_assets(target: Dictionary, sources: Array[Dictionary], warnings: PackedStringArray) -> void:
	for assets in sources:
		for group in assets.keys():
			if typeof(assets[group]) != TYPE_DICTIONARY:
				continue
			if not target.has(group):
				target[group] = {}
			for key in (assets[group] as Dictionary).keys():
				if target[group].has(key):
					warnings.append("assets.%s already defines \"%s\"; the first definition wins." % [group, key])
					continue
				target[group][key] = assets[group][key]


## Reads the top-level `gallery` block: the CG pictures a player can collect, each
## with its picture, a title, and the progress that unlocks it. Images resolve
## like backgrounds - an `assets.cg` / `assets.backgrounds` / `assets.characters`
## alias, or a path - and the goals are checked in [method _finalize_gallery],
## once every slide id is known.
static func _parse_gallery(data: Dictionary, assets: Dictionary, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, languages: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = data.get("gallery")
	if raw == null:
		return out
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s - \"gallery\" must be an array of CG entries." % source_path)
		return out

	# Every alias a gallery image may name, from any of the picture groups.
	var aliases := {}
	for group in GALLERY_ALIAS_GROUPS:
		var table := _dict_of(assets.get(group))
		for key in table.keys():
			if not aliases.has(key):
				aliases[key] = table[key]
	var base_dir := source_path.get_base_dir()

	for i in (raw as Array).size():
		var where := "%s gallery[%d]" % [source_path, i]
		var value: Variant = (raw as Array)[i]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s - a gallery entry must be an object." % where)
			continue
		var entry: Dictionary = value
		_report_unknown_keys(entry, GALLERY_KEYS, where, warnings)
		var id := str(entry.get("id", "")).strip_edges()
		if id.is_empty():
			errors.append("%s - a gallery entry needs an \"id\"." % where)
			continue
		if not entry.has("image"):
			errors.append("%s - \"%s\" needs an \"image\": a path, or an assets.cg / backgrounds / characters alias." % [where, id])
		# A title and a caption may be written once, or once per language.
		var codes: PackedStringArray = languages.get("codes", PackedStringArray())
		var default_language: String = languages.get("default", "")
		var title := _localized_string(entry.get("title", id), codes, default_language, where, "title", errors)
		var caption := _localized_string(entry.get("caption", ""), codes, default_language, where, "caption", errors)
		var cg := {
			"id": id,
			"title": str(title["default"]),
			"caption": str(caption["default"]),
			"image": _resolve_asset(entry.get("image", ""), aliases, base_dir, IMAGE_EXTENSIONS, errors, "%s \"%s\".image" % [where, id]),
			"goal": _parse_cg_goal(entry.get("unlock"), "%s \"%s\"" % [where, id], errors, warnings),
		}
		if not (title["by_language"] as Dictionary).is_empty():
			cg["titles"] = title["by_language"]
		if not (caption["by_language"] as Dictionary).is_empty():
			cg["captions"] = caption["by_language"]
		out.append(cg)
	return out


## One `unlock` goal: a slide id, or `{ "seen": "id", "index": 12 }` (both,
## when both are written). Returns `{ seen, index }`, with "" / -1 for the parts
## that were not asked for.
static func _parse_cg_goal(value: Variant, where: String, errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	var goal := {"seen": "", "index": -1}
	if value == null:
		errors.append("%s - needs an \"unlock\" goal: a slide id, or { \"seen\": \"id\", \"index\": 12 }." % where)
		return goal
	if typeof(value) == TYPE_STRING:
		goal["seen"] = str(value).strip_edges()
		if str(goal["seen"]).is_empty():
			errors.append("%s - \"unlock\" is empty; name the slide the player has to reach." % where)
		return goal
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s - \"unlock\" must be a slide id or an object with \"seen\" / \"index\"." % where)
		return goal
	var spec: Dictionary = value
	_report_unknown_keys(spec, UNLOCK_KEYS, where + ".unlock", warnings)
	if spec.has("seen"):
		goal["seen"] = str(spec["seen"]).strip_edges()
		if str(goal["seen"]).is_empty():
			errors.append("%s - \"unlock.seen\" is empty; name the slide the player has to reach." % where)
	if spec.has("index"):
		if typeof(spec["index"]) != TYPE_INT and typeof(spec["index"]) != TYPE_FLOAT:
			errors.append("%s - \"unlock.index\" must be a whole slide index." % where)
		elif float(spec["index"]) != floorf(float(spec["index"])):
			errors.append("%s - \"unlock.index\" must be a whole number, not %s." % [where, str(spec["index"])])
		else:
			goal["index"] = int(spec["index"])
	if str(goal["seen"]).is_empty() and int(goal["index"]) < 0:
		errors.append("%s - \"unlock\" needs a \"seen\" id, an \"index\", or both." % where)
	return goal


# --- one file ----------------------------------------------------------------

## Reads structure and text out of one story file. Asset paths, slide ids and
## "next" targets stay raw; they are resolved once every file is merged.
static func _parse_slides_and_settings(data: Dictionary, source_path: String, errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	var settings := _dict_of(data.get("settings"))
	var assets := _dict_of(data.get("assets"))
	_report_unknown_keys(settings, SETTINGS_KEYS, source_path + " settings", warnings)
	_report_unknown_keys(assets, ASSET_KEYS, source_path + " assets", warnings)
	var variables := _parse_variables(data, settings, source_path, errors, warnings)

	var raw_slides: Variant = data.get("slides")
	var slides: Array[Dictionary] = []
	if typeof(raw_slides) != TYPE_ARRAY:
		errors.append("%s - \"slides\" must be an array." % source_path)
		return {"settings": settings, "assets": assets, "slides": slides, "variables": variables}
	if (raw_slides as Array).is_empty():
		errors.append("%s - \"slides\" is empty, there is nothing to play." % source_path)
		return {"settings": settings, "assets": assets, "slides": slides, "variables": variables}

	for i in (raw_slides as Array).size():
		var raw: Variant = (raw_slides as Array)[i]
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("%s - slides[%d] must be an object." % [source_path, i])
			continue
		slides.append(_parse_slide(raw, i, source_path, errors, warnings))
	return {"settings": settings, "assets": assets, "slides": slides, "variables": variables}


## Reads the story's `variables` block. It may sit at the top level of a story
## file or inside `settings`; a top level block wins, key by key.
static func _parse_variables(data: Dictionary, settings: Dictionary, source_path: String, errors: PackedStringArray, _warnings: PackedStringArray) -> Dictionary:
	var variables := {}
	var blocks := [
		{"where": source_path + " settings.variables", "value": settings.get("variables")},
		{"where": source_path + " variables", "value": data.get("variables")},
	]
	for block in blocks:
		var value: Variant = block["value"]
		if value == null:
			continue
		var where := str(block["where"])
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s - must be an object of name: value pairs." % where)
			continue
		for key in (value as Dictionary).keys():
			var name := str(key)
			# The name becomes an expression input, so it has to be a plain
			# identifier nothing else in the expression language already uses.
			var problem := StoryVars.name_problem(name)
			if not problem.is_empty():
				errors.append("%s - %s" % [where, problem])
				continue
			variables[name] = value[key]
	return variables



## Checks every gallery goal against the finished story: a `seen` id has to be a
## slide id (a typo would otherwise mean a CG that can never unlock), an `index`
## has to be inside the story, and no two entries may share an id. The entries
## are then attached to the story.
static func _finalize_gallery(story: Story, entries: Array[Dictionary], errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var ids := {}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var id := str(entry.get("id", ""))
		var where := "%s gallery[%d] \"%s\"" % [story.source_path, i, id]
		if ids.has(id):
			errors.append("%s - duplicate gallery id \"%s\" (also gallery[%d])." % [where, id, ids[id]])
		else:
			ids[id] = i
		if story.id_to_index.has(id):
			warnings.append("%s - the gallery id \"%s\" is also a slide id. They are kept apart - a condition never sees the CG and the gallery never jumps to the slide - but renaming one reads more clearly." % [where, id])

		var goal: Dictionary = entry.get("goal", {})
		var seen_id := str(goal.get("seen", ""))
		if not seen_id.is_empty() and not story.id_to_index.has(seen_id):
			errors.append("%s - \"%s\" is not a slide id in this story, so the condition could never be met; check the spelling, or use \"index\"." % [where, seen_id])
		var want_index := int(goal.get("index", -1))
		if want_index >= story.slides.size():
			errors.append("%s - \"unlock.index\" %d is past the end of the story (%d slides, indexes 0..%d)." % [where, want_index, story.slides.size(), story.slides.size() - 1])
	story.gallery = entries


static func _apply_settings(story: Story, settings: Dictionary, errors: PackedStringArray) -> void:
	# The title may be written once, or once per language.
	var title := _localized_string(settings.get("title", "Untitled"), story.language_codes(), story.default_language, story.source_path, "settings.title", errors)
	story.title = str(title["default"])
	story.titles = title["by_language"]
	story.background_color = _color_of(settings.get("background_color"), Color(0.06, 0.06, 0.09))
	story.default_text_speed = _speed_of(settings.get("default_text_speed"), DEFAULT_TEXT_SPEED)
	story.default_fade = _speed_of(settings.get("default_fade"), DEFAULT_FADE)
	story.music_volume = clampf(_float_of(settings.get("music_volume"), DEFAULT_MUSIC_VOLUME), 0.0, 1.0)
	story.sound_volume = clampf(_float_of(settings.get("sound_volume"), DEFAULT_SOUND_VOLUME), 0.0, 1.0)


static func _finalize(story: Story, slides: Array[Dictionary], settings: Dictionary, variables: Dictionary, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	story.slides = slides

	# Variables first: every condition below is compiled against their names, so
	# an expression can never reach anything that is not a declared variable.
	story.variables = variables
	var names := PackedStringArray()
	for key in variables.keys():
		names.append(str(key))
	names.sort()
	story.variable_names = names

	# Slide ids next, so "next", a "branch" and a choice can point at them in any
	# order we like.
	for i in slides.size():
		var id := str(slides[i].get("id", ""))
		if id.is_empty():
			continue
		if story.id_to_index.has(id):
			errors.append("%s - duplicate slide id \"%s\" (slides[%d] and slides[%d])." % [slides[i].get("source", "?"), id, story.id_to_index[id], i])
			continue
		story.id_to_index[id] = i

	# Compile the conditions and the computed writes (ids are known, so a slide id
	# used where a variable belongs can be named in the error).
	_compile_expressions(story, slides, errors, warnings)

	# Then turn every "next" into a real index (-1 = end of story).
	for i in slides.size():
		var slide := slides[i]
		if slide.has("next"):
			slide["next_index"] = _resolve_target(slide["next"], story, str(slide.get("source", "?")), "slides[%d].next" % i, errors)
		else:
			slide["next_index"] = i + 1 if i + 1 < slides.size() else -1
		if slide.has("choices"):
			var choices: Array = slide["choices"]
			for j in choices.size():
				var choice: Dictionary = choices[j]
				if not choice.has("next_raw"):
					continue
				choice["next_index"] = _resolve_target(choice["next_raw"], story, str(slide.get("source", "?")), "slides[%d].choices[%d].next" % [i, j], errors)
		if slide.has("branch"):
			var branch: Array = slide["branch"]
			for j in branch.size():
				var entry: Dictionary = branch[j]
				entry["next_index"] = _resolve_target(entry["next_raw"], story, str(slide.get("source", "?")), "slides[%d].branch[%d].next" % [i, j], errors)

	# Where does the story start?
	story.start_index = 0
	if settings.has("start"):
		var start_index := _resolve_target(settings["start"], story, story.source_path, "settings.start", errors)
		if start_index >= 0:
			story.start_index = start_index

	# A name that is also a slide id is legal - the two namespaces never meet -
	# but say so once, so it is a choice rather than a surprise.
	for name in story.variable_names:
		if story.id_to_index.has(name):
			warnings.append("%s - \"%s\" is both a variable and a slide id. They are kept apart, so \"next\": \"%s\" still means the slide and a condition reading %s still means the variable; renaming one reads more clearly." % [story.source_path, name, name, name])


## Compiles every `"if"`, every `"branch"` entry's `"if"`, every choice's `"if"`
## and every `{ "expr": ... }` write in the story, against the declared variable
## names. Each one becomes a real [Expression] living on the slide, so nothing is
## re-parsed while the story plays.
static func _compile_expressions(story: Story, slides: Array[Dictionary], errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var inputs := StoryVars.input_names(story.variable_names)
	# Conditions are compiled against the story's own starting values, so a
	# name nothing can resolve is caught here rather than mid-story.
	var probe := StoryVars.new(story.variables, story.variable_names)
	for i in slides.size():
		var slide := slides[i]
		var source := str(slide.get("source", "?"))
		var where := "slides[%d]" % i

		if slide.has("if_raw"):
			# The text is kept beside the compiled expression, so tools and
			# describe_slide() can show the condition a player is up against.
			slide["if_text"] = str(slide["if_raw"])
			var condition := _compile_condition(str(slide["if_raw"]), inputs, probe, source, where + ".if", story, errors, warnings)
			if condition != null:
				slide["if_expr"] = condition
			slide.erase("if_raw")

		if slide.has("sets_raw"):
			var sets: Array = []
			for raw in (slide["sets_raw"] as Array):
				var name := str(raw["name"])
				var slot_where := "%s.set.%s" % [where, name]
				if not story.variables.has(name):
					errors.append("%s - %s writes \"%s\", which is not a declared variable.%s Declared variables: %s." % [source, slot_where, name, _slide_id_note(name, story), story.variable_names_string()])
					continue
				if raw.has("expr_text"):
					var value_expression := _compile_condition(str(raw["expr_text"]), inputs, probe, source, slot_where, story, errors, warnings)
					if value_expression != null:
						sets.append({"name": name, "expr": value_expression})
				else:
					sets.append({"name": name, "value": raw["value"]})
			slide["sets"] = sets
			slide.erase("sets_raw")

		if slide.has("branch_raw"):
			var branch: Array = []
			var has_default := false
			for j in (slide["branch_raw"] as Array).size():
				var raw: Dictionary = slide["branch_raw"][j]
				var entry := {"next_raw": raw["next_raw"]}
				if raw.has("if_raw"):
					entry["if_text"] = str(raw["if_raw"])
					var condition := _compile_condition(str(raw["if_raw"]), inputs, probe, source, "%s.branch[%d].if" % [where, j], story, errors, warnings)
					if condition != null:
						entry["if_expr"] = condition
				else:
					has_default = true
				branch.append(entry)
			if not has_default:
				warnings.append("%s - %s.branch has no entry without an \"if\", so nothing may match and the slide would fall back to its own \"next\". Add a last entry without an \"if\" to make the default answer explicit." % [source, where])
			slide["branch"] = branch
			slide.erase("branch_raw")

		if slide.has("choices"):
			for j in (slide["choices"] as Array).size():
				var choice: Dictionary = slide["choices"][j]
				if not choice.has("if_raw"):
					continue
				choice["if_text"] = str(choice["if_raw"])
				var condition := _compile_condition(str(choice["if_raw"]), inputs, probe, source, "%s.choices[%d].if" % [where, j], story, errors, warnings)
				if condition != null:
					choice["if_expr"] = condition
				choice.erase("if_raw")


## Parses one condition with Godot's [Expression] class. Returns null (and adds
## an error) when it does not compile, or when it names something that is not a
## variable; when the offending word is a slide id the message says so, since
## that is the one mistake this can invite.
static func _compile_condition(text: String, inputs: PackedStringArray, probe: StoryVars, source_path: String, where: String, story: Story, errors: PackedStringArray, warnings: PackedStringArray) -> Expression:
	var expression := Expression.new()
	if expression.parse(text, inputs) != OK:
		errors.append("%s - %s: \"%s\" is not a valid condition - %s%s" % [
			source_path, where, text, expression.get_error_text().trim_suffix("."), _slide_id_note_from_text(text, story)])
		return null

	# Godot's Expression does not check names while it parses: a name it cannot
	# resolve is taken as a property of `self`, so it only complains when it runs
	# ("self can't be used because instance is null"). Running it once against the
	# story's starting values is therefore the way to catch a typo or a slide id
	# used where a variable belongs. Any other failure may be about these
	# particular values (a division by zero, say), so it is only a warning.
	var problem := probe.probe(expression)
	if problem.is_empty():
		return expression
	var lower := problem.to_lower()
	if lower.contains("identifier") or lower.contains("instance is null"):
		errors.append("%s - %s: \"%s\" is not a valid condition - it names something that is not a variable.%s" % [source_path, where, text, _not_a_variable_note(text, story)])
		return null
	warnings.append("%s - %s: \"%s\" does not work out against the story's starting values - %s It may still be right once the story runs." % [source_path, where, text, problem])
	return expression


## Explains what a condition is allowed to read, naming the one word that is a
## slide id when there is one - the mistake this invites most.
static func _not_a_variable_note(text: String, story: Story) -> String:
	for token in _identifier_tokens(text):
		if story.id_to_index.has(token):
			return " (\"%s\" is a slide id, not a variable; a condition only reads the story's variables.)" % token
	var suspects := _unknown_tokens(text, story)
	if suspects.size() == 1:
		return " (\"%s\" is not a variable; the story declares: %s.)" % [suspects[0], story.variable_names_string()]
	return " The story declares: %s." % story.variable_names_string()


## The words in a condition that are neither a declared variable nor something
## the expression language already knows, so a message can name the likely one.
static func _unknown_tokens(text: String, story: Story) -> PackedStringArray:
	var out := PackedStringArray()
	for token in _identifier_tokens(text):
		if story.variables.has(token) or StoryVars.RESERVED_NAMES.has(token):
			continue
		out.append(token)
	return out


## " (\"stairs\" is a slide id, not a variable ...)" when [param name] is one.
static func _slide_id_note(name: String, story: Story) -> String:
	if story.id_to_index.has(name):
		return " (\"%s\" is a slide id, not a variable; use \"next\" or \"branch\" to reach a slide.)" % name
	return ""


## The same note, for a condition that failed to compile: any slide id the text
## mentions is worth pointing out.
static func _slide_id_note_from_text(text: String, story: Story) -> String:
	for token in _identifier_tokens(text):
		if story.id_to_index.has(token):
			return " (\"%s\" is a slide id, not a variable; a condition only reads the story's variables.)" % token
	return ""


static func _identifier_tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var regex := RegEx.new()
	if regex.compile("[A-Za-z_][A-Za-z0-9_]*") != OK:
		return out
	for found in regex.search_all(text):
		out.append(found.get_string())
	return out


# --- slide -------------------------------------------------------------------

static func _parse_slide(raw: Dictionary, index: int, source_path: String, errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	var where := "slides[%d]" % index
	_report_unknown_keys(raw, SLIDE_KEYS, source_path + " " + where, warnings)

	if raw.has("text") and typeof(raw["text"]) != TYPE_STRING:
		errors.append("%s - %s.text must be a string." % [source_path, where])

	var slide := {
		"index": index,
		"source": source_path,
		"id": str(raw.get("id", "")).strip_edges(),
		"speaker": str(raw.get("speaker", "")),
		"text": str(raw.get("text", "")),
		# -1 means "use the story default".
		"fade": -1.0,
		"text_speed": -1.0,
		"wait": 0.0,
		"auto_advance": false,
	}

	# {w=0.5} (or a bare {w}) inside the line becomes a pause in the typewriter. It
	# is taken out of the text, so the history, the save preview and the reading
	# pace all see the clean line.
	var timed := _extract_pauses(str(slide["text"]), source_path, errors, where)
	slide["text"] = timed["text"]
	if not (timed["pauses"] as Array).is_empty():
		slide["pauses"] = timed["pauses"]

	if raw.has("background"):
		slide["background_raw"] = str(raw["background"])
	if raw.has("characters"):
		slide["characters"] = _parse_characters(raw["characters"], source_path, errors, warnings, where + ".characters")
	if raw.has("show"):
		var showing := _parse_show(raw["show"], source_path, errors, warnings, where + ".show")
		if not showing.is_empty():
			slide["show"] = showing
	if raw.has("hide"):
		var hiding := _parse_hide(raw["hide"], source_path, errors, warnings, where + ".hide")
		if not hiding.is_empty():
			slide["hide"] = hiding
	if raw.has("with"):
		var with_effect := _parse_stage_effect(raw["with"], source_path, errors, where + ".with")
		if not with_effect.is_empty():
			slide["with"] = with_effect
	if raw.has("choices"):
		slide["choices"] = _parse_choices(raw["choices"], source_path, errors, warnings, where + ".choices")
	if raw.has("set"):
		var sets := _parse_set(raw["set"], source_path, errors, warnings, where + ".set")
		if not sets.is_empty():
			slide["sets_raw"] = sets
	if raw.has("if"):
		var condition := _parse_condition(raw["if"], source_path, errors, where + ".if")
		if not condition.is_empty():
			slide["if_raw"] = condition
	if raw.has("branch"):
		var branch := _parse_branch(raw["branch"], source_path, errors, warnings, where + ".branch")
		if not branch.is_empty():
			slide["branch_raw"] = branch
	if raw.has("sfx"):
		slide["sfx_raw"] = _string_list(raw["sfx"], source_path, errors, where + ".sfx")
	if raw.has("portrait"):
		slide["portrait_raw"] = "" if raw["portrait"] == null else str(raw["portrait"])
	if raw.has("transition"):
		var transition := _parse_transition(raw["transition"], source_path, errors, where + ".transition")
		if not transition.is_empty():
			slide["transition"] = transition
	if raw.has("effects"):
		var effects := _parse_effects(raw["effects"], source_path, errors, warnings, where + ".effects")
		if not effects.is_empty():
			slide["effects"] = effects
	if raw.has("bgm"):
		var music: Variant = raw["bgm"]
		if music == null or (typeof(music) == TYPE_STRING and MUSIC_STOP_WORDS.has(str(music).strip_edges().to_lower())):
			# "bgm": null / "stop" -> fade the music out on this slide.
			slide["bgm"] = ""
		else:
			slide["bgm_raw"] = str(music)
	# Kept verbatim: it becomes a real slide index once every slide id is known.
	if raw.has("next"):
		slide["next"] = raw["next"]
	if raw.has("fade"):
		slide["fade"] = maxf(0.0, _float_of(raw["fade"], -1.0))
	if raw.has("text_speed"):
		slide["text_speed"] = maxf(0.0, _float_of(raw["text_speed"], -1.0))

	var wait := maxf(0.0, _float_of(raw.get("wait"), 0.0))
	slide["wait"] = wait
	# A slide with a "wait" (or "auto") moves on by itself instead of blinking
	# for a click. Slides without any text default to auto as well. A slide with
	# choices never auto-advances, it is waiting for the player.
	var has_choices := slide.has("choices") and not (slide["choices"] as Array).is_empty()
	slide["auto_advance"] = (bool(raw.get("auto", false)) or wait > 0.0 or str(slide["text"]).is_empty()) and not has_choices
	return slide


static func _parse_characters(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var list: Array = []
	if typeof(value) == TYPE_STRING:
		# Shorthand: "characters": "mika"
		list = [value]
	elif typeof(value) == TYPE_ARRAY:
		list = value
	else:
		errors.append("%s - %s must be an array of characters (or a single character name)." % [source_path, where])
		return entries

	for i in list.size():
		var entry := _parse_character(list[i], source_path, errors, warnings, "%s[%d]" % [where, i])
		if entry.is_empty():
			continue
		_auto_position(entry, i, list.size())
		entries.append(entry)
	return entries


## Parses a slide's "show": the same shapes as "characters" (a name, an object,
## or an array of those), plus a per-entry "effect" / "duration" for the way the
## character comes in. Unlike "characters" this adds to the line-up instead of
## replacing it.
static func _parse_show(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var list: Array = []
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_DICTIONARY:
		list = [value]
	elif typeof(value) == TYPE_ARRAY:
		list = value
	else:
		errors.append("%s - %s must be a character name, an object, or an array of those." % [source_path, where])
		return entries

	for i in list.size():
		var item_where := "%s[%d]" % [where, i]
		var raw := {}
		if typeof(list[i]) == TYPE_STRING:
			raw = {"id": list[i], "image": list[i]}
		elif typeof(list[i]) == TYPE_DICTIONARY:
			raw = (list[i] as Dictionary).duplicate()
		else:
			errors.append("%s - %s must be a character name or an object like { \"id\": \"mika\", \"position\": \"right\" }." % [source_path, item_where])
			continue
		var effect := _parse_stage_effect(raw.get("effect"), source_path, errors, item_where + ".effect")
		var duration := _float_of(raw.get("duration"), -1.0)
		for key in SHOW_EXTRA_KEYS:
			raw.erase(key)
		var entry := _parse_character(raw, source_path, errors, warnings, item_where)
		if entry.is_empty():
			continue
		entry["effect"] = effect
		entry["duration"] = duration
		_auto_position(entry, i, list.size())
		entries.append(entry)
	return entries


## Parses a slide's "hide": a character name (or an object with "id" and an
## optional "effect" / "duration"), or an array of those.
static func _parse_hide(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var list: Array = []
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_DICTIONARY:
		list = [value]
	elif typeof(value) == TYPE_ARRAY:
		list = value
	else:
		errors.append("%s - %s must be a character name, or an array of names." % [source_path, where])
		return entries

	for i in list.size():
		var item_where := "%s[%d]" % [where, i]
		var entry := {"id": "", "effect": "", "duration": -1.0}
		if typeof(list[i]) == TYPE_STRING:
			entry["id"] = str(list[i]).strip_edges()
		elif typeof(list[i]) == TYPE_DICTIONARY:
			var raw: Dictionary = list[i]
			_report_unknown_keys(raw, HIDE_KEYS, source_path + " " + item_where, warnings)
			entry["id"] = str(raw.get("id", raw.get("image", ""))).strip_edges()
			entry["effect"] = _parse_stage_effect(raw.get("effect"), source_path, errors, item_where + ".effect")
			entry["duration"] = _float_of(raw.get("duration"), -1.0)
		else:
			errors.append("%s - %s must be a character name or an object like { \"id\": \"ren\", \"effect\": \"dissolve\" }." % [source_path, item_where])
			continue
		if str(entry["id"]).is_empty():
			errors.append("%s - %s needs a character name." % [source_path, item_where])
			continue
		entries.append(entry)
	return entries


## Reads a "with" or an entry's "effect". Returns "" when it was not set, so the
## caller can fall back to the slide's "with" and then to "dissolve".
static func _parse_stage_effect(value: Variant, source_path: String, errors: PackedStringArray, where: String) -> String:
	if value == null:
		return ""
	var effect := str(value).strip_edges().to_lower()
	if effect.is_empty():
		return ""
	if not STAGE_EFFECTS.has(effect):
		errors.append("%s - \"%s\" is not a known transition. Use one of: %s." % [where, effect, ", ".join(PackedStringArray(STAGE_EFFECTS))])
		return ""
	return effect


## Spreads the characters that did not ask for a position evenly across the
## screen.
static func _auto_position(entry: Dictionary, slot: int, total: int) -> void:
	if entry["horizontal"] == "auto" and float(entry["x"]) < 0.0:
		entry["x"] = float(slot + 1) / float(total + 1)


static func _parse_character(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Dictionary:
	var raw: Dictionary = {}
	if typeof(value) == TYPE_STRING:
		# Shorthand: { "characters": ["mika", "ren"] }
		var name := (value as String).strip_edges()
		raw = {"id": name, "image": name}
	elif typeof(value) == TYPE_DICTIONARY:
		raw = value
	else:
		errors.append("%s - %s must be an object like {\"image\": \"mika\", \"position\": \"left\"} or a character name." % [source_path, where])
		return {}

	_report_unknown_keys(raw, CHARACTER_KEYS, where, warnings)

	var image_raw: Variant = raw.get("image", raw.get("id", ""))
	# A character shows up in the text box as itself unless it says otherwise.
	var portrait_raw := str(image_raw)
	if raw.has("portrait"):
		portrait_raw = "" if raw["portrait"] == null else str(raw["portrait"])

	var entry := {
		"id": str(raw.get("id", image_raw)).strip_edges(),
		"image_raw": str(image_raw),
		"portrait_raw": portrait_raw,
		"horizontal": "auto",
		"vertical": "bottom",
		# Negative x / y means "not set", the caller works it out.
		"x": -1.0,
		"y": -1.0,
		"scale": maxf(0.01, _float_of(raw.get("scale"), 1.0)),
		"flip": bool(raw.get("flip", false)),
		"offset_y": _float_of(raw.get("offset_y"), 0.0),
		"tint": _color_of(raw.get("tint"), Color.WHITE),
	}

	# "position" is either a single name or a pair: "left", "middle",
	# "bottom-right", "top-center"...
	var position := str(raw.get("position", "auto")).strip_edges().to_lower()
	for token in position.split("-", false):
		if HORIZONTAL_POSITIONS.has(token):
			entry["horizontal"] = token
		elif VERTICAL_POSITIONS.has(token):
			entry["vertical"] = token
		else:
			errors.append("%s - %s.position \"%s\" is not one of: %s, or a pair like \"bottom-left\"." % [source_path, where, token, ", ".join(PackedStringArray(HORIZONTAL_POSITIONS + VERTICAL_POSITIONS))])
			entry["horizontal"] = "auto"
			break

	var vertical := str(raw.get("vertical", "")).strip_edges().to_lower()
	if not vertical.is_empty():
		if VERTICAL_POSITIONS.has(vertical):
			entry["vertical"] = vertical
		else:
			errors.append("%s - %s.vertical \"%s\" is not one of: %s." % [source_path, where, vertical, ", ".join(PackedStringArray(VERTICAL_POSITIONS))])

	if raw.has("x"):
		entry["x"] = clampf(_float_of(raw["x"], 0.5), 0.0, 1.0)
	elif entry["horizontal"] != "auto":
		entry["x"] = HORIZONTAL_RATIOS[entry["horizontal"]]
	if raw.has("y"):
		# Where the bottom edge of the picture sits, 0 = top, 1 = bottom.
		entry["y"] = clampf(_float_of(raw["y"], 1.0), 0.0, 1.0)
	elif entry["vertical"] != "bottom":
		entry["y"] = VERTICAL_RATIOS[entry["vertical"]]
	return entry


static func _parse_choices(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s - %s must be an array of { \"text\": ..., \"next\": ... } objects." % [source_path, where])
		return choices

	var list: Array = value
	for i in list.size():
		var entry_where := "%s[%d]" % [where, i]
		if typeof(list[i]) != TYPE_DICTIONARY:
			errors.append("%s - %s must be an object with \"text\" and \"next\"." % [source_path, entry_where])
			continue
		var raw: Dictionary = list[i]
		_report_unknown_keys(raw, CHOICE_KEYS, entry_where, warnings)

		var text := str(raw.get("text", "")).strip_edges()
		if text.is_empty():
			errors.append("%s - %s.text is required." % [source_path, entry_where])
		var choice := {"text": text}
		if raw.has("next"):
			choice["next_raw"] = raw["next"]
		else:
			errors.append("%s - %s needs a \"next\" (a slide id, an index, or null for the end)." % [source_path, entry_where])
		if raw.has("if"):
			var condition := _parse_condition(raw["if"], source_path, errors, entry_where + ".if")
			if not condition.is_empty():
				choice["if_raw"] = condition
		if raw.has("sfx"):
			choice["sfx_raw"] = str(raw["sfx"])
		choices.append(choice)
	return choices


## A slide's `"if"`, a `"branch"` entry's `"if"` and a choice's `"if"` are all
## the same thing: an [Expression] string read against the story's variables.
static func _parse_condition(value: Variant, source_path: String, errors: PackedStringArray, where: String) -> String:
	if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
		errors.append("%s - %s must be a non-empty condition string, like \"affection >= 3 and met_mika\"." % [source_path, where])
		return ""
	return str(value).strip_edges()


## A slide's `"set"`: every key is a declared variable, every value is either a
## plain JSON value or `{ "expr": "..." }` to work one out from the current
## state. Keeping the computed form behind its own key means a string value is
## always a string, never an expression by accident.
static func _parse_set(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s - %s must be an object of name: value pairs, like { \"affection\": 3 } or { \"affection\": { \"expr\": \"affection + 1\" } }." % [source_path, where])
		return out
	var raw: Dictionary = value
	for key in raw.keys():
		var name := str(key)
		var item: Variant = raw[key]
		var entry := {"name": name}
		if typeof(item) == TYPE_DICTIONARY:
			var computed: Dictionary = item
			_report_unknown_keys(computed, SET_VALUE_KEYS, "%s %s.%s" % [source_path, where, name], warnings)
			var text := str(computed.get("expr", "")).strip_edges()
			if text.is_empty():
				errors.append("%s - %s.%s must be a plain value or { \"expr\": \"...\" } with a non-empty expression." % [source_path, where, name])
				continue
			entry["expr_text"] = text
		else:
			entry["value"] = item
		out.append(entry)
	return out


## A slide's `"branch"`: the first entry whose `"if"` holds wins, and an entry
## with no `"if"` is the default. It sits beside `"next"` rather than inside it,
## so `"next"` keeps meaning exactly one thing - a slide id or an index.
static func _parse_branch(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s - %s must be an array of { \"if\": \"...\", \"next\": ... } objects." % [source_path, where])
		return out
	var list: Array = value
	for i in list.size():
		var entry_where := "%s[%d]" % [where, i]
		if typeof(list[i]) != TYPE_DICTIONARY:
			errors.append("%s - %s must be an object with a \"next\"." % [source_path, entry_where])
			continue
		var raw: Dictionary = list[i]
		_report_unknown_keys(raw, BRANCH_KEYS, "%s %s" % [source_path, entry_where], warnings)
		if not raw.has("next"):
			errors.append("%s - %s needs a \"next\" (a slide id, an index, or null for the end)." % [source_path, entry_where])
			continue
		var entry := {"next_raw": raw["next"]}
		if raw.has("if"):
			var condition := _parse_condition(raw["if"], source_path, errors, entry_where + ".if")
			if not condition.is_empty():
				entry["if_raw"] = condition
		out.append(entry)
	return out


## "transition": "wipe_left" or { "type": "wipe_left", "duration": 0.8 }.
## A duration below 0 means "use the slide's fade / the story default".
static func _parse_transition(value: Variant, source_path: String, errors: PackedStringArray, where: String) -> Dictionary:
	var raw := {}
	if typeof(value) == TYPE_STRING:
		raw = {"type": value}
	elif typeof(value) == TYPE_DICTIONARY:
		raw = value
	else:
		errors.append("%s - %s must be a transition name or an object like { \"type\": \"wipe_left\", \"duration\": 0.6 }." % [source_path, where])
		return {}

	var type := str(raw.get("type", "")).strip_edges().to_lower()
	if not TRANSITIONS.has(type):
		errors.append("%s - %s has unknown transition \"%s\". Known transitions: %s." % [source_path, where, type, ", ".join(PackedStringArray(TRANSITIONS))])
		return {}
	for key in raw.keys():
		if key != "type" and key != "duration":
			errors.append("%s - %s has unknown key \"%s\" (transition \"%s\" only takes \"type\" and \"duration\")." % [source_path, where, key, type])
	return {"type": type, "duration": _float_of(raw.get("duration"), -1.0)}


## "effects": "shake", { "type": "flash" } or an array of those.
static func _parse_effects(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	var list: Array = []
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_DICTIONARY:
		list = [value]
	elif typeof(value) == TYPE_ARRAY:
		list = value
	else:
		errors.append("%s - %s must be an effect name, an effect object, or an array of those." % [source_path, where])
		return effects

	for i in list.size():
		var effect := _parse_effect(list[i], source_path, errors, warnings, "%s[%d]" % [where, i])
		if not effect.is_empty():
			effects.append(effect)
	return effects


static func _parse_effect(value: Variant, source_path: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> Dictionary:
	var raw := {}
	if typeof(value) == TYPE_STRING:
		raw = {"type": value}
	elif typeof(value) == TYPE_DICTIONARY:
		raw = value
	else:
		errors.append("%s - %s must be an effect name or an object like { \"type\": \"shake\", \"strength\": 20 }." % [source_path, where])
		return {}

	var type := str(raw.get("type", "")).strip_edges().to_lower()
	if not EFFECTS.has(type):
		errors.append("%s - %s has unknown effect \"%s\". Known effects: %s." % [source_path, where, type, ", ".join(PackedStringArray(EFFECTS))])
		return {}
	var known: Array = EFFECT_PARAMS[type]
	for key in raw.keys():
		if str(key) != "type" and not known.has(str(key)):
			warnings.append("%s - %s has unknown key \"%s\" for effect \"%s\" (ignored)." % [source_path, where, key, type])

	# Defaults are the same ones VNPlayer uses when an effect is played by hand.
	var effect := {"type": type, "delay": maxf(0.0, _float_of(raw.get("delay"), 0.0))}
	match type:
		"shake":
			effect["strength"] = _float_of(raw.get("strength"), 18.0)
			effect["duration"] = maxf(0.01, _float_of(raw.get("duration"), 0.45))
		"flash":
			effect["color"] = _color_of(raw.get("color"), Color.WHITE)
			effect["duration"] = maxf(0.01, _float_of(raw.get("duration"), 0.4))
		"zoom":
			effect["from"] = _float_of(raw.get("from"), 1.0)
			effect["to"] = _float_of(raw.get("to"), 1.08)
			effect["duration"] = maxf(0.0, _float_of(raw.get("duration"), 1.0))
		"pulse":
			effect["strength"] = _float_of(raw.get("strength"), 0.04)
			effect["duration"] = maxf(0.01, _float_of(raw.get("duration"), 0.35))
		"reset":
			effect["duration"] = maxf(0.0, _float_of(raw.get("duration"), 0.0))
	return effect


# --- resolving ---------------------------------------------------------------

static func _resolve_slides(slides: Array[Dictionary], assets: Dictionary, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var backgrounds := _dict_of(assets.get("backgrounds"))
	var characters := _dict_of(assets.get("characters"))
	var music := _dict_of(assets.get("music"))
	var sounds := _dict_of(assets.get("sounds"))
	for i in slides.size():
		var slide := slides[i]
		var source := str(slide.get("source", ""))
		var base_dir := source.get_base_dir()
		var where := "%s slides[%d]" % [source, i]
		slide["index"] = i

		# The key is only added when the file had one, so the player can tell "keep
		# the picture that is already on screen" from "background": "" (clear it).
		if slide.has("background_raw"):
			slide["background"] = _resolve_asset(slide["background_raw"], backgrounds, base_dir, IMAGE_EXTENSIONS, errors, where + ".background")
			slide.erase("background_raw")

		if slide.has("characters"):
			_resolve_character_assets(slide["characters"], characters, base_dir, errors, where)
		if slide.has("show"):
			_resolve_character_assets(slide["show"], characters, base_dir, errors, where)

		if slide.has("portrait_raw"):
			var portrait := str(slide["portrait_raw"])
			slide["portrait"] = "" if portrait.is_empty() else _resolve_asset(portrait, characters, base_dir, IMAGE_EXTENSIONS, errors, where + ".portrait")
			slide.erase("portrait_raw")

		if slide.has("bgm_raw"):
			slide["bgm"] = _resolve_audio(slide["bgm_raw"], music, base_dir, errors, warnings, where + ".bgm")
			slide.erase("bgm_raw")

		var resolved_sounds: Array[String] = []
		for raw in (slide.get("sfx_raw", []) as Array):
			resolved_sounds.append(_resolve_audio(raw, sounds, base_dir, errors, warnings, where + ".sfx"))
		slide["sfx"] = resolved_sounds
		slide.erase("sfx_raw")

		if slide.has("choices"):
			for choice in (slide["choices"] as Array[Dictionary]):
				if choice.has("sfx_raw"):
					choice["sfx"] = _resolve_audio(choice["sfx_raw"], sounds, base_dir, errors, warnings, where + ".choice.sfx")
					choice.erase("sfx_raw")


## Fills in the image and portrait of every entry of a character list (the
## entries still carry their raw "..._raw" names from parsing).
static func _resolve_character_assets(entries: Array[Dictionary], characters: Dictionary, base_dir: String, errors: PackedStringArray, where: String) -> void:
	for entry in entries:
		var id := str(entry.get("id", ""))
		entry["image"] = _resolve_asset(entry["image_raw"], characters, base_dir, IMAGE_EXTENSIONS, errors, "%s.character \"%s\".image" % [where, id])
		entry["portrait"] = ""
		if not str(entry["portrait_raw"]).is_empty():
			entry["portrait"] = _resolve_asset(entry["portrait_raw"], characters, base_dir, IMAGE_EXTENSIONS, errors, "%s.character \"%s\".portrait" % [where, id])
		entry.erase("image_raw")
		entry.erase("portrait_raw")


## Turns "room", "bg/room", "res://VN/assets/bg/room.png" or an alias into a
## real, existing resource path.
static func _resolve_asset(value: Variant, aliases: Dictionary, base_dir: String, extensions: Array, errors: PackedStringArray, where: String) -> String:
	var raw := str(value).strip_edges()
	if raw.is_empty():
		return ""

	var candidates := PackedStringArray()
	if raw.begins_with("res://") or raw.begins_with("user://"):
		candidates.append(raw)
	elif aliases.has(raw):
		candidates.append(str(aliases[raw]))
	else:
		var joined := base_dir.path_join(raw) if not base_dir.is_empty() else raw
		candidates.append(joined)
		if not joined.begins_with("res://"):
			candidates.append("res://".path_join(joined))

	# Also try the usual extensions when none was written.
	var attempts := PackedStringArray()
	for candidate in candidates:
		var path := candidate
		if not path.begins_with("res://") and not path.begins_with("user://"):
			path = "res://".path_join(path)
		attempts.append(path)
		if path.get_extension().is_empty():
			for extension in extensions:
				attempts.append(path + extension)
	for attempt in attempts:
		if ResourceLoader.exists(attempt):
			return attempt

	errors.append("%s - asset \"%s\" was not found. Tried: %s" % [where, raw, ", ".join(attempts)])
	return attempts[0] if attempts.size() > 0 else ""


## Resolves an audio asset and adds a warning when the file's contents do not
## match its extension. Godot imports by extension, so an Ogg renamed to ".wav"
## imports as an empty WAV and the slide would play silence instead.
static func _resolve_audio(value: Variant, aliases: Dictionary, base_dir: String, errors: PackedStringArray, warnings: PackedStringArray, where: String) -> String:
	var unsupported := _unsupported_audio_extension(value, aliases)
	if not unsupported.is_empty():
		errors.append("%s - audio \"%s\" uses %s, which Godot cannot import. Use .ogg, .wav or .mp3 instead - convert the file and update the reference." % [where, str(value).strip_edges(), unsupported])
		return ""
	var path := _resolve_asset(value, aliases, base_dir, AUDIO_EXTENSIONS, errors, where)
	var problem := _audio_mismatch(path)
	if not problem.is_empty():
		warnings.append("%s - %s" % [where, problem])
	return path


## Returns the audio extension a reference (or its alias target) names that
## Godot cannot import, or "" when it does not name one.
static func _unsupported_audio_extension(value: Variant, aliases: Dictionary) -> String:
	var raw := str(value).strip_edges()
	var target := str(aliases[raw]) if aliases.has(raw) else raw
	var extension := "." + target.get_extension().to_lower()
	return extension if UNSUPPORTED_AUDIO_EXTENSIONS.has(extension) else ""


## Describes how a file's extension disagrees with the audio it actually
## contains, or "" when they agree (or the format cannot be told).
static func _audio_mismatch(path: String) -> String:
	var extension := "." + path.get_extension().to_lower()
	if not AUDIO_FORMATS.has(extension):
		return ""
	var actual := _sniff_audio_format(path)
	if actual.is_empty() or actual == extension:
		return ""
	return "\"%s\" is named %s but the file contains %s audio. Godot imports by extension, so this would play as silence - rename it to \"%s\"." % [path.get_file(), extension, actual, path.get_basename() + actual]


## Reads the first bytes of an audio file and returns the extension they imply,
## or "" when they are not a format we recognise.
static func _sniff_audio_format(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var head := file.get_buffer(12)
	file.close()
	if head.size() >= 4:
		var magic := head.slice(0, 4).get_string_from_ascii()
		if magic == "OggS":
			return ".ogg"
		if magic == "RIFF" and head.size() >= 12 and head.slice(8, 12).get_string_from_ascii() == "WAVE":
			return ".wav"
	if head.size() >= 3 and head.slice(0, 3).get_string_from_ascii() == "ID3":
		return ".mp3"
	# A bare MPEG frame sync (11 set bits) is an MP3 without an ID3 tag.
	if head.size() >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0:
		return ".mp3"
	return ""


static func _resolve_target(value: Variant, story: Story, source_path: String, where: String, errors: PackedStringArray) -> int:
	if value == null:
		return -1
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var index := int(value)
		if index < 0 or index >= story.slide_count():
			errors.append("%s - %s points at slide %d, but the story has %d slide(s)." % [source_path, where, index, story.slide_count()])
			return -1
		return index
	var key := str(value).strip_edges()
	if key.is_empty() or key == "end":
		return -1
	var found := story.index_of(key)
	if found < 0:
		errors.append("%s - %s refers to unknown slide id \"%s\"." % [source_path, where, key])
		return -1
	return found


static func _resolve_story_path(value: Variant, base_dir: String, errors: PackedStringArray, where: String) -> String:
	var raw := str(value).strip_edges()
	if raw.is_empty():
		errors.append("%s - empty chapter path." % where)
		return ""
	var candidates := PackedStringArray()
	if raw.begins_with("res://") or raw.begins_with("user://"):
		candidates.append(raw)
	else:
		candidates.append(base_dir.path_join(raw) if not base_dir.is_empty() else raw)
		if not raw.begins_with("res://"):
			candidates.append("res://".path_join(raw))
	var attempts := PackedStringArray()
	for candidate in candidates:
		var path := candidate
		if not path.begins_with("res://") and not path.begins_with("user://"):
			path = "res://".path_join(path)
		attempts.append(path)
		if path.get_extension().is_empty():
			for extension in STORY_EXTENSIONS:
				attempts.append(path + extension)
	for attempt in attempts:
		if FileAccess.file_exists(attempt):
			return attempt
	errors.append("%s - chapter file \"%s\" was not found. Tried: %s" % [where, raw, ", ".join(attempts)])
	return ""


# --- helpers -----------------------------------------------------------------

static func _read_story_file(path: String, errors: PackedStringArray) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Story file not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("Story file is empty or could not be read: %s" % path)
		return {}
	return _decode(text, path, errors)


static func _decode(text: String, source_path: String, errors: PackedStringArray) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d - invalid JSON: %s" % [source_path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("%s - the top level of a story file must be a JSON object with a \"slides\" array." % source_path)
		return {}
	return json.data


## Splits "{w=1.5}" (and a bare "{w}", which waits for a click) out of a line.
## Returns { "text": <line without the tags>, "pauses": [ { "at": <how many
## characters are visible when the pause starts>, "time": <seconds, or -1 for a
## click> }, ... ] }. Any other {...} is left alone, since it may be literal.
static func _extract_pauses(text: String, source_path: String, errors: PackedStringArray, where: String) -> Dictionary:
	var out := ""
	var pauses: Array[Dictionary] = []
	# Characters the player will actually draw. BBCode tags do not count, but
	# [lb] / [rb] (literal brackets) do - this is what visible_characters counts.
	var visible := 0
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == "[":
			var close := text.find("]", i)
			if close < 0:
				out += c
				visible += 1
				i += 1
				continue
			var tag := text.substr(i + 1, close - i - 1)
			out += text.substr(i, close - i + 1)
			if tag.to_lower() == "lb" or tag.to_lower() == "rb":
				visible += 1
			i = close + 1
			continue
		if c == "{":
			var brace := text.find("}", i)
			if brace >= 0:
				var parsed := _parse_wait_tag(text.substr(i + 1, brace - i - 1), source_path, errors, where)
				if parsed["known"]:
					var time := float(parsed["time"])
					if not is_zero_approx(time):
						pauses.append({"at": visible, "time": time})
					i = brace + 1
					continue
		out += c
		visible += 1
		i += 1
	return {"text": out, "pauses": pauses}


## Reads the inside of a {...} tag. "known" is false for anything that is not a
## wait, which is then left in the text as an ordinary character.
static func _parse_wait_tag(tag: String, source_path: String, errors: PackedStringArray, where: String) -> Dictionary:
	var lower := tag.strip_edges().to_lower()
	if lower == "w":
		# A bare {w} holds the line until the player clicks.
		return {"known": true, "time": -1.0}
	if lower.begins_with("w="):
		var raw := lower.substr(2).strip_edges()
		if not raw.is_valid_float() or raw.to_float() < 0.0:
			errors.append("%s - %s.text - \"{%s}\" is not a valid pause. Use {w=0.5} in seconds, or a bare {w} to wait for a click." % [source_path, where, tag])
			return {"known": true, "time": 0.0}
		return {"known": true, "time": raw.to_float()}
	return {"known": false, "time": 0.0}


## Accepts a single value or an array of values and returns them as strings.
static func _string_list(value: Variant, source_path: String, errors: PackedStringArray, where: String) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for item in (value as Array):
			if item == null:
				continue
			if typeof(item) != TYPE_STRING:
				errors.append("%s - %s entries must be strings." % [source_path, where])
				continue
			out.append(str(item))
	elif typeof(value) == TYPE_STRING:
		out.append(str(value))
	else:
		errors.append("%s - %s must be a string or an array of strings." % [source_path, where])
	return out


static func _report_unknown_keys(source: Dictionary, known: Array, where: String, warnings: PackedStringArray) -> void:
	for key in source.keys():
		if not known.has(str(key)):
			warnings.append("%s - unknown key \"%s\" (ignored)." % [where, key])


static func _dict_of(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _float_of(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_STRING and (value as String).is_valid_float():
		return (value as String).to_float()
	return fallback


static func _speed_of(value: Variant, fallback: float) -> float:
	var parsed := _float_of(value, fallback)
	return maxf(0.0, parsed)


static func _color_of(value: Variant, fallback: Color) -> Color:
	if value == null:
		return fallback
	if typeof(value) == TYPE_COLOR:
		return value
	if typeof(value) == TYPE_STRING:
		var text := (value as String).strip_edges()
		if not text.begins_with("#"):
			text = "#" + text
		if Color.html_is_valid(text):
			return Color.html(text)
	return fallback
