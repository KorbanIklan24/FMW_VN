# FMW_VN

A small, data-driven visual novel framework for Godot 4.

The engine knows how to show a picture, a line-up of characters, a block of text
that types itself out, music, choices and history; **the story itself is JSON**.
No GDScript needed to write, reorder or extend a scene - edit a chapter file,
press F5, done.

`VN/Story/story.json` -> `StoryParser` (validate + resolve) -> `VNPlayer` (render) -> screen

## Features

- **Full HD pictures** - the project renders at 1920x1080 and scales to any
  window; backgrounds crossfade into each other.
- **Block text** - a styled text box with a speaker name plate and a typewriter
  effect. First click fills the line in, the next one moves on.
- **Asset-driven text box** - the dialogue panel is a nine-slice picture at
  `VN/assets/ui/textbox.png`, not hard-coded in the scene, so it can be replaced
  with your own art like a background.
- **Main menu** - New game, Load, Gallery, Settings, Info and Credits, in a
  plain-colour column on the left. Its backdrop and buttons are real assets too
  (`VN/assets/ui/menu_bg.png`, `menu_button*.png`), so you can reskin it in place.
- **Characters, placed from the JSON** - left, center or right of the screen
  (or a pair like `"bottom-left"`), higher or lower with `vertical` / `y`,
  scaled, flipped and tinted per slide.
- **Show and hide, one at a time** - `show` and `hide` change the cast a
  character at a time, Ren'Py style, each with a simple `dissolve` or `none`
  transition. `characters` still sets a whole line-up at once.
- **Square portraits** - the speaker also shows up as a small square with a thin
  border in the left of the text box, which makes room for it. Which picture,
  and whether it shows at all, comes from the same JSON.
- **Next slide** - click, tap, `Space` or `Enter` advances. Slides can also move
  on by themselves (`wait`, `auto`), and `next` jumps to any slide by id.
- **Inline pauses** - `{w=0.5}` in a line holds the next words for half a
  second (or a bare `{w}` until a click), Ren'Py style.
- **Read at your own speed** - `Ctrl` + `Left` / `Right` turn the typewriter
  from `0.25x` to `8x`; `Tab` (or a held `Ctrl`) switches fast-forward on - `4x`
  faster to start with, and it skips on to the next line the moment one finishes
  instead of waiting for a click.
- **Auto-forward** - `A` reads hands-free: a line holds for `0.05 s` per
  character (spaces included) plus its own `{w}` pauses, then moves on.
- **Told in more than one language** - a story declares its languages
  (`"languages": { "en": "English", "id": "Indonesian" }`), keeps its **base
  scripts** in one of them and puts every other language in a **mirror file**
  beside the script it mirrors (`ch01.json` -> `ch01.id.json`) carrying the same
  lines in the same order - so switching language cannot move the story: it is
  the same slide, at the same point, in the other language, with the same
  variables, progress and history. A mirror carries the words only (a line's
  `text`, its `speaker`, the answers and their `{w}` pauses); the pictures,
  `next`, conditions and pacing stay in the base script, and a mirror that does
  not line up is a reported error rather than something quietly carried along.
  The demo is English (the language it is written in) with Indonesian mirrors.
- **Settings the player keeps** - a **Settings** page with five dials: the writing
  speed (`0.25x`..`8x`), the fast-forward speed (`1x`..`16x`), the auto-forward
  formula's time per character (`0`..`0.5 s`), the screen mode (Windowed /
  Maximize / Full screen, through `DisplayServer.window_set_mode()`) and the
  language to read in (offered only for a story told in more than one, and taken
  from the story itself). They are
  the player's rather than the story's, and they live in one file of their own
  (`user://fmw_vn_settings.json`) - not in a save slot, so loading an old save
  does not put the dials back. Hand-editable: a value out of range is clamped and
  a malformed one falls back to its default, so the file can never strand the
  player. `remember_settings = false` runs on the defaults and never touches it.
- **Hide the box** - a right click takes the text box, the hint and the choices
  off the screen so the picture shows through, and brings them back.
- **Choices** - a slide can offer buttons that lead anywhere, including `null`
  for "the ending". As many as you like: the list is centred on the screen and
  stays clear of the text box.
- **Variables and conditions** - a story declares its state (`"variables"`),
  writes it from any slide (`"set"`, literal or `{ "expr": "count + 1" }`) and
  reads it back: a slide can be skipped by its `"if"`, an answer can be offered
  only while its `"if"` holds - and that check is live, so writing a variable an
  answer reads toggles its button on and off while the question is still on
  screen - and `"branch"` picks the next slide from a list of conditions. Every condition is a string run against the live state by
  Godot's own `Expression`, so a typo is a reported parse error. `"next"` keeps
  taking a slide id or a plain index exactly as before, and variables live in
  their own table, so a name can never be mistaken for a slide id.
- **Chapters** - a story can be split over as many JSON files as you like. Slide
  ids and asset aliases are shared, and the last slide of a chapter flows into
  the next one.
- **Transitions** - `fade`, `cut`, `fade_black`, `wipe_*` and `slide_*`, named
  per slide. The picture decides how it arrives.
- **Screen effects** - `shake`, `flash`, `zoom`, `pulse` and `reset`, with
  parameters, straight from the JSON.
- **Music and sound** - per-slide `bgm` changes (crossfaded, looping) and `sfx`
  effects, with volumes in the story file. Any `.ogg`, `.wav` or `.mp3` of your
  own works - those are the only formats Godot 4 can import; the generated WAVs
  are only placeholders.
- **One book for everything you keep** - the `Book` button (`B`) opens the
  history, the save slots and the load slots as three pages of one overlay, with
  bookmark tabs: the page that is showing is the tab tucked into the page edge.
- **Scrollable history** - every line read, plus the answers taken, in one
  reviewable list (the book's first page).
- **Save slots** - six slots in an on-screen menu, with the chapter, a preview
  of the line and a timestamp on every row. JSON on disk, pictures and cast
  included.
- **Progress that outlives the saves** - one file
  (`user://fmw_vn_progress.json`, kept apart from the slots) remembers how far
  the player has ever got in *every* story: the furthest dialogue id it reached,
  that line and its chapter, and every id seen along the way. It is written as
  the story is played and nothing but a reset moves it back - not loading an
  older save, not replaying a chapter, not taking the other branch - so a
  "Continue" is one call. `track_progress = false` turns it off.
- **A CG gallery that cannot be un-earned** - a story declares its collectable
  pictures (`"gallery"`), each with a goal: a dialogue id the player has to have
  seen, a slide index they have to have got past, or both. The main menu's
  **Gallery** button shows them as a grid - unlocked tiles carry their picture and
  title, locked ones are dark `???` - and clicking one opens it full size. It is
  judged against the global record rather than a save, so loading an older save
  cannot lock a CG again, and an unlock is written down the moment it is earned.
- **JSON -> script parser** - `StoryParser` validates the files and turns them
  into a flat list of slides that `VNPlayer` plays. Every mistake (unknown slide
  id, missing picture, typo in a key) is reported instead of crashing.

Every picture is a real PNG file and the music and effects are real WAV files,
generated as simple placeholders so you can watch and hear the framework work
before you make anything of your own.

## Quick start

```bash
godot --path .          # or open project.godot in the Godot editor and press F5
```

It opens on the **main menu**; press **New game** to play. `Load` reads a save
slot, and `Settings` / `Info` / `Credits` are pages over it.

| input | action |
| --- | --- |
| click / tap / `Space` / `Enter` | next slide |
| `B` or the Book button | open / close the book (history, save and load) |
| the book's tabs | click a tab to turn to that page |
| `Tab` / held `Ctrl` | fast-forward on / off (types at the fast-forward speed, 4x to start, and skips a finished line) |
| `Ctrl` + `Left` / `Right` | slower / faster typewriter, `0.25x` a step |
| `A` | auto-forward on / off |
| right click | hide / show the box, the hint and the choices |
| `Esc` | close the topmost overlay, or quit |

Then:

1. Open `VN/Story/ch01_after_the_bell.json` and edit the text of any slide. The
   demo's base scripts are written in English, and the Indonesian lines sit in
   the `.id.json` mirror files beside them - see
   [languages](GUIDE.md#languages-the-same-story-in-more-than-one).
2. Drop your own pictures under `VN/assets/` and music under `VN/assets/audio/`, then
   point an alias or a slide at them. Your own `.ogg` / `.wav` / `.mp3` plays
   as-is - replace the generated placeholder WAVs, or point a `music` / `sounds`
   alias at your file (see
   [music and sound](GUIDE.md#using-your-own-audio-files)).
3. Place the cast with `"position"` (`"left"`, `"center"`, `"right"`, or a pair)
   and put the speaker in the text box with `"portrait"` - see
   [characters](GUIDE.md#characters) and
   [squares in the text box](GUIDE.md#squares-in-the-text-box).
4. Add movement with `"transition"` (how a new picture arrives) and `"effects"`
   (`shake`, `flash`, `zoom`, `pulse`) - see
   [Transitions](GUIDE.md#transitions) and [Screen effects](GUIDE.md#screen-effects).
5. Make the story remember things with `"variables"`, `"set"` and `"if"` -
   see [variables and conditions](GUIDE.md#variables-and-conditions).
6. Add pictures worth collecting with a `"gallery"` block and an `"unlock"` goal
   each - see [the CG gallery](GUIDE.md#the-cg-gallery).
7. Tell the story in more than one language: declare `"languages"` and give each
   script a mirror file beside it holding the same lines in the same order - see
   [languages](GUIDE.md#languages-the-same-story-in-more-than-one).
8. Keep the checker running while you write - no editor needed:

```bash
godot --headless --path . --script res://Framework_VN/tools/validate_story.gd
godot --headless --path . --script res://Framework_VN/tools/smoke_test.gd
```

`validate_story.gd` checks the JSON (and every chapter it pulls in);
`smoke_test.gd` plays the whole story through and confirms the player followed
every `next` and `branch`, took the first answer at each choice, skipped the
slides a condition hides and showed the right picture.
Both exit with code 1 when something is wrong, so they work in a git hook or CI.

## Layout

The project is split by who edits what: **`VN/`** holds everything about the
story — the **`Story/`** JSON the writer writes and the **`assets/`** (pictures,
music and sound) it plays — **`Framework_VN/`** is the engine that plays it, and
**`Others/`** is the documentation. Everything runs from the project root, where
`project.godot` lives.

```
project.godot                        Full HD settings (1920x1080, canvas_items stretch)
icon.png                             the project icon

VN/Story/story.json                  the index: settings, chapters, shared aliases
VN/Story/ch01_*.json                 chapter one, chapter two... (the actual slides)
VN/Story/ch01_*.id.json              their Indonesian mirrors (one per script, per language)

VN/assets/bg, VN/assets/char         background and character pictures
VN/assets/cg                         the CGs the demo's gallery collects
VN/assets/audio                      music and sound effects
VN/assets/ui                         text box panel, main-menu background and buttons

Framework_VN/scenes/vn_screen.tscn   screen: pictures, text box, choices, history, menu
Framework_VN/scripts/story_parser.gd JSON -> validated slide list (StoryParser)
Framework_VN/scripts/story_vars.gd   the story's variables, and the Expression that reads them
Framework_VN/scripts/story_progress.gd   how far the player has ever got, in one file
Framework_VN/scripts/story_settings.gd   the player's own settings, in one file
Framework_VN/scripts/vn_player.gd    plays it: pictures, text, audio, history, saves
Framework_VN/tools/                  validate_story, smoke_test, the placeholder makers

Others/README.md                     this file
Others/GUIDE.md                      schema reference, recipes, API
```

Every picture, sound and song is a file under `VN/assets/`, named by an alias in
`VN/Story/story.json` — replace the file, or point the alias somewhere else, and
the story plays your art with no code change. The shipped pictures are simple
placeholders; drop your own over them.

## Using it in your own project

Copy `Framework_VN/` and `VN/`, or just point the existing scene at your own
file. Two calls are all it takes:

```gdscript
var player := load("res://Framework_VN/scenes/vn_screen.tscn").instantiate()
add_child(player)
player.play_on_start = false          # if you want to drive it yourself
var result := StoryParser.parse_file("res://VN/Story/story.json")
if result.ok:
    player.begin(result.story)
```

See **[GUIDE.md](GUIDE.md)** for the full JSON schema, the save format and the
complete `VNPlayer` API.
