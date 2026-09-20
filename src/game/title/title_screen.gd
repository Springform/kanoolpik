class_name TitleScreen
extends CanvasLayer
## The front page (WP-1.6): name, tagline, a start button, an optional island
## code so friends can play the exact same mess, and a language toggle.
##
## Owns no game state — it emits [signal start_requested] and lets [Main] do the
## work. Texts are re-applied on a language change so the toggle is live.

## Emitted when the player wants to play. [param seed] < 0 means "level default".
signal start_requested(seed: int)
## Emitted when the player wants to resume the autosave.
signal continue_requested()
## Emitted when the player wants to open a room for friends (WP-4.4).
signal host_requested()
## Emitted when the player typed a room code and wants in.
signal join_requested(code: String)

const LEVEL_DEFAULT_SEED := -1
const LOCALES: Array[String] = ["da", "en"]

@onready var title_label: Label = $Root/Panel/VBox/Title
@onready var tagline_label: Label = $Root/Panel/VBox/Tagline
@onready var seed_label: Label = $Root/Panel/VBox/SeedRow/SeedLabel
@onready var seed_input: LineEdit = $Root/Panel/VBox/SeedRow/SeedInput
@onready var continue_button: Button = $Root/Panel/VBox/Continue
@onready var start_button: Button = $Root/Panel/VBox/Start
@onready var language_button: Button = $Root/Panel/VBox/Language
@onready var panel: PanelContainer = $Root/Panel
@onready var notice_label: Label = $Root/Panel/VBox/Notice
@onready var host_button: Button = $Root/Panel/VBox/Host
@onready var room_input: LineEdit = $Root/Panel/VBox/JoinRow/RoomInput
@onready var join_button: Button = $Root/Panel/VBox/JoinRow/Join

## Test-mode toggle, built in code because it exists only in a build that offers
## test mode at all (WP-3.10). A node in the scene would have to be hidden in
## every other build, which is the same thing said less clearly.
var test_mode_button: Button
## Kept so a language toggle re-translates the notice instead of clearing it.
var _notice_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only offer to continue when there is something to continue.
	continue_button.visible = GameSession.has_save()
	apply_texts()
	continue_button.pressed.connect(continue_requested.emit)
	start_button.pressed.connect(_on_start)
	seed_input.text_submitted.connect(func(_t: String) -> void: _on_start())
	host_button.pressed.connect(host_requested.emit)
	join_button.pressed.connect(_on_join)
	room_input.text_submitted.connect(func(_t: String) -> void: _on_join())
	# The relay's alphabet has no vowels and no lookalikes, so a lower-case "b"
	# is simply the same character said quietly. Uppercase it as they type
	# rather than refusing it later.
	room_input.text_changed.connect(_on_room_text_changed)
	language_button.pressed.connect(toggle_language)
	if TestMode.is_available():
		test_mode_button = Button.new()
		test_mode_button.name = "TestMode"
		test_mode_button.pressed.connect(_toggle_test_mode)
		language_button.get_parent().add_child(test_mode_button)
		_apply_test_mode_text()
	if continue_button.visible:
		continue_button.grab_focus()
	else:
		start_button.grab_focus()
	_fit_panel.call_deferred()


## Size the panel to whatever is actually in it, rather than to a number typed
## into the scene file.
##
## WP-4.4 added two buttons and a row, and the content grew past the fixed
## offsets: the background stopped halfway down and the last three controls sat
## on the island with nothing behind them. Every string assertion passed. The
## same thing waits for anyone who adds a row here, or whose language makes a
## label wrap, so the number is gone rather than raised.
func _fit_panel() -> void:
	PanelFit.centre(panel)


## Why we are back here, when we did not arrive by choice — the host left, the
## connection died (WP-4.6). Empty clears it.
func show_notice(reason_key: String) -> void:
	_notice_key = reason_key
	notice_label.text = tr(reason_key) if not reason_key.is_empty() else ""
	notice_label.visible = not reason_key.is_empty()
	_fit_panel.call_deferred()


## Put a code in the join field and aim the player at the button.
##
## [b]The way back in, after being dropped.[/b] Joining a running round already
## works (WP-4.6) and nothing personal is lost when you go — progression lives
## in the replicated world, so you come back with the party's points and
## abilities. What stood between a dropped player and the round was that they
## had just been thrown away from the six characters they needed to type.
##
## So reconnect is not a grace period and not a number: it is this field, filled
## in, with the button focused. [Main] calls it when a connection died under a
## round that is probably still going on without us.
func prefill_room(code: String) -> void:
	if code.is_empty():
		return
	room_input.text = RoomCode.normalize(code)
	join_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		apply_texts()


## The seed the player typed, or [constant LEVEL_DEFAULT_SEED] when the field is
## blank or not a number.
func chosen_seed() -> int:
	var text := seed_input.text.strip_edges()
	return int(text) if text.is_valid_int() else LEVEL_DEFAULT_SEED


func toggle_language() -> void:
	var next: String = LOCALES[(LOCALES.find(TranslationServer.get_locale()) + 1) % LOCALES.size()]
	TranslationServer.set_locale(next)
	apply_texts()


func apply_texts() -> void:
	title_label.text = tr("ui.title")
	tagline_label.text = tr("ui.title.tagline")
	seed_label.text = tr("ui.title.seed")
	seed_input.placeholder_text = tr("ui.title.seed_hint")
	continue_button.text = tr("ui.title.continue")
	start_button.text = tr("ui.title.start")
	host_button.text = tr("ui.title.host")
	join_button.text = tr("ui.title.join")
	room_input.placeholder_text = tr("ui.title.room_hint")
	language_button.text = "%s: %s" % [tr("ui.title.language"), TranslationServer.get_locale().to_upper()]
	_apply_test_mode_text()
	show_notice(_notice_key)
	# A longer language can change the panel's minimum size, so re-fit after the
	# labels have had a frame to measure themselves.
	_fit_panel.call_deferred()


func _toggle_test_mode() -> void:
	TestMode.set_enabled(not TestMode.is_enabled())
	_apply_test_mode_text()


func _apply_test_mode_text() -> void:
	if test_mode_button == null:
		return
	var on := TestMode.is_enabled()
	test_mode_button.text = tr("ui.title.test_mode_on") if on else tr("ui.title.test_mode_off")
	test_mode_button.tooltip_text = tr("ui.test.hint") if on else ""


func _on_start() -> void:
	start_requested.emit(chosen_seed())


func _on_room_text_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper == text:
		return
	var caret := room_input.caret_column
	room_input.text = upper
	room_input.caret_column = caret


## Emits whatever was typed, valid or not. [LobbyController] owns the verdict —
## the title screen saying "that is not a code" and the lobby saying it too
## would be two places to keep one sentence.
func _on_join() -> void:
	join_requested.emit(RoomCode.normalize(room_input.text))
