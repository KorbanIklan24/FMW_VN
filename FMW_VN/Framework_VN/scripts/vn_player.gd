class_name VNPlayer
extends Control

## FMW_VN player - the "engine" half of the framework.
##
## It plays a [Story] produced by [StoryParser]: full HD pictures, a line-up of
## character pictures, a block of text that types itself out, music, sound
## effects and choices. Click, tap, Space or Enter moves to the next slide; the
## first click of a text block simply fills it in.
##
## Keys: [code]B[/code] the book (history, save and load as tabs),
## [code]Esc[/code] close the top overlay - or, with nothing in the way, ask
## before leaving with [method open_quit_dialog] - [code]Tab[/code] fast-forward
## (types [member _fast_speed] times faster and skips a finished line),
## [code]A[/code] auto-forward, and holding [code]Ctrl[/code] fast-forwards while
## it is down (with [code]Ctrl[/code] + [code]Left[/code] / [code]Right[/code]
## turning the speed itself up and down). Right click hides the text box, the
## hint, the choices and the HUD button, and brings them back.
##
## The four dials behind those keys - the writing speed, the fast-forward speed,
## the auto-forward formula and the screen mode - are the player's settings.
## They are kept between runs in a file of their own (see [StorySettings]), the
## menu's Settings page changes them, and none of them belongs to a story or to
## a save.
##
## A story may be told in several languages. Each one is a **mirror** of the same
## script - the same slides in the same order, carrying only the words - so
## switching language shows the same slide again in the other language instead of
## somewhere else in the story. The language the player picked is a setting, and
## [method set_language] switches without moving the story at all.
##
## With [member play_on_start] the scene opens on its main menu - New game, Load,
## Settings, Info and Credits - instead of jumping straight into the story.
##
## Wire-up from your own code:
## [codeblock]
## var player: VNPlayer = load("res://Framework_VN/scenes/vn_screen.tscn").instantiate()
## add_child(player)
## var result := StoryParser.parse_file("res://VN/Story/story.json")
## if result.ok:
##     player.begin(result.story)
## [/codeblock]

# Loaded by path (instead of by global class name) so the project also runs
# from a cold start, before the editor ever built its class cache.
const StoryLib := preload("res://Framework_VN/scripts/story_parser.gd")
# Likewise for the player's own settings and their ranges.
const SettingsLib := preload("res://Framework_VN/scripts/story_settings.gd")

## Emitted once the story started playing.
signal story_loaded(story: RefCounted)
## Emitted when a story file could not be parsed.
signal story_failed(errors: PackedStringArray)
## Emitted every time a new slide is on screen.
signal slide_shown(index: int)
## Emitted when the last slide was passed.
signal story_finished()
## Emitted when the player picks one of a slide's choices.
signal choice_made(index: int)

## Emitted whenever a story variable changes, from a slide's own `"set"` or from
## [method set_variable]. [param name] is the variable, [param value] its new
## value.
signal variable_changed(name: String, value: Variant)

## Emitted when the player reaches further into a story than they ever have
## before. [param story_path] is the story, [param entry] the progress record for
## it (furthest slide, its dialogue id, and every id seen so far).
signal progress_advanced(story_path: String, entry: Dictionary)

## Emitted when a CG is unlocked for the first time - the player reached further
## into a story than they ever had, and that met a gallery entry's goal.
## [param cg_id] is the gallery entry's id. Unlocking only ever happens once.
signal cg_unlocked(story_path: String, cg_id: String)

## Emitted when the player asks to leave the game: the confirmation's **Exit
## game** button, or [method quit_game] from your own code. Connect to it to
## write down something of your own first - the scene tree quits straight after,
## so keep it short.
signal quit_requested()

enum State { IDLE, TYPING, WAITING, CHOOSING, FINISHED }
## The three pages of the book: what has been read, the slots to save into and
## the slots to load out of. Its order is the tab order.
enum BookPage { HISTORY, SAVE, LOAD }
## The slot side of the book, for code that only cares whether it is saving or
## loading. Left over from the days of a separate slot menu.
enum MenuMode { SAVE, LOAD }

## How much of the screen height a character picture may use.
const CHARACTER_HEIGHT_RATIO := 0.92
## The square portrait in the left of the text box: the gap around it (which is
## also the gap between it and the text) and the thickness of its border.
const PORTRAIT_MARGIN := 24.0
const PORTRAIT_BORDER := 3.0
## Default left margin of the text inside the box, used when no portrait shows.
const TEXT_MARGIN_LEFT := 52
## Stops a story that loops through text-free slides from spinning forever.
const AUTO_CHAIN_LIMIT := 256
## Choice button geometry, in 1080p pixels. The buttons borrow the small HUD
## button style, so a list of them stays compact.
const CHOICE_WIDTH := 760.0
const CHOICE_HEIGHT := 52.0
const CHOICE_FONT_SIZE := 26
## Clear space kept between the choice list and the top of the text box, and the
## smallest gap left at the top of the screen for a long list.
const CHOICE_GAP := 64.0
const CHOICE_TOP_MARGIN := 40.0
## Save slots the menu offers, and the files behind them.
const SLOT_COUNT := 6
const SLOT_PREFIX := "user://fmw_vn_slot_"
## Gallery tiles, in 1080p pixels. Three columns fit the menu's page width, and
## the scroll cuts the grid off rather than the screen.
const GALLERY_COLUMNS := 3
const GALLERY_TILE_WIDTH := 346.0
const GALLERY_TILE_HEIGHT := 250.0
const GALLERY_THUMB_HEIGHT := 170.0
const GALLERY_SCROLL_HEIGHT := 660.0
## Where "0 volume" ends up.
const SILENT_DB := -80.0
const TOAST_SECONDS := 1.8
## How strongly [b] runs are emboldened. Godot's default theme bolds by drawing
## the regular face at embolden 1.2, which reads a lot heavier than 30 px body
## text; this is roughly half that.
const BOLD_EMBOLDEN := 0.6
## A {w=...} pause counts as over this close to its end, so floating-point dust
## does not stretch it by a frame.
const PAUSE_EPSILON := 0.0001
## The player's own speed controls. Ctrl + Right / Left nudges the typewriter
## speed by [constant StorySettings.TEXT_SPEED_STEP] at a time, between
## [constant StorySettings.TEXT_SPEED_MIN] and [constant StorySettings.TEXT_SPEED_MAX]
## times a line's own speed; [code]Tab[/code] and a held [code]Ctrl[/code] run it
## [constant StorySettings.FAST_SPEED_DEFAULT] times faster on top, until the
## player changes that. Every one of these is a setting rather than a fixed
## number - see [StorySettings].
## Auto-forward has nobody to click, so a bare {w} becomes this fixed hold
## instead of waiting for one.
const AUTO_FORWARD_BARE_SECONDS := 0.5
## How a new background comes in when a slide does not say.
const DEFAULT_TRANSITION := "fade"

@export_file("*.json") var story_path: String = "res://VN/Story/story.json"
## Load [member story_path] as soon as the scene is ready.
@export var play_on_start: bool = true
## Clicking after the ending replays the story.
@export var replay_on_finish: bool = true
## Where [method save_game] and [method load_game] look by default.
@export var save_path: String = "user://fmw_vn_save.json"
## Keep a global record of how far the player has ever got, in every story. It is
## written as the story is played and is never used to move the story itself.
@export var track_progress: bool = true
## Where that record lives. One file for the whole project, not one per save slot.
@export var progress_path: String = "user://fmw_vn_progress.json"
## Where the player's own settings live: the two writing speeds, the
## auto-forward formula and the screen mode. One file for the whole project, and
## no story or save can reach into it.
@export var settings_path: String = "user://fmw_vn_settings.json"
## Read the settings at startup and write them when they change. Off means the
## player runs on its defaults and never touches the file - the tools and the
## review harnesses run that way, so a probe can neither be disturbed by
## somebody's saved speeds nor overwrite them.
@export var remember_settings: bool = true

@onready var _world: Control = %World
@onready var _bg_fallback: ColorRect = %BgFallback
@onready var _bg_a: TextureRect = %BgA
@onready var _bg_mask: Control = %BgMask
@onready var _bg_b: TextureRect = %BgB
@onready var _characters: Control = %Characters
@onready var _flash: ColorRect = %Flash
@onready var _curtain: ColorRect = %TransitionCurtain
@onready var _text_box: Panel = %TextBox
@onready var _text_content: MarginContainer = %TextContent
@onready var _portrait_frame: Panel = %PortraitFrame
@onready var _portrait_clip: Control = %PortraitClip
@onready var _portrait: TextureRect = %Portrait
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _dialogue_label: RichTextLabel = %DialogueLabel
@onready var _hint_label: Label = %HintLabel
@onready var _choice_holder: Control = %ChoiceHolder
@onready var _choice_box: VBoxContainer = %ChoiceBox
@onready var _book_button: Button = %BookButton
@onready var _book_overlay: ColorRect = %BookOverlay
@onready var _book_title: Label = %BookTitle
@onready var _book_close: Button = %BookClose
@onready var _book_settings: Button = %BookSettings
@onready var _book_main_menu: Button = %BookMainMenu
@onready var _tab_history: Button = %TabHistory
@onready var _tab_save: Button = %TabSave
@onready var _tab_load: Button = %TabLoad
@onready var _history_page: Control = %HistoryPage
@onready var _slots_page: Control = %SlotsPage
@onready var _history_scroll: ScrollContainer = %HistoryScroll
@onready var _history_list: VBoxContainer = %HistoryList
@onready var _toast_label: Label = %ToastLabel
@onready var _menu_slots: VBoxContainer = %MenuSlots
@onready var _music_a: AudioStreamPlayer = %MusicA
@onready var _music_b: AudioStreamPlayer = %MusicB
@onready var _sfx_holder: Node = %Sfx
@onready var _message_overlay: ColorRect = %MessageOverlay
@onready var _message_title: Label = %MessageTitle
@onready var _message_body: Label = %MessageBody
@onready var _message_hint: Label = %MessageHint
@onready var _main_menu: Control = %MainMenu
@onready var _menu_new_game: Button = %MenuNewGame
@onready var _menu_load: Button = %MenuLoad
@onready var _menu_settings: Button = %MenuSettings
@onready var _menu_info: Button = %MenuInfo
@onready var _menu_credits: Button = %MenuCredits
@onready var _menu_page: Control = %MenuPage
@onready var _menu_page_title: Label = %MenuPageTitle
@onready var _menu_page_body: RichTextLabel = %MenuPageBody
@onready var _menu_page_back: Button = %MenuPageBack
@onready var _menu_credits_note: Label = %CreditsNote
@onready var _menu_gallery: Button = %MenuGallery
@onready var _gallery_page: VBoxContainer = %MenuGalleryPage
@onready var _gallery_count: Label = %GalleryCount
@onready var _gallery_grid: GridContainer = %GalleryGrid
@onready var _gallery_viewer: Control = %GalleryViewer
@onready var _viewer_image: TextureRect = %ViewerImage
@onready var _viewer_title: Label = %ViewerTitle
@onready var _viewer_caption: Label = %ViewerCaption
## The Settings page is an overlay of its own rather than a page of the main
## menu, so the book can open it over a running story as well.
@onready var _settings_overlay: ColorRect = %SettingsOverlay
@onready var _settings_back: Button = %SettingsBack
## The confirmation the [code]Esc[/code] key shows in place of quitting outright:
## the topmost overlay in the scene, so nothing can be drawn over it.
@onready var _quit_overlay: ColorRect = %QuitOverlay
@onready var _quit_exit: Button = %QuitExitGame
@onready var _quit_main_menu: Button = %QuitMainMenu
@onready var _quit_cancel: Button = %QuitCancel
@onready var _text_speed_slider: HSlider = %WritingSpeedSlider
@onready var _text_speed_value: Label = %WritingSpeedValue
@onready var _fast_speed_slider: HSlider = %FastWritingSpeedSlider
@onready var _fast_speed_value: Label = %FastWritingSpeedValue
@onready var _auto_forward_slider: HSlider = %AutoForwardSlider
@onready var _auto_forward_value: Label = %AutoForwardValue
@onready var _master_volume_slider: HSlider = %MasterVolumeSlider
@onready var _master_volume_value: Label = %MasterVolumeValue
@onready var _screen_mode_option: OptionButton = %ScreenModeOption
@onready var _language_row: HBoxContainer = %SettingsLanguageRow
@onready var _language_option: OptionButton = %LanguageOption
@onready var _viewer_close: Button = %ViewerClose

var _story: StoryLib.Story = null
var _slide_index: int = -1
var _state: State = State.IDLE
var _reveal: float = 0.0
## The story's variables. Declared in the story's `variables` block, read by every
## `"if"`, written by `"set"` and by [method set_variable]. Rebuilt from the
## story's starting values by [method begin].
var _vars: StoryVars = null
## The speed the current line asked for. The player's own [member _speed_scale]
## and fast-forward are applied on top of it by [method typing_speed].
var _chars_per_second: float = 45.0
## What the player did to that speed: Ctrl + Left / Right steps this, the
## Settings page's writing speed sets it, and [member _fast_forward] / a held
## Ctrl multiply it by [member _fast_speed].
var _speed_scale: float = 1.0
## What fast-forward multiplies the speed by. The player's setting.
var _fast_speed: float = SettingsLib.FAST_SPEED_DEFAULT
## Seconds of hold per drawn character in the auto-forward formula.
var _auto_forward_seconds: float = SettingsLib.AUTO_FORWARD_DEFAULT
## The player's overall volume, 0 to 1. The story's own music and sound levels are
## played multiplied by it, so [code]0[/code] is silence and [code]1[/code] leaves
## the story's mix alone. The player's setting.
var _master_volume: float = SettingsLib.MASTER_VOLUME_DEFAULT
var _fast_forward: bool = false
var _auto_forward: bool = false
## True while the Settings page is being filled in from the settings, so the
## controls do not write back what they were just given.
var _updating_settings_ui: bool = false
## True while a Ctrl key is down, which reads faster like Tab does.
var _ctrl_held: bool = false
## True while the story UI is hidden so the artwork can be seen on its own.
var _ui_hidden: bool = false
## The inline "{w=0.5}" pauses of the current line: where each one sits (how
## many characters are visible when it starts) and how long it holds.
var _pauses: Array = []
var _pause_index: int = 0
var _pause_time: float = -1.0
## True while a bare "{w}" is holding the line for a click.
var _pause_hold: bool = false
var _auto_timer: float = -1.0
var _auto_chain: int = 0
## The choices actually on screen: the slide's list with every answer whose own
## `"if"` does not hold taken out. [method choose] and [method visible_choices]
## both index this, so the first button is always choice 0.
var _visible_choices: Array = []
## The slide the buttons in the box were built for, or -1 when none are up. It
## keeps a write made while the story is moving between slides from rebuilding the
## previous slide's answers.
var _choices_slide: int = -1
var _current_background: String = ""
## Slot name -> character picture on screen. Each node also carries its parsed
## entry as the "entry" metadata, which is what save files store.
var _character_nodes: Dictionary = {}
var _bg_tween: Tween = null
## Everything that has been read, for the history screen.
var _history: Array[Dictionary] = []
## The music and sound levels, in 0..1.
var _music_volume: float = 0.6
var _sound_volume: float = 0.8
var _current_music: String = ""
var _music_active: AudioStreamPlayer = null
var _music_idle: AudioStreamPlayer = null
var _music_tween: Tween = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _toast_time: float = 0.0
## One tween per screen effect, so starting one stops the previous one.
var _shake_tween: Tween = null
var _zoom_tween: Tween = null
var _flash_tween: Tween = null
## Which page of the book is showing. The tab it belongs to is the bookmark.
var _book_page: BookPage = BookPage.HISTORY
var _menu_mode: MenuMode = MenuMode.SAVE
## Each tab's own "normal" stylebox, kept so the bookmark highlight can be taken
## back off a tab when it stops being the page that is showing.
var _tab_styles: Dictionary = {}
## True while the main menu is on screen. It pauses the story and owns the input,
## the way the book does.
var _main_menu_open: bool = false
## True while the Settings page was opened from the book rather than from the
## main menu, so closing it goes back to the book instead of the menu's buttons.
var _settings_came_from_book: bool = false
## The global progress record: how far the player has ever got, in every story.
## Separate from any save file, and only ever moves forwards.
var _progress: StoryProgress = null
# Typed through the preloaded script rather than its global class name, so the
# file still parses from a cold start, before the class cache has built.
## The player's own settings, read and written through [member settings_path].
var _settings: SettingsLib = null
## The language the story is being read in, already resolved against the story's
## own languages. "" when the story declares none.
var _language: String = ""
## `languages_of()` reads a file, and the Settings page asks for the languages
## whenever it is filled in, so the answer is kept per story path.
var _languages_cache: Dictionary = {}
## The CG being shown full size over the gallery, or "" when none is.
var _viewer_id: String = ""


func _ready() -> void:
	# The global progress record, read before anything can be played.
	_progress = StoryProgress.new()
	_progress.path = progress_path
	_progress.load_from_disk()
	# The player's own settings, and the reading knobs they stand behind.
	_settings = SettingsLib.new()
	_settings.path = settings_path
	if remember_settings:
		if not _settings.load_from_disk():
			# Nothing saved yet: leave the window in the mode the project itself
			# opens in, rather than dragging it to a default nobody asked for.
			_settings.screen_mode = SettingsLib.screen_mode_of(DisplayServer.window_get_mode())
		_speed_scale = _settings.text_speed
		_fast_speed = _settings.fast_speed
		_auto_forward_seconds = _settings.auto_forward_seconds
		_master_volume = _settings.master_volume
		apply_screen_mode()
	else:
		# No file of our own: report the window as it really is, so the Settings
		# page cannot show a mode the window is not in.
		_settings.screen_mode = SettingsLib.screen_mode_of(DisplayServer.window_get_mode())
	# Which language to read in, resolved against the story that is set to play.
	_refresh_language()
	# Behaviours that are easier to guarantee from code than from a scene file.
	_dialogue_label.bbcode_enabled = true
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_dialogue_label.visible_characters = 0
	_soften_bold(_dialogue_label)
	_message_overlay.visible = false
	_book_overlay.visible = false
	_settings_overlay.visible = false
	_quit_overlay.visible = false
	_toast_label.visible = false
	_bg_b.modulate = Color(1, 1, 1, 0)
	_music_active = _music_a
	_music_idle = _music_b
	for child in _sfx_holder.get_children():
		if child is AudioStreamPlayer:
			_sfx_players.append(child)
	_flash.color = Color(1, 1, 1, 0)
	_curtain.color = Color(0, 0, 0, 0)
	_world.pivot_offset = size * 0.5
	_reset_bg_geometry()
	_layout_portrait.call_deferred()
	_book_button.pressed.connect(_on_book_button)
	_book_close.pressed.connect(close_book)
	# The book reaches the same Settings page the main menu does, and can put the
	# story down and go back to the menu.
	_book_settings.pressed.connect(open_settings)
	_book_main_menu.pressed.connect(_on_book_main_menu)
	for page in [BookPage.HISTORY, BookPage.SAVE, BookPage.LOAD]:
		var tab := _tab_for(page)
		# Remember what the scene gave this tab, before the bookmark highlight
		# starts swapping its normal stylebox about.
		_tab_styles[tab] = tab.get_theme_stylebox("normal")
		tab.pressed.connect(set_book_page.bind(page))
	_refresh_tabs()
	resized.connect(_on_resized)
	_main_menu.visible = false
	_menu_page.visible = false
	_menu_new_game.pressed.connect(start_new_game)
	_menu_load.pressed.connect(_on_menu_load)
	_menu_settings.pressed.connect(open_settings)
	_menu_info.pressed.connect(show_menu_page.bind("info"))
	_menu_credits.pressed.connect(show_menu_page.bind("credits"))
	_menu_gallery.pressed.connect(open_gallery)
	_menu_page_back.pressed.connect(_close_menu_page)
	# The Settings page's controls. Their ranges come from the settings model, so
	# a range lives in exactly one place.
	_text_speed_slider.min_value = SettingsLib.TEXT_SPEED_MIN
	_text_speed_slider.max_value = SettingsLib.TEXT_SPEED_MAX
	_text_speed_slider.step = SettingsLib.TEXT_SPEED_STEP
	_fast_speed_slider.min_value = SettingsLib.FAST_SPEED_MIN
	_fast_speed_slider.max_value = SettingsLib.FAST_SPEED_MAX
	_fast_speed_slider.step = SettingsLib.FAST_SPEED_STEP
	_auto_forward_slider.min_value = SettingsLib.AUTO_FORWARD_MIN
	_auto_forward_slider.max_value = SettingsLib.AUTO_FORWARD_MAX
	_auto_forward_slider.step = SettingsLib.AUTO_FORWARD_STEP
	_master_volume_slider.min_value = SettingsLib.MASTER_VOLUME_MIN
	_master_volume_slider.max_value = SettingsLib.MASTER_VOLUME_MAX
	_master_volume_slider.step = SettingsLib.MASTER_VOLUME_STEP
	_screen_mode_option.clear()
	for label in SettingsLib.SCREEN_MODE_LABELS:
		_screen_mode_option.add_item(label)
	_text_speed_slider.value_changed.connect(_on_text_speed_slider)
	_fast_speed_slider.value_changed.connect(_on_fast_speed_slider)
	_auto_forward_slider.value_changed.connect(_on_auto_forward_slider)
	_master_volume_slider.value_changed.connect(_on_master_volume_slider)
	_screen_mode_option.item_selected.connect(_on_screen_mode_selected)
	_language_option.item_selected.connect(_on_language_selected)
	_settings_back.pressed.connect(close_settings)
	_refresh_settings_page()
	# The confirmation Esc shows: leave, go back to the menu, or think again.
	_quit_exit.pressed.connect(quit_game)
	_quit_main_menu.pressed.connect(_on_quit_main_menu)
	_quit_cancel.pressed.connect(close_quit_dialog)
	_viewer_close.pressed.connect(close_gallery_view)
	# Clicking the picture - or the space around it - closes a CG again.
	_viewer_image.gui_input.connect(_on_viewer_input)
	_gallery_viewer.gui_input.connect(_on_viewer_input)
	if play_on_start:
		open_main_menu()


func _exit_tree() -> void:
	# Never leave an unwritten progress record behind, even if the scene is torn
	# down between two slides.
	if _progress != null and _progress.is_dirty():
		_progress.save()
	# Do not leave sound running behind us when the scene goes away.
	for player in [_music_a, _music_b]:
		if player != null:
			(player as AudioStreamPlayer).stop()
	for player in _sfx_players:
		player.stop()
	for tween in [_bg_tween, _shake_tween, _zoom_tween, _flash_tween]:
		_kill_tween(tween)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_ctrl_held = false


func _process(delta: float) -> void:
	_tick_toast(delta)
	if _story == null or _is_paused():
		# An open overlay pauses typing and auto-advancing.
		return

	match _state:
		State.TYPING:
			_tick_typing(delta)
		State.WAITING:
			if is_fast_forward_active():
				# Fast-forward does not stop for a click: the line has finished
				# typing, so go straight on to the next one.
				advance(true)
			elif _auto_timer >= 0.0:
				_auto_timer -= delta
				# The same grace the {w=...} pauses use, so a 1.1 s hold is 1.1 s
				# and not a frame longer.
				if _auto_timer <= PAUSE_EPSILON:
					_auto_timer = -1.0
					advance(true)
		_:
			pass


## Two inputs are caught before the GUI runs, because Godot would take them
## first: right click hides / shows the story UI, and Tab is Godot's own "move
## the focus" key. An overlay, the choice buttons or the message screen keep Tab
## for their own buttons.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_RIGHT and not _overlay_is_up():
			accept_event()
			toggle_ui()
		return

	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_TAB:
		return
	if _overlay_is_up() or _state == State.CHOOSING:
		return
	accept_event()
	toggle_fast_forward()


## True while something else is on top of the story and owns the input.
func _overlay_is_up() -> bool:
	return _is_paused() or _message_overlay.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		# Esc always closes the topmost overlay first - and while the confirmation
		# is up, Esc is its Cancel button, so it never quits by being pressed
		# twice.
		if is_quit_dialog_open():
			close_quit_dialog()
		elif is_gallery_view_open():
			close_gallery_view()
		elif is_settings_open():
			close_settings()
		elif _menu_page.visible:
			_close_menu_page()
		elif is_book_open():
			close_book()
		elif _main_menu_open:
			# A story that was put down is still there: Esc goes back to it. With
			# nothing being played the menu is the root of the scene and Esc has
			# nowhere further to go.
			if _story != null:
				close_main_menu()
		else:
			# Nothing is in the way: ask first rather than quitting outright.
			open_quit_dialog()
		return

	# The Settings page and the confirmation are modal: they are the only thing on
	# screen, so no story key fires behind them. Esc, handled above, is how each is
	# closed.
	if is_settings_open() or is_quit_dialog_open():
		return

	# The menu owns its own input; no story key fires behind it.
	if _main_menu_open:
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		# Ctrl on its own is a "hold to read faster" key, so only its state is
		# kept - the boost itself is read while typing.
		if key.keycode == KEY_CTRL:
			_ctrl_held = key.pressed
			return
		# Hold Ctrl + Left / Right to move the typewriter speed. These repeat
		# while held, so echo events count here.
		if key.pressed and key.ctrl_pressed and (key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT):
			accept_event()
			adjust_speed(-1.0 if key.keycode == KEY_LEFT else 1.0)
			return

	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_A:
				accept_event()
				toggle_auto_forward()
				return
			KEY_B:
				accept_event()
				toggle_book()
				return

	if _is_paused():
		return
	if event.is_action_pressed("ui_accept") or _is_advance_click(event):
		accept_event()
		advance()


# --- public API --------------------------------------------------------------

## Parses [member story_path] (or [param path]) and starts playing it.
## Returns true when the story started.
func load_story(path: String = "") -> bool:
	var target := path if not path.is_empty() else story_path
	var result: StoryLib.Result = StoryLib.parse_file(target)
	for message in result.warnings:
		push_warning("FMW_VN: " + message)
	if not result.ok:
		_report_errors(result.errors)
		return false
	story_path = target
	_languages_cache.clear()
	begin(result.story)
	return true


## Starts playing an already parsed story.
func begin(new_story: StoryLib.Story) -> void:
	_story = new_story
	# The story decides which languages exist, so the language is resolved again
	# here - the setting alone does not know what this story is told in.
	_refresh_language()
	# A fresh story always starts from its declared values, whatever ran before.
	_vars = new_story.new_vars()
	_vars.changed.connect(_on_variable_changed)
	_visible_choices = []
	_message_overlay.visible = false
	close_book()
	# A new story always starts with its text box on screen.
	set_ui_hidden(false)
	_ctrl_held = false
	_clear_stage()
	_bg_fallback.color = _story.background_color
	_music_volume = _story.music_volume
	_sound_volume = _story.sound_volume
	_apply_sound_volume()
	_auto_chain = 0
	_go_to_slide(_story.start_index, true)
	story_loaded.emit(_story)


## Plays the current story from the beginning again.
func restart() -> void:
	if _story != null:
		begin(_story)


## Advances the story: fills in a running text block, otherwise shows the next
## slide. [param auto] is only used internally by auto-advancing slides.
func advance(auto: bool = false) -> void:
	if _story == null or _is_paused():
		return
	match _state:
		State.TYPING:
			# While a {w=...} pause is holding the line, the click only ends the
			# pause - the text carries on. One more click fills it in.
			if _pause_hold or _pause_time > 0.0:
				_pause_hold = false
				_pause_time = -1.0
				return
			# First click completes the typewriter, the next one moves on.
			_reveal = float(_dialogue_label.get_total_character_count())
			_dialogue_label.visible_characters = -1
			_state = State.WAITING
			_after_text_shown(_story.slides[_slide_index])
		State.WAITING:
			if auto:
				_auto_chain += 1
			else:
				_auto_chain = 0
			if _auto_chain > AUTO_CHAIN_LIMIT:
				push_error("FMW_VN: %d slides in a row advanced on their own, the story probably loops through slides without text." % _auto_chain)
				_finish()
				return
			# next_after() is where a slide's own "branch" is decided, against the
			# variables as they stand now (so a "set" on this slide has landed).
			_go_to_slide(_story.next_after(_slide_index, _vars))
		State.CHOOSING:
			pass
		State.FINISHED:
			if replay_on_finish:
				restart()


## Picks one of the choices on screen, exactly like clicking its button.
## Handy for keyboard-driven menus and for tests.
func choose(index: int) -> void:
	if _state != State.CHOOSING:
		return
	if index < 0 or index >= _visible_choices.size():
		push_error("FMW_VN: slide %d has no choice %d (%d on screen)." % [_slide_index, index, _visible_choices.size()])
		return
	_take_choice(index, _visible_choices[index])


## The answers on screen right now: the slide's own list, with every choice
## whose `"if"` does not hold left out. These are the buttons the player sees, in
## the order [method choose] numbers them.
func visible_choices() -> Array:
	return _visible_choices


## Jumps to a slide by id or index. Handy for menus and debug keys.
func go_to(target: Variant) -> void:
	if _story == null:
		return
	var index := -1
	if typeof(target) == TYPE_STRING:
		index = _story.index_of(str(target))
	else:
		index = int(target)
	_go_to_slide(index)


# --- variables ---------------------------------------------------------------

## The live variable state: read it, write it, or connect to its `changed`
## signal. `get_variable()` / `set_variable()` below are the short way.
func story_variables() -> StoryVars:
	return _vars


## True when the story declared this variable, so its conditions can read it.
func has_variable(name: String) -> bool:
	return _vars != null and _vars.is_declared(name)


func get_variable(name: String) -> Variant:
	return null if _vars == null else _vars.get_value(name)


## Writes a variable from code. A name the story never declared is stored too,
## but it stays invisible to the story's conditions - the declared names are what
## they were compiled with - so declare anything a condition must read in the
## story's `variables` block.
func set_variable(name: String, value: Variant) -> void:
	if _vars == null:
		return
	if not _vars.is_declared(name):
		push_warning("FMW_VN: \"%s\" is not a declared variable, so no condition can read it. Declared: %s." % [name, _declared_names()])
	_vars.set_value(name, value)


func set_variables(values: Dictionary) -> void:
	for key in values.keys():
		set_variable(str(key), values[key])


## Every value back to the ones the story declared.
func reset_variables() -> void:
	if _vars != null:
		_vars.reset()


## Evaluates a condition string exactly as `"if"` does, against the live state.
## Returns the value it works out to, or null when the string does not compile.
func evaluate(condition: String) -> Variant:
	if _story == null or _vars == null:
		return null
	var expression := Expression.new()
	if expression.parse(condition, StoryVars.input_names(_story.variable_names)) != OK:
		push_error("FMW_VN: \"%s\" is not a valid condition - %s." % [condition, expression.get_error_text()])
		return null
	return _vars.evaluate(expression)


func _declared_names() -> String:
	return _story.variable_names_string() if _story != null else "none"


func _on_variable_changed(name: String, value: Variant) -> void:
	# An answer's "if" is a live condition, so the buttons follow the state: writing
	# what a choice reads toggles that choice on or off while its question is up.
	_sync_choices()
	variable_changed.emit(name, value)


# --- progress ----------------------------------------------------------------

## The global progress record: one file for every story, outside the saves. Read
## how far the player has got, or connect to its own `advanced` signal.
func progress() -> StoryProgress:
	return _progress


## What is known about a story - furthest slide and dialogue id, the ids seen, and
## when it was first and last played. {} when it has never been played. An empty
## [param story_path] means the story that is loaded.
func progress_summary(story_path: String = "") -> Dictionary:
	return {} if _progress == null else _progress.summary(_story_path_for(story_path))


## The furthest dialogue id the player has ever reached in a story ("" when it
## has never been played, or when the furthest slide has no id of its own).
func furthest_id(story_path: String = "") -> String:
	return "" if _progress == null else _progress.furthest_id(_story_path_for(story_path))


## The furthest slide index reached - how deep into the file the player has ever
## got. -1 when the story has never been played.
func furthest_index(story_path: String = "") -> int:
	return -1 if _progress == null else _progress.furthest_index(_story_path_for(story_path))


## Speaker and line of the furthest slide, for a "continue from" menu.
func furthest_label(story_path: String = "") -> String:
	return "" if _progress == null else _progress.furthest_label(_story_path_for(story_path))


## Every dialogue id ever shown in a story, in the order they were first reached.
func seen_ids(story_path: String = "") -> PackedStringArray:
	return PackedStringArray() if _progress == null else _progress.seen_ids(_story_path_for(story_path))


## True when this dialogue id has ever been shown to the player.
func was_seen(id: String, story_path: String = "") -> bool:
	return false if _progress == null else _progress.was_seen(_story_path_for(story_path), id)


## Forgets the progress of one story (the loaded one by default).
func reset_progress(story_path: String = "") -> void:
	if _progress == null:
		return
	_progress.clear(_story_path_for(story_path))
	_progress.save()


## Forgets the progress of every story. For a "reset progress" menu item.
func reset_all_progress() -> void:
	if _progress == null:
		return
	_progress.clear_all()
	_progress.save()


## Writes the record now. It is written for you as the story is played, so this
## is only for a caller that wants to be certain.
func save_progress() -> bool:
	return _progress != null and _progress.save()


func _story_path_for(story_path: String) -> String:
	if not story_path.is_empty():
		return story_path
	return _story.source_path if _story != null else ""


# --- the CG gallery ----------------------------------------------------------

## The loaded story's CGs, each with whether the player has unlocked it:
## [code][{ id, title, caption, image, goal, unlocked }][/code]. With no story
## loaded - the main menu is opened before one starts - the story this player
## would start ([member story_path]) is read for its gallery alone, so the menu
## can show it. Empty when there is no gallery at all.
func gallery() -> Array[Dictionary]:
	var path := _gallery_path()
	var story := _gallery_story()
	var out: Array[Dictionary] = []
	for entry in _gallery_entries():
		var item: Dictionary = entry.duplicate(true)
		item["unlocked"] = _cg_unlocked_in(path, entry)
		# A CG's title and caption are written once, or once per language.
		if story != null:
			item["title"] = story.cg_title_for(entry, _language)
			item["caption"] = story.cg_caption_for(entry, _language)
		out.append(item)
	return out


## How many CGs of that gallery are unlocked, and how many there are:
## [code]{ unlocked, total }[/code].
func gallery_progress() -> Dictionary:
	var unlocked := 0
	for entry in gallery():
		if bool(entry.get("unlocked", false)):
			unlocked += 1
	return {"unlocked": unlocked, "total": _gallery_entries().size()}


## True when this CG is unlocked.
##
## Two things make a CG unlocked, and both only ever add: the global record lists
## it (written the moment the goal was met, so it stays unlocked even if the
## story's goal is later edited), or the progress already meets the goal now (so
## a record from before the gallery existed does not show an earned CG as
## locked). Loading an older save cannot undo either - the record never loses a
## CG, and progress never goes backwards.
func is_cg_unlocked(cg_id: String, story_path: String = "") -> bool:
	var path := story_path if not story_path.is_empty() else _gallery_path()
	if _progress == null or path.is_empty() or cg_id.is_empty():
		return false
	if _progress.is_unlocked(path, cg_id):
		return true
	for entry in _gallery_entries():
		if str(entry.get("id", "")) == cg_id:
			return _cg_goal_met(path, entry.get("goal", {}))
	return false


## Every unlocked CG id of a story, in the order they were first unlocked.
func unlocked_cgs(story_path: String = "") -> PackedStringArray:
	return PackedStringArray() if _progress == null else _progress.unlocked_ids(_story_path_for(story_path))


## The story the gallery belongs to: the loaded one, or - before anything is
## played - the story this player would start.
func _gallery_path() -> String:
	return _story.source_path if _story != null else story_path


## The gallery entries to show: the loaded story's, or the story file's when
## nothing is loaded yet (the main menu is open before the first New game).
## The story the menu's gallery is read from: the one playing, or the one this
## player would start - so the menu shows the gallery before the first New game.
func _gallery_story() -> StoryLib.Story:
	if _story != null:
		return _story
	var result := StoryLib.parse_file(story_path)
	if not result.ok or result.story == null:
		return null
	return result.story


func _gallery_entries() -> Array[Dictionary]:
	var story := _gallery_story()
	if story == null:
		return []
	return story.gallery


## "Is this entry unlocked": the record first (it never forgets, which is what
## makes an unlock permanent), then the goal against the progress so far.
func _cg_unlocked_in(path: String, entry: Dictionary) -> bool:
	return is_cg_unlocked(str(entry.get("id", "")), path)


## Notes the slide the player has just been shown in the global record, and writes
## it when that changed anything. Nothing here moves the record backwards: the
## furthest point only ever moves on, and the seen ids only ever accumulate.
func _note_progress(index: int) -> void:
	if not track_progress or _progress == null or _story == null:
		return
	if index < 0 or index >= _story.slide_count():
		return
	var slide := _story.slide_at(index)
	var result := _progress.record(
		_story.source_path,
		_story.title_for(_language),
		index,
		str(slide.get("id", "")),
		_slide_label(slide),
		str(_story.chapter_of(index).get("path", "")).get_file()
	)
	# The CGs whose goal this slide has just met. Checked against the global record
	# rather than a save, so the gallery never goes backwards.
	var unlocked := _unlock_reached_cgs()
	if not result["changed"] and unlocked.is_empty():
		return
	save_progress()
	# The record itself tells us whether this was new ground; relayed once, here,
	# after the file is written, rather than twice via StoryProgress.advanced.
	if bool(result["advanced"]):
		progress_advanced.emit(_story.source_path, result["entry"])
	for cg_id in unlocked:
		cg_unlocked.emit(_story.source_path, cg_id)


## Marks every CG whose goal the record now meets, and says so on screen. Returns
## the ids that were unlocked by this call - each one only ever once.
func _unlock_reached_cgs() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _story.gallery:
		var id := str(entry.get("id", ""))
		if id.is_empty() or not _cg_goal_met(_story.source_path, entry.get("goal", {})):
			continue
		if _progress.unlock(_story.source_path, id):
			out.append(id)
			_show_toast("CG unlocked: %s" % str(entry.get("title", id)))
	return out


## True when the record has reached what a CG's goal asks for: the dialogue id
## has been seen, and/or the furthest slide index is at least as deep as asked.
## [param path] is the story, since the gallery can be looked at before one is
## loaded (the main menu).
func _cg_goal_met(path: String, goal: Dictionary) -> bool:
	if _progress == null or path.is_empty() or not _progress.has(path):
		return false
	var seen_id := str(goal.get("seen", ""))
	if not seen_id.is_empty() and not _progress.was_seen(path, seen_id):
		return false
	var want_index := int(goal.get("index", -1))
	if want_index >= 0 and _progress.furthest_index(path) < want_index:
		return false
	return true


func current_slide_index() -> int:
	return _slide_index


func current_slide() -> Dictionary:
	return _story.slide_at(_slide_index) if _story != null else {}


func current_story() -> StoryLib.Story:
	return _story


func is_playing() -> bool:
	return _state == State.TYPING or _state == State.WAITING


func is_choosing() -> bool:
	return _state == State.CHOOSING


## True while the book is open, whichever page it is on.
func is_book_open() -> bool:
	return _book_overlay.visible


## Which page of the book is showing.
func book_page() -> BookPage:
	return _book_page


## The history page is the one this name used to open on its own.
func is_history_open() -> bool:
	return is_book_open() and _book_page == BookPage.HISTORY


## The two slot pages are what this name used to open on its own.
func is_menu_open() -> bool:
	return is_book_open() and _book_page != BookPage.HISTORY


## Which way the slot pages of the book are working.
func menu_mode() -> MenuMode:
	return _menu_mode


## The tab button that belongs to a page.
func _tab_for(page: BookPage) -> Button:
	match page:
		BookPage.SAVE:
			return _tab_save
		BookPage.LOAD:
			return _tab_load
		_:
			return _tab_history


## True while an overlay is in the way of the story.
func _is_paused() -> bool:
	return is_book_open() or _main_menu_open or is_settings_open() or is_quit_dialog_open()


func music_volume() -> float:
	return _music_volume


func sound_volume() -> float:
	return _sound_volume


## The player's overall volume, 0..1. Every story's music and sound effects are
## played at their own level multiplied by it.
func master_volume() -> float:
	return _master_volume


## Sets the overall volume, clamped to 0..1 and kept between runs with the other
## settings. It takes effect straight away, also on music that is already
## playing. Returns the value it ended up at.
func set_master_volume(value: float) -> float:
	if not _settings.set_master_volume(value):
		return _master_volume
	_master_volume = _settings.master_volume
	_persist_settings()
	_apply_master_volume()
	_refresh_settings_page_if_open()
	return _master_volume


## Puts the current overall volume on what is playing right now: the music,
## through the same dB its crossfade aims at, and the sound-effect players.
func _apply_master_volume() -> void:
	if _music_active != null and _music_active.playing:
		_music_active.volume_db = _music_db()
	_apply_sound_volume()


## 0..1. Takes effect straight away, also while music is playing.
func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	if _music_active != null and _music_active.playing:
		_music_active.volume_db = _music_db()


## 0..1.
func set_sound_volume(value: float) -> void:
	_sound_volume = clampf(value, 0.0, 1.0)
	_apply_sound_volume()


# --- hiding the story UI -----------------------------------------------------

## True while the text box, the hint inside it and the choices are hidden.
func is_ui_hidden() -> bool:
	return _ui_hidden


## Hides or shows the text box (with its hint, speaker plate and portrait), the
## choice list and the HUD button, so the picture behind them is on its own. A
## hidden line keeps typing, and a hidden list cannot be answered by accident
## because the keyboard focus is let go with it.
func set_ui_hidden(hidden: bool) -> void:
	if _ui_hidden == hidden:
		return
	_ui_hidden = hidden
	_text_box.visible = not hidden
	_choice_holder.visible = not hidden
	_book_button.visible = not hidden
	if hidden:
		if get_viewport() != null:
			get_viewport().gui_release_focus()
	else:
		_grab_choice_focus()


## Right click: hide the story UI, or bring it back.
func toggle_ui() -> void:
	set_ui_hidden(not _ui_hidden)


## Puts the keyboard back on the first answer of a list that is on screen, and
## leaves it alone while the UI is hidden - Space or Enter must not pick an
## answer nobody can see.
func _grab_choice_focus() -> void:
	if _ui_hidden or _state != State.CHOOSING or _choice_box.get_child_count() == 0:
		return
	(_choice_box.get_child(0) as Button).grab_focus()


# --- reading speed -----------------------------------------------------------

## The player's own multiplier on every line's speed, held between
## [constant StorySettings.TEXT_SPEED_MIN] and [constant StorySettings.TEXT_SPEED_MAX].
func speed_scale() -> float:
	return _speed_scale


## Sets the multiplier straight away, also in the middle of a line. This is the
## writing speed the Settings page shows, and it is kept between runs.
func set_speed_scale(value: float) -> void:
	if not _settings.set_text_speed(value):
		# Already as fast (or as slow) as it goes: say nothing.
		return
	_speed_scale = _settings.text_speed
	_persist_settings()
	_refresh_settings_page_if_open()
	_show_toast(_speed_toast())


## Nudges the speed by [param steps] x [constant StorySettings.TEXT_SPEED_STEP] and
## returns the new multiplier. Ctrl + Right calls this with 1, Ctrl + Left with -1.
func adjust_speed(steps: float) -> float:
	set_speed_scale(_speed_scale + steps * SettingsLib.TEXT_SPEED_STEP)
	return _speed_scale


## True while Tab's fast-forward toggle is on.
func is_fast_forward() -> bool:
	return _fast_forward


## True while either fast-forward input is on: Tab's toggle
## ([member _fast_forward]) or a held Ctrl ([member _ctrl_held]). Both read at the
## settings' fast speed and move a finished line on without waiting for a click.
func is_fast_forward_active() -> bool:
	return _fast_forward or _ctrl_held


func set_fast_forward(on: bool) -> void:
	if _fast_forward == on:
		return
	_fast_forward = on
	if on:
		_show_toast("Fast-forward on (%s, skips)." % _multiplier_text(_fast_speed))
	else:
		_show_toast("Fast-forward off.")
	_refresh_hint()


## Tab: fast typing on or off.
func toggle_fast_forward() -> void:
	set_fast_forward(not _fast_forward)


## True while every line moves on to the next one by itself.
func is_auto_forward() -> bool:
	return _auto_forward


func set_auto_forward(on: bool) -> void:
	if _auto_forward == on:
		return
	_auto_forward = on
	if on:
		_show_toast("Auto-forward on.")
		if _pause_hold:
			# A bare {w} is holding the line for a click that is not coming.
			_pause_hold = false
			_pause_time = AUTO_FORWARD_BARE_SECONDS
	else:
		_show_toast("Auto-forward off.")
	_refresh_auto_forward()


## A: auto-forward on or off.
func toggle_auto_forward() -> void:
	set_auto_forward(not _auto_forward)


## What the toast says while the speed is being moved.
func _speed_toast() -> String:
	var text := "Speed %sx" % String.num(_speed_scale, 2)
	if _chars_per_second > 0.0:
		text += " (%d chars/sec)" % int(round(_chars_per_second * _speed_scale))
	return text


# --- the player's settings ----------------------------------------------------

## x the speed of every line, the same dial Ctrl + Right turns.
func writing_speed() -> float:
	return _speed_scale


## x the speed while fast-forwarding - the [code]Tab[/code] key, or Ctrl held.
func fast_writing_speed() -> float:
	return _fast_speed


## Seconds of hold for every drawn character, once auto-forward is on.
func auto_forward_seconds() -> float:
	return _auto_forward_seconds


## One of [enum StorySettings.ScreenMode]: the mode the player picked.
func screen_mode() -> int:
	return _settings.screen_mode


## The player's settings, all four in one place.
func settings() -> SettingsLib:
	return _settings


## Sets the fast-forward multiplier, also in the middle of a line, and returns
## the value it ended up at (a value outside the range is clamped).
func set_fast_speed(value: float) -> float:
	if _settings.set_fast_speed(value):
		_fast_speed = _settings.fast_speed
		_persist_settings()
		_refresh_settings_page_if_open()
		_show_toast("Fast-forward %s, skips." % _multiplier_text(_fast_speed))
		_refresh_hint()
	return _fast_speed


## Sets the auto-forward formula's hold per drawn character, also while a line is
## on screen. Returns the value it ended up at.
func set_auto_forward_seconds(value: float) -> float:
	if _settings.set_auto_forward_seconds(value):
		_auto_forward_seconds = _settings.auto_forward_seconds
		_persist_settings()
		_refresh_settings_page_if_open()
		_show_toast("Auto-forward %.2f s a character." % _auto_forward_seconds)
		_refresh_auto_forward()
	return _auto_forward_seconds


## Sets the screen mode - one of [enum StorySettings.ScreenMode]; anything else is
## ignored - and puts the window in it. Returns the mode that is now set.
func set_screen_mode(mode: int) -> int:
	if _settings.set_screen_mode(mode):
		_persist_settings()
		_refresh_settings_page_if_open()
		apply_screen_mode()
	return _settings.screen_mode


## Puts the window in the mode the settings ask for, through
## [method DisplayServer.window_set_mode]. The headless display server has no
## window to put anywhere, and a window that is already in the right mode is left
## alone, so the common case never calls into Godot at all.
func apply_screen_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var wanted := SettingsLib.window_mode_of(_settings.screen_mode)
	if DisplayServer.window_get_mode() != wanted:
		DisplayServer.window_set_mode(wanted)


## Every setting back to its default and written out: both writing speeds, the
## auto-forward formula, the overall volume and the screen mode.
func reset_settings() -> void:
	_settings.reset()
	_speed_scale = _settings.text_speed
	_fast_speed = _settings.fast_speed
	_auto_forward_seconds = _settings.auto_forward_seconds
	_master_volume = _settings.master_volume
	_persist_settings()
	apply_screen_mode()
	_apply_master_volume()
	_refresh_settings_page_if_open()


## What the settings are, for a menu line, a log or a probe.
func settings_summary() -> Dictionary:
	return {
		"writing_speed": _speed_scale,
		"fast_writing_speed": _fast_speed,
		"auto_forward_seconds": _auto_forward_seconds,
		"master_volume": _master_volume,
		"screen_mode": _settings.screen_mode,
		"screen_mode_name": _settings.screen_mode_name(),
	}


## Writes the settings, when the player asked for them to be remembered.
func _persist_settings() -> void:
	if remember_settings:
		_settings.save()


## "1x", "1.25x", "8x" - the way the Settings page says a multiplier.
func _multiplier_text(value: float) -> String:
	return String.num(value, 2).rstrip("0").rstrip(".") + "x"


## "0%", "35%", "100%" - the way the Settings page says a volume.
func _percent_text(value: float) -> String:
	return "%d%%" % roundi(clampf(value, 0.0, 1.0) * 100.0)


## Keeps the Settings page in step when a setting changes from code: while it is
## on screen it always shows what the player is really doing. Nothing to do while
## it is away.
func _refresh_settings_page_if_open() -> void:
	if _settings_overlay != null and _settings_overlay.visible:
		_refresh_settings_page()


## Puts the current settings into the Settings page's controls, and the numbers
## beside them. The controls do not write back what they are given.
func _refresh_settings_page() -> void:
	if _settings == null:
		return
	_updating_settings_ui = true
	_text_speed_slider.value = _speed_scale
	_text_speed_value.text = _multiplier_text(_speed_scale)
	_fast_speed_slider.value = _fast_speed
	_fast_speed_value.text = _multiplier_text(_fast_speed)
	_auto_forward_slider.value = _auto_forward_seconds
	_auto_forward_value.text = "%.2f s/char" % _auto_forward_seconds
	_master_volume_slider.value = _master_volume
	_master_volume_value.text = _percent_text(_master_volume)
	_screen_mode_option.selected = _settings.screen_mode
	_refresh_language_options()
	_updating_settings_ui = false


func _on_text_speed_slider(value: float) -> void:
	if _updating_settings_ui:
		return
	set_speed_scale(value)
	_text_speed_value.text = _multiplier_text(_speed_scale)


func _on_fast_speed_slider(value: float) -> void:
	if _updating_settings_ui:
		return
	set_fast_speed(value)
	_fast_speed_value.text = _multiplier_text(_fast_speed)


func _on_auto_forward_slider(value: float) -> void:
	if _updating_settings_ui:
		return
	set_auto_forward_seconds(value)
	_auto_forward_value.text = "%.2f s/char" % _auto_forward_seconds


func _on_master_volume_slider(value: float) -> void:
	if _updating_settings_ui:
		return
	set_master_volume(value)
	_master_volume_value.text = _percent_text(_master_volume)


func _on_screen_mode_selected(index: int) -> void:
	if _updating_settings_ui:
		return
	set_screen_mode(index)


## Fills the language picker from the story, or from [member story_path] when
## nothing is loaded yet, and hides the whole row for a story told in one
## language - there is nothing to choose between, and an empty picker would only
## look broken.
func _refresh_language_options() -> void:
	var names := story_languages()
	_language_row.visible = names.size() > 1
	_language_option.clear()
	if names.is_empty():
		_language_option.selected = -1
		return
	var selected := -1
	var index := 0
	for code in names.keys():
		_language_option.add_item(str(names[code]))
		if str(code) == _language:
			selected = index
		index += 1
	_language_option.selected = selected


func _on_language_selected(index: int) -> void:
	if _updating_settings_ui:
		return
	var codes: Array = story_languages().keys()
	if index < 0 or index >= codes.size():
		return
	set_language(str(codes[index]))


# --- languages ----------------------------------------------------------------

## The language the story is being read in. "" when it declares no languages.
func language() -> String:
	return _language


## The languages the story is told in - code -> the name to show the player, in
## the order the story declares them. Empty for a story in one language.
##
## Before anything has been played this reads them out of [member story_path], so
## the menu's Settings page can offer them without a story loaded.
func story_languages() -> Dictionary:
	if _story != null:
		return _story.languages
	return _languages_of(story_path)["names"]


## The code of the language the story is written in: the one every line falls back
## to when a translation is missing.
func default_language() -> String:
	if _story != null:
		return _story.default_language
	return str(_languages_of(story_path)["default"])


## True when there is more than one language to choose between.
func is_multilingual() -> bool:
	return story_languages().size() > 1


## What to call a language in a menu: the story's own name for it, or the code.
func language_name(code: String) -> String:
	if code.is_empty():
		return ""
	return str(story_languages().get(code, code))


## Switches the language the story is told in, and writes the choice down. The
## story does not move: every language's lines live on the same slides, so the
## slide that is on screen is shown again in the other language - same place, same
## variables, same progress. Returns the language now in force, which is unchanged
## when the story does not have the one asked for.
func set_language(code: String) -> String:
	var wanted := code.strip_edges().to_lower()
	if not story_languages().has(wanted):
		push_warning("FMW_VN: \"%s\" is not a language of %s; the story stays in \"%s\"." % [
			wanted, story_path if _story == null else _story.source_path, _language])
		return _language
	_settings.set_language(wanted)
	_persist_settings()
	if _language == wanted:
		_refresh_settings_page_if_open()
		return _language
	_language = wanted
	_refresh_settings_page_if_open()
	_reapply_language()
	_show_toast("Language: %s" % language_name(wanted))
	return _language


## Puts the language back to the story's own default, the way a fresh player
## would read it. Returns the language now in force.
func reset_language() -> String:
	_settings.set_language("")
	_persist_settings()
	var wanted := _resolve_language()
	if wanted == _language:
		_refresh_settings_page_if_open()
		return _language
	_language = wanted
	_refresh_settings_page_if_open()
	_reapply_language()
	return _language


## The language to read in: the one the player picked when this story has it, and
## the story's own default otherwise.
func _resolve_language() -> String:
	var names := story_languages()
	if names.has(_settings.language):
		return _settings.language
	var fallback := default_language()
	return fallback if names.has(fallback) else ""


func _refresh_language() -> void:
	_language = _resolve_language()


## The languages of a story file, read once per path.
func _languages_of(path: String) -> Dictionary:
	if not _languages_cache.has(path):
		_languages_cache[path] = StoryLib.languages_of(path)
	return _languages_cache[path]


## Shows the slide that is on screen again, in the language that has just been
## set. It is put up whole rather than typed again - the reader has already read
## this far - and the history keeps the lines as they were read, in the language
## they were read in.
func _reapply_language() -> void:
	if _story == null or _slide_index < 0 or _slide_index >= _story.slide_count():
		return
	if _state != State.TYPING and _state != State.WAITING and _state != State.CHOOSING:
		return
	_apply_text(_story.slides[_slide_index], true, false)


## The line to show for a slide, in the language being read.
func _text(slide: Dictionary) -> String:
	if _story == null:
		return str(slide.get("text", ""))
	return _story.text_for(slide, _language)


## Who is speaking, in the language being read.
func _speaker(slide: Dictionary) -> String:
	if _story == null:
		return str(slide.get("speaker", ""))
	return _story.speaker_for(slide, _language)


## The {w=...} pauses of the line being read: a translation may put its own
## pauses somewhere else, so they travel with the text.
func _pauses_for(slide: Dictionary) -> Array:
	if _story == null:
		return slide.get("pauses", [])
	return _story.pauses_for(slide, _language)


## An answer's text, in the language being read.
func _choice_text(choice: Dictionary) -> String:
	if _story == null:
		return str(choice.get("text", ""))
	return _story.choice_text_for(choice, _language)


# --- the book: history, save and load ----------------------------------------

## Opens the book on [param page], or moves it to that page when it is already
## open. The page that shows is the tab with the bookmark on it.
func open_book(page: BookPage = BookPage.HISTORY) -> void:
	set_book_page(page)
	_book_overlay.visible = true
	# So Enter / Space closes the book again instead of advancing the story.
	_book_close.grab_focus()


## Opens [param page], or closes the book when that page is already showing, so
## one key can both open and close the same page.
func open_book_page(page: BookPage) -> void:
	if is_book_open() and _book_page == page:
		close_book()
		return
	open_book(page)


func close_book() -> void:
	if not is_book_open():
		return
	_book_overlay.visible = false
	_book_close.release_focus()


## The Book button, and the [code]B[/code] key: open the book, or close it when
## it is already open.
func toggle_book() -> void:
	if is_book_open():
		close_book()
	else:
		open_book(_book_page)


# --- the main menu -----------------------------------------------------------

## True while the main menu is on screen.
func is_main_menu_open() -> bool:
	return _main_menu_open


## Shows the main menu over the story, which pauses it.
func open_main_menu() -> void:
	close_book()
	_message_overlay.visible = false
	# Also takes the gallery's full-size CG and the Settings page down, if either
	# was up.
	_set_menu_page_visible(false)
	_main_menu.visible = true
	_main_menu_open = true
	# The menu is not the story's "hidden UI" state.
	set_ui_hidden(false)
	_menu_new_game.grab_focus()


## Hides the main menu.
func close_main_menu() -> void:
	_main_menu.visible = false
	_main_menu_open = false


## New game: closes the menu and plays [member story_path] from the top.
func start_new_game() -> void:
	close_main_menu()
	load_story(story_path)


## The Book's Main Menu button: puts the story down and opens the menu over it.
## The story keeps its place - the menu pauses it rather than resetting it - and
## Esc on the menu comes back to it.
func _on_book_main_menu() -> void:
	close_book()
	open_main_menu()


# --- the confirmation Esc asks with ------------------------------------------

## True while the confirmation is on screen.
func is_quit_dialog_open() -> bool:
	return _quit_overlay.visible


## Asks the player whether they meant to leave. [code]Esc[/code] shows this
## instead of quitting outright whenever no other overlay is in the way, so a
## slipped key can never end a session. The story is paused, not moved.
func open_quit_dialog() -> void:
	# Nothing may sit on top of it: it is the last word on the screen.
	_set_menu_page_visible(false)
	close_book()
	_quit_overlay.visible = true
	# The safe answer holds the keyboard, so Space and Enter cannot leave by
	# accident.
	_quit_cancel.grab_focus()


## Takes the confirmation down and does nothing else - the Cancel button, and
## what a second [code]Esc[/code] does.
func close_quit_dialog() -> void:
	if not is_quit_dialog_open():
		return
	_quit_overlay.visible = false
	_quit_cancel.release_focus()


## Leaves the game: emits [signal quit_requested] first, then quits the scene
## tree. This is what the confirmation's **Exit game** button calls.
func quit_game() -> void:
	quit_requested.emit()
	get_tree().quit()


## The confirmation's Main menu button: puts the story down and opens the menu
## over it, exactly like the book's own Main Menu button.
func _on_quit_main_menu() -> void:
	close_quit_dialog()
	open_main_menu()


# --- the Settings page -------------------------------------------------------

## True while the Settings page is up. It belongs to the player rather than to
## the menu or the book, which is why it is an overlay of its own.
func is_settings_open() -> bool:
	return _settings_overlay.visible


## Shows the Settings page over whatever is on screen - the main menu, or the
## book in the middle of a story - and remembers which, so [method
## close_settings] goes back there. Nothing here touches the story: the controls
## only read and write the player's own settings, so the slide on screen, the
## variables and the history are exactly as they were.
func open_settings() -> void:
	# Nothing may sit on top of it, or the page would open behind what is there.
	_set_menu_page_visible(false)
	# Where to go back to when it closes. Read after the line above, which puts a
	# settings page that was already open away - and clears this flag with it.
	_settings_came_from_book = is_book_open()
	_refresh_settings_page()
	_settings_overlay.visible = true
	_settings_back.grab_focus()


## Closes the Settings page and hands the input back to whatever it was opened
## over: the book, if that is what was underneath, otherwise the main menu - and
## with neither, to the story, which was paused all along.
func close_settings() -> void:
	if not is_settings_open():
		return
	_settings_overlay.visible = false
	_settings_back.release_focus()
	var came_from_book := _settings_came_from_book
	_settings_came_from_book = false
	if came_from_book and is_book_open():
		_book_settings.grab_focus()
	elif _main_menu_open:
		_menu_settings.grab_focus()


## Load, from the menu: opens the book on its Load page, over the menu. Picking a
## slot closes the book and the menu; closing the book comes back to the menu.
func _on_menu_load() -> void:
	open_book(BookPage.LOAD)


## Turns the menu's page overlay to "gallery", "settings", "info" or "credits".
func show_menu_page(page: String) -> void:
	# The Settings page is an overlay of its own, so the book can reach it too;
	# the name is kept here because it is still one of the menu's pages.
	if page == "settings":
		open_settings()
		return
	# Any other page takes the Settings page down with it.
	close_settings()
	# The gallery is its own control rather than a block of text, so the text body
	# steps aside for it.
	var gallery := page == "gallery"
	match page:
		"gallery":
			_menu_page_title.text = "Gallery"
			_menu_credits_note.visible = false
			_rebuild_gallery()
		"info":
			_menu_page_title.text = "Info"
			_menu_page_body.text = _keybinds_text()
			_menu_credits_note.visible = false
		"credits":
			_menu_page_title.text = "Credits"
			_menu_page_body.text = "place ur credits here."
			_menu_credits_note.visible = true
		_:
			# Anything else is a plain page of text, like Info and Credits.
			_menu_page_title.text = page.capitalize()
			_menu_credits_note.visible = false
	_menu_page_body.visible = not gallery
	_gallery_page.visible = gallery
	_set_menu_page_visible(true)
	_menu_page_back.grab_focus()


## True while one of the menu's pages is on screen - the gallery, Info, Credits,
## or the Settings overlay.
func is_menu_page_open() -> bool:
	return _menu_page.visible or is_settings_open()


## The name of the page that is showing, or "" when none is.
func menu_page_name() -> String:
	if is_settings_open():
		return "Settings"
	return _menu_page_title.text if _menu_page.visible else ""


func _close_menu_page() -> void:
	_set_menu_page_visible(false)
	if _main_menu_open:
		_menu_new_game.grab_focus()


func _set_menu_page_visible(visible_now: bool) -> void:
	_menu_page.visible = visible_now
	if not visible_now:
		_menu_credits_note.visible = false
		close_gallery_view()
		close_settings()
		close_quit_dialog()


# --- the gallery page --------------------------------------------------------

## Opens the gallery: the main menu, turned to its Gallery page. From the menu
## the CGs come from [member story_path]; while a story is playing they come
## from it. A story with no `gallery` block shows an empty page rather than an
## error.
func open_gallery() -> void:
	if not _main_menu_open:
		open_main_menu()
	show_menu_page("gallery")


## True while the menu's Gallery page is the one showing.
func is_gallery_open() -> bool:
	return _menu_page.visible and _gallery_page.visible


## Shows one CG full size, over the gallery. A locked CG cannot be shown - that
## is the whole point of collecting them - and an image that will not load is
## refused rather than shown blank. Returns true when it went up.
func open_gallery_view(cg_id: String) -> bool:
	var entry := _gallery_entry(cg_id)
	if entry.is_empty() or not is_cg_unlocked(cg_id):
		return false
	var texture := load(str(entry.get("image", "")))
	if not texture is Texture2D:
		push_warning("FMW_VN: the CG \"%s\" has no picture at %s." % [cg_id, entry.get("image", "")])
		return false
	_viewer_image.texture = texture
	_viewer_title.text = str(entry.get("title", cg_id))
	_viewer_caption.text = str(entry.get("caption", ""))
	_viewer_id = cg_id
	_gallery_viewer.visible = true
	_viewer_close.grab_focus()
	return true


## Takes the full-size CG down again, back to the gallery.
func close_gallery_view() -> void:
	if not _gallery_viewer.visible:
		return
	_gallery_viewer.visible = false
	_viewer_image.texture = null
	_viewer_id = ""
	_viewer_close.release_focus()


## True while a CG is showing full size.
func is_gallery_view_open() -> bool:
	return _gallery_viewer.visible


## The id of the CG being shown full size, or "" when none is.
func gallery_view_id() -> String:
	return _viewer_id


## The gallery entry for an id, from the loaded story or the story file.
func _gallery_entry(cg_id: String) -> Dictionary:
	# Through gallery() rather than the raw list, so the title and the caption
	# come back in the language being read.
	for entry in gallery():
		if str(entry.get("id", "")) == cg_id:
			return entry
	return {}


## Rebuilds the gallery from the story's CGs: one tile each, the locked ones
## dark and unnamed. The line above the grid counts what is unlocked.
func _rebuild_gallery() -> void:
	for child in _gallery_grid.get_children():
		_gallery_grid.remove_child(child)
		child.queue_free()
	var entries := gallery()
	var unlocked := 0
	for entry in entries:
		if bool(entry.get("unlocked", false)):
			unlocked += 1
		_gallery_grid.add_child(_gallery_tile(entry))
	if entries.is_empty():
		_gallery_count.text = "this story has no gallery"
	else:
		_gallery_count.text = "%d of %d unlocked" % [unlocked, entries.size()]


## One tile: the CG's picture (dark, with a question mark, while locked) and its
## title. The menu's own button art frames it, so the tiles match the menu.
func _gallery_tile(entry: Dictionary) -> Control:
	var unlocked := bool(entry.get("unlocked", false))
	var normal := _menu_page_back.get_theme_stylebox("normal")
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(GALLERY_TILE_WIDTH, GALLERY_TILE_HEIGHT)
	tile.add_theme_stylebox_override("normal", normal)
	tile.add_theme_stylebox_override("disabled", normal)
	tile.add_theme_stylebox_override("hover", _menu_page_back.get_theme_stylebox("hover"))
	tile.add_theme_stylebox_override("pressed", _menu_page_back.get_theme_stylebox("pressed"))
	tile.add_theme_stylebox_override("focus", _menu_page_back.get_theme_stylebox("focus"))
	tile.disabled = not unlocked
	if unlocked:
		tile.pressed.connect(open_gallery_view.bind(str(entry.get("id", ""))))
	else:
		# Nothing to click yet: no focus, and dimmed so it reads as a slot that
		# is still empty rather than a tile that is broken.
		tile.focus_mode = Control.FOCUS_NONE
		tile.modulate = Color(1, 1, 1, 0.5)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 12)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	box.add_child(_gallery_picture(entry, unlocked))

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = str(entry.get("title", "")) if unlocked else "???"
	box.add_child(title)

	margin.add_child(box)
	tile.add_child(margin)
	return tile


## The picture half of a tile: the CG itself, or a dark panel with a question
## mark where a locked one would be.
func _gallery_picture(entry: Dictionary, unlocked: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, GALLERY_THUMB_HEIGHT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked:
		var picture := TextureRect.new()
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var texture := load(str(entry.get("image", "")))
		picture.texture = texture if texture is Texture2D else null
		holder.add_child(picture)
		return holder
	var panel := ColorRect.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.color = Color(0.09, 0.1, 0.16, 0.9)
	holder.add_child(panel)
	var mark := Label.new()
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_size_override("font_size", 64)
	mark.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75, 0.8))
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(mark)
	return holder


## Clicking the picture, or the space around it, closes the full-size view.
func _on_viewer_input(event: InputEvent) -> void:
	if not is_gallery_view_open() or not _is_advance_click(event):
		return
	accept_event()
	close_gallery_view()


## The keybind list the Info page shows. Kept beside the keys it documents.
func _keybinds_text() -> String:
	return "\n".join([
		"[b]click / tap / Space / Enter[/b]     next slide",
		"[b]B[/b]     open / close the book",
		"[b]the book's tabs[/b]     turn to a page",
		"[b]Tab[/b]     fast typing on / off",
		"[b]Ctrl[/b] (held)     read faster",
		"[b]Ctrl + Left / Right[/b]     slower / faster typewriter",
		"[b]A[/b]     auto-forward on / off",
		"[b]right click[/b]     hide / show the text box",
		"[b]Esc[/b]     close the top overlay, or ask to leave",
	])


## Shows a page of the book: rebuilds what that page lists, retitles it and
## moves the bookmark to its tab.
func set_book_page(page: BookPage) -> void:
	_book_page = page
	_menu_mode = MenuMode.LOAD if page == BookPage.LOAD else MenuMode.SAVE
	var history := page == BookPage.HISTORY
	_history_page.visible = history
	_slots_page.visible = not history
	if history:
		_rebuild_history_view()
		_book_title.text = "History"
		_history_scroll.scroll_vertical = 1 << 24
		_scroll_history_to_bottom()
	else:
		_rebuild_slots()
		_book_title.text = "Save game" if page == BookPage.SAVE else "Load game"
	_refresh_tabs()


## The bookmark: the tab of the page that is showing turns brighter and sits
## lower, tucked into the top edge of the page below it. The other tabs stay up
## at the top, rounded and dim.
func _refresh_tabs() -> void:
	for page in [BookPage.HISTORY, BookPage.SAVE, BookPage.LOAD]:
		var tab := _tab_for(page)
		var current: bool = page == _book_page
		var style: StyleBox = tab.get_theme_stylebox("pressed") if current else _tab_styles[tab]
		tab.add_theme_stylebox_override("normal", style)
		tab.size_flags_vertical = Control.SIZE_SHRINK_END if current else Control.SIZE_SHRINK_BEGIN


## The history page on its own, the way it used to be opened.
func open_history() -> void:
	open_book(BookPage.HISTORY)


func close_history() -> void:
	if is_history_open():
		close_book()


func history() -> Array[Dictionary]:
	return _history


func _record_history(speaker: String, text: String, is_choice: bool) -> void:
	if text.is_empty():
		return
	var entry: Dictionary = {"speaker": speaker, "text": text, "choice": is_choice}
	if _story != null and _slide_index >= 0:
		var ch := _story.chapter_of(_slide_index)
		var chapter_file := str(ch.get("path", "")).get_file()
		var chapter_idx := _chapter_index_of_slide(_slide_index)
		if not chapter_file.is_empty():
			entry["chapter"] = chapter_file
		if chapter_idx >= 0:
			entry["chapter_index"] = chapter_idx
	_history.append(entry)


func _rebuild_history_view() -> void:
	for child in _history_list.get_children():
		_history_list.remove_child(child)
		child.queue_free()
	if _history.is_empty():
		_add_history_row("Nothing has been read yet.")
		return

	var current_ch := _chapter_index_of_slide(_slide_index)
	var min_ch := maxi(0, current_ch - 1)
	var rendered := 0
	for entry in _history:
		if not _is_entry_in_history_scope(entry, min_ch, current_ch):
			continue
		_add_history_row(str(entry.get("text", "")), str(entry.get("speaker", "")), bool(entry.get("choice", false)))
		rendered += 1
	if rendered == 0:
		_add_history_row("Nothing has been read yet.")


## Returns the 0-based index of the chapter containing [param slide_idx].
func _chapter_index_of_slide(slide_idx: int) -> int:
	if _story == null or _story.chapters.is_empty():
		return 0
	var idx := slide_idx if slide_idx >= 0 else (_story.start_index if _story != null else 0)
	for i in _story.chapters.size():
		var ch: Dictionary = _story.chapters[i]
		var first: int = int(ch.get("first_index", 0))
		var last: int = int(ch.get("last_index", -1))
		if idx >= first and idx <= last:
			return i
	return 0


## Returns the 0-based chapter index for a chapter file or path, or -1 when not found.
func _chapter_index_of_name(chapter_name: String) -> int:
	if _story == null or _story.chapters.is_empty() or chapter_name.is_empty():
		return -1
	var target := chapter_name.get_file()
	for i in _story.chapters.size():
		if str(_story.chapters[i].get("path", "")).get_file() == target:
			return i
	return -1


## Decides whether a history entry falls within the allowed chapter range.
## Older saves whose history entries have no chapter tags are accepted safely.
func _is_entry_in_history_scope(entry: Dictionary, min_ch: int, max_ch: int) -> bool:
	if not entry.has("chapter_index") and not entry.has("chapter"):
		return true
	var ch_idx := -1
	if entry.has("chapter_index") and entry["chapter_index"] != null:
		ch_idx = int(entry["chapter_index"])
	elif entry.has("chapter") and entry["chapter"] != null:
		ch_idx = _chapter_index_of_name(str(entry["chapter"]))
	if ch_idx >= 0:
		return ch_idx >= min_ch and ch_idx <= max_ch
	return true


## Godot's default theme draws [b] by emboldening the regular face at 1.2, which
## is heavy beside 30 px body text. Redrawing it from the same face at a lower
## embolden keeps the emphasis without the shout.
func _soften_bold(label: RichTextLabel) -> void:
	var pairs := [
		["bold_font", label.get_theme_font("normal_font")],
		["bold_italics_font", label.get_theme_font("italics_font")],
	]
	for pair in pairs:
		var base: Font = pair[1]
		if base == null:
			continue
		var soft := FontVariation.new()
		soft.base_font = base
		soft.variation_embolden = BOLD_EMBOLDEN
		label.add_theme_font_override(pair[0], soft)


func _add_history_row(text: String, speaker: String = "", is_choice: bool = false) -> void:
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_font_size_override("normal_font_size", 30)
	row.add_theme_font_size_override("bold_font_size", 30)
	row.add_theme_font_size_override("italics_font_size", 30)
	_soften_bold(row)
	if is_choice:
		row.text = "[color=#8ea8ff]> %s[/color]" % text
	elif speaker.is_empty():
		row.text = text
	else:
		row.text = "[b]%s[/b]\n%s" % [speaker, text]
	_history_list.add_child(row)


## The list is only laid out once it is visible, so jump to the bottom a frame
## later (that is where the newest line is).
func _scroll_history_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_history_open():
		_history_scroll.scroll_vertical = 1 << 24


# --- choices -----------------------------------------------------------------

## Re-reads the whole line: [method _refresh_hint] and, when the line is already
## waiting, the end-of-line bookkeeping - so Tab and A take effect on the line
## that is on screen rather than the next one.
func _refresh_auto_forward() -> void:
	if _story == null or _state != State.WAITING:
		_refresh_hint()
		return
	var slide := current_slide()
	if _story.visible_choices(_slide_index, _vars).is_empty():
		_after_text_shown(slide)
	else:
		_refresh_hint()


func _show_choices(slide: Dictionary) -> void:
	_hide_choices()
	# Only the answers whose own "if" holds; a hidden one is not built at all, so
	# the buttons and choose(i) always agree on what is where.
	_visible_choices = _story.visible_choices(_slide_index, _vars)
	var choices: Array = _visible_choices
	if choices.is_empty():
		_state = State.WAITING
		return
	_choices_slide = _slide_index
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var button := Button.new()
		button.text = _choice_text(choice)
		button.custom_minimum_size = Vector2(0, CHOICE_HEIGHT)
		_apply_choice_style(button)
		if button.has_method("set_autowrap_mode"):
			button.set("autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
		button.pressed.connect(_take_choice.bind(i, choice))
		_choice_box.add_child(button)
	_layout_choices()
	_state = State.CHOOSING
	_refresh_hint()
	_grab_choice_focus()


func _take_choice(index: int, choice: Dictionary) -> void:
	if _state != State.CHOOSING:
		return
	# speaker, text, is_choice - a picked choice shows up as "> text" in the log.
	_record_history("", _choice_text(choice), true)
	play_sfx(str(choice.get("sfx", "")))
	choice_made.emit(index)
	_hide_choices()
	_go_to_slide(int(choice.get("next_index", -1)))


func _hide_choices() -> void:
	_visible_choices = []
	_choices_slide = -1
	for child in _choice_box.get_children():
		_choice_box.remove_child(child)
		child.queue_free()


## Keeps the answers on screen in step with the variables.
##
## A choice's `"if"` is not a one-off check made once when the line ends: writing
## the variable it reads - from a script through [method set_variable], or from a
## `"set"` on the slide itself - toggles that button on or off there and then. An
## answer that comes back keeps its written order, an answer that goes away takes
## its button with it, and when the last one goes the question turns back into an
## ordinary line (which waits, or auto-forwards, like any other).
func _sync_choices() -> void:
	if _story == null or _vars == null:
		return
	# Either a question is up for this slide, or a line is waiting with no answers
	# on screen yet. Anything else (mid-slide-change, typing, an ending) has
	# nothing to keep in step.
	var showing := _state == State.CHOOSING and _choices_slide == _slide_index
	var waiting := _state == State.WAITING and _choices_slide == -1
	if not showing and not waiting:
		return

	var slide := current_slide()
	if slide.is_empty() or not slide.has("choices"):
		return
	var wanted: Array = _story.visible_choices(_slide_index, _vars)
	if wanted.is_empty():
		if not showing:
			return
		# The last answer went away, so the question is a plain line again.
		_hide_choices()
		_state = State.WAITING
		_after_text_shown(slide)
		return
	if showing and _same_choices(wanted):
		return

	# Remembered so the keyboard does not jump when the list is rebuilt.
	var held := _focused_choice_text()
	# A question is up now, so nothing may be counting down behind it.
	_auto_timer = -1.0
	_show_choices(slide)
	if not held.is_empty():
		_focus_choice_text(held)


## True when the answers on screen are already exactly the ones the conditions
## allow, in the same order. The same choice dictionaries come back every time,
## so this is an identity comparison, not a value one.
func _same_choices(wanted: Array) -> bool:
	if _visible_choices.size() != wanted.size():
		return false
	for i in wanted.size():
		if not is_same(_visible_choices[i], wanted[i]):
			return false
	return true


## The label of the answer the keyboard is on, or "" when it is not on one.
func _focused_choice_text() -> String:
	if _ui_hidden or not is_inside_tree():
		return ""
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button and _choice_box.is_ancestor_of(focus):
		return (focus as Button).text
	return ""


## Puts the keyboard back on the answer with this label, when it is still there.
func _focus_choice_text(text: String) -> void:
	if _ui_hidden:
		return
	for child in _choice_box.get_children():
		if child is Button and (child as Button).text == text:
			(child as Button).grab_focus()
			return


## The choice list is centred on the screen, so one answer sits in the middle
## and a list of five straddles it just the same. The height is summed from the
## buttons' own minimum sizes (their font and padding decide it). A list long
## enough to reach the text box is lifted until CHOICE_GAP is left between them,
## and one longer still stops at the top of the screen instead of running off it.
func _layout_choices() -> void:
	var count := _choice_box.get_child_count()
	if count == 0:
		return
	var separation := float(_choice_box.get_theme_constant("separation"))
	var total := 0.0
	for child in _choice_box.get_children():
		if child is Control:
			total += (child as Control).get_combined_minimum_size().y
	total += float(count - 1) * separation

	_choice_box.size = Vector2(CHOICE_WIDTH, total)
	# Centred: the middle of the list sits on the middle of the screen.
	var top := (size.y - total) * 0.5
	# Never creep down into the text box...
	var clear_bottom := _text_box.position.y - CHOICE_GAP
	if top + total > clear_bottom:
		top = clear_bottom - total
	# ...and never run off the top of the screen.
	if top < CHOICE_TOP_MARGIN:
		top = CHOICE_TOP_MARGIN
		push_warning("FMW_VN: %d choices need %d px but only %d px are free above the text box; the list will reach down to it." % [count, int(total), int(clear_bottom - CHOICE_TOP_MARGIN)])
	_choice_box.position = Vector2((size.x - CHOICE_WIDTH) * 0.5, top)


## The choice buttons wear the same small style as the Book button and the book's
## tabs, so they read as compact without touching the shared theme.
func _apply_choice_style(button: Button) -> void:
	button.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
	for state in ["disabled", "focus", "hover", "normal", "pressed"]:
		var style := _book_button.get_theme_stylebox(state)
		if style != null:
			button.add_theme_stylebox_override(state, style)


# --- playback ----------------------------------------------------------------

## Walks past slides whose `"if"` does not hold, so a condition can quietly take
## a slide (or a run of them) out of the story. A skipped slide runs nothing -
## its `"set"` included - and hands over to its own `"branch"` / `"next"`.
## Returns an index past the end (or -1) when the walk runs out of story.
func _visible_entry(index: int) -> int:
	if _story == null or _vars == null:
		return index
	var guard := 0
	while index >= 0 and index < _story.slide_count():
		if _story.is_visible(index, _vars):
			return index
		index = _story.next_after(index, _vars)
		guard += 1
		if guard > _story.slide_count():
			push_error("FMW_VN: more than %d slides in a row are hidden by their own \"if\"; that looks like a loop. Check the conditions." % _story.slide_count())
			return -1
	return index


func _go_to_slide(index: int, instant: bool = false) -> void:
	if _story == null:
		return
	index = _visible_entry(index)
	if index < 0 or index >= _story.slide_count():
		_finish()
		return

	_slide_index = index
	var slide := _story.slides[index]
	# The slide's own "set" writes land before anything on it is read.
	_story.apply_set(index, _vars)
	var fade := float(slide.get("fade", -1.0))
	if fade < 0.0:
		fade = _story.default_fade

	# How the new picture comes in. A slide's own "duration" wins over its
	# "fade" (or the story default, when it has neither).
	var transition := DEFAULT_TRANSITION
	var transition_duration := fade
	if slide.has("transition"):
		var spec: Dictionary = slide["transition"]
		transition = str(spec.get("type", DEFAULT_TRANSITION))
		var wanted := float(spec.get("duration", -1.0))
		if wanted >= 0.0:
			transition_duration = wanted

	# No "background" key means "keep the picture that is already on screen".
	if slide.has("background"):
		_apply_background(str(slide["background"]), transition, transition_duration, instant)
	_apply_stage(slide, fade, instant)
	_apply_music(slide, fade)
	_apply_sfx(slide)
	_apply_text(slide, instant)
	_apply_effects(slide)
	slide_shown.emit(index)
	_note_progress(index)


## Characters per second the current line types at: the speed the line asked
## for, times the player's own multiplier, times fast-forward. 0 means the line
## is shown all at once.
func typing_speed() -> float:
	var speed := _chars_per_second * _speed_scale
	if _fast_forward or _ctrl_held:
		speed *= _fast_speed
	return speed


## Types one frame of the current line, honouring any {w=...} pause that is due.
func _tick_typing(delta: float) -> void:
	# A pause the writer asked for holds the line exactly where it is.
	if _pause_hold:
		return
	if _pause_time > 0.0:
		_pause_time -= delta
		if _pause_time > PAUSE_EPSILON:
			return
		_pause_time = -1.0

	var total := float(_dialogue_label.get_total_character_count())
	var step := delta * typing_speed()
	# Never type past the next pause in a single frame.
	if _pause_index < _pauses.size():
		step = minf(step, maxf(0.0, float(int(_pauses[_pause_index]["at"])) - _reveal))
	_reveal += step
	_dialogue_label.visible_characters = int(_reveal)

	if _pause_index < _pauses.size() and _reveal >= float(int(_pauses[_pause_index]["at"])):
		var pause: Dictionary = _pauses[_pause_index]
		_pause_index += 1
		var hold := float(pause.get("time", 0.0))
		if hold < 0.0:
			# A bare {w}: wait for the player. Auto-forward has nobody to
			# click, so it turns the wait into a fixed hold instead, and
			# fast-forward skips the wait entirely.
			if _auto_forward:
				_pause_time = AUTO_FORWARD_BARE_SECONDS
			elif is_fast_forward_active():
				_pause_time = 0.0
			else:
				_pause_hold = true
			return
		if hold > 0.0:
			_pause_time = hold
			return

	if _reveal >= total:
		_dialogue_label.visible_characters = -1
		_state = State.WAITING
		_after_text_shown(_story.slides[_slide_index])


func _apply_text(slide: Dictionary, instant: bool = false, record: bool = true) -> void:
	var speaker := _speaker(slide)
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_apply_portrait(slide)

	var text := _text(slide)
	_dialogue_label.text = text
	var speed := float(slide.get("text_speed", -1.0))
	if speed < 0.0:
		speed = _story.default_text_speed
	_chars_per_second = speed
	_reveal = 0.0
	_pauses = _pauses_for(slide)
	_pause_index = 0
	_pause_time = -1.0
	_pause_hold = false
	_auto_timer = -1.0
	_hide_choices()

	if record and not text.is_empty():
		_record_history(speaker, text, false)

	if text.is_empty():
		# Nothing to read: hold the picture for "wait" seconds, then move on.
		_dialogue_label.visible_characters = 0
		_state = State.WAITING
		if slide.has("choices"):
			_show_choices(slide)
			return
		_auto_timer = maxf(0.0, float(slide.get("wait", 0.0)))
		_refresh_hint()
		return

	_auto_chain = 0
	if instant or _chars_per_second <= 0.0:
		# text_speed of 0 means "show it all at once".
		_dialogue_label.visible_characters = -1
		_state = State.WAITING
		_after_text_shown(slide)
	else:
		_dialogue_label.visible_characters = 0
		_state = State.TYPING
		_refresh_hint()


func _after_text_shown(slide: Dictionary) -> void:
	# A slide whose choices are all hidden by their own "if" is a plain line, not
	# a question, so it waits (or auto-forwards) like any other.
	if not _story.visible_choices(_slide_index, _vars).is_empty():
		_show_choices(slide)
		return

	# -1 means "no timer": the line waits for the reader to move it on.
	var hold := -1.0
	if bool(slide.get("auto_advance", false)):
		hold = float(slide.get("wait", 0.0))
		if hold <= 0.0:
			# No explicit wait: give the reader roughly reading speed.
			hold = maxf(1.0, float(_text(slide).length()) / 25.0)
	if _auto_forward:
		# The player's own reading timer, never under what the slide asked for.
		hold = maxf(hold, _auto_forward_hold(slide))
	_auto_timer = hold
	_refresh_hint()


## How long auto-forward leaves a finished line on screen: the settings' seconds
## for every drawn character (spaces included), plus the {w=...} pauses the line
## uses.
func _auto_forward_hold(slide: Dictionary) -> float:
	var hold := _auto_forward_seconds * float(_dialogue_label.get_total_character_count())
	var pauses: Array = _pauses_for(slide)
	for pause in pauses:
		var time := float(pause.get("time", 0.0))
		hold += AUTO_FORWARD_BARE_SECONDS if time < 0.0 else time
	return hold


## The faded line in the corner of the text box: what the input does here, plus
## whichever of the player's own reading modes are on.
func _refresh_hint() -> void:
	var base := ""
	match _state:
		State.TYPING:
			base = "click / space to skip"
		State.WAITING:
			if _auto_forward and _auto_timer >= 0.0:
				base = "auto-forward"
			elif _auto_timer >= 0.0:
				base = "auto"
			else:
				base = "click / space"
	var modes: PackedStringArray = []
	if _fast_forward:
		modes.append("fast")
	if _auto_forward and base != "auto-forward":
		modes.append("auto")
	if modes.is_empty():
		_set_hint(base)
	elif base.is_empty():
		_set_hint(" \u00b7 ".join(modes))
	else:
		_set_hint(" \u00b7 ".join(modes) + " \u00b7 " + base)


## Brings a new background picture in and, when the fade is over, makes it the
## base layer. [param transition] is one of StoryParser.TRANSITIONS.
func _apply_background(path: String, transition: String = DEFAULT_TRANSITION, duration: float = 0.35, instant: bool = false) -> void:
	if path == _current_background:
		return
	_current_background = path
	# Settle whatever was running, then start from a clean slate.
	_stop_background_transition()
	_curtain.color = Color(0, 0, 0, 0)

	var texture: Texture2D = null
	if not path.is_empty():
		texture = load(path) as Texture2D
	if texture == null:
		# No picture: whatever is behind (the fallback colour) shows through.
		_bg_a.texture = null
		return

	if instant or duration <= 0.0 or transition == "cut":
		_bg_a.texture = texture
		return

	match transition:
		"fade_black":
			_transition_via_black(texture, duration)
		"wipe_left", "wipe_right", "wipe_up", "wipe_down":
			_transition_wipe(texture, transition, duration)
		"slide_left", "slide_right", "slide_up", "slide_down":
			_transition_slide(texture, transition, duration)
		_:
			_transition_crossfade(texture, duration)


## The default: the new picture fades in on top of the old one.
func _transition_crossfade(texture: Texture2D, duration: float) -> void:
	_bg_b.texture = texture
	_bg_b.modulate = Color(1, 1, 1, 0)
	_bg_tween = create_tween()
	_bg_tween.set_parallel(true)
	_bg_tween.tween_property(_bg_b, "modulate:a", 1.0, duration)
	_bg_tween.tween_property(_bg_a, "modulate:a", 0.0, duration)
	_bg_tween.chain().tween_callback(_settle_background_fade)


## Fades to black, swaps the picture behind the curtain, then fades back in.
func _transition_via_black(texture: Texture2D, duration: float) -> void:
	var half := maxf(0.01, duration * 0.5)
	_bg_b.texture = texture
	_bg_b.modulate = Color(1, 1, 1, 1)
	_bg_tween = create_tween()
	_bg_tween.tween_property(_curtain, "color:a", 1.0, half)
	_bg_tween.tween_callback(_settle_background_fade)
	_bg_tween.tween_property(_curtain, "color:a", 0.0, half)


## The new picture is revealed by a growing hole in front of it.
func _transition_wipe(texture: Texture2D, kind: String, duration: float) -> void:
	var view := _world.size
	_bg_b.texture = texture
	_bg_b.position = Vector2.ZERO
	_bg_b.size = view
	_bg_mask.size = view
	_bg_mask.position = Vector2.ZERO

	_bg_tween = create_tween()
	_bg_tween.set_parallel(true)
	match kind:
		"wipe_left":
			# Grows rightwards from the left edge.
			_bg_mask.size = Vector2(0.0, view.y)
			_bg_tween.tween_property(_bg_mask, "size:x", view.x, duration)
		"wipe_right":
			# Grows leftwards from the right edge.
			_bg_mask.size = Vector2(0.0, view.y)
			_bg_mask.position = Vector2(view.x, 0.0)
			_bg_tween.tween_property(_bg_mask, "size:x", view.x, duration)
			_bg_tween.tween_property(_bg_mask, "position:x", 0.0, duration)
		"wipe_up":
			# Grows upwards from the bottom edge.
			_bg_mask.size = Vector2(view.x, 0.0)
			_bg_mask.position = Vector2(0.0, view.y)
			_bg_tween.tween_property(_bg_mask, "size:y", view.y, duration)
			_bg_tween.tween_property(_bg_mask, "position:y", 0.0, duration)
		_:
			# "wipe_down": grows downwards from the top edge.
			_bg_mask.size = Vector2(view.x, 0.0)
			_bg_tween.tween_property(_bg_mask, "size:y", view.y, duration)
	_bg_tween.chain().tween_callback(_settle_background_fade)


## The whole new picture slides in from an edge, pushing over the old one.
func _transition_slide(texture: Texture2D, kind: String, duration: float) -> void:
	var view := _world.size
	_reset_bg_geometry()
	_bg_b.texture = texture
	_bg_b.size = view
	match kind:
		"slide_left":
			_bg_b.position = Vector2(view.x, 0.0)
		"slide_right":
			_bg_b.position = Vector2(-view.x, 0.0)
		"slide_up":
			_bg_b.position = Vector2(0.0, view.y)
		_:
			# "slide_down"
			_bg_b.position = Vector2(0.0, -view.y)
	_bg_tween = create_tween()
	_bg_tween.tween_property(_bg_b, "position", Vector2.ZERO, duration)
	_bg_tween.tween_callback(_settle_background_fade)


## Stops whatever transition is running and settles it right away.
func _stop_background_transition() -> void:
	_kill_tween(_bg_tween)
	_bg_tween = null
	_settle_background_fade()


## Leaves [member _bg_a] holding the picture that was (or was becoming) visible,
## and puts the transition layers back to rest. Careful: this is also called from
## the middle of a "fade_black", where the rest of the tween still has to run,
## so it must not touch the tween itself.
func _settle_background_fade() -> void:
	if _bg_b.texture != null:
		_bg_a.texture = _bg_b.texture
		_bg_b.texture = null
	_bg_a.modulate = Color(1, 1, 1, 1)
	_bg_b.modulate = Color(1, 1, 1, 0)
	_reset_bg_geometry()


## Puts the transition layers back to their resting state.
func _reset_bg_geometry() -> void:
	_bg_mask.position = Vector2.ZERO
	_bg_mask.size = _world.size
	_bg_b.position = Vector2.ZERO
	_bg_b.size = _world.size


## True while a background transition is still playing.
func _is_transition_running() -> bool:
	return _bg_tween != null and _bg_tween.is_valid() and _bg_tween.is_running()


## The cast a slide asks for. A "characters" list still replaces the whole
## line-up (the original behaviour); "hide" and "show" change it one character
## at a time, so you can send someone off or bring them back without repeating
## everyone else. Hide runs before show, so a character can leave and return on
## the same slide.
func _apply_stage(slide: Dictionary, fade: float, instant: bool) -> void:
	var default_effect := str(slide.get("with", "dissolve"))
	if slide.has("characters"):
		_apply_characters(slide["characters"], fade, instant)
	for entry in (slide.get("hide", []) as Array):
		_hide_character(entry, default_effect, fade, instant)
	for entry in (slide.get("show", []) as Array):
		_show_character(entry, default_effect, fade, instant)


func _apply_characters(list: Variant, fade: float, instant: bool) -> void:
	if list == null:
		# The slide said nothing about characters, so the line-up stays as is.
		return

	var wanted: Array = list
	var keep := {}
	for i in wanted.size():
		var entry: Dictionary = wanted[i]
		var slot := str(entry.get("id", ""))
		if slot.is_empty():
			slot = "char_%d" % i
		keep[slot] = true

		var node: TextureRect = _character_nodes.get(slot)
		var is_new := node == null
		if is_new:
			node = _make_character_node()
			_characters.add_child(node)
			_character_nodes[slot] = node
		_place_character(node, entry, is_new)
		if is_new:
			_fade_node(node, 1.0, fade, instant)

	# Whoever is no longer on stage leaves it.
	for slot in _character_nodes.keys():
		if keep.has(slot):
			continue
		var leaving: TextureRect = _character_nodes[slot]
		_character_nodes.erase(slot)
		_fade_node(leaving, 0.0, fade, instant, true)


## Brings one character in (or moves one that is already there) with the
## transition its entry asks for.
func _show_character(entry: Dictionary, default_effect: String, fade: float, instant: bool) -> void:
	var slot := str(entry.get("id", "")).strip_edges()
	if slot.is_empty():
		return
	var node: TextureRect = _character_nodes.get(slot)
	var is_new := node == null
	if is_new:
		node = _make_character_node()
		_characters.add_child(node)
		_character_nodes[slot] = node
	_place_character(node, entry, is_new)
	if is_new:
		# One that is already on stage just moves, it does not fade in again.
		_fade_node(node, 1.0, _stage_duration(entry, fade), instant, false, _stage_effect(entry, default_effect))


## Takes one character off the stage.
func _hide_character(entry: Dictionary, default_effect: String, fade: float, instant: bool) -> void:
	var slot := str(entry.get("id", "")).strip_edges()
	if slot.is_empty() or not _character_nodes.has(slot):
		return
	var leaving: TextureRect = _character_nodes[slot]
	_character_nodes.erase(slot)
	_fade_node(leaving, 0.0, _stage_duration(entry, fade), instant, true, _stage_effect(entry, default_effect))


## Puts a picture's texture, flip, tint and place on screen. [param is_new] is
## used so a fresh picture starts transparent and can fade in.
func _place_character(node: TextureRect, entry: Dictionary, is_new: bool) -> void:
	node.set_meta("entry", entry)
	var image_path := str(entry.get("image", ""))
	node.texture = load(image_path) as Texture2D if not image_path.is_empty() else null
	node.flip_h = bool(entry.get("flip", false))
	var tint: Color = entry.get("tint", Color.WHITE)
	node.modulate = Color(tint.r, tint.g, tint.b, 0.0 if is_new else node.modulate.a)
	_layout_character(node)


## The transition a show / hide entry uses: its own "effect", else the slide's
## "with", else the fade this framework has always used.
func _stage_effect(entry: Dictionary, fallback: String) -> String:
	var effect := str(entry.get("effect", "")).strip_edges().to_lower()
	if effect.is_empty():
		effect = fallback.strip_edges().to_lower()
	return effect if not effect.is_empty() else "dissolve"


func _stage_duration(entry: Dictionary, fallback: float) -> float:
	var duration := float(entry.get("duration", -1.0))
	return fallback if duration < 0.0 else duration


func _make_character_node() -> TextureRect:
	var node := TextureRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.modulate = Color(1, 1, 1, 0)
	return node


## Places a character picture so its centre sits at the slide's horizontal
## ratio (0 = left edge, 1 = right edge) and its bottom edge at the vertical
## one (0 = top of the screen, 1 = the bottom edge, the default).
func _layout_character(node: TextureRect) -> void:
	var entry: Dictionary = node.get_meta("entry", {})
	var view := size
	var height := view.y * CHARACTER_HEIGHT_RATIO * float(entry.get("scale", 1.0))
	var aspect := 0.5
	if node.texture != null and node.texture.get_height() > 0:
		aspect = float(node.texture.get_width()) / float(node.texture.get_height())
	var width := height * aspect
	node.size = Vector2(width, height)
	var center_x := view.x * float(entry.get("x", 0.5))
	# -1 means "nothing was asked for", which is the classic line-up with the
	# feet on the bottom edge of the screen.
	var bottom := view.y
	var vertical := float(entry.get("y", -1.0))
	if vertical >= 0.0:
		bottom = view.y * vertical
	node.position = Vector2(center_x - width * 0.5, bottom - height + float(entry.get("offset_y", 0.0)))


## The little square picture in the left of the text box. The slide's own
## "portrait" always wins (an empty one hides the square); otherwise whoever is
## speaking shows their own picture. Narration leaves the square as it is.
func _apply_portrait(slide: Dictionary) -> void:
	if slide.has("portrait"):
		_set_portrait(str(slide["portrait"]))
		return
	var speaker := str(slide.get("speaker", "")).strip_edges()
	if speaker.is_empty():
		return
	var entry := _character_entry(speaker)
	if entry.is_empty():
		return
	_set_portrait(str(entry.get("portrait", "")))


func _set_portrait(path: String) -> void:
	var texture: Texture2D = null
	if not path.is_empty():
		texture = load(path) as Texture2D
	_portrait.texture = texture
	_portrait_frame.visible = texture != null
	_layout_portrait()


## The cast entry currently on stage whose id matches [param name], any case.
func _character_entry(name: String) -> Dictionary:
	var wanted := name.strip_edges().to_lower()
	if wanted.is_empty():
		return {}
	for node in _character_nodes.values():
		if not is_instance_valid(node):
			continue
		var entry: Dictionary = (node as Node).get_meta("entry", {})
		if str(entry.get("id", "")).to_lower() == wanted:
			return entry
	return {}


## Keeps the portrait slot a square as tall as the text box, with its border
## drawn on top of the picture, and gives the text the room beside it.
func _layout_portrait() -> void:
	if _portrait_frame == null or _text_box == null:
		return
	var box := _text_box.size
	var side := maxf(64.0, box.y - PORTRAIT_MARGIN * 2.0)
	_portrait_frame.position = Vector2(PORTRAIT_MARGIN, (box.y - side) * 0.5)
	_portrait_frame.size = Vector2(side, side)
	var inner := maxf(1.0, side - PORTRAIT_BORDER * 2.0)
	_portrait_clip.position = Vector2(PORTRAIT_BORDER, PORTRAIT_BORDER)
	_portrait_clip.size = Vector2(inner, inner)
	# The text slides right when the square is there, and back when it is not.
	var text_left := TEXT_MARGIN_LEFT
	if _portrait_frame.visible:
		text_left = int(side + PORTRAIT_MARGIN * 2.0)
	_text_content.add_theme_constant_override("margin_left", text_left)


func _on_resized() -> void:
	_world.pivot_offset = size * 0.5
	for node in _character_nodes.values():
		if is_instance_valid(node):
			_layout_character(node)
	_layout_portrait()
	_layout_choices()
	if not _is_transition_running():
		_reset_bg_geometry()


## Brings a picture in or out over [param fade] seconds. [param effect] is one
## of StoryParser.STAGE_EFFECTS: "none" cuts, anything else ("dissolve", the
## default) fades.
func _fade_node(node: CanvasItem, target_alpha: float, fade: float, instant: bool, free_when_done: bool = false, effect: String = "dissolve") -> void:
	if effect == "none" or instant or fade <= 0.0:
		node.modulate.a = target_alpha
		if free_when_done:
			node.queue_free()
		return
	# Owned by the node, so a node that is freed before the fade ends takes its
	# tween with it instead of leaving a callback pointing at a dead object.
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", target_alpha, fade)
	if free_when_done:
		tween.tween_callback(node.queue_free)


func _clear_stage() -> void:
	for child in _characters.get_children():
		_characters.remove_child(child)
		child.queue_free()
	_character_nodes.clear()
	_set_portrait("")
	_stop_background_transition()
	reset_effects()
	_current_background = ""
	_bg_a.texture = null
	_curtain.color = Color(0, 0, 0, 0)
	_hide_choices()
	_history.clear()
	stop_music(0.0)


# --- audio -------------------------------------------------------------------

## Crossfades to [param path], looping forever. 0 volume to 1.
func play_music(path: String, fade: float = 0.6) -> void:
	if path.is_empty():
		stop_music(fade)
		return
	if path == _current_music and _music_active.playing:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("FMW_VN: could not load music \"%s\"." % path)
		return
	_make_looping(stream)

	var incoming := _music_idle
	var outgoing := _music_active
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_kill_music_tween()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	# The fade-in is driven by a fraction rather than by a frozen dB value, so the
	# level it arrives at is worked out on every step: a player turning the master
	# volume down while a track fades in is obeyed there and then, instead of only
	# when the fade is over.
	_music_tween.tween_method(_fade_music_in.bind(incoming), 0.0, 1.0, maxf(0.01, fade))
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, maxf(0.01, fade))
	_music_tween.chain().tween_callback(func() -> void:
		outgoing.stop()
		outgoing.volume_db = SILENT_DB
	)
	_music_active = incoming
	_music_idle = outgoing
	_current_music = path


## One step of a fade-in: [param t] 0 is silent and 1 is the level the track is
## meant to be at *now* - [method _music_db], asked for again on every step, so a
## change to the master volume (or to the story's own music level) is followed
## while the track climbs rather than only once it has arrived.
func _fade_music_in(t: float, player: AudioStreamPlayer) -> void:
	player.volume_db = SILENT_DB if t <= 0.0 else lerpf(SILENT_DB, _music_db(), t)


func stop_music(fade: float = 0.6) -> void:
	_current_music = ""
	_kill_music_tween()
	if not _music_a.playing and not _music_b.playing:
		return
	var fade_time := maxf(0.01, fade)
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	for player in [_music_a, _music_b]:
		if (player as AudioStreamPlayer).playing:
			_music_tween.tween_property(player, "volume_db", SILENT_DB, fade_time)
	_music_tween.chain().tween_callback(_reset_music_players)


## Plays a one-shot sound effect through the next free player.
func play_sfx(path: String) -> void:
	if path.is_empty() or _sfx_players.is_empty():
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("FMW_VN: could not load sound \"%s\"." % path)
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = _sound_db()
	player.play()


func _apply_music(slide: Dictionary, fade: float) -> void:
	if not slide.has("bgm"):
		return
	var path := str(slide["bgm"])
	if path == _current_music:
		return
	if path.is_empty():
		stop_music(fade)
	else:
		play_music(path, fade)


func _apply_sfx(slide: Dictionary) -> void:
	for path in (slide.get("sfx", []) as Array):
		play_sfx(str(path))


## What the music is played at: the story's own music level multiplied by the
## player's master volume. Either one at 0 means silence, and [constant
## SILENT_DB] is used rather than the -inf [method linear_to_db] would give.
func _music_db() -> float:
	var level := _music_volume * _master_volume
	return SILENT_DB if level <= 0.0 else linear_to_db(level)


## The same for a one-shot sound effect.
func _sound_db() -> float:
	var level := _sound_volume * _master_volume
	return SILENT_DB if level <= 0.0 else linear_to_db(level)


func _apply_sound_volume() -> void:
	for player in _sfx_players:
		player.volume_db = _sound_db()


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null


func _reset_music_players() -> void:
	for player in [_music_a, _music_b]:
		(player as AudioStreamPlayer).stop()
		(player as AudioStreamPlayer).volume_db = SILENT_DB
	_music_active = _music_a
	_music_idle = _music_b


## Music plays until it is stopped, so loop what can loop.
static func _make_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


# --- screen effects ----------------------------------------------------------

## Plays the effects a slide asked for, in the order it listed them.
func _apply_effects(slide: Dictionary) -> void:
	for effect in (slide.get("effects", []) as Array):
		play_effect(str(effect.get("type", "")), effect)


## Plays one screen effect. [param params] use the same keys as the JSON:
## "delay", "strength", "duration", "color", "from" and "to".
func play_effect(type: String, params: Dictionary = {}) -> void:
	match type:
		"shake":
			_effect_shake(params)
		"flash":
			_effect_flash(params)
		"zoom":
			_effect_zoom(params)
		"pulse":
			_effect_pulse(params)
		"reset":
			reset_effects()
		_:
			push_warning("FMW_VN: unknown effect \"%s\"." % type)


## Stops every screen effect and puts the picture layer back to normal.
func reset_effects() -> void:
	_kill_tween(_shake_tween)
	_kill_tween(_zoom_tween)
	_kill_tween(_flash_tween)
	_shake_tween = null
	_zoom_tween = null
	_flash_tween = null
	_world.position = Vector2.ZERO
	_world.scale = Vector2.ONE
	_flash.color = Color(_flash.color.r, _flash.color.g, _flash.color.b, 0.0)


## True while a screen effect is still moving things around.
func is_effect_running() -> bool:
	for tween in [_shake_tween, _zoom_tween, _flash_tween]:
		if tween != null and (tween as Tween).is_valid() and (tween as Tween).is_running():
			return true
	return false


## Shakes the picture layer for a moment.
func _effect_shake(params: Dictionary) -> void:
	var strength := float(params.get("strength", 18.0))
	var duration := maxf(0.01, float(params.get("duration", 0.45)))
	var delay := maxf(0.0, float(params.get("delay", 0.0)))
	_kill_tween(_shake_tween)
	_world.position = Vector2.ZERO
	_shake_tween = create_tween()
	if delay > 0.0:
		_shake_tween.tween_interval(delay)
	# A handful of quick offsets that settle down, then straight back to rest.
	var steps := 6
	var step_time := duration / float(steps)
	for i in steps:
		var falloff := 1.0 - float(i) / float(steps)
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		_shake_tween.tween_property(_world, "position", offset, step_time)
	_shake_tween.tween_property(_world, "position", Vector2.ZERO, step_time)


## Flashes the screen in a colour: quick in, slower out.
func _effect_flash(params: Dictionary) -> void:
	var colour: Color = params.get("color", Color.WHITE)
	var duration := maxf(0.01, float(params.get("duration", 0.4)))
	var delay := maxf(0.0, float(params.get("delay", 0.0)))
	_kill_tween(_flash_tween)
	_flash.color = Color(colour.r, colour.g, colour.b, 0.0)
	_flash_tween = create_tween()
	if delay > 0.0:
		_flash_tween.tween_interval(delay)
	_flash_tween.tween_property(_flash, "color:a", 1.0, duration * 0.25)
	_flash_tween.tween_property(_flash, "color:a", 0.0, duration * 0.75)


## Pushes the picture layer in (or out) and leaves it there.
func _effect_zoom(params: Dictionary) -> void:
	var from := float(params.get("from", 1.0))
	var to := float(params.get("to", 1.08))
	var duration := maxf(0.0, float(params.get("duration", 1.0)))
	var delay := maxf(0.0, float(params.get("delay", 0.0)))
	_kill_tween(_zoom_tween)
	_world.scale = Vector2(from, from)
	if duration <= 0.0:
		_world.scale = Vector2(to, to)
		return
	_zoom_tween = create_tween()
	if delay > 0.0:
		_zoom_tween.tween_interval(delay)
	_zoom_tween.tween_property(_world, "scale", Vector2(to, to), duration)


## A quick throb: out and straight back, leaving the zoom where it was.
func _effect_pulse(params: Dictionary) -> void:
	var strength := float(params.get("strength", 0.04))
	var duration := maxf(0.01, float(params.get("duration", 0.35)))
	var delay := maxf(0.0, float(params.get("delay", 0.0)))
	var base := _world.scale.x
	_kill_tween(_zoom_tween)
	_zoom_tween = create_tween()
	if delay > 0.0:
		_zoom_tween.tween_interval(delay)
	_zoom_tween.tween_property(_world, "scale", Vector2(base + strength, base + strength), duration * 0.5)
	_zoom_tween.tween_property(_world, "scale", Vector2(base, base), duration * 0.5)


# --- save / load -------------------------------------------------------------

## The one-line preview of a slide: the speaker and the line, trimmed. Used by the
## save slots and by the global progress record.
func _slide_label(slide: Dictionary) -> String:
	var label := _speaker(slide)
	if not label.is_empty() and not _text(slide).is_empty():
		label += ": "
	label += _text(slide)
	if label.length() > 70:
		label = label.substr(0, 69) + "..."
	return label


## Writes the current position to [param path] as JSON.
func save_game(path: String = "") -> bool:
	if _story == null:
		return false
	var target := path if not path.is_empty() else save_path
	var slide := current_slide()
	var chapter := _story.chapter_of(_slide_index)
	var label := _slide_label(slide)

	var data := {
		"version": 1,
		"title": _story.title_for(_language),
		"story": _story.source_path,
		"chapter": str(chapter.get("path", "")).get_file(),
		"slide_index": _slide_index,
		"slide_id": str(slide.get("id", "")),
		"label": label,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"background": _current_background,
		"characters": _lineup_for_save(),
		"music": _current_music,
		"music_volume": _music_volume,
		"sound_volume": _sound_volume,
		"history": _history,
		# The variable state travels with the save, so a loaded story keeps every
		# flag and counter exactly where it was.
		"variables": _vars.to_dict() if _vars != null else {},
	}
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("FMW_VN: could not write %s (%s)." % [target, error_string(FileAccess.get_open_error())])
		_show_toast("Save failed.")
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_show_toast("Saved.")
	return true


## Restores a save written by [method save_game]. Returns true when it worked.
func load_game(path: String = "") -> bool:
	var target := path if not path.is_empty() else save_path
	if not FileAccess.file_exists(target):
		_show_toast("No save file yet.")
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(target)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("FMW_VN: %s is not a valid save file." % target)
		_show_toast("Save file could not be read.")
		return false

	var data: Dictionary = json.data
	var saved_story := str(data.get("story", ""))
	if saved_story.is_empty():
		_show_toast("Save file does not remember its story.")
		return false

	if _story == null or _story.source_path != saved_story:
		var result: StoryLib.Result = StoryLib.parse_file(saved_story)
		for message in result.warnings:
			push_warning("FMW_VN: " + message)
		if not result.ok:
			_report_errors(result.errors)
			return false
		_story = result.story
		story_path = saved_story
		_vars = _story.new_vars()
		_vars.changed.connect(_on_variable_changed)
		_clear_stage()
		_bg_fallback.color = _story.background_color
		_music_volume = _story.music_volume
		_sound_volume = _story.sound_volume
	_message_overlay.visible = false

	_music_volume = clampf(_float_of(data.get("music_volume"), _music_volume), 0.0, 1.0)
	_sound_volume = clampf(_float_of(data.get("sound_volume"), _sound_volume), 0.0, 1.0)
	_apply_sound_volume()

	if _vars == null:
		_vars = _story.new_vars()
		_vars.changed.connect(_on_variable_changed)
	# Reset first, so a load always lands on the save's own state. Every value
	# goes back to the story's declared starting value and only the ones the save
	# actually holds are written over it, so a variable added to the story in a
	# later revision - one an older save never knew - keeps its declared default
	# instead of being wiped.
	reset_variables()
	var saved_variables: Variant = data.get("variables")
	if typeof(saved_variables) == TYPE_DICTIONARY:
		_vars.from_dict(saved_variables)

	_history.clear()
	for entry in (data.get("history", []) as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			_history.append(entry)

	var lineup: Array[Dictionary] = []
	for entry in (data.get("characters", []) as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			lineup.append(_entry_from_save(entry))

	# The saved slide id comes first: if a later revision added or removed slides
	# ahead of it, the index alone would land on the wrong line, while the id still
	# names the same scene. Only when the id is gone - the slide was deleted or
	# renamed - does the index come into it: clamped into range, and nudged to the
	# start of the chapter the save was in when it no longer lands inside it.
	var saved_id := str(data.get("slide_id", ""))
	var saved_index := int(data.get("slide_index", 0))
	var resumed_nearby := false
	var resolved := saved_index
	if not saved_id.is_empty() and _story.has_slide(saved_id):
		resolved = _story.index_of(saved_id)
	else:
		resumed_nearby = true
		resolved = clampi(saved_index, 0, maxi(_story.slide_count() - 1, 0))
		var chapter := _chapter_for_save(data)
		if not chapter.is_empty():
			var first := int(chapter["first_index"])
			var last := int(chapter["last_index"])
			if resolved < first or resolved > last:
				resolved = first

	_restore_slide(
		resolved,
		str(data.get("background", "")),
		lineup,
		str(data.get("music", ""))
	)
	if resumed_nearby:
		_show_toast("Scene changed after update, resuming nearby.")
	else:
		_show_toast("Loaded.")
	return true


## True when a save file is sitting at [param path].
func save_exists(path: String = "") -> bool:
	return FileAccess.file_exists(path if not path.is_empty() else save_path)


## The chapter a save was in, matched by the file name the save recorded, or {}
## when that chapter is no longer part of the story. A save stores the chapter by
## file name, so it survives the chapter being moved on disk.
func _chapter_for_save(data: Dictionary) -> Dictionary:
	var name := str(data.get("chapter", "")).get_file()
	if name.is_empty():
		return {}
	for chapter in _story.chapters:
		if str(chapter.get("path", "")).get_file() == name:
			return chapter
	return {}


## Shows a saved position without writing anything. The pictures and cast come
## from the save file, because a slide does not have to repeat what is already
## on screen.
func _restore_slide(index: int, background: String, lineup: Array[Dictionary], music: String) -> void:
	_current_background = ""
	_apply_background(background, "cut", 0.0, true)
	_apply_characters(lineup, 0.0, true)

	_slide_index = clampi(index, 0, _story.slide_count() - 1)
	var slide := _story.slide_at(_slide_index)
	_apply_text(slide, true, false)
	# A restored save waits for the player instead of moving on by itself.
	_auto_timer = -1.0
	_apply_effects(slide)

	_current_music = ""
	if music.is_empty():
		stop_music(0.2)
	else:
		play_music(music, 0.4)
	_apply_sfx(slide)
	slide_shown.emit(_slide_index)
	# A restored position is somewhere the player has now been seen.
	_note_progress(_slide_index)


func _lineup_for_save() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in _character_nodes.values():
		var entry := (node.get_meta("entry", {}) as Dictionary).duplicate()
		var tint: Color = entry.get("tint", Color.WHITE)
		# Colours are not JSON, so they travel as "#rrggbbaa".
		entry["tint"] = "#" + tint.to_html()
		out.append(entry)
	return out


func _entry_from_save(raw: Dictionary) -> Dictionary:
	var entry := raw.duplicate()
	entry["tint"] = _color_of(entry.get("tint"))
	return entry


static func _color_of(value: Variant) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
	if typeof(value) == TYPE_STRING:
		var text := (value as String).strip_edges()
		if not text.begins_with("#"):
			text = "#" + text
		if Color.html_is_valid(text):
			return Color.html(text)
	return Color.WHITE


# --- save slots and the slot menu --------------------------------------------

## Path of a save slot. Slots are numbered from 1 in the menu, from 0 in code.
func slot_path(index: int) -> String:
	return "%s%d.json" % [SLOT_PREFIX, index + 1]


func slot_count() -> int:
	return SLOT_COUNT


func slot_exists(index: int) -> bool:
	return index >= 0 and index < SLOT_COUNT and FileAccess.file_exists(slot_path(index))


## Writes the current position into a slot.
func save_game_to_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		push_error("FMW_VN: there is no save slot %d (0..%d)." % [index, SLOT_COUNT - 1])
		return false
	if not save_game(slot_path(index)):
		return false
	_show_toast("Saved to slot %d." % (index + 1))
	return true


## Reads a slot back. Returns false when the slot is empty or unreadable.
func load_game_from_slot(index: int) -> bool:
	if not slot_exists(index):
		_show_toast("Slot %d is empty." % (index + 1))
		return false
	if not load_game(slot_path(index)):
		return false
	_show_toast("Loaded slot %d." % (index + 1))
	return true


## The summary the menu shows for a slot: {} when the slot is empty.
func slot_info(index: int) -> Dictionary:
	if not slot_exists(index):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(index))) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"broken": true}
	var data: Dictionary = json.data
	return {
		"title": str(data.get("title", "")),
		"chapter": str(data.get("chapter", "")),
		"label": str(data.get("label", "")),
		"saved_at": str(data.get("saved_at", "")),
		"slide_index": int(data.get("slide_index", 0)),
		"slide_id": str(data.get("slide_id", "")),
		"variables": int((data.get("variables", {}) as Dictionary).size()) if typeof(data.get("variables")) == TYPE_DICTIONARY else 0,
	}


## Opens the book on the slots, ready to save into one or to load out of one.
## The old names still work: the slot menu is the Save and Load pages of the
## book now.
func open_save_menu(mode: MenuMode = MenuMode.SAVE) -> void:
	open_book(BookPage.SAVE if mode == MenuMode.SAVE else BookPage.LOAD)


func close_save_menu() -> void:
	if is_menu_open():
		close_book()


func _on_book_button() -> void:
	toggle_book()


## Fills the save / load page with one row per slot.
func _rebuild_slots() -> void:
	var saving := _book_page == BookPage.SAVE
	for child in _menu_slots.get_children():
		_menu_slots.remove_child(child)
		child.queue_free()
	for i in SLOT_COUNT:
		_menu_slots.add_child(_make_slot_row(i, saving))


## One row: a button carrying two lines, the slot and what is in it.
func _make_slot_row(index: int, saving: bool) -> Button:
	var info := slot_info(index)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 92)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# An empty slot has nothing to load.
	button.disabled = not saving and info.is_empty()
	button.pressed.connect(_on_slot_pressed.bind(index))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)

	var heading := Label.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_size_override("font_size", 30)
	var detail := Label.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_theme_font_size_override("font_size", 22)
	detail.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95, 1.0))

	var title := "Slot %d" % (index + 1)
	if info.is_empty():
		detail.text = "- empty -"
	elif bool(info.get("broken", false)):
		detail.text = "- this save could not be read -"
	else:
		if not str(info.get("chapter", "")).is_empty():
			title += "    %s" % info["chapter"]
		detail.text = "%s    %s" % [info.get("label", ""), info.get("saved_at", "")]
	heading.text = title

	box.add_child(heading)
	box.add_child(detail)
	margin.add_child(box)
	button.add_child(margin)
	return button


func _on_slot_pressed(index: int) -> void:
	if _menu_mode == MenuMode.SAVE:
		if save_game_to_slot(index):
			close_save_menu()
	elif load_game_from_slot(index):
		close_save_menu()
		# Loading from the main menu starts the story, so the menu steps aside.
		close_main_menu()


# --- ui helpers --------------------------------------------------------------

func _finish() -> void:
	_state = State.FINISHED
	_set_hint("")
	_show_message("The End", "", "click / space to replay")
	story_finished.emit()


func _show_message(title: String, body: String, hint: String) -> void:
	_message_title.text = title
	_message_body.text = body
	_message_body.visible = not body.is_empty()
	_message_hint.text = hint
	_message_hint.visible = not hint.is_empty()
	_message_overlay.visible = true


func _report_errors(errors: PackedStringArray) -> void:
	for message in errors:
		push_error("FMW_VN: " + message)
	_state = State.FINISHED
	_show_message("Story could not be loaded", "\n".join(errors), "")
	story_failed.emit(errors)


func _set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_time = TOAST_SECONDS


func _tick_toast(delta: float) -> void:
	if _toast_time <= 0.0:
		return
	_toast_time -= delta
	if _toast_time <= 0.0:
		_toast_label.visible = false


static func _float_of(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


static func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


static func _is_advance_click(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false
