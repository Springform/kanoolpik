class_name SettingsPanel
extends CanvasLayer
## The panel where a player changes the things [Settings] remembers (WP-5.1).
##
## [b]Built in code, not as a `.tscn`.[/b] A scene file is the one thing two
## agents cannot merge, and this panel is where every later WP adds its option —
## WP-5.2 wants head bob live, WP-5.4 wants the intro toggle, WP-5.3 may want a
## captions switch. A row here is an entry in [constant ROWS]; nobody has to
## open a scene to add one.
##
## [b]It does not decide whether the game is paused.[/b] Opened from the title
## screen nothing is running; opened from [PauseMenu] the tree is already
## paused and must stay that way until the player resumes. So the panel runs
## with PROCESS_MODE_ALWAYS and never touches `get_tree().paused` — whoever
## opened it owns that.

signal closed()

## One row per setting, in the order they are shown. `kind` picks the control.
## A separator is a row with no key.
const ROWS: Array = [
	{"kind": "slider", "key": Settings.LOOK_SENSITIVITY, "label": "ui.settings.sensitivity", "format": "relative"},
	{"kind": "slider", "key": Settings.LOOK_FOV, "label": "ui.settings.fov", "format": "degrees"},
	# Head bob and the intro toggle are NOT here yet. Their keys exist in
	# [Settings] so WP-5.2 and WP-5.4 have somewhere to write, but nothing reads
	# them, and a switch that does nothing is worse than a missing switch — it
	# is a bug report from somebody who flicked it and watched carefully.
	{"kind": "separator"},
	{"kind": "slider", "key": Settings.AUDIO_SFX, "label": "ui.settings.sfx", "format": "percent"},
	{"kind": "slider", "key": Settings.AUDIO_MUSIC, "label": "ui.settings.music", "format": "percent"},
	{"kind": "slider", "key": Settings.AUDIO_AMBIENCE, "label": "ui.settings.ambience", "format": "percent"},
	{"kind": "separator"},
	{"kind": "locale", "label": "ui.settings.language"},
]

const LOCALES: Array[String] = ["da", "en"]
const LABEL_WIDTH := 170.0
const VALUE_WIDTH := 64.0
const PANEL_WIDTH := 460.0

var root: Control
var panel: PanelContainer
var title_label: Label
var close_button: Button
var reset_button: Button

## key -> the control showing it, so [method refresh] can put every control back
## in step with the store after a reset.
var _controls: Dictionary = {}
var _value_labels: Dictionary = {}
var _locale_button: Button


static func install(parent: Node) -> SettingsPanel:
	var made := SettingsPanel.new()
	made.name = "SettingsPanel"
	parent.add_child(made)
	return made


func _init() -> void:
	# Above the pause menu (layer 8), which is the thing it is usually opened
	# on top of.
	layer = 9


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	root.visible = false
	apply_texts()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		apply_texts()


## Esc closes the panel and nothing else.
##
## [method Node._input] rather than `_unhandled_input`: [PauseMenu] listens for
## the same action, and `_input` runs first for everybody, so the panel closing
## can never also unpause the game behind it. Guarded on being open, so a closed
## panel is not silently eating the key.
func _input(event: InputEvent) -> void:
	if not is_open() or not event.is_action_pressed("ui_cancel"):
		return
	close()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return root != null and root.visible


func open() -> void:
	refresh()
	root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	close_button.grab_focus()
	_fit.call_deferred()


func close() -> void:
	root.visible = false
	closed.emit()


# --- Building ----------------------------------------------------------------------

func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = load("res://assets/ui/theme.tres")
	add_child(root)
	# Presets after add_child: a preset resolves against the parent rect, and a
	# node that has not been added yet has no parent to resolve against. It
	# happens to come out right for an anchor-only preset like this one, which
	# is exactly why it is worth doing in the order that is right for all of
	# them rather than the order that works for this one.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := PanelContainer.new()
	dim.name = "Dim"
	var dim_style := StyleBoxFlat.new()
	dim_style.bg_color = Color(0.02, 0.05, 0.08, 0.6)
	dim.add_theme_stylebox_override("panel", dim_style)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)

	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	title_label = Label.new()
	title_label.name = "Title"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	box.add_child(HSeparator.new())

	for row: Dictionary in ROWS:
		match String(row.get("kind", "")):
			"separator":
				box.add_child(HSeparator.new())
			"slider":
				box.add_child(_slider_row(row))
			"toggle":
				box.add_child(_toggle_row(row))
			"locale":
				box.add_child(_locale_row(row))

	box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	reset_button = Button.new()
	reset_button.name = "Reset"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.pressed.connect(_on_reset)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(close)
	buttons.add_child(reset_button)
	buttons.add_child(close_button)
	box.add_child(buttons)


func _row(label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.name = "Label"
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.set_meta("key", label_key)
	row.add_child(label)
	return row


func _slider_row(row: Dictionary) -> HBoxContainer:
	var key := String(row["key"])
	var box := _row(String(row["label"]))
	var bounds := Settings.range_for(key)

	var slider := HSlider.new()
	slider.name = "Slider_" + key
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = float(bounds["min"])
	slider.max_value = float(bounds["max"])
	slider.step = float(bounds["step"])
	# Writing slider.value from refresh() emits this too, and that is fine:
	# [method Settings.set_value] ignores a write of the value it already holds,
	# so a control being put back in step announces nothing. A guard here would
	# be that rule stated a second time — and two statements of one rule are how
	# the two start to differ.
	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_value(key, value)
		_write_value_label(key)
	)
	box.add_child(slider)

	var value_label := Label.new()
	value_label.name = "Value_" + key
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.set_meta("format", String(row.get("format", "percent")))
	box.add_child(value_label)

	_controls[key] = slider
	_value_labels[key] = value_label
	return box


func _toggle_row(row: Dictionary) -> HBoxContainer:
	var key := String(row["key"])
	var box := _row(String(row["label"]))
	var check := CheckButton.new()
	check.name = "Toggle_" + key
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
	)
	box.add_child(check)
	_controls[key] = check
	return box


func _locale_row(row: Dictionary) -> HBoxContainer:
	var box := _row(String(row["label"]))
	_locale_button = Button.new()
	_locale_button.name = "Locale"
	_locale_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locale_button.pressed.connect(_cycle_locale)
	box.add_child(_locale_button)
	return box


# --- Keeping the controls and the store in step -------------------------------------

## Put every control where the store says it should be.
##
## Writing `slider.value` emits `value_changed`, which runs the handler above —
## and that is harmless, because [method Settings.set_value] does nothing when
## the value has not changed. The test that matters is
## `test_refreshing_the_panel_is_not_the_player_choosing`; a mutation that
## removed a guard here survived precisely because the guard was redundant.
func refresh() -> void:
	for key: Variant in _controls:
		var control: Control = _controls[key]
		if control is HSlider:
			(control as HSlider).value = Settings.get_float(String(key))
		elif control is CheckButton:
			(control as CheckButton).button_pressed = Settings.get_bool(String(key))
		_write_value_label(String(key))
	_write_locale_text()


func _write_value_label(key: String) -> void:
	var label: Label = _value_labels.get(key)
	if label == null:
		return
	var value := Settings.get_float(key)
	match String(label.get_meta("format", "percent")):
		"degrees":
			label.text = "%d°" % int(roundf(value))
		"relative":
			# Raw sensitivity is 0.0025 radians per pixel, which means nothing
			# to anybody. Shown as a multiple of the default instead: 1.0 is
			# what the game has always felt like, 2.0 is twice as fast.
			label.text = "%.1f×" % (value / float(Settings.DEFAULTS[key]))
		_:
			label.text = "%d %%" % int(roundf(value * 100.0))


func _write_locale_text() -> void:
	if _locale_button != null:
		_locale_button.text = TranslationServer.get_locale().to_upper()


func _cycle_locale() -> void:
	var current := TranslationServer.get_locale()
	var next: String = LOCALES[(maxi(LOCALES.find(current), 0) + 1) % LOCALES.size()]
	Settings.set_value(Settings.UI_LOCALE, next)
	# The locale change re-translates everything through _notification, which
	# calls apply_texts; the button's own text is written there too.


func _on_reset() -> void:
	Settings.reset()
	refresh()
	apply_texts()


func apply_texts() -> void:
	if root == null:
		return
	title_label.text = tr("ui.settings.title")
	reset_button.text = tr("ui.settings.reset")
	close_button.text = tr("ui.settings.close")
	for label: Label in _labels_with_keys(root):
		label.text = tr(String(label.get_meta("key")))
	_write_locale_text()
	_fit.call_deferred()


func _labels_with_keys(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child: Node in node.get_children():
		if child is Label and child.has_meta("key"):
			found.append(child as Label)
		found.append_array(_labels_with_keys(child))
	return found


## The panel is built from a list, and a longer language makes a label wrap, so
## its height is never a number anybody could have typed into a scene. See
## [PanelFit] for the two bugs that live behind this one call.
func _fit() -> void:
	PanelFit.centre(panel)
