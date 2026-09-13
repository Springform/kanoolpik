class_name TitleScreen
extends CanvasLayer
## The front page (WP-1.6): name, tagline, a start button, an optional island
## code so friends can play the exact same mess, and a language toggle.
##
## Owns no game state — it emits [signal start_requested] and lets [Main] do the
## work. Texts are re-applied on a language change so the toggle is live.

## Emitted when the player wants to play. [param seed] < 0 means "level default".
signal start_requested(seed: int)

const LEVEL_DEFAULT_SEED := -1
const LOCALES: Array[String] = ["da", "en"]

@onready var title_label: Label = $Root/Panel/VBox/Title
@onready var tagline_label: Label = $Root/Panel/VBox/Tagline
@onready var seed_label: Label = $Root/Panel/VBox/SeedRow/SeedLabel
@onready var seed_input: LineEdit = $Root/Panel/VBox/SeedRow/SeedInput
@onready var start_button: Button = $Root/Panel/VBox/Start
@onready var language_button: Button = $Root/Panel/VBox/Language


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_texts()
	start_button.pressed.connect(_on_start)
	seed_input.text_submitted.connect(func(_t: String) -> void: _on_start())
	language_button.pressed.connect(toggle_language)
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
	start_button.text = tr("ui.title.start")
	language_button.text = "%s: %s" % [tr("ui.title.language"), TranslationServer.get_locale().to_upper()]


func _on_start() -> void:
	start_requested.emit(chosen_seed())
