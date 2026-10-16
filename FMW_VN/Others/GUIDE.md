# FMW_VN guide

Everything the framework reads lives in JSON. This is the full reference.

- [The file at a glance](#the-file-at-a-glance)
- [Chapters: one story, many files](#chapters-one-story-many-files)
- [Languages: the same story in more than one](#languages-the-same-story-in-more-than-one)
- [`settings`](#settings)
- [`assets`](#assets)
- [`slides`](#slides)
- [`characters`](#characters)
- [Showing and hiding, one at a time](#showing-and-hiding-one-at-a-time)
- [Squares in the text box](#squares-in-the-text-box)
- [`choices`](#choices)
- [Variables and conditions](#variables-and-conditions)
- [Transitions](#transitions)
- [Screen effects](#screen-effects)
- [Pictures and paths](#pictures-and-paths)
- [Music and sound](#music-and-sound)
- [Text formatting](#text-formatting)
- [The main menu](#the-main-menu)
- [The book, and the controls](#the-book-and-the-controls)
- [Reading speed and auto-forward](#reading-speed-and-auto-forward)
- [The Settings page](#the-settings-page)
- [Saving and loading](#saving-and-loading)
- [Save slots and the book](#save-slots-and-the-book)
- [Progress: how far the player ever got](#progress-how-far-the-player-ever-got)
- [The CG gallery](#the-cg-gallery)
- [Recipes](#recipes)
- [Tools and API](#tools-and-api)
- [What is not included](#what-is-not-included)

## The file at a glance

An index file with two chapters, sharing their aliases:

```json
{
  "settings": { "title": "My Story", "start": "opening", "default_text_speed": 45 },
  "chapters": ["ch01.json", "ch02.json"],
  "assets": {
    "backgrounds": { "room": "res://VN/assets/bg/bg_classroom.png" },
    "characters": { "mika": "res://VN/assets/char/char_mika.png" },
    "music": { "calm": "res://VN/assets/audio/music_calm.wav" },
    "sounds": { "blip": "res://VN/assets/audio/sfx_blip.wav" }
  }
}
```

and a chapter (`ch01.json`):

```json
{
  "slides": [
    { "id": "opening", "background": "room", "characters": ["mika"],
      "speaker": "Mika", "text": "Hi there!", "bgm": "calm", "next": "fork" },
    { "id": "fork", "text": "Say something.", "choices": [
        { "text": "Say hello", "next": "ch02_goodbye", "sfx": "blip" },
        { "text": "Stay quiet", "next": null }
    ]}
  ]
}
```

Every slide plays in the order it appears, unless it has its own `next`. Keys are
optional unless stated otherwise. A file **without** `chapters` works on its own,
so single-file stories are still just one JSON.

## Chapters: one story, many files

Put `"chapters": ["ch01.json", "ch02.json"]` in a file (top level or under
`settings`) and everything is merged into one story, in that order:

- **Slide ids are shared**, so any slide can jump to any other slide, anywhere.
- **Aliases are shared.** `assets` from the index and from every chapter are
  merged; the first definition of a name wins (repeats are reported as warnings).
  Chapter files can therefore stay short and just use the aliases.
- **Chapters flow into each other.** The last slide of a chapter that has no
  `next` continues with the first slide of the next chapter.

**Settings** come from the first chapter, with the index file overriding them, so
a chapter that starts with the same `settings` block works standalone *and* as
part of a set.

Chapter paths are relative to the file that lists them (`"ch02.json"` next to
`story.json`), or absolute `res://` paths. `.json` is added when missing.
Chapters cannot list chapters of their own.

## Languages: the same story in more than one

A story can be told in more than one language. The **base scripts** stay in the
one language the story is written in, and every other language is a **mirror
file** beside the script it mirrors, carrying the same lines, in the same order,
in that language:

```
VN/Story/story.json                    <- the index: languages, title, gallery
VN/Story/ch01_after_the_bell.json      <- the base script, in "en"
VN/Story/ch01_after_the_bell.id.json   <- its Indonesian mirror
VN/Story/ch02_the_rooftop.json
VN/Story/ch02_the_rooftop.id.json
```

| key | type | default | meaning |
| --- | --- | --- | --- |
| `languages` | object | - | `code: name` - every language, and what to call it in a menu. The order is the order they are offered in. |
| `default_language` | code | the first one | The language the base scripts are written in. Every line falls back to it. |

Both go at the top level of the story's first file (or under `settings`); a
chapter may declare them too, and the first file that does wins. A code names a
file, so it may only use `a-z`, `0-9`, `_` and `-`, at most 16 characters:
`ch01.json` -> `ch01.id.json`. A story with **no** `languages` block is a story
in one language, exactly as it was before there were languages: nothing is read
differently, and no slide gains a translation table it has no use for.

### The mirror contract

A mirror carries `slides` and nothing else, and it must carry **the same lines
in the same order** as the script it mirrors. That is the whole contract, and it
is what makes a language switch unable to move the story. Every way of breaking
it is a reported parse error rather than something quietly carried along:

- a different number of lines;
- an `id` on a line that is not the base script's `id` there;
- anything that is not words. A mirror may carry `id`, `text`, `speaker` and an
  answer's `text`; the pictures, `next`, `bgm`, `if`, `set`, `wait`, `text_speed`,
  the transitions and effects, and a chapter's `gallery` all stay in the base
  script;
- an answer that carries its own `next`, `if` or `sfx`, or a line with a
  different number of answers than the base script has there.

A line is translated as a whole - its words, who says it, and its own `{w=...}`
pauses, which a translation may put somewhere else. Leave a line's `text` out (or
empty) and that line stays in the story's own language while the rest of the file
is translated. Leave the mirror file out altogether and the whole chapter stays
in it, with a warning naming the file it looked for, so a story can be translated
one chapter at a time.

The story's own words outside a script - `settings.title`, and each CG's `title`
and `caption` - are written once for everybody, or once per language:

```json
"settings": {
  "title": { "en": "FMW_VN Demo - After the Bell", "id": "FMW_VN Demo - Setelah Bel Berbunyi" },
  "start": "opening"
}
```

### Reading in another language

The player reads every line through the language in force - the text, the
speaker, the answers, the `{w}` pauses, the story's title and the gallery.
Switching **does not move the story**: the same slide is put up again in the
other language, whole rather than typed again, with the same variables, the same
progress and the same history (which keeps the lines the way they were read).

The **Settings** page offers it (`%LanguageOption`), and it is the player's
setting rather than the story's - kept in `user://fmw_vn_settings.json` beside
the other dials. A story not told in that language is read in its own default.

A story is what is translated: the framework's own words - the menu pages, the
book's tabs, `3 of 4 unlocked`, the hints - are not part of a story and stay as
they are. What the load slots, saves and the progress record call a story is the
title in the language it was read in, so one story can be listed under two names.

From your own code:

```gdscript
player.language()               # "en": the language being read
player.set_language("id")       # switches, and leaves the story where it is
player.story_languages()        # { "en": "English", "id": "Indonesian" }
player.language_name("en")      # "English", what a menu shows
player.default_language()       # "en": what the scripts are written in
player.is_multilingual()        # whether there is anything to choose between
player.reset_language()         # back to the story's own default
```

The parsed story carries every language side by side rather than one at a time,
so a tool can ask for any of them: `story.text_for(slide, code)`,
`speaker_for`, `pauses_for`, `choice_text_for`, `title_for`, `cg_title_for`,
`cg_caption_for`, `story.language_codes()` and `story.resolve_language(code)` -
which answers with the default language for a code the story does not have,
exactly as the player does.

## `settings`

| key | type | default | meaning |
| --- | --- | --- | --- |
| `title` | string or one per language | `"Untitled"` | Shown by `Story.describe()`, handy in tools. |
| `start` | id or index | `0` | Where playback begins. |
| `chapters` | array | - | Story files to merge in (see above). |
| `languages` | object | - | The languages the story is told in (see above). |
| `default_language` | code | the first one | The language the base scripts are written in. |
| `background_color` | hex colour | `#101018` | Shows through when a slide has no picture. |
| `default_text_speed` | number | `45` | Characters per second for every slide. |
| `default_fade` | number | `0.35` | Seconds for background, cast and music transitions. |
| `music_volume` | number 0-1 | `0.6` | Music level. |
| `sound_volume` | number 0-1 | `0.8` | Sound effect level. |
| `variables` | object | - | Starting values for the story's variables (see below). May also sit at the top level of the file. |

`default_text_speed` may be `0`, which prints the whole line at once.

## `assets`

Five lookup tables, so slides stay short. A slide may use an alias instead of a
path: `"background": "room"` instead of the full `res://` path.

```json
"assets": {
  "backgrounds": { "room": "res://VN/assets/bg/bg_classroom.png" },
  "characters": { "mika": "res://VN/assets/char/char_mika.png" },
  "music": { "calm": "res://VN/assets/audio/music_calm.wav" },
  "sounds": { "blip": "res://VN/assets/audio/sfx_blip.wav" },
  "cg": { "rooftop_sunset": "res://VN/assets/cg/cg_rooftop.png" }
}
```

`cg` holds the pictures the [gallery](#the-cg-gallery) collects. Aliases only
matter where they are read: a background alias is for `"background"`, a `cg` alias
for a gallery entry - and a gallery entry may also point straight at any
background or character alias, so one picture can be both.

## `slides`

An array. Each entry is one picture, one block of text, and whatever happens with
them.

| key | type | default | meaning |
| --- | --- | --- | --- |
| `id` | string | - | Name so other slides can jump here. Must be unique across all chapters. |
| `background` | picture | keeps current | New background picture, crossfaded in. `""` clears it. |
| `characters` | array | keeps current | The whole line-up for this slide (see below). `[]` clears the stage. |
| `show` | name, object or array | - | Add or move characters without clearing the rest (see below). |
| `hide` | name or array | - | Take characters off the stage (see below). |
| `with` | transition name | `dissolve` | How this slide's `show` / `hide` come and go. `none` cuts. |
| `speaker` | string | `""` | Name on the plate, and whose square portrait shows in the text box. Empty hides the plate. |
| `portrait` | picture or `""` | speaker's own picture | Picture for the square in the left of the text box. `""` / `null` hides it. |
| `text` | string | `""` | The line to read. BBCode allowed. |
| `choices` | array | - | Options to pick from (see below). |
| `next` | id, index or `null` | next slide | Where to go afterwards. `null` (or the word `"end"`) ends the story. |
| `bgm` | music, `"stop"` or `null` | keeps playing | Music change on this slide. |
| `sfx` | sound or array | - | One or more sound effects to fire now. |
| `transition` | name or object | `fade` | How a new `background` comes in. |
| `effects` | name, object or array | - | Screen effects, played when the slide appears. |
| `fade` | number | `default_fade` | Transition time for this slide. `0` = instant. |
| `text_speed` | number | `default_text_speed` | Characters per second for this line. `0` = instant. |
| `wait` | number | `0` | Seconds to hold the slide, then advance without a click. |
| `auto` | bool | `false` | Move on by itself after `wait` (or after a reading pause). |
| `set` | object | - | Write variables when this slide appears (see below). |
| `if` | condition | - | Skip this slide unless the condition holds (see below). |
| `branch` | array | - | Pick where to go next from a list of conditions (see below). |

A slide with **no text** always advances by itself after `wait` seconds, which
makes it a nice way to hold a picture or change scenes quietly:

```json
{ "background": "hallway", "wait": 0.9 },
{ "text": "We walk in silence." }
```

Leaving `background` or `characters` out keeps what is already on screen, so a
scene only has to be set up once.

## `characters`

The line-up is replaced in full each time a slide has a `characters` key.

```json
"characters": [
  { "id": "mika", "image": "mika", "position": "right" },
  { "id": "ren", "image": "ren", "position": "bottom-left" },
  { "id": "ren", "image": "ren", "position": "left", "vertical": "middle", "scale": 0.6 }
]
```

The short form `"characters": ["mika", "ren"]` gives both of them an even spread
across the screen. `"characters": "mika"` works for a single one.

| key | type | default | meaning |
| --- | --- | --- | --- |
| `id` | string | the image name | Slot name. Reusing a slot keeps that picture on stage and moves it. |
| `image` | picture | - | Which picture to show. |
| `portrait` | picture or `""` | this character's picture | Picture for the square in the text box while this character speaks. `""` / `null` shows no square. |
| `position` | `left` `center` `right` + `top` `middle` `bottom`, `auto` | `auto` | Where the picture stands. One name, or a pair like `"bottom-left"`. |
| `vertical` | `top` `middle` `bottom` | `bottom` | Convenience for `y`. Only useful together with a `scale` below 1. |
| `x` | number 0-1 | from `position`, else spread out | Horizontal centre of the picture (0 = left edge). |
| `y` | number 0-1 | from `vertical` | Where the **bottom edge** of the picture sits (0 = top of the screen). |
| `scale` | number | `1` | Multiplied onto the default height (92% of the screen). |
| `flip` | bool | `false` | Mirror the picture horizontally. |
| `offset_y` | number | `0` | Nudge up (negative) or down in pixels at 1080p. |
| `tint` | hex colour | white | Multiply colour, for recoloured or "in shadow" versions. |

`position: "left"` puts the centre of the picture at 22% of the screen width,
`"center"` at 50% and `"right"` at 78%, so a line-up reads the way the dialogue
does. `x` overrides it when you want an exact spot.

By default a picture keeps its feet on the bottom edge of the screen, so a
720x1440 picture like the placeholders fills the height nicely. `y` (or
`vertical`) lifts the picture when the scene calls for it - a character sitting
on a ledge, peeking over something - and a smaller `scale` keeps it whole:

```json
{ "id": "ren", "image": "ren", "position": "left", "scale": 0.6, "vertical": "middle" }
```

## Showing and hiding, one at a time

`characters` replaces the whole line-up, which is fine when a scene first comes
together but tedious when only one person walks out of frame. `show` and `hide`
change the cast one character at a time, Ren'Py style, with a simple transition
each.

```json
{ "id": "ren_slips_away", "hide": ["ren"], "with": "dissolve",
  "text": "Ren ducks out of frame to fetch his bag." },

{ "id": "ren_back", "with": "dissolve",
  "show": [ { "id": "ren", "image": "ren", "position": "left" } ],
  "text": "Found it. So - the roof?" }
```

- `show` takes the same entries as `characters` (a character name, or an object
  with `id`, `image`, `position`, …). It **adds or moves** those characters and
  leaves everyone else alone. One that is already on stage just moves; a new one
  comes in with the transition.
- `hide` takes a character name, or several, and takes them off the stage. It
  runs **before** `show`, so a character can leave and come back on one slide.
- `with` is the transition for the slide's `show` / `hide`. `dissolve` fades - the
  default - and `none` cuts. A single entry can override it with its own
  `"effect"` and `"duration"` (seconds):

```json
{ "with": "dissolve",
  "show": [ { "id": "mika", "effect": "none" } ],
  "hide": [ { "id": "ren", "effect": "dissolve", "duration": 0.8 } ] }
```

Both keys also accept a single value, so `"hide": "ren"` and
`"show": "mika"` work. `"characters": []` is still the way to clear the whole
stage at once, and leaving `show` / `hide` (and `characters`) out leaves the cast
exactly as it is.

## Squares in the text box

Besides the line-up on screen, the speaker shows up as a **square portrait** in
the left of the text box, with a thin border, and the text moves over to make
room for it. By default a character portraits itself, so `"speaker": "Mika"`
with Mika in the cast is enough - just leave her out of `characters` if the
picture belongs in the box and not on the screen.

```json
{ "characters": ["ren"], "speaker": "Mika", "text": "Over here!" },
{ "portrait": "ren", "text": "Narration with Ren smiling in the corner." },
{ "portrait": "", "text": "No square at all on this one." }
```

- The slide's own `portrait` always wins; `""` / `null` hides the square.
- Without one, the square is the speaking character's `portrait` (its `image`
  when it does not say otherwise).
- On a slide with **no speaker** and no `portrait` the square stays exactly as it
  was, so narration does not make it flicker.

Any picture will do - it is cropped to a square, centred, so a tall character
picture shows its middle.

## `choices`

Give a slide a `choices` array and it waits for the player instead of advancing.
The buttons appear once the line has been read (or straight away when the slide
has no text).

```json
{
  "id": "the_way_up",
  "speaker": "Mika",
  "text": "How are we getting up to the roof?",
  "choices": [
    { "text": "Take the stairs.", "next": "stairs", "sfx": "confirm" },
    { "text": "The window.", "next": "window" },
    { "text": "Actually, let us not.", "next": null }
  ]
}
```

| key | type | default | meaning |
| --- | --- | --- | --- |
| `text` | string | required | Button label. |
| `next` | id, index or `null` | required | Where that answer leads. |
| `sfx` | sound | - | Effect played when this answer is picked. |
| `if` | condition | - | Offer this answer only while the condition holds. Live: it can appear and disappear while the question is up (see below). |

While choices are on screen, clicking the story does nothing; the player has to
pick one. Keyboard players can use Tab / the arrow keys and Enter - while the
answers are up, Tab walks them instead of toggling fast-forward. Every answer is
written into the history as `> text`.

An answer can carry an `if` and is then only offered while it holds (see
**Variables and conditions** below). That check is live rather than a snapshot, so
an answer whose condition changes while the question is on screen is added or
taken away there and then. The answers that are left are renumbered, so the first
button is always answer 0.

## Variables and conditions

A story can keep its own state - flags, counters, who saw what - and read it back
in an `if`. The names are declared once, in a `variables` block:

```json
{
  "settings": { "title": "After the Bell", "start": "opening" },

  "variables": {
    "route": "",
    "roof_visits": 0,
    "asked_about_clouds": false
  },

  "slides": [
    {
      "id": "mika_teases",
      "text": "Clouds! The festival starts in an hour.",
      "set": { "asked_about_clouds": true },
      "next": "the_way_up"
    },
    {
      "id": "roof",
      "text": "Three floors of city below us.",
      "set": { "roof_visits": { "expr": "roof_visits + 1" } },
      "branch": [
        { "if": "route == \"window\"", "next": "roof_window" },
        { "next": "roof_quiet" }
      ]
    },
    {
      "id": "the_way_up",
      "speaker": "Mika",
      "text": "How are we getting up to the roof?",
      "choices": [
        { "text": "Take the stairs.", "next": "stairs" },
        { "text": "What were you doing up there?", "next": "clouds", "if": "asked_about_clouds" }
      ]
    }
  ]
}
```

The `variables` block may sit at the top level of a story file or inside
`settings`, and it is shared across chapters the way asset aliases are: every
chapter contributes, and the first definition of a name wins (the validator says
so when two files disagree).

Declaring a name is what lets a condition read it. Values are plain JSON -
numbers, strings, `true` / `false`, `null`, and also arrays and objects.

### Writing: `set`

A slide's `set` writes when the slide appears. A plain value is written as it
stands; an object with an `expr` is worked out from the values as they are at
that moment:

```json
"set": { "route": "stairs", "met": false, "roof_visits": { "expr": "roof_visits + 1" } }
```

```json
"set": { "affection": { "expr": "affection + 1 if gave_gift else affection" } }
```

A computed write reading the variable it writes is the usual counter. String
values are always literal text - a computed one always goes behind `"expr"` -
so there is no way to write a string by accident. A `set` may only write names
that were declared; anything else is a parse error that lists what is available.

### Reading: `if`

`if` is a condition string, evaluated against the variables when the player
reaches it:

```json
{ "id": "window_thought", "if": "route == \"window\"", "text": "The window route cost us a scratched knee." }
{ "id": "quiet", "text": "Nobody says anything for a while." }
```

A slide whose `if` does not hold is simply not part of the story this time round:
playback walks past it to that slide's own `branch` / `next`, and nothing on it
runs - not the text, not the pictures, not its `set`. A whole run of skipped
slides is walked through in one step.

An answer's own `if` works the same way, one answer at a time: while it does not
hold the button is not built at all, and the answers that are left are renumbered
behind it. The check is live, not a snapshot taken once when the line ended -
write a variable an answer reads and that answer toggles on or off while its
question is still on screen, back in its written place:

```gdscript
player.set_variable("has_key", true)   # an answer with "if": "has_key" appears now
player.set_variable("has_key", false)  # and is taken away again
```

When the last answer goes the slide stops asking and behaves like any other line
(waiting for the reader, or auto-forwarding if that is on). When one comes back it
asks again, and any countdown that was running behind it is dropped, so a question
can never be auto-forwarded past. Re-entering the slide re-checks everything too,
so a hub slide always reflects the state the player came back with.

### Branching: `branch`

`branch` picks where to go next from a list, and it is separate from `next` on
purpose, so `next` keeps meaning exactly one thing.

```json
{
  "id": "roof",
  "text": "Up on the roof.",
  "next": "roof_quiet",
  "branch": [
    { "if": "roof_visits >= 3", "next": "roof_regular" },
    { "if": "route == \"window\"", "next": "roof_window" },
    { "next": "roof_quiet" }
  ]
}
```

The first entry whose `if` holds wins. An entry with no `if` is the default, so
put it last. If nothing matches and there is no default, the slide's own `next`
is used; the validator warns when a `branch` has no default and no `next` either.

### What a condition can say

Conditions are strings, compiled at parse time with Godot's own
[`Expression`](https://docs.godotengine.org/en/stable/classes/class_expression.html)
class and run against the current values, so a typo is a parse error with a
message instead of a surprise mid-story. Anything `Expression` understands works:

| in a condition | example |
| --- | --- |
| comparisons | `roof_visits >= 3`, `route != "window"` |
| booleans | `asked_about_clouds and not met_ren` |
| a whole variable as a flag | `asked_about_clouds` (0, `""`, `null` and `[]` count as false) |
| lists and text | `"key" in items`, `name == "Ren"` |
| arithmetic | `affection + attention > 4` |
| the state dictionary | `vars["route"] == "window"`, `vars.get("count", 0)` |

A condition is compiled with the declared variable names and nothing else, so it
can never read a slide id by mistake: writing a slide id where a variable belongs
is a parse error that names it. `"next"` is unchanged by any of this - a slide
id, a plain index or `null`, exactly as before - and a variable may even share a
slide id's name, since the two live in separate tables. (The validator points
that out as a warning, and to avoid confusion: `"end"` written as a target means
"the end of the story", so name a slide something else.)

### From GDScript

```gdscript
player.get_variable("route")            # the value, or null if undeclared
player.set_variable("roof_visits", 2)    # write it; warns if it was never declared
player.set_variables({ "met": true })    # several at once
player.has_variable("route")             # was it declared in the story?
player.reset_variables()                 # every value back to the declared one
player.evaluate("route == \"window\"")    # run a condition against the live state
player.story_variables()                 # the StoryVars itself
player.variable_changed.connect(func(name, value): print(name, " -> ", value))
```

`set_variable()` while a question is on screen is what toggles its answers around,
and `variable_changed` fires before the buttons are rebuilt, so a listener that
reads `visible_choices()` sees the new list.

`set_variable()` also takes a name the story never declared, and the value is
kept - but only the declared names are what the conditions were compiled with, so
anything a condition has to read belongs in the story's `variables` block.

Variables travel in the save file, and a save written before variables existed
still loads: it simply falls back to the declared values.

`review/check_variables.gd` covers all of it end to end.

## Transitions

`transition` says how a **new background** comes in. It does nothing when the
slide has no `background` key, because there is nothing to swap.

```json
{ "background": "hallway", "transition": "wipe_left" },
{ "background": "sunset",  "transition": { "type": "fade_black", "duration": 1.2 } }
```

| name | what it looks like |
| --- | --- |
| `fade` | (default) the new picture fades in over the old one. |
| `cut` | no animation at all. |
| `fade_black` | fades to black, swaps, fades back in. |
| `wipe_left` `wipe_right` `wipe_up` `wipe_down` | the new picture is revealed by a growing edge. |
| `slide_left` `slide_right` `slide_up` `slide_down` | the new picture slides in from that edge. |

The direction in the name is where **the new picture comes from**: `wipe_left`
grows in from the left edge, `slide_up` slides up from below.

Timing: the slide's `fade` (or the story's `default_fade`) is used, unless the
transition object sets its own `duration`.

## Screen effects

`effects` moves the whole picture layer (background *and* characters - the text
box and menus stay readable). Each entry is a name or an object with parameters.

```json
{ "text": "...", "effects": "shake" },
{ "text": "...", "effects": [
    { "type": "shake", "strength": 24, "duration": 0.5 },
    { "type": "flash", "color": "#ffd0d0", "duration": 0.8, "delay": 0.2 }
] }
```

| effect | parameters (with defaults) | what it does |
| --- | --- | --- |
| `shake` | `strength` 18, `duration` 0.45 | shakes the picture for a moment, then settles. |
| `flash` | `color` white, `duration` 0.4 | flashes the screen in a colour: quick in, slow out. |
| `zoom` | `from` 1.0, `to` 1.08, `duration` 1.0 | pushes in (or out) and **stays** there. |
| `pulse` | `strength` 0.04, `duration` 0.35 | a quick throb, back to where it was. |
| `reset` | - | cancels zoom / shake / flash and puts the picture back to normal. |

Every effect also takes `delay` (seconds before it starts). Effects run in the
order they are listed. A `zoom` lasts until another `zoom` or a `reset`
changes it, so a long scene can stay pushed in and be released later.

Effects can be played by hand too: `player.play_effect("shake", { "strength": 30 })`.

## Pictures and paths

A picture or sound value can be:

1. an **alias** from `assets` - `"room"`, `"mika"`, `"calm"`
2. a **`res://` path** - `"res://VN/assets/bg/bg_sunset.png"`
3. a **path relative to the file that names it** - `"bg/sunset.png"` written in
   `VN/Story/ch01_after_the_bell.json` means `res://VN/Story/bg/sunset.png`,
   because it is joined onto the folder of the file that names it. Aliases
   (option 1) and full `res://` paths (option 2) are usually easier to follow

If no extension is given, the usual ones are tried: `.png`, `.svg`, `.webp`,
`.jpg`, `.jpeg`, `.bmp` for pictures and `.ogg`, `.wav`, `.mp3` for audio.
Anything that cannot be found is an error, and the validator tells you every path
it tried.

## Music and sound

```json
{ "bgm": "calm" },                  // start or switch, crossfaded
{ "bgm": "stop" },                  // fade out ("null" does the same)
{ },                                // no "bgm" key: the current track plays on
{ "sfx": "blip" },                  // one effect
{ "sfx": ["blip", "confirm"] }      // several at once
```

- Music **loops** and is crossfaded over `fade` seconds (`default_fade` when the
  slide does not set one).
- Sound effects are one-shot and share a pool of players, so they can overlap.
- Volumes come from `settings.music_volume` / `settings.sound_volume` and can be
  changed at runtime with `player.set_music_volume(v)` / `set_sound_volume(v)`.
  Both are played multiplied by the player's own **Master volume** setting - the
  story decides how its own mix sounds, the player decides how loud the game is
  (see [the Settings page](#the-settings-page)).

The demo plays plain generated WAVs. Regenerate or replace them with
`Framework_VN/tools/make_placeholder_audio.gd` (see the tools section) - or drop your own
files into `VN/assets/audio/` and point the `music` / `sounds` aliases at them.

### Using your own audio files

The generated sine waves are only a placeholder so the demo has something to
play; there is nothing synthetic about the engine's audio. Any `.ogg`, `.wav` or
`.mp3` file works, and each one is loaded as the matching Godot stream type
(`AudioStreamOggVorbis`, `AudioStreamWAV`, `AudioStreamMP3`). Those three are the
only supported formats - Godot 4 ships no importer for anything else. There are
two ways to bring your own:

1. **Point an alias at your file.** Add it under `assets.music` or
   `assets.sounds` (a `res://` path, or a path relative to the story file) and
   use the alias in a slide.

```json
"assets": {
  "music": { "opening": "res://VN/assets/audio/my_opening_theme.ogg" },
  "sounds": { "click": "res://audio/ui_click.mp3" }
}
```

2. **Replace a placeholder in place.** Overwrite `VN/assets/audio/music_calm.wav`
   with your own file under the same name and the demo keeps working untouched.

A few rules worth knowing:

- **Only `.ogg`, `.wav` and `.mp3` are supported.** Godot 4 has no importer for
  other audio formats, so a `.flac`, `.aac` or `.m4a` reference can never load.
  The validator reports it as an error and tells you to convert the file rather
  than letting it fail silently later:

  ```
  error:   ... slides[0].bgm - audio "res://VN/assets/audio/theme.flac" uses .flac,
  which Godot cannot import. Use .ogg, .wav or .mp3 instead - convert the file and
  update the reference.
  ```

- **The extension decides how Godot imports the file, not its contents.** A
  `.wav` is imported as a WAV, a `.ogg` as Ogg Vorbis, and so on. An Ogg renamed
to `.wav` imports as an empty WAV, so the slide would play **silence**. The
  validator warns about this and tells you what to rename the file to, so it is
easy to catch:

  ```
  warning: ... slides[0].bgm - "music_calm.wav" is named .wav but the file contains .ogg audio.
  Godot imports by extension, so this would play as silence - rename it to "res://VN/assets/audio/music_calm.ogg".
  ```

- **Run `godot --headless --path . --import` after adding or replacing a file**
  (or just open the project in the editor). New audio is not picked up until it
  is imported, which is easy to miss on a headless or CI run.

Music **loops whatever the format**: the player sets `LOOP_FORWARD` on a WAV and
`loop = true` on an Ogg or MP3 when it starts the track, so a one-shot file loops
seamlessly. A file with no extension is searched for as `.ogg`, `.wav` then
`.mp3`.

## Text formatting

`text` is rendered by a `RichTextLabel`, so BBCode works:

```json
{ "speaker": "Mika", "text": "I checked [b]every[/b] hallway. [i]Every[/i] one." }
```

Useful tags: `[b]`, `[i]`, `[u]`, `[color=#ff88aa]`, `[wave]`, `[shake]`,
`[font_size=52]`. A line break inside JSON is `\n`.

### Pausing inside a line

Put `{w=seconds}` where the typewriter should wait, Ren'Py style:

```json
{ "text": "So...{w=0.5} same time tomorrow?" }
{ "text": "Wait for it...{w} there." }
```

- `{w=0.5}` holds the line for half a second, then carries on typing.
- A bare `{w}` holds it until the player clicks.
- A click **ends a pause** rather than filling the line in; the next click
  completes the text as usual.

The tags are taken out of the line before it is shown, so the history, the save
preview and the reading-speed estimate never see them. Anything else in braces
(`{x=1}`) is left alone as ordinary text. Any other bracket-tag is not counted
against the pause position, so `[b]Hi[/b]{w=0.5} there` still pauses after the
"Hi".

## The main menu

The scene opens on a main menu instead of jumping into the story. (Set
`VNPlayer.play_on_start = false` to skip it and drive the player from your own
code - the tools and review harnesses do exactly that.) Its six buttons stack in
a column centred on the left of the screen:

| button | what it does |
| --- | --- |
| **New game** | starts the story from the beginning |
| **Load** | opens the book on its **Load** page, over the menu. Picking a slot starts that save and steps the menu aside; closing the book comes back to the menu. |
| **Gallery** | the CG gallery, as a page of its own (see [The CG gallery](#the-cg-gallery)) |
| **Settings** | the player's own dials: two writing speeds, the auto-forward formula, the screen mode and the language (see [the Settings page](#the-settings-page)). A full-screen page of its own, so the book opens it too. |
| **Info** | the keybind list |
| **Credits** | your credits ("place ur credits here."), with the framework's note in the bottom right |

Everything is plain colours, but every look is a real asset you can swap: the
backdrop is `VN/assets/ui/menu_bg.png` (`MainMenu/MenuBackground`), and each button
is a nine-slice `StyleBoxTexture` over `VN/assets/ui/menu_button.png`,
`menu_button_hover.png` and `menu_button_pressed.png` (`texture_margin` 24). The
title and subtitle are ordinary Labels in the scene (`MenuTitle`,
`MenuSubtitle`).

From code:

```gdscript
player.open_main_menu()        # show it
player.close_main_menu()
player.is_main_menu_open()
player.start_new_game()        # what the New game button calls
player.show_menu_page("info")  # "gallery" / "settings" / "info" / "credits"
player.is_menu_page_open()
player.menu_page_name()
player.open_settings()         # the Settings page, from here or from the book
player.is_settings_open()
player.close_settings()
```

`show_menu_page("settings")` is kept and means the same as `open_settings()`:
the page is one of the menu's pages, and `menu_page_name()` still answers
`"Settings"` while it is up.

While the menu is up it pauses the story and owns the input, so the story keys
(save for `Esc`) do not fire behind it. `Esc` closes an open page; on the menu's
own screen it goes back to a story that is still running - which is what the
book's **Main Menu** button needs - and does nothing when nothing is being
played, because then the menu is the root of the scene and there is nowhere
further back to go. (The confirmation `Esc` shows during gameplay is not
reachable from here - see [Leaving the game](#leaving-the-game).)

## The book, and the controls

Every line with text is remembered, with the speaker name, and the options the
player picked are recorded as `> text`. The **Book** button in the top right (or
`B`) opens one overlay with three pages, like a book with a bookmark: **History**
(a scrollable list of everything read so far, jumping to the newest line),
**Save** and **Load** (the six save slots). The page that is showing is the tab
with the bookmark on it - brighter, and sitting a little lower so it tucks into
the top edge of the page. Reading any of it pauses typing and auto-advancing.
Under the pages sit three buttons of its own: **Settings** (the player's dials,
over the book), **Main Menu** (put the story down and go back to the menu) and
**Close (Esc)**.

| input | action |
| --- | --- |
| click / tap / `Space` / `Enter` | next slide (first press fills in a running line) |
| `B` or the Book button | open / close the book (on the page you were last on) |
| the book's tabs | click a tab to turn to that page |
| the book's **Settings** / **Main Menu** / **Close** buttons | the Settings page over the book, the main menu, or back to the story |
| `Tab` | fast-forward on / off (types at the fast-forward speed, 4x to start with, then skips a finished line) |
| `Ctrl` held | fast-forward while it is held (faster, and skips a finished line) |
| `Ctrl` + `Left` / `Right` | slower / faster typewriter, `0.25x` at a time |
| `A` | auto-forward on / off |
| right click | hide / show the text box, the hint and the choices |
| `Esc` | close the topmost overlay (the Settings page, the confirmation, a menu page, or the book); on the main menu, back to a story that is still running; or, with nothing in the way, open the confirmation instead of quitting outright |

The faded hint in the corner of the text box says where the input stands:
`click / space to skip` while a line types, `click / space` when it waits for
you, `auto` / `auto-forward` when it will move on by itself, and `fast` while
fast-forward is on.

### Hiding the box to see the picture

A right click hides the text box - with its speaker plate, portrait and hint -
and the choice list, so the artwork has the screen to itself. Another right click
brings them back. Nothing else stops: the line keeps typing, a left click still
fills it in and moves on, and auto-forward keeps counting. While the choices are
hidden nothing can answer them by accident, because the keyboard focus is let go
along with the list (and put back on the first answer when it returns).

The **Book** button goes with it, so the screen is the artwork and nothing else;
right click over an open overlay belongs to that overlay, and a story that starts
again always starts with its box on screen. `B` still works while the box is
hidden, so the book can be opened from a hidden screen.

### Leaving the game

`Esc` with nothing open - no menu, no book, no Settings page - does **not** quit.
It shows the confirmation `QuitOverlay`, the last thing in the scene and so drawn
over everything else, with three answers:

| button | what it does |
| --- | --- |
| **Exit game** | leaves the game: the `quit_requested` signal is emitted first, then the scene tree quits |
| **Main menu** | takes the confirmation down and opens the main menu over the story, which keeps its place (see [The main menu](#the-main-menu)) |
| **Cancel** | takes the confirmation down and puts the player back where they were |

`Esc` again is **Cancel**, so the key that opened it can never leave by being
pressed twice, and **Cancel** holds the keyboard when the dialog opens, so a
stray `Space` or `Enter` cannot leave either. The story is paused, not moved:
neither the slide, the line part-way through typing, the variables nor the
history change, and it carries on from the same character when the dialog closes.
While it is up it is modal - `B`, `A`, `Tab` and a right click all do nothing
behind it.

```gdscript
player.is_quit_dialog_open()
player.open_quit_dialog()      # what Esc shows when nothing is in the way
player.close_quit_dialog()     # what Cancel and a second Esc do
player.quit_game()             # what Exit game calls: asked, then quit
player.quit_requested.connect(_on_quit_requested)   # save something first
```

One note on scope: on the **main menu's own screen** `Esc` still does nothing
when no story is loaded, so the confirmation is not reachable from there - a
player who wants to leave from the menu uses the window's own close button.

## Reading speed and auto-forward

Two player-side comfort features need nothing in the JSON. Both the *modes*
start off in every new story; the speeds behind them are settings, and those are
kept between runs (see [the Settings page](#the-settings-page)).

**Speed and fast-forward.** `Ctrl` + `Right` and `Ctrl` + `Left` step a
multiplier between `0.25x` and `8x` (the toast shows the new speed and the
characters a second it works out to). `Tab` switches **fast-forward** on and off:
the typewriter runs at the **fast-forward speed** - `4x` to start with, `1x` to
`16x` on the Settings page - and, the moment a line finishes typing, it moves on to
the next slide by itself instead of waiting for a click. Holding `Ctrl` down does
the same while it is held. Both multipliers apply to every line's own
`text_speed`, so `"text_speed": 40` reads at 160 characters a second under a `4x`
fast-forward and at 640 under a `16x` one. A line that prints all at once
(`text_speed: 0`) is still shown at once and is skipped immediately. Fast-forward
never answers a choice: a slide with `choices` stops on its buttons until the
player picks.

**Auto-forward.** `A` turns reading hands-free. Once a line is fully shown the
player holds it for

```
the auto-forward setting x every drawn character (spaces included)
+ every {w=...} in the line
+ 0.5 s for a bare {w}, since there is nobody there to click
```

and then moves on to the next slide by itself. The setting is `0.05 s` a
character to begin with, so `"Hello there"` is 11 characters and holds 0.55 s, and
`"AB{w=0.5}CD"` holds 0.7 s; turn it up to `0.2` and the same lines hold 2.2 s and
1.3 s. BBCode tags are not characters and are not counted. A slide that asks for
its own hold (`"auto": true` with `wait`) keeps it: auto-forward takes the longer
of the two.

From your own code:

```gdscript
player.set_speed_scale(2.0)    # 2x every text_speed, also mid-line
player.adjust_speed(1.0)       # one Ctrl + Right step (0.25x)
player.set_fast_forward(true)
player.set_auto_forward(true)
player.typing_speed()          # characters a second the current line types at
```

Auto-forward is not the same as a slide's `"auto": true`: that one is the
writer saying "this picture holds for two seconds", while auto-forward is the
player saying "keep going while I read".

## The Settings page

Six things are the **player's**, not the story's, and they are what the menu's
**Settings** button opens:

| setting | what it is | range | starts at |
| --- | --- | --- | --- |
| **Writing speed** | x every line's own `text_speed` | `0.25x` .. `8x`, in `0.25x` steps | `1x` |
| **Fast-forward speed** | x again while `Tab` is on or `Ctrl` is held | `1x` .. `16x` | `4x` |
| **Auto-forward formula** | seconds a drawn character is held | `0` .. `0.5` s | `0.05` s |
| **Screen mode** | how the window is displayed | Windowed / Maximize / Full screen | the mode the project opens in |
| **Language** | which language the story is read in | the story's own languages | the story's own default |
| **Master volume** | x every story's own `music_volume` / `sound_volume` | `0%` .. `100%`, in `5%` steps | `100%` |

It is a **page of its own**, not a corner of the menu: `SettingsOverlay` at the
top level of `Framework_VN/scenes/vn_screen.tscn`, a full-screen dim with
`SettingsTitle`, the controls, and a **Back (Esc)** button. That is what lets the
book open it in the middle of a story as well as the menu - the page does not
belong to either.

The controls are `%SettingsPage`'s children: `%WritingSpeedSlider`,
`%FastWritingSpeedSlider`, `%AutoForwardSlider`, `%MasterVolumeSlider`,
`%ScreenModeOption` and `%LanguageOption`, each with a label and a number (or a
name) beside it - the volumes as percentages (`35%`). The
screen mode calls `DisplayServer.window_set_mode()`. The sliders take their ranges
from `StorySettings`, so a range only ever has to be changed in one place, and a
change made from code moves the controls too. The language row hides itself for a
story that is told in one language, where there would be nothing to choose.

Opening it from the **book** in the middle of a story is the same page: it covers
the screen, the book stays open underneath it, and the story is *paused* rather
than moved - the slide, the line part-way through typing, the variables and the
history are all exactly as they were. Closing it (`Esc`, or the **Back** button)
puts the keyboard back on the book's own **Settings** button, so the player lands
where they left off and the line carries on from the character it was on. Nothing
on the page touches the story: the dials only read and write the player's own
settings, so no setting can reset a story or make it jump.

Writing speeds are **multipliers**, not characters a second, so a line the writer
gave its own `text_speed` - or set to `0` to print at once - keeps its shape
however the player sets the dial. The two multiply: `2x` writing with an `8x`
fast-forward reads sixteen times the line.

The auto-forward number is the per-character term of the formula above: at `0.2`,
an 11-character line is held for 2.2 s. A line's own `{w=...}` pauses are added on
top and are not scaled with it.

**Master volume** is the one dial that changes what the game *sounds* like rather
than how it reads. Every story names the level its own music and sound effects are
played at (`settings.music_volume` / `settings.sound_volume`, and a save carries
them), and the master volume multiplies them: `60%` master with a story at `0.6`
music plays at `0.36`, or `-8.9` dB. `0%` is silence - reported to Godot as
the framework's own silent level (`-80` dB) rather than the `-inf` a bare
`linear_to_db(0)` would give - and the music keeps playing underneath, so turning
the dial back up restores it without restarting the track. It takes effect at
once, also on music that is already fading in - the fade climbs towards the level
asked for at that moment, not the one it started with - and `set_music_volume()`
/ `set_sound_volume()` respect it, so the two never fight.

All six are kept in `user://fmw_vn_settings.json` (`@export`ed as
`settings_path`) - one file for the whole project, separate from every save slot
and from the progress record, so loading an old save does not put the dials back:

```json
{
  "version": 1,
  "writing_speed": 1.0,
  "fast_writing_speed": 4.0,
  "auto_forward_seconds": 0.05,
  "master_volume": 1.0,
  "screen_mode": "maximize",
  "language": ""
}
```

`language` is empty until the player picks one, which means "no opinion": every
story is read in its own default. A code the story is not told in is refused by
`set_language()` and falls back to the story's own default when reading, so the
file can never leave a reader with no line to read.

The file is meant to be readable: an unknown key is dropped, a value out of range
is clamped into it, and one that is not a number at all falls back to that
setting's default - so a hand-edited file can never leave the player in a state it
cannot read. A file that is not JSON is reported and treated as absent. The screen
mode is stored by name (`windowed` / `maximize` / `full_screen`), so it stays
readable.

`remember_settings = false` (the `@export` next to `settings_path`) makes the
player run on its defaults and never read or write the file - the tools and the
review harnesses run that way, so a probe can be neither disturbed by somebody's
saved speeds nor write over them. On a display server with no window (headless)
the mode is stored and applied to nothing.

From your own code:

```gdscript
player.writing_speed()            # 1x, the multiplier on every text_speed
player.set_speed_scale(2.0)       # the same dial Ctrl + Right turns
player.fast_writing_speed()       # 4x
player.set_fast_speed(10.0)       # clamped to 1x..16x
player.auto_forward_seconds()     # 0.05
player.set_auto_forward_seconds(0.2)
player.screen_mode()              # StorySettings.ScreenMode.MAXIMIZED
player.set_screen_mode(StorySettings.ScreenMode.FULLSCREEN)
player.apply_screen_mode()        # put the window in the mode that is set
player.settings()                 # the StorySettings object itself
player.settings_summary()         # the dials and the screen mode, for a log
player.language()                 # "id": the language being read
player.set_language("en")         # switches it, keeping the place in the story
player.reset_language()           # back to the story's own default
player.master_volume()            # 1.0: x every story's own music/sound levels
player.set_master_volume(0.5)     # clamped to 0..1, and heard straight away
player.reset_settings()           # back to the defaults, and written
```

Every one of those returns the value it ended up at, so a value that was clamped
(or a mode that is not one of the three, or a language the story is not told in,
which are both ignored) is visible to the caller.

## Saving and loading

`save_game()` writes the current position to `user://fmw_vn_save.json`
(`@export`ed as `save_path`). It stores the story file, the slide index, the
pictures currently on screen, the music and the history:

```json
{
  "version": 1,
  "title": "FMW_VN Demo - After the Bell",
  "story": "res://VN/Story/story.json",
  "chapter": "ch02_the_rooftop.json",
  "slide_index": 13,
  "slide_id": "mika_promises",
  "label": "Mika: Worth it. Look at that sky.",
  "saved_at": "2026-09-29 21:30:12",
  "background": "res://VN/assets/bg/bg_sunset.png",
  "characters": [ { "id": "ren", "image": "...", "x": 0.22, "tint": "#c8d8ffff" } ],
  "music": "res://VN/assets/audio/music_sunset.wav",
  "music_volume": 0.5,
  "sound_volume": 0.8,
  "history": [ { "speaker": "Mika", "text": "There you are!", "choice": false } ]
}
```

Pictures and cast travel with the save, because a slide does not have to repeat
what is already on screen - loading jumps straight back into the scene. Loading
also re-reads the story, so saves keep working after you edit text.

A save written against an older revision of the story still loads. The **slide
id** is what names the scene, so it is used in preference to `slide_index`: if an
update added or removed slides ahead of the saved one, the index alone would land
on the wrong line, while the id still leads to the same scene. When the id is gone
- the slide was deleted or renamed - the load falls back gracefully: the saved
index is clamped into range, and nudged to the start of the chapter the save was
in when it no longer lands inside it, with a toast reading `Scene changed after
update, resuming nearby.` rather than an error. `version` stays `1`.

Variables are restored on top of the story's declared starting values, so a
variable added to the story after the save was written keeps its default instead
of being wiped by the older save data.

```gdscript
player.save_game()                  # or save_game("user://my_save.json")
player.load_game()                  # or load_game("user://my_save.json")
if player.save_exists():
    print("there is a saved game")
```

To load a save automatically when the game starts:

```gdscript
func _ready() -> void:
    player.play_on_start = false
    if player.save_exists():
        player.load_game()
    else:
        player.load_story()
```

## Save slots and the book

On top of the single file above, the player has a fixed set of **slots**
(`user://fmw_vn_slot_1.json` .. `fmw_vn_slot_6.json`, `VNPlayer.SLOT_COUNT`).

```gdscript
player.save_game_to_slot(2)          # slot 3 in the book
player.load_game_from_slot(2)
player.slot_exists(2)
var info := player.slot_info(2)      # {} when the slot is empty, otherwise
                                     # title / chapter / label / saved_at / slide_index / slide_id
```

The slots are the **Save** and **Load** pages of the book, all part of
`Framework_VN/scenes/vn_screen.tscn` (`BookOverlay`), so restyling them is the same as
restyling anything else. From code:

```gdscript
player.open_book(VNPlayer.BookPage.LOAD)   # the book, already on a page
player.open_book_page(VNPlayer.BookPage.SAVE)  # or toggle that page
player.is_book_open()
player.book_page()
player.close_book()
```

Under the pages the book carries three buttons of its own: **Settings** (the same
page the main menu opens, over the book), **Main Menu** (puts the story down and
opens the menu over it, which pauses the story without resetting it), and
**Close (Esc)**. Both are wired to `open_settings()` and `open_main_menu()`, so
turning one into a different button is a change in the scene alone.

The older names still work and mean the pages of the book:
`open_save_menu(VNPlayer.MenuMode.LOAD)` / `close_save_menu()` (the slot pages),
`is_menu_open()` / `menu_mode()` (which way the slots are working), and
`open_history()` / `close_history()` / `is_history_open()` (the History page).

Each row shows the chapter, a preview of the line that was on screen and when it
was saved. On the Load page, empty slots are disabled. Saving from the book
closes it again; loading jumps straight back into the scene and closes it too.

## Progress: how far the player ever got

A save answers "where is the player right now". The **progress record** answers a
different question - how far the player has ever got - and it is deliberately not
a save: it is global (one file for every story in the project, not one per slot),
it is written as the story is played rather than when the player asks, and it
only ever moves forwards. Loading an older save, replaying a chapter or taking
the other branch cannot take it back. Only the reset calls below can.

```gdscript
player.furthest_id()      # "curtain_same_place" - the furthest dialogue id
player.furthest_index()   # its slide index
player.furthest_label()   # its line, for a menu row
player.progress_summary() # everything above, plus `slides_seen`
player.seen_ids()         # every dialogue id ever shown, in order
player.was_seen("opening")
player.progress().has("res://VN/Story/story.json")
```

Every one of them also takes a story path, so a menu can list every story the
player has touched without loading any of them:

```gdscript
for path in player.progress().stories():
    var info := player.progress_summary(path)
    print("%s - %d id(s), last played %s" % [info["title"], info["slides_seen"], info["updated_at"]])
```

An empty path means the story that is loaded; a player with nothing loaded has no
furthest point to report.

### The file

`user://fmw_vn_progress.json` (`@export`ed as `progress_path`), one entry per
story, keyed by the story file:

```json
{
  "version": 1,
  "stories": {
    "res://VN/Story/story.json": {
      "title": "FMW_VN Demo - After the Bell",
      "furthest_index": 18,
      "furthest_id": "curtain_same_place",
      "furthest_label": "",
      "furthest_chapter": "ch02_the_rooftop.json",
      "seen": ["opening", "mika_appears", "..."],
      "first_played_at": "2026-10-11 06:10:00",
      "updated_at": "2026-10-11 06:12:31"
    }
  }
}
```

`furthest_index` is the highest slide index ever reached - "how deep into the
file", not "how far through the plot", since a branching story's file order is
not its story order. `furthest_id` is that slide's `id` (empty when it has none)
and `furthest_label` is what is on screen there. Every dialogue id that was ever
shown is in `seen` too, so a second playthrough down another branch shows up
there even when it does not move the furthest point; a slide with no `id` is
counted by index only and adds nothing to `seen`.

Nothing is written until there is something to remember: a player who has not
started the story leaves no file behind, and a reset takes the file away with it
rather than leaving an empty one to be read back.

### Watching it, and resetting it

```gdscript
player.progress_advanced.connect(func(story_path: String, entry: Dictionary) -> void:
    print("new ground: ", entry["furthest_id"]))

player.reset_progress()       # forget one story (the loaded one by default)
player.reset_all_progress()   # forget every story
player.save_progress()        # it is written for you; this forces it now
```

`progress_advanced(story_path, entry)` fires after the file is written, once per
slide that reached further. Set `track_progress = false` on the player to record
nothing at all - `Framework_VN/tools/smoke_test.gd` does this, so a test run never touches the
player's own record.

The store on its own is `StoryProgress`: `load_from_disk()`, `is_loaded()`,
`has_file()`, `is_dirty()`, `save()`, `to_dict()` / `from_dict(data)`,
`stories()`, `has(path)`, `entry_for(path)`, `summary(path)`, `furthest_id` /
`furthest_index` / `furthest_label(path)`, `seen_ids(path)`, `seen_count(path)`,
`was_seen(path, id)`, `record(path, title, index, id, label, chapter)`,
`clear(path)`, `clear_all()`, `default_path()`, its `advanced(story_path, entry)`
signal and its format `VERSION`.

### Continuing where the player left off

The record keeps the dialogue id, not just the index, so a Continue is one call -
and because the id is looked up in the story as it is now, a slide that has since
been renamed is noticed and the player starts from the top instead of jumping
somewhere unrelated:

```gdscript
var result := StoryParser.parse_file("res://VN/Story/story.json")
player.begin(result.story)                        # the opening is on screen
var furthest := player.furthest_id()
if furthest != "" and player.current_story().index_of(furthest) >= 0:
    player.go_to(furthest)                        # back to where they got to
```

The demo's main menu has no Continue button, but `furthest_label()` is exactly
what a row in one would show.

## The CG gallery

A story can declare the pictures worth collecting - a `gallery` block at the top
level of the story's first file (beside `settings`, not in a chapter):

```json
"gallery": [
  { "id": "cg_classroom", "title": "The Classroom, After the Bell",
    "caption": "Where chapter one starts.",
    "image": "classroom_after_bell",
    "unlock": "opening" },
  { "id": "cg_rooftop", "title": "The Rooftop at Sunset",
    "image": "rooftop_sunset", "unlock": { "index": 12 } },
  { "id": "cg_worth_it", "title": "Worth It", "image": "worth_it",
    "unlock": { "seen": "ending_same_place", "index": 17 } }
]
```

| key | type | default | meaning |
| --- | --- | --- | --- |
| `id` | string | - | The name the unlock is recorded under. Must be unique. |
| `title` | string or one per language | the id | Shown under the tile, and over the big view. |
| `caption` | string or one per language | `""` | The line under the title in the big view. |
| `image` | alias or path | - | The picture: an `assets.cg`, `backgrounds` or `characters` alias, or a path. |
| `unlock` | string or object | - | What the player has to have done. |

`unlock` is either a slide id - the dialogue id the player has to have **seen** -
or an object with `seen` and/or `index` (the furthest slide index, counted from 0,
has to be at least that). An id that names no slide, or an index past the end of
the story, is a parse error: a goal nothing can reach is a CG nobody can unlock.

### What unlocks a CG

The goal is judged against the **global progress record** - the one
[above](#progress-how-far-the-player-ever-got), never a save. That is the whole
point, and it gives the gallery three properties worth knowing:

- **A save cannot take it back.** Loading an older save, replaying a chapter or
  taking the other branch leaves the gallery exactly as it was, because the
  furthest point and the seen ids only ever grow.
- **It is one-way.** Once unlocked, a CG stays unlocked: the id is written down
  the moment it was earned, so even editing the story afterwards - a goal that
  now reads as something the player never reached - cannot lock it again.
- **It is checked live.** A goal the progress already covers counts at once (a
  record written before the gallery existed, or a CG added in a later version),
  so the menu never shows a CG as locked that the player has plainly earned.

Unlocking happens as the story is played: every slide shown is noted in the
record, and each CG whose goal that record now meets unlocks there and then.
`cg_unlocked(story_path, cg_id)` fires once per CG, and a toast says so on screen.

```gdscript
player.gallery()            # [{ id, title, caption, image, goal, unlocked }, ...]
player.gallery_progress()   # { "unlocked": 3, "total": 4 }
player.is_cg_unlocked("cg_rooftop")
player.unlocked_cgs()       # the ids, in the order they were unlocked
player.cg_unlocked.connect(func(_story: String, cg_id: String) -> void:
    print("collected ", cg_id))
```

`is_cg_unlocked(id, story_path)` and `unlocked_cgs(story_path)` take a story path;
with none they mean the story that is loaded, or - before anything has started -
the story this player *would* start (`story_path`), which is what the menu needs.

### The Gallery button

The main menu has a **Gallery** button between Load and Settings. It turns to a
page of tiles, one per CG: an unlocked tile shows its picture and its title, a
locked one is dark and says `???`, and the line above counts them (`3 of 4
unlocked`). Clicking an unlocked tile shows it full size with its title and
caption; a click or `Esc` closes the picture, a second `Esc` (or **Back**) the
page. A locked tile is not clickable at all.

```gdscript
player.open_gallery()
player.is_gallery_open()
player.open_gallery_view("cg_worth_it")   # false for a locked CG
player.gallery_view_id()
player.close_gallery_view()
player.is_gallery_view_open()
```

The tiles come from the loaded story, or from `story_path` when nothing has
started yet, so the menu shows the gallery before the first **New game**.

### Resetting, and tests

`track_progress = false` records nothing, so no CG can unlock behind it - the
tools and the review harnesses run that way. Resetting the record
(`reset_progress()` / `reset_all_progress()`) forgets the CGs with it; that is the
only thing that can.

The placeholder CGs the demo collects are generated rather than drawn:

```bash
godot --headless --path . --script res://Framework_VN/tools/make_placeholder_cg.gd
godot --headless --path . --import
```

## Recipes

**Change a line** - edit `text` in the chapter file.

**Add a slide in the middle** - paste a new object in the `slides` array. Slides
without `next` simply play in order, so nothing else has to change.

**Branch on a choice** - see [`choices`](#choices); `next` accepts an id, a slide
index, or `null` for "the end".

**Jump backwards** (a loop) - `"next": "some_id"`. The parser only rejects
unknown targets, not loops.

**Hold a picture with no text** - `{ "background": "sunset", "wait": 1.2 }`.

**Play a line slowly** - `"text_speed": 20`. Fast: `"text_speed": 90`. Instant:
`"text_speed": 0`.

**Auto-advance a line** - `"auto": true` moves on after roughly reading speed;
add `"wait": 3` to set the pause exactly.

**Stop the music at the ending** - `{ "bgm": "stop", "wait": 1.6, "next": null }`.

**Change scene with a wipe instead of a fade** -
`{ "background": "hallway", "transition": "wipe_left", "wait": 0.9 }`.

**Punch up a line** - `{ "speaker": "Mika", "text": "Run.", "effects": "shake" }`.
Bigger: `{ "type": "shake", "strength": 40, "duration": 0.7 }`.

**Hold a slow push-in over a scene** - put `{ "type": "zoom", "to": 1.08, "duration": 4 }`
on the first slide of the scene, and `"effects": ["reset"]` on the slide where
it should snap back.

**Flash something important** - `{ "type": "flash", "color": "#ffe9b0", "duration": 0.9 }`.

**Save into a slot from a script** - `save_game_to_slot(0)`, and list what is
there with `slot_info(0)`.

**Show only a name plate, no line** - `{ "speaker": "Mika", "text": "", "wait": 1.5 }`.
A slide without text always advances by itself, so it needs a `wait` to stay on
screen.

**Put a character on the left / in the middle / on the right** -
`"position": "left"`, `"center"` or `"right"` (or a pair, like `"bottom-left"`),
and `"x": 0.35` when you want an exact spot.

**Lift a character off the floor** - `"scale": 0.6, "vertical": "middle"` (or an
`"y"` between 0, the top of the screen, and 1, the bottom edge).

**Show the speaker as a square in the text box** - nothing to do: the speaking
character portraits itself. Point `"portrait"` at another picture to change it,
or at `""` to hide the square on that slide.

**Send one character off, then bring them back** - `"hide": ["ren"]` on one
slide and `"show": ["ren"]` on a later one, each with a simple `"with"`
transition. Only that character changes; the rest of the line-up stays put.

**Pause mid-sentence** - `{w=0.5}` (half a second, then carry on) or a bare
`{w}` (hold until the player clicks) anywhere inside `text`. Clicking during a
pause ends it without filling in the rest of the line.

**Resize the choice buttons** - `VNPlayer` holds `CHOICE_WIDTH`, `CHOICE_HEIGHT`,
`CHOICE_FONT_SIZE` and `CHOICE_GAP`. They wear the same small style as the
Book button and the book's tabs, and the list is centred on the screen, so one
answer sits in the middle and five straddle it just the same. A list long enough
to reach the text box is lifted until `CHOICE_GAP` is left between them, and one
longer still stops at `CHOICE_TOP_MARGIN` and logs a warning rather than running
off the top.

**Reskin the text box** - the panel is a real asset: `VN/assets/ui/textbox.png`, a
nine-slice picture the scene points a `StyleBoxTexture` at. Overwrite it (or
point `TextBox`'s `panel` style at your own file) to change the box's body,
frame, corners and shadow without touching the scene. The nine-patch border is
48 px on every side (`texture_margin_*`), and the style also expands the box by
24 px (`expand_margin_*`), so keep those bands in your own picture: in the stock
file the outer 24 px is the soft shadow (transparent), then a 3 px frame, then
the body. The stock file is a placeholder you can overwrite.

**Change text box size / fonts / colours** - it is all in `Framework_VN/scenes/vn_screen.tscn`:
`TextBox` (its `offset_*` say where it sits; its look comes from
`VN/assets/ui/textbox.png`), `TextBox/SpeakerLabel` (name plate),
`TextBox/TextContent/DialogueLabel` (body
text - set `normal_font_size`, `bold_font_size`, `italics_font_size` and
`bold_italics_font_size` together, or `[b]`/`[i]` words fall back to the 16 px
theme default and render much smaller than the rest of the line),
`TextBox/PortraitFrame` (+ its stylebox, the border of
the square portrait), and the `Theme_vn` sub-resource for every button in the
scene. The `BookButton` HUD button carries its own small styleboxes
(`StyleBoxFlat_btn_sm*`) and a 20 px font override, and the book's tabs carry
`StyleBoxFlat_tab*` (rounded on top only, so they read as bookmarks), so sizing
any of them leaves the choice buttons on the `Theme_vn` default. How heavy `[b]` looks
is `VNPlayer.BOLD_EMBOLDEN` (0.6; Godot's default theme uses 1.2).

**Start in fullscreen** - in `project.godot`, set `display/window/size/mode = 3`.
A player who has picked a screen mode on the Settings page keeps it; with no
`user://fmw_vn_settings.json` yet, the project's own mode is left alone.

**Different resolution** - change `display/window/size/viewport_width/height` in
`project.godot`. The scene is anchored, and characters scale with the screen
height, so 1280x720 works too.

## Tools and API

```bash
# check the story (and every chapter it lists), prints errors and warnings
godot --headless --path . --script res://Framework_VN/tools/validate_story.gd

# same, plus a dump of every parsed slide, its chapters and settings
godot --headless --path . --script res://Framework_VN/tools/validate_story.gd -- res://VN/Story/story.json -v

# play the whole story through with no window and check the path taken
godot --headless --path . --script res://Framework_VN/tools/smoke_test.gd

# rewrite the placeholder music and sound effects
godot --headless --path . --script res://Framework_VN/tools/make_placeholder_audio.gd

# rewrite the placeholder CG pictures the gallery collects
godot --headless --path . --script res://Framework_VN/tools/make_placeholder_cg.gd
godot --headless --path . --import        # after adding or changing assets
```

The first two exit with code 1 when something is wrong, so they fit in a git hook
or CI. (Godot may print a harmless "instances were leaked at exit" notice after
the smoke test, because it stops the game mid-fade.)

From GDScript:

```gdscript
var result := StoryParser.parse_file("res://VN/Story/story.json")
for warning in result.warnings:
    push_warning(warning)
if not result.ok:
    for error in result.errors:
        push_error(error)
    return
player.begin(result.story)          # or player.load_story() to use its own path
```

`StoryParser` also offers `parse_text(json_string)` and `parse_dict(dictionary)`
if the story arrives from somewhere else, plus `describe_slide(slide)` for
debugging. `Story` gives you `slide_count()`, `slide_at(index)`,
`index_of(id)`, `chapter_of(index)`, `describe()` and, for a story with
conditions, `variables`, `variable_names`, `has_variable(name)`, `new_vars()`,
`is_visible(index, vars)`, `next_after(index, vars)`,
`visible_choices(index, vars)` and `apply_set(index, vars)` - the same answers the
player uses, so a tool can walk a story that branches. `StoryVars` is the live
state: `get_value`, `set_value`, `is_declared`, `reset`, `to_dict` / `from_dict`,
`evaluate(expression)` and `is_true(expression)`.

`VNPlayer` emits `story_loaded`, `slide_shown(index)`, `choice_made(index)`,
`variable_changed(name, value)`, `progress_advanced(story_path, entry)`,
`cg_unlocked(story_path, cg_id)`, `story_finished` and `story_failed(errors)`, and
offers `advance()`, `choose(i)`, `visible_choices()`, `go_to(id)`, `restart()`,
`current_slide()`, `current_slide_index()`, `get_variable(name)`,
`set_variable(name, value)`, `set_variables(values)`, `has_variable(name)`,
`reset_variables()`, `evaluate(condition)`, `story_variables()`,
`is_playing()`, `is_choosing()`, `history()`, `open_book(page)`,
`open_book_page(page)`, `close_book()`, `toggle_book()`, `is_book_open()`,
`book_page()`, `open_history()`, `close_history()`, `is_history_open()`,
`save_game()`, `load_game()`, `save_exists()`,
`save_game_to_slot(i)`, `load_game_from_slot(i)`, `slot_info(i)`,
`progress()`, `progress_summary(path)`, `furthest_id(path)`,
`furthest_index(path)`, `furthest_label(path)`, `seen_ids(path)`,
`was_seen(id, path)`, `reset_progress(path)`, `reset_all_progress()`,
`save_progress()`, `gallery()`, `gallery_progress()`, `is_cg_unlocked(id, path)`,
`unlocked_cgs(path)`, `open_gallery()`, `is_gallery_open()`,
`open_gallery_view(id)`, `gallery_view_id()`, `close_gallery_view()`,
`is_gallery_view_open()`,
`open_save_menu(mode)`, `close_save_menu()`, `is_menu_open()`,
`play_effect(type, params)`, `reset_effects()`, `is_effect_running()`,
`play_music(path)`, `stop_music()`, `play_sfx(path)`,
`set_music_volume(v)` and `set_sound_volume(v)`.

## What is not included

Deliberately missing, because this is a small framework rather than a full
engine:

- **A title screen.** The main menu's pages (and the **Settings** page) are a good
  template for one, and `set_music_volume()` / `set_sound_volume()` are already
  there to drive it.
- **Chapter select.** `story.chapters` lists every file with its slide range,
  and `go_to(id)` jumps anywhere, so a menu over the first slide of each chapter
  is a small script.
- **Voiced lines, lip flaps, animated sprites.**
- **A visual editor for conditions.** They are strings in JSON; the validator
  and `describe_slide()` (via `validate_story.gd -v`) are what check them.
- **Variables that outlive one playthrough.** `variables` is the *starting*
  state and the save file carries the current one. The progress record is the
  only thing written between sessions on its own, and it holds one dialogue id,
  not the variables: there is no engine-side save of counters, flags or
  inventory - a save (or a `"set"` that reads the record's furthest slide) is
  how that travels.
- **Per-character crossfade of expressions** - reuse the same `id` and swap
  `image`: the picture is replaced in place.
