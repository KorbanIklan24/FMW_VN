class_name StoryVars
extends RefCounted

## The variable state a running story carries.
##
## Every variable is *declared* in the story's `variables` block, and the
## expressions that read it (`"if"`, a `"branch"` entry, a choice's `"if"` and a
## `{"expr": ...}` write) are evaluated by Godot's own [Expression] class against
## this state. Declaring a name is what makes it available to every expression:
## the parser collects the names first and compiles the expressions with them as
## inputs, so an expression can only ever see declared variables.
##
## Values are plain JSON: numbers, strings, booleans, null, and also arrays and
## dictionaries. Inside an expression a variable is either its bare name -
## [code]affection >= 3[/code] - or a key of the whole state dictionary, which is
## always bound as [code]vars[/code]:
## [codeblock]
## var store := StoryVars.new({"affection": 2}, PackedStringArray(["affection"]))
## store.get_value("affection")        # 2
## store.set_value("affection", 4)
## store.get_value("affection")        # 4
## [/codeblock]
##
## [b]Names never collide with slide ids.[/b] Variables live in their own
## dictionary, separate from [member Story.id_to_index]; a condition is never
## a slide target and a slide target (`"next"`) is never a condition. A name can
## therefore be both a variable and a slide id without either shadowing the
## other, and the parser warns when that happens so it is never a surprise.

## Emitted whenever a variable's value changes, from a `set` in the story or
## from code. [param name] is the variable, [param value] its new value.
signal changed(name: String, value: Variant)

## The state dictionary inside an expression: [code]vars["affection"] == 3[/code].
const STATE_NAME := "vars"

## Names an expression already uses for something else - the literals, the
## keywords and the built-in functions [Expression] knows. A variable called
## `min` or `true` would shadow them, so those names are refused outright with a
## clear message instead of failing later inside a condition.
const RESERVED_NAMES := [
	"vars",
	"true", "false", "null", "self", "PI", "TAU", "INF", "NAN",
	"and", "or", "not", "in", "is", "as", "if", "elif", "else",
	"for", "while", "match", "break", "continue", "pass", "return",
	"var", "const", "func", "class", "class_name", "extends", "signal",
	"await", "yield", "static", "enum", "preload", "super", "typeof", "void",
	"abs", "sign", "floor", "ceil", "round", "trunc", "int", "float", "bool",
	"str", "min", "max", "clamp", "lerp", "snapped", "pow", "sqrt", "exp",
	"log", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "deg_to_rad",
	"rad_to_deg", "randi", "randf", "print", "push_error", "push_warning",
]

var _defaults: Dictionary = {}
var _names: PackedStringArray = PackedStringArray()
var _values: Dictionary = {}


func _init(defaults: Dictionary = {}, names: PackedStringArray = PackedStringArray()) -> void:
	_defaults = defaults.duplicate(true)
	_names = _sorted_names_static(names)
	reset()


## The names expressions are compiled with, in the one order every story uses:
## the state dictionary first, then the declared variables alphabetically.
static func input_names(names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray([STATE_NAME])
	for name in _sorted_names_static(names):
		if name != STATE_NAME:
			out.append(name)
	return out


## "" when [param name] can be a variable, otherwise why it cannot. Kept as a
## static so the parser can refuse a bad name before anything is built.
static func name_problem(name: String) -> String:
	if name.is_empty():
		return "a variable name cannot be empty"
	if not name.is_valid_identifier():
		return "\"%s\" is not a usable variable name; use letters, digits and \"_\" only, and do not start with a digit" % name
	if RESERVED_NAMES.has(name):
		return "\"%s\" is reserved - it is a keyword, a literal or a built-in expression function" % name
	return ""


static func is_valid_name(name: String) -> bool:
	return name_problem(name).is_empty()


## A one-line rendering used by the debug tools, e.g. `affection=3 bool=false`.
static func describe_value(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return "\"%s\"" % value
	if value == null:
		return "null"
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
		return JSON.stringify(value)
	return str(value)


# --- reading -----------------------------------------------------------------

func names() -> PackedStringArray:
	return _names.duplicate()


func defaults() -> Dictionary:
	return _defaults.duplicate(true)


## True when the story declared this variable. That is the set of names the
## conditions were compiled with, so it is what "can an expression read this?"
## means - a name [method set_value] invented from code is a value, not a
## declaration.
func is_declared(name: String) -> bool:
	return _defaults.has(name)


## True when this store holds a value for [param name] right now.
func has(name: String) -> bool:
	return _values.has(name)


func get_value(name: String) -> Variant:
	return _values.get(name)


## The whole state, as the dictionary an expression sees as `vars`.
func values() -> Dictionary:
	return _values.duplicate(true)


func count() -> int:
	return _values.size()


# --- writing -----------------------------------------------------------------

## Writes [param value] into [param name] and tells every listener. Works for a
## name the story never declared too (a script may push its own state), but such
## a name is invisible to the compiled expressions - the parser is what decides
## which names they know, so declaring it in JSON is the way to read it back.
func set_value(name: String, value: Variant) -> void:
	var previous: Variant = _values.get(name)
	var had_value := _values.has(name)
	_values[name] = value
	if not had_value or previous != value:
		changed.emit(name, value)


## Back to the values the story declared. Handy between runs.
func reset() -> void:
	var before := _values
	_values = _defaults.duplicate(true)
	var touched := PackedStringArray(_names)
	for name in before.keys():
		if not touched.has(str(name)):
			touched.append(str(name))
	for name in touched:
		if not before.has(name) or before[name] != _values.get(name):
			changed.emit(name, _values.get(name))


# --- save / load -------------------------------------------------------------

## JSON-safe copy of every value, for a save file.
func to_dict() -> Dictionary:
	return _values.duplicate(true)


## Restores values from [method to_dict]. Names that are not in the save keep
## what they have, so an older save still loads.
func from_dict(data: Dictionary) -> void:
	for key in data.keys():
		set_value(str(key), data[key])


# --- expressions -------------------------------------------------------------

## Runs a compiled condition or value expression against this state.
## Returns null (and pushes an error) when it could not be evaluated.
func evaluate(expression: Expression) -> Variant:
	if expression == null:
		return null
	var result: Variant = expression.execute(_inputs(), null, false)
	if expression.has_execute_failed():
		push_error("FMW_VN: could not evaluate a condition: %s" % expression.get_error_text())
		return null
	return result


## Runs the expression and reports what went wrong, without pushing an error.
## The parser uses this to check a condition before the story is ever played:
## Godot's [Expression] accepts an unknown name at parse time and only complains
## when it runs, so "did it resolve?" can only be answered by running it.
## Returns "" when it ran cleanly.
func probe(expression: Expression) -> String:
	if expression == null:
		return ""
	var inputs: Array = [_values]
	for name in _names:
		inputs.append(_values.get(name))
	@warning_ignore("return_value_discarded")
	expression.execute(inputs, null, false)
	return expression.get_error_text() if expression.has_execute_failed() else ""


## A condition's verdict, using GDScript's own truthiness: false, 0, 0.0, "",
## null, an empty array and an empty object all count as false. That reads
## naturally on a flag - `"if": "asked_about_clouds"` - and on a list that may
## be empty, so `"if": "items"` means "the player has some".
func is_true(expression: Expression) -> bool:
	var value: Variant = evaluate(expression)
	if value == null:
		return false
	if value:
		return true
	return false


## The positional inputs an expression expects, in the order [method input_names]
## declares them: the whole state dictionary, then each variable by name.
func _inputs() -> Array:
	var inputs: Array = [_values]
	for name in _names:
		inputs.append(_values.get(name))
	return inputs


# --- helpers -----------------------------------------------------------------

static func _sorted_names_static(names: PackedStringArray) -> PackedStringArray:
	var sorted := PackedStringArray(names)
	sorted.sort()
	return sorted
