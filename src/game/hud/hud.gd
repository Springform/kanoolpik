class_name HUD
extends CanvasLayer
## In-game HUD v1 (WP-1.4).
##
## Top-left: progress + bar + containers packed. Top-right: elapsed time.
## Bottom-left: carrying load with capacity squares and the held item names
## (last = active, marked with ▶). Centre: crosshair + contextual prompt.
## Top-centre: stacking toast queue (max [const MAX_TOASTS]) coloured by verdict.
##
## Reads state via GameSession (read-only) and reacts to GameEvents. Other
## features can call [method show_toast]. Every string goes through tr().

const MAX_TOASTS := 3
const TOAST_SECONDS := 2.2
const TOAST_FADE := 0.4
const SLOT_SIZE := Vector2(22, 22)
const COLOR_SLOT_EMPTY := Color(1, 1, 1, 0.25)
const COLOR_SLOT_FULL := Color(0.9, 0.85, 0.6, 1)
const COLOR_INFO := Color(0.96, 0.96, 0.94)
const COLOR_ERROR := Color(1.0, 0.6, 0.4)

@onready var progress_label: Label = $Root/TopLeft/VBox/Progress
@onready var progress_bar: ProgressBar = $Root/TopLeft/VBox/ProgressBar
@onready var containers_label: Label = $Root/TopLeft/VBox/Containers
@onready var time_label: Label = $Root/TopRight/Time
@onready var carrying_label: Label = $Root/BottomLeft/VBox/Carrying
@onready var slots_box: HBoxContainer = $Root/BottomLeft/VBox/Slots
@onready var held_label: Label = $Root/BottomLeft/VBox/Held
@onready var prompt_label: Label = $Root/Prompt
@onready var toasts_box: VBoxContainer = $Root/Toasts

var _player: Player
var _last_progress: Dictionary = {}


func _ready() -> void:
	GameEvents.progress_changed.connect(_on_progress)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.container_completed.connect(_on_container_completed)
	GameEvents.island_clean.connect(_on_island_clean)
	GameEvents.command_rejected.connect(_on_rejected)
	GameEvents.local_player_spawned.connect(func(p: Node3D) -> void: _player = p)
	prompt_label.text = ""
	held_label.text = ""
	if GameSession.catalog != null:
		_on_progress(Evaluation.progress(GameSession.catalog, GameSession.state))
		_refresh_carrying()


func _process(_delta: float) -> void:
	if GameSession.state != null:
		time_label.text = format_time(GameSession.state.elapsed_ticks / Evaluation.TICKS_PER_SECOND)
	if _player == null:
		return
	_refresh_carrying()
	prompt_label.text = _prompt_for(_player.aimed_target(), _player.carried_items())


# --- Public ----------------------------------------------------------------------

## Show a toast for [param seconds]. Oldest toast is dropped beyond MAX_TOASTS.
func show_toast(text: String, seconds: float = TOAST_SECONDS, color: Color = COLOR_INFO) -> void:
	while toasts_box.get_child_count() >= MAX_TOASTS:
		var oldest := toasts_box.get_child(0)
		toasts_box.remove_child(oldest)
		oldest.queue_free()
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	toasts_box.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(maxf(0.0, seconds - TOAST_FADE))
	tween.tween_property(label, "modulate:a", 0.0, TOAST_FADE)
	tween.tween_callback(label.queue_free)


func toast_count() -> int:
	return toasts_box.get_child_count()


func toast_texts() -> Array[String]:
	var out: Array[String] = []
	for c in toasts_box.get_children():
		out.append((c as Label).text)
	return out


static func format_time(total_seconds: int) -> String:
	var m := total_seconds / 60
	var s := total_seconds % 60
	return "%02d:%02d" % [m, s]


## i18n key for a CommandProcessor error id.
static func error_key(error_id: String) -> String:
	match error_id:
		CommandProcessor.E_HANDS_FULL, CommandProcessor.E_BAD_SLOT, CommandProcessor.E_NOT_ON_GROUND, \
		CommandProcessor.E_NOT_CARRIED, CommandProcessor.E_NOT_PLACED:
			return "ui.error." + error_id
		_:
			return "ui.error.generic"


## Prompt text for what the crosshair is on and what is held.
func _prompt_for(target: Node, held: Array[String]) -> String:
	var active := "" if held.is_empty() else tr(GameSession.catalog.get_item(held[held.size() - 1]).name_key)
	if target is PickupItem:
		return tr("ui.hud.pickup") % tr((target as PickupItem).def.name_key)
	if target is ContainerNode and not held.is_empty():
		return tr("ui.hud.place") % [active, tr((target as ContainerNode).def.name_key)]
	if not held.is_empty():
		return tr("ui.hud.drop") % active
	return ""


# --- Refresh ------------------------------------------------------------------------

func _refresh_carrying() -> void:
	var pid := _player.player_id if _player != null else GameSession.local_player_id()
	var capacity := GameSession.state.player_capacity(pid)
	var carried := GameSession.processor.carried_load(GameSession.state, pid)
	carrying_label.text = tr("ui.hud.carrying") % [carried, capacity]
	while slots_box.get_child_count() < capacity:
		var r := ColorRect.new()
		r.custom_minimum_size = SLOT_SIZE
		slots_box.add_child(r)
	while slots_box.get_child_count() > capacity:
		var extra := slots_box.get_child(slots_box.get_child_count() - 1)
		slots_box.remove_child(extra)
		extra.queue_free()
	for i in range(slots_box.get_child_count()):
		(slots_box.get_child(i) as ColorRect).color = COLOR_SLOT_FULL if i < carried else COLOR_SLOT_EMPTY
	var held := GameSession.state.carried_by(pid)
	if held.is_empty():
		held_label.text = tr("ui.hud.hands_empty")
		return
	var names: Array[String] = []
	for i in range(held.size()):
		var n := tr(GameSession.catalog.get_item(held[i]).name_key)
		names.append(("▶ " + n) if i == held.size() - 1 else n)
	held_label.text = ", ".join(names)


# --- Event handlers -----------------------------------------------------------------

func _on_progress(p: Dictionary) -> void:
	_last_progress = p
	progress_label.text = tr("ui.hud.progress") % [p["correct"], p["total"]]
	progress_bar.value = p["completion"]
	containers_label.text = tr("ui.hud.containers") % [p["containers_completed"], p["containers_total"]]


func _on_item_placed(_item_id: String, _player_id: int, _cid: String, _slot: int, verdict: int) -> void:
	show_toast(tr(VerdictStyle.toast_key(verdict)), TOAST_SECONDS, VerdictStyle.color_for(verdict))


func _on_container_completed(cid: String) -> void:
	show_toast(tr("ui.container_complete") % tr(GameSession.catalog.get_container(cid).name_key), 3.0, VerdictStyle.COLOR_COMPLETE)


func _on_island_clean() -> void:
	show_toast(tr("ui.island_clean"), 10.0, VerdictStyle.COLOR_COMPLETE)


func _on_rejected(_cmd: Dictionary, error: String) -> void:
	show_toast(tr(error_key(error)), 1.5, COLOR_ERROR)
