class_name ContainerNode
extends StaticBody3D
## Presentation of one container (pant bag, cooler, canoe...).
##
## Placeholder visual: a translucent box with a label and a row of [SlotNode]
## children — each slot is separately aimable (WP-1.3), so the player chooses
## where an item goes and can take items back out.
##
## Feedback (WP-1.2): placing flashes the slot and plays a chime (correct) or a
## thud (wrong); wrong slots carry an ✕ marker; a completed container turns
## gold, glows and plays a fanfare; the island-clean fanfare plays from the
## container that received the final item.
##
## Phase 2 replaces the box with a real model via ContainerDef.scene.

const FLASH_SECONDS := 0.35
const COMPLETE_PULSE_SECONDS := 0.6
## Correct chimes within this window step up in pitch (a little melody when you're on a roll).
const CHIME_COMBO_WINDOW := 2.0
const CHIME_MAX_STEPS := 7
## Slots sit just above the lid so the interaction ray reaches them before the body.
const SLOT_HEIGHT := 0.74

var container_id: String
var def: ContainerDef
var is_complete := false

@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label
@onready var slots_root: Node3D = $Slots
@onready var sfx_correct: AudioStreamPlayer3D = $SfxCorrect
@onready var sfx_wrong: AudioStreamPlayer3D = $SfxWrong
@onready var sfx_complete: AudioStreamPlayer3D = $SfxComplete
@onready var sfx_clean: AudioStreamPlayer3D = $SfxClean

var _slots: Array[SlotNode] = []
var _last_chime_time := -100.0
var _chime_steps := 0
var _received_last_item := false


func setup(p_def: ContainerDef) -> void:
	def = p_def
	container_id = p_def.id


func _ready() -> void:
	# Footprint comes from ContainerDef so the level layout and the mess generator
	# agree with what is actually drawn here.
	var width := def.width()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.6, ContainerDef.DEPTH)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.4, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	var shape: BoxShape3D = $Collision.shape
	shape.size = box.size
	label.text = tr(def.name_key)
	label.position.y = 1.15
	for i in range(def.slot_count):
		var slot := SlotNode.create(container_id, i)
		slot.position = Vector3(-width * 0.5 + 0.25 + i * ContainerDef.SLOT_SPACING, SLOT_HEIGHT, 0)
		slots_root.add_child(slot)
		_slots.append(slot)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.item_taken_out.connect(_on_item_taken_out)
	GameEvents.container_completed.connect(_on_completed)
	GameEvents.island_clean.connect(_on_island_clean)
	refresh()


# --- Queries ---------------------------------------------------------------------

func slot_count() -> int:
	return _slots.size()


func slot_node(slot: int) -> SlotNode:
	return _slots[slot] if slot >= 0 and slot < _slots.size() else null


func slot_mesh(slot: int) -> MeshInstance3D:
	var node := slot_node(slot)
	return node.mesh if node != null else null


func slot_mark(slot: int) -> Label3D:
	var node := slot_node(slot)
	return node.mark if node != null else null


func first_free_slot() -> int:
	for i in range(def.slot_count):
		if GameSession.state.item_in_slot(container_id, i).is_empty():
			return i
	return -1


## Verdict currently shown for a slot: -1 empty, else PlacementRules.Verdict.
func slot_verdict(slot: int) -> int:
	var item_id := GameSession.state.item_in_slot(container_id, slot)
	if item_id.is_empty():
		return -1
	return PlacementRules.evaluate(GameSession.catalog, GameSession.state, item_id, container_id, slot)


## Slot index for a raycast collider, or -1 when the hit was the container body.
func slot_at(collider: Node) -> int:
	var node := collider
	while node != null and not (node is SlotNode):
		if node is ContainerNode:
			return -1
		node = node.get_parent()
	return (node as SlotNode).slot_index if node is SlotNode else -1


# --- Look ------------------------------------------------------------------------

func refresh() -> void:
	for i in range(_slots.size()):
		_apply_resting_material(i)


## The material a slot should show when nothing is animating, derived from current state.
func resting_material_kind(slot: int) -> String:
	var v := slot_verdict(slot)
	if v < 0:
		return "empty"
	if is_complete:
		return "complete"
	return "correct" if VerdictStyle.is_good(v) else "wrong"


func _apply_resting_material(slot: int) -> void:
	var kind := resting_material_kind(slot)
	_slots[slot].mesh.material_override = VerdictStyle.material(kind)
	_slots[slot].mark.visible = kind == "wrong"


# --- Event handlers ------------------------------------------------------------

func _on_item_placed(_item_id: String, _player_id: int, cid: String, slot: int, verdict: int) -> void:
	_received_last_item = cid == container_id
	if cid != container_id:
		return
	is_complete = false
	refresh()
	_flash_slot(slot, VerdictStyle.is_good(verdict))
	if VerdictStyle.is_good(verdict):
		_play_chime()
	else:
		sfx_wrong.play()


func _on_item_taken_out(_item_id: String, _player_id: int, cid: String) -> void:
	if cid == container_id:
		is_complete = false
		label.text = tr(def.name_key)
		label.modulate = Color.WHITE
		refresh()


func _on_completed(cid: String) -> void:
	if cid != container_id:
		return
	is_complete = true
	label.text = tr("ui.container_packed") % tr(def.name_key)
	label.modulate = VerdictStyle.COLOR_COMPLETE
	refresh()
	_pulse_all_slots()
	sfx_complete.play()


func _on_island_clean() -> void:
	if _received_last_item:
		sfx_clean.play()


# --- Feedback helpers -----------------------------------------------------------

func _flash_slot(slot: int, good: bool) -> void:
	var node := slot_node(slot)
	if node == null:
		return
	var m := node.mesh
	var flash := StandardMaterial3D.new()
	flash.albedo_color = VerdictStyle.COLOR_FLASH_GOOD if good else VerdictStyle.COLOR_FLASH_BAD
	flash.emission_enabled = true
	flash.emission = flash.albedo_color
	flash.emission_energy_multiplier = 2.0 if good else 0.5
	m.material_override = flash
	m.scale = Vector3.ONE * (1.6 if good else 1.2)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(m, "scale", Vector3.ONE, FLASH_SECONDS).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "emission_energy_multiplier", 0.0, FLASH_SECONDS)
	# Recompute the resting look at the end: state may have changed (e.g. completed) during the flash.
	tween.chain().tween_callback(func() -> void: if is_instance_valid(m): _apply_resting_material(slot))


func _pulse_all_slots() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	for s in _slots:
		s.mesh.scale = Vector3.ONE * 1.4
		tween.tween_property(s.mesh, "scale", Vector3.ONE, COMPLETE_PULSE_SECONDS).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	mesh.scale = Vector3(1.05, 1.15, 1.05)
	tween.tween_property(mesh, "scale", Vector3.ONE, COMPLETE_PULSE_SECONDS).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _play_chime() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_chime_time <= CHIME_COMBO_WINDOW:
		_chime_steps = mini(_chime_steps + 1, CHIME_MAX_STEPS)
	else:
		_chime_steps = 0
	_last_chime_time = now
	sfx_correct.pitch_scale = pow(2.0, _chime_steps / 12.0) # semitone steps
	sfx_correct.play()
