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

const LEVEL_DEFAULT_SEED := -1
const LOCALES: Array[String] = ["da", "en"]

@onready var title_label: Label = $Root/Panel/VBox/Title
@onready var tagline_label: Label = $Root/Panel/VBox/Tagline
@onready var seed_label: Label = $Root/Panel/VBox/SeedRow/SeedLabel
@onready var seed_input: LineEdit = $Root/Panel/VBox/SeedRow/SeedInput
@onready var continue_button: Button = $Root/Panel/VBox/Continue
@onready var start_button: Button = $Root/Panel/VBox/Start
@onready var language_button: Button = $Root/Panel/VBox/Language

## Test-mode toggle, built in code because it exists only in a build that offers
## test mode at all (WP-3.10). A node in the scene would have to be hidden in
## every other build, which is the same thing said less clearly.
var test_mode_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only offer to continue when there is something to continue.
	continue_button.visible = GameSession.has_save()
	apply_texts()
	continue_button.pressed.connect(continue_requested.emit)
	start_button.pressed.connect(_on_start)
	seed_input.text_submitted.connect(func(_t: String) -> void: _on_start())
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
	language_button.text = "%s: %s" % [tr("ui.title.language"), TranslationServer.get_locale().to_upper()]
	_apply_test_mode_text()


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
