# REVIEW — FMW_VN

**Subject:** `FMW_VN` — a small, data-driven visual novel framework for Godot 4:
the story is JSON, the engine is GDScript.
**Engine:** Godot `4.7.2.stable.fedora.ed1daf0bf`, headless.
**Method:** every feature driven through the real project (the scene, the parser,
the player, the stores) by 22 independent harnesses, plus the two shipped tools.
The harnesses live in the clone `FMW_VN_test/review/`, whose `VN/`,
`Framework_VN/` and `Others/README.md` + `Others/GUIDE.md` are byte-identical to
this project, so they exercise exactly the code reviewed here. Both projects use
the same layout - `VN/Story/` (the story the writer edits), `VN/assets/` (the
pictures, music and sound it plays, all named by `story.json`), `Framework_VN/`
(the code that plays it), `Others/` (the documents) - with `project.godot` at the
root. Nothing was modified to make a test pass.

## Short answer

**Yes — the framework does everything it claims, and the two updates this review
round is about (English as the primary language, and a save that survives content
revisions) are real, not papered over.**

- **22 of 22 harnesses exit 0**, reporting `failures=0` (or `ok=true`).
- Both shipped tools exit 0: `validate_story.gd` → `OK … 0 warning(s)`;
  `smoke_test.gd` → `OK - played 16 slide(s)`.
- The demo (`FMW_VN Demo - After the Bell`, 21 slides, 2 chapters, 4 CGs) parses
  clean, plays end to end, and reads in **English by default** with a working
  Indonesian switch.
- A save written against a superseded revision of the story still loads: the
  saved **slide id wins over the saved index**, and when the scene is gone the
  load lands nearby and says so instead of failing.

## How it was tested

```bash
# the harnesses (in the clone; its shared tree is identical to this project)
cd FMW_VN_test
godot --headless --path . --import            # once, on a fresh checkout
for p in review/check_*.gd; do
    godot --headless --path . --script "res://$p"
done

# the two shipped tools (in this project)
cd ../FMW_VN
godot --headless --path . --script res://Framework_VN/tools/validate_story.gd
godot --headless --path . --script res://Framework_VN/tools/smoke_test.gd
```

Every command's exit status was read directly (`$?` / `PIPESTATUS`), never
inferred from filtered output. The runner additionally requires the harness's own
summary line: a run that exits 0 without printing it ended somewhere it should
not have, and is reported as a failure (`exit=9`). That is checked with a
negative control - a probe that quits immediately - which the runner does flag,
so a harness that dies early cannot pass quietly.

## Results at a glance

| harness | subject | result |
| --- | --- | --- |
| `check_json_and_png.gd` | JSON becomes a story; PNGs reach the screen (pixel-checked) | `review: ok=true slides=2`, exit 0 |
| `check_audio.gd` | external Ogg / MP3 / WAV play and loop; import-by-extension mismatch is caught | `review-audio: ok=true`, exit 0 |
| `check_long_text.gd` | how much text fits in the box, and WHEN it overflows | `long-text: ok=true` (fits 400 chars, overflows at 480; first overflow at 436) |
| `check_cast.gd` | name plate vs portrait geometry; `characters` / `show` / `hide` / `with` | `cast: failures=0` |
| `check_choices.gd` | the choice box for 1–16 answers, centred and clear of the text box | `choices: failures=0` |
| `check_pauses.gd` | `{w=…}` pauses, tick by tick | `pauses: failures=0` |
| `check_speed.gd` | `Ctrl`/`Tab`/`A` through the real input path; the typewriter speed | `speed: failures=0` |
| `check_auto_forward.gd` | the auto-forward hold formula, tick by tick | `auto-forward: failures=0` |
| `check_fast_forward.gd` | fast-forward skips a finished line | `fast-forward: failures=0` |
| `check_hide.gd` | right-click hides the box, hint and choices, and brings them back | `hide: failures=0` |
| `check_book.gd` | the book: history, save and load pages, its button row; **and save/load across revisions** | `book: failures=0` |
| `check_book_settings.gd` | the Settings page opened from the book: pausing without moving the story, and the book's Main Menu button | `book settings: failures=0` |
| `check_quit_dialog.gd` | the confirmation `Esc` shows instead of quitting: its three answers, its modality, and that it asks before leaving | `quit dialog: failures=0` |
| `check_main_menu.gd` | the menu, its pages, Load and New game | `main menu: failures=0` |
| `check_ui.gd` | the HUD button and the softened bold in the dialogue | `ui: failures=0` |
| `check_textbox_asset.gd` | the nine-slice text box panel against the generated asset | `textbox asset: failures=0` |
| `check_variables.gd` | the variable system, conditions, and live choice toggling | `variables: failures=0` |
| `check_progress.gd` | the global, one-way progress record | `progress: failures=0` |
| `check_gallery.gd` | the CG gallery: goals, one-way unlocks, the menu page and viewer | `gallery: failures=0` |
| `check_settings.gd` | the settings page, the speeds, the formula, the file behind them | `settings: failures=0` |
| `check_master_volume.gd` | the master volume: the slider's range, what it does to music and sound, and that it survives a later run | `master volume: failures=0` |
| `check_language.gd` | the mirror contract, the switch that keeps the place, the setting | `language: failures=0` |

## The demo story

```
FMW_VN validating: res://VN/Story/story.json
OK - FMW_VN Demo - After the Bell (21 slides, 2 chapters, 4 CGs), 0 warning(s).

smoke test: FMW_VN Demo - After the Bell (21 slides, 2 chapters, 4 CGs) -> 16 slide(s) to play
smoke test: OK - played 16 slide(s), 2 choice(s), backgrounds correct, reached the ending.
```

The demo is told in two languages, declared in `VN/Story/story.json` as
`{ "en": "English", "id": "Indonesian" }` with `"default_language": "en"`. Its
**base scripts are English** (`ch01_after_the_bell.json`, `ch02_the_rooftop.json`)
and the **Indonesian mirrors sit beside them** (`ch01_after_the_bell.id.json`,
`ch02_the_rooftop.id.json`), one entry per line in the same order.

## Feature findings

### Languages — the same story in more than one

```
demo       FMW_VN Demo - After the Bell … | languages={ "en": "English", "id": "Indonesian" } default=en
demo       17 of 21 lines read differently per language, 4 with no text
languages  languages_of(story.json) = { "en": "English", "id": "Indonesian" } default=en
```

- The **mirror contract is enforced, not assumed**. A mirror with the wrong
  number of lines, a line out of order, a structural key inside a mirror, an
  answer count that differs, an answer carrying its own `next`, a mirror with a
  `settings` or `chapters` block, a `default_language` that was never declared, a
  code unsafe in a file name, a language with no name to show — each is a
  reported parse error naming the file and the line.
- A **missing mirror** is a warning, not an error, and those lines stay in the
  default language; a line a mirror leaves `text` out of keeps the default
  language's line while the rest of the file is translated. A story with no
  `languages` block parses exactly as before and gains no translation table.
- **Switching does not move the story.** At rest, mid-typing and at a choice,
  the slide index, the dialogue id, the variables and the history are the same
  before and after:

```
line 2     index=1 id=mika_appears text="There you are! I checked [b]every[/b] hallway in this school."
line 2 ID  index=1 id=mika_appears text="Rupanya kau di sini! Aku sudah menyusuri [b]semua[/b] koridor di sekolah ini." speaker="Mika"
choice EN  index=8 buttons=["Take the stairs, like a normal person.", "Climb out of the music room window."]
choice ID  index=8 buttons=["Lewat tangga, seperti orang normal.", "Keluar lewat jendela ruang musik."]
chapter 2  index=13 id=mika_promises text="Worth it. Look at that sky."
```

- The language is a **player setting**, written to `user://fmw_vn_settings.json`
  and read back by a later run; the page offers the story's own names
  (`items=["English", "Indonesian"]`, English picked by default), and a code the
  story is not told in is refused rather than guessed.

### Save and load across content revisions

This is the newest behaviour and the reason the round exists. A save records both
`slide_index` and `slide_id`; the id is the scene, so on load the id is asked for
first and the index is only a fallback.

| case | what was written | what happened |
| --- | --- | --- |
| the index drifted (slides added ahead) | `slide_index: 8`, `slide_id: "mika_appears"` | loaded `slide=1 id=mika_appears`, toast `Loaded.` — the **id won** |
| the scene was renamed/deleted, index still in range | `slide_index: 3`, `slide_id: "mika_appears_v2"` | loaded `slide=3`, toast `Scene changed after update, resuming nearby.` |
| the index no longer lands inside the saved chapter | `slide_index: 5`, chapter `ch02_the_rooftop.json` | loaded `slide=12 id=rooftop_arrival` — **the chapter's start** |
| an older save with fewer variables | `variables: { "asked_about_clouds": true }` | `{ asked_about_clouds: true, heard_clouds: false, roof_visits: 0.0, route: "" }` — the ones the save lacks keep their defaults |

`"version": 1` is kept in `save_game()`. The ordinary round trip also still
works (`save bytes=550 loaded_slide=1`, landing on the slide that was saved).

### Story, parser and variables

- `validate_story.gd` follows every chapter and every asset: **0 warnings** on
  the demo.
- The variable system declares names, writes them (literal or
  `{ "expr": "affection + 1" }`) and reads them back. Every malformed shape is
  refused with a message: a reserved name, a name with a space, a name starting
  with a digit, a built-in function name, a `variables` block that is not an
  object, a `set` of an undeclared name, an empty `expr`, an `if` that is not a
  string or empty, and an `if` naming something that is not a variable.
- Conditions are live: writing a variable an answer reads toggles its button on
  and off while the question is on screen, and the list renumbers with the focus
  kept (`hub again after asking: slide=0 -> ["Never mind"] (asked=true)`).

### Presentation, UI and menu

- Character placement, `show`/`hide`/`with` and the name plate/portrait geometry
  behave (`nameplate overlaps portrait? false`; `slide b stage=["mika"]` …).
- The choice box stays clear of the text box for 1–5 answers (`gap 194 → 70`) and
  is held above the box for 6+ (`gap=64`), with a warning past the point it can
  fit.
- The book is one overlay with three bookmark tabs; `B` opens it, `H`/`S`/`L` no
  longer do anything, the showing page's tab is the lit one. Under the pages it
  carries its own button row - `["Settings", "Main Menu", "Close  (Esc)"]`.
- The menu is `["New game", "Load", "Gallery", "Settings", "Info", "Credits"]`,
  built from real assets; its Gallery page shows `4` tiles and `3 of 4 unlocked`.
- The settings page offers writing speed `0.25–8.00`, fast speed `1.00–16.00`,
  the auto-forward formula `0.00–0.50`, the screen modes
  `["Windowed", "Maximize", "Full screen"]`, the language and the **master
  volume**; out-of-range values clamp and malformed files fall back to defaults.
  It is a **top-level, full-screen overlay** (`SettingsOverlay`, 1920×1080 at the
  scene root), not a page of text inside the menu, which is what lets the book
  open it too.
- **The master volume scales the story's own two levels, and nothing else.**
  `StorySettings.master_volume` (the slider is `0.0–1.0` in `0.05` steps, shown as
  `0%`–`100%`) is applied only where the story's `music_volume` / `sound_volume`
  are: the mix as written is untouched, so `100%` is exactly the old behaviour
  and a story that asked for half-volume music still gets half. The full range is
  heard: a story at `0.6` music plays at `-4.4 dB` at full volume, `-10.5 dB` at
  half, and `-80 dB` (silence) at zero — a real level rather than the `-inf` a bare
  `linear_to_db(0)` would hand the player. It is heard **at once**, also on a track
  that is still fading in: the fade climbs towards the level asked for *now*, so a
  change made while it climbs is followed rather than overruled (this one was a
  real defect — the fade used to arrive at the level it began with).
- **Opening it from the book mid-story changes nothing about the story.**
  Measured from a two-slide probe part-way through the second line: the story
  object, slide index, slide id, state, `visible_characters`, the variables and
  the history are identical before, during and after, a control on the page still
  writes the player's setting, and `Esc` comes back to the book's own **Settings**
  button so the line carries on from the character it was on:

```
before  slide=1 id=s2 state=1 chars=2 vars=… history=2
paused  slide=1 id=s2 state=1 chars=2 story==true vars=… history=2
esc     settings=false book=true menu=false slide=1 chars=2 focus=BookSettings
resume  chars=2 -> 4, state=1, slide=1
```

- **The book's Main Menu button cannot strand the reader.** It closes the book,
  opens the menu over the untouched story, and `Esc` on the menu goes back to it
  (`menu=false story=… slide=1`); with no story loaded the menu is still the root
  of the scene and `Esc` goes nowhere.
- **`Esc` asks before it leaves.** With nothing in the way it opens the
  confirmation - a top-level, full-screen overlay with `["Exit game", "Main
  menu", "Cancel"]` - instead of quitting, and the story behind it does not move:
  slide, id, state, characters drawn, variables, history and the story object are
  all identical, and the line does not carry on typing. `Esc` again is Cancel
  (focus starts on Cancel, so a stray Space or Enter cannot leave either), and
  the story resumes from the same character (`chars=2 -> 4`). While it is up it is
  modal: `A`, `B`, `Tab` and a right click all do nothing behind it
  (`auto_forward=false fast_forward=false book=false ui_hidden=false`).
  **Exit game** is the one press that leaves, and `quit_requested` fires first -
  which is also how the harness can watch it without ending the run by accident.

### Gallery and progress

- The gallery declares four CGs with all four goal shapes; a first-choice walk
  earns `["cg_classroom", "cg_rooftop", "cg_worth_it"]` and leaves the other
  ending's locked. Fourteen malformed galleries are each refused with a message.
  The unlock is judged against the global record, so an older save loaded on top
  cannot re-lock a CG, and editing the story's goals afterwards keeps what was
  earned (`edited unlocked=[…, "cg_new"] (4/5)`).
- The progress record is one file for every story, one-way: `reset_progress()` /
  `reset_all_progress()` clear it and take the file away; nothing else moves it
  back (`monotonic after go_to b1: furthest=1/b2`).

## What could not be tested here

- **No rendered frames.** Headless Godot has no framebuffer, so every visual is
  checked as node geometry, styleboxes, texture paths and sampled pixels — never
  as a screenshot. Whether the choice box *looks* centred, the bookmark *reads*
  as a bookmark, or the gallery tiles *look* like a classroom, rests on those
  numbers.
- **No real input device.** Keys and clicks are synthesised
  (`Input.parse_input_event`, `pressed.emit()`), so keyboard repeat rate, a real
  mouse and a window that loses focus are not exercised.
- **The screen mode.** With no window, what `DisplayServer.window_set_mode()`
  does to a *window* is unverified; only the mapping onto Godot's modes and that
  applying one is harmless.
- **A second process.** "A later run reads the file" is a second player over the
  same file in one process, not two launches of Godot.
- **Audio was not listened to.** The files load and loop, and a name that lies
  about its contents is caught, but no one heard the output.
- **The demo is the only real story played end to end.** Probe stories cover the
  parser refusals and edge cases; the demo covers a real play-through.

## Limitations and notes

- **Only the story is translated.** The framework's own words — the menu pages,
  the book's tabs, `3 of 4 unlocked`, the hints — stay English, so picking
  Indonesian reads an Indonesian story inside an English shell. That is a scope
  decision: a menu string table would sit in front of the same setting.
- **Save/load is verified through the same code path the slot buttons call**, but
  no slot file is written by any harness (a real write would overwrite a
  player's save); the round trip and the revision probes use probe-owned files
  under `user://` and clean them up.
- Godot prints `ObjectDB instances were leaked at exit` / `resources still in
  use` for several `SceneTree` scripts. That is Godot's own teardown notice for a
  headless script that ends with nodes still alive, present on the shipped
  `smoke_test.gd` too; it is not a failure and the exit status is 0.
- Tested on Godot 4.7.2 only; other 4.x builds were not available.

## Reproducing this review

```bash
cd FMW_VN_test
godot --headless --path . --import              # once, on a fresh checkout

# every harness; each prints its own summary and exits non-zero on failure
for p in review/check_*.gd; do
    godot --headless --path . --script "res://$p" || echo "FAILED: $p"
done

cd ../FMW_VN
godot --headless --path . --script res://Framework_VN/tools/validate_story.gd
godot --headless --path . --script res://Framework_VN/tools/smoke_test.gd
```

Expected: every harness exits 0 with `failures=0` (or `ok=true`), and both tools
exit 0.
