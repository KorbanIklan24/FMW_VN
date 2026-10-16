class_name StoryProgress
extends RefCounted

## The player's progress through every story they have played, kept in one file
## of its own - how far they got, and which CGs they collected.
##
## This is deliberately [b]not[/b] a save. A save answers "where is the player
## right now" - one position, one set of variables, rewritable, replaced every
## time the player saves. This answers "how far has the player ever got", it is
## global (one file for every story in the project, not one per slot), and it
## only ever moves forwards: nothing a player does - loading an older save,
## replaying a chapter, taking the other branch - can take it back. Only
## [method clear] does.
##
## One entry per story, keyed by the story file's path:
##
## [codeblock]
## {
##   "version": 1,
##   "stories": {
##     "res://VN/Story/story.json": {
##       "title": "FMW VN Demo - After the Bell",  # as it was read
##       "furthest_index": 17,                 # the furthest slide reached, by index
##       "furthest_id": "ending_same_place",   # its dialogue id
##       "furthest_label": "Mika: Of course.", # speaker and text, for menus
##       "furthest_chapter": "ch02_the_rooftop.json",
##       "seen": ["opening", "mika_appears", ...],  # every dialogue id ever shown
##       "gallery": ["cg_classroom", "cg_rooftop"],    # every CG ever unlocked
##       "first_played_at": "2026-10-11 06:10:00",
##       "updated_at": "2026-10-11 06:12:31"
##     }
##   }
## }
## [/codeblock]
##
## [code]gallery[/code] is the other one-way list: the ids of the story's CGs the
## player has unlocked. It is filled by the player as the story is played, and
## like the furthest point it never goes back - loading an older save, replaying
## a chapter or a new playthrough only ever adds to it. [method clear] and
## [method clear_all] are the only things that empty it.
##
## [b]furthest[/b] is the highest slide index reached, which is "how deep into the
## file" rather than "how far through the plot", since a branching story's file
## order is not its story order. Every dialogue id that was actually shown is in
## [code]seen[/code] as well, so a second playthrough down another branch shows up
## there even when it does not move the furthest point. A slide with no `id` is
## counted by index only and adds nothing to `seen`.

## Emitted when the furthest point moves forward for a story.
signal advanced(story_path: String, entry: Dictionary)

const VERSION := 1

## Where the record lives. One file, every story, outside the save slots.
var path: String = "user://fmw_vn_progress.json"

## story path -> entry. Read through the methods rather than directly.
var _stories: Dictionary = {}
var _loaded: bool = false
## True when something has changed since the last write.
var _dirty: bool = false


static func default_path() -> String:
	return "user://fmw_vn_progress.json"


# --- disk ---------------------------------------------------------------------

## Reads the record from disk. Returns false when there was nothing to read (a
## missing file is not a problem: it just means the player has not played yet).
## A file that cannot be read is reported and then treated as empty.
func load_from_disk() -> bool:
	_loaded = true
	_stories = {}
	_dirty = false
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("FMW_VN: %s is not a readable progress file; starting a fresh record." % path)
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


## Writes the record, so a later run picks it up. Returns true when it was
## written (or when there was nothing to write).
func save() -> bool:
	if _stories.is_empty():
		# Nothing left to remember: take the file away rather than leave an empty
		# - or stale - one behind. This is what makes a reset stick.
		_dirty = false
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FMW_VN: could not write the progress file %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dict(), "  "))
	file.close()
	_dirty = false
	return true


## The whole record, as it is written to disk.
func to_dict() -> Dictionary:
	return {"version": VERSION, "stories": _stories.duplicate(true)}


## Replaces the record from a decoded dictionary. Unknown keys are dropped and
## anything malformed is skipped, so an edited or older file still loads.
func from_dict(data: Dictionary) -> void:
	_stories = {}
	var raw: Variant = data.get("stories")
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for key in (raw as Dictionary).keys():
		var entry: Variant = (raw as Dictionary)[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_stories[str(key)] = _clean_entry(entry)


# --- reading ------------------------------------------------------------------

func stories() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _stories.keys():
		out.append(str(key))
	out.sort()
	return out


## True when this story has ever been played.
func has(story_path: String) -> bool:
	return _stories.has(story_path)


## Everything known about one story, or {} when it has never been played.
func entry_for(story_path: String) -> Dictionary:
	return (_stories.get(story_path, {}) as Dictionary).duplicate(true)


## The summary a menu would show: the entry, plus how many slides it has seen and
## how many CGs it has unlocked. {} when the story has never been played.
func summary(story_path: String) -> Dictionary:
	var entry := entry_for(story_path)
	if entry.is_empty():
		return {}
	entry["story"] = story_path
	entry["slides_seen"] = (entry.get("seen", []) as Array).size()
	entry["cgs_unlocked"] = (entry.get("gallery", []) as Array).size()
	return entry


## The furthest dialogue id the player has reached in this story, or "" when it
## has never been played (or when the furthest slide has no id of its own).
func furthest_id(story_path: String) -> String:
	return str(entry_for(story_path).get("furthest_id", ""))


## The furthest slide index reached: the deepest into the file the player has
## ever got. -1 when the story has never been played.
func furthest_index(story_path: String) -> int:
	var entry := entry_for(story_path)
	return int(entry.get("furthest_index", -1)) if not entry.is_empty() else -1


## The speaker and line of the furthest slide, for a "continue from" menu.
func furthest_label(story_path: String) -> String:
	return str(entry_for(story_path).get("furthest_label", ""))


## Every dialogue id ever shown in this story, in the order they were first
## reached.
func seen_ids(story_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in (entry_for(story_path).get("seen", []) as Array):
		out.append(str(id))
	return out


func seen_count(story_path: String) -> int:
	return (entry_for(story_path).get("seen", []) as Array).size()


## True when this dialogue id has ever been shown to the player.
func was_seen(story_path: String, id: String) -> bool:
	return id.is_empty() or (entry_for(story_path).get("seen", []) as Array).has(id)


## Every CG id the player has ever unlocked in this story, in the order they were
## unlocked.
func unlocked_ids(story_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in (entry_for(story_path).get("gallery", []) as Array):
		out.append(str(id))
	return out


func unlocked_count(story_path: String) -> int:
	return (entry_for(story_path).get("gallery", []) as Array).size()


## True when this CG has ever been unlocked. Unlocking is one-way: nothing here
## can take it back except [method clear].
func is_unlocked(story_path: String, id: String) -> bool:
	return not id.is_empty() and (entry_for(story_path).get("gallery", []) as Array).has(id)


# --- writing ------------------------------------------------------------------

## Notes that the slide at [param index] has been reached.
##
## [param id] is the slide's dialogue id ("" when it has none). Returns
## [code]{ "changed": bool, "advanced": bool, "entry": Dictionary }[/code]:
## `changed` says the record needs writing, `advanced` says the player has never
## been this far before. Nothing here ever moves backwards.
func record(story_path: String, title := "", index := -1, id := "", label := "", chapter := "") -> Dictionary:
	if story_path.is_empty() or index < 0:
		return {"changed": false, "advanced": false, "entry": {}}
	var entry: Dictionary = (_stories.get(story_path, {}) as Dictionary).duplicate(true)
	var changed := false
	# Not called `advanced`: that is the signal this method may emit.
	var moved_on := false
	if entry.is_empty():
		entry = {
			"title": title,
			"furthest_index": -1,
			"furthest_id": "",
			"furthest_label": "",
			"furthest_chapter": "",
			"seen": [],
			"gallery": [],
			"first_played_at": _now(),
		}
		changed = true
	elif not title.is_empty() and str(entry.get("title", "")) != title:
		# A story can be retitled between versions.
		entry["title"] = title
		changed = true

	if index > int(entry.get("furthest_index", -1)):
		entry["furthest_index"] = index
		entry["furthest_id"] = id
		entry["furthest_label"] = label
		entry["furthest_chapter"] = chapter
		changed = true
		moved_on = true

	var seen: Array = entry.get("seen", [])
	if not id.is_empty() and not seen.has(id):
		seen.append(id)
		changed = true

	if changed:
		entry["updated_at"] = _now()
		entry["seen"] = seen
		_stories[story_path] = entry
		_dirty = true
		if moved_on:
			advanced.emit(story_path, entry.duplicate(true))
	return {"changed": changed, "advanced": moved_on, "entry": entry.duplicate(true)}


## Marks a CG as unlocked. One-way like everything else here: a CG that is
## already unlocked stays unlocked, and this can only ever add. Returns true when
## something changed (so the caller knows to write the file).
func unlock(story_path: String, id: String) -> bool:
	if story_path.is_empty() or id.is_empty():
		return false
	if not _stories.has(story_path):
		# A CG can only be unlocked by playing, which records first; without an
		# entry there is no story to hold it, so say no rather than invent one.
		return false
	var entry: Dictionary = (_stories[story_path] as Dictionary).duplicate(true)
	var gallery: Array = entry.get("gallery", [])
	if gallery.has(id):
		return false
	gallery.append(id)
	entry["gallery"] = gallery
	entry["updated_at"] = _now()
	_stories[story_path] = entry
	_dirty = true
	return true


## Forgets one story's progress (its CGs included). The only thing that moves a
## record backwards - for a "reset progress" menu item, or for a test.
func clear(story_path: String) -> void:
	if story_path.is_empty():
		return
	if _stories.erase(story_path):
		_dirty = true


## Forgets every story's progress.
func clear_all() -> void:
	if _stories.is_empty():
		return
	_stories = {}
	_dirty = true


# --- helpers ------------------------------------------------------------------

## Keeps only the keys this class knows, with the right shapes. An entry with a
## mangled `seen` list (or a missing furthest) is repaired rather than trusted.
func _clean_entry(value: Dictionary) -> Dictionary:
	var seen := PackedStringArray()
	for id in (value.get("seen", []) as Array):
		seen.append(str(id))
	# Unlocked CGs are the same kind of list: kept in order, without repeats, and
	# with anything that is not a plain id dropped rather than trusted.
	var gallery := PackedStringArray()
	for id in (value.get("gallery", []) as Array):
		var cg := str(id)
		if not cg.is_empty() and not gallery.has(cg):
			gallery.append(cg)
	return {
		"title": str(value.get("title", "")),
		"furthest_index": int(value.get("furthest_index", -1)),
		"furthest_id": str(value.get("furthest_id", "")),
		"furthest_label": str(value.get("furthest_label", "")),
		"furthest_chapter": str(value.get("furthest_chapter", "")),
		"seen": Array(seen),
		"gallery": Array(gallery),
		"first_played_at": str(value.get("first_played_at", "")),
		"updated_at": str(value.get("updated_at", "")),
	}


func _now() -> String:
	return Time.get_datetime_string_from_system(false, true)
