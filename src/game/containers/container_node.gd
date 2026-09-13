class_name ContainerNode
extends StaticBody3D
## Presentation of one container (pant bag, cooler, canoe...).
##
## Placeholder visual: a translucent box with a label and a row of small
## "slot" cubes. Feedback (WP-1.2): placing flashes the slot and plays a chime
## (correct) or a thud (wrong); wrong slots carry an ✕ marker; a completed
## container turns gold, glows and plays a fanfare; the island-clean fanfare
## plays from the container that received the final item.
## Phase 2 replaces the box with a real model via ContainerDef.scene.

const FLASH_SECONDS := 0.35
const COMPLETE_PULSE_SECONDS := 0.6
## Correct chimes within this window step up in pitch (a little melody when you're on a roll).
const CHIME_COMBO_WINDOW := 2.0
const CHIME_MAX_STEPS := 7

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

var _slot_meshes: Array[MeshInstance3D] = []
var _slot_marks: Array[Label3D] = []
var _last_chime_time := -100.0
var _chime_steps := 0
var _received_last_item := false


func setup(p_def: ContainerDef) -> void:
	def = p_def
	container_id = p_def.id


func _ready() -> void:
	var width := 0.25 * def.slot_count + 0.3
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.6, 0.8)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.4, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	var shape: BoxShape3D = $Collision.shape
	shape.size = box.size
	label.text = tr(def.name_key)
	label.position.y = 0.9
	for i in range(def.slot_count):
		var m := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.18, 0.18, 0.18)
		m.mesh = cube
		m.material_override = VerdictStyle.material("empty")
		m.position = Vector3(-width * 0.5 + 0.25 + i * 0.25, 0.4, 0)
		slots_root.add_child(m)
		_slot_meshes.append(m)
		var mark := Label3D.new()
		mark.text = VerdictStyle.MARK_WRONG
		mark.modulate = VerdictStyle.COLOR_WRONG
		mark.outline_size = 6
		mark.pixel_size = 0.004
		mark.font_size = 40
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.position = m.position + Vector3(0, 0.2, 0)
		mark.visible = false
		slots_root.add_child(mark)
		_slot_marks.append(mark)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.item_taken_out.connect(_on_item_taken_out)
	GameEvents.container_completed.connect(_on_completed)
	GameEvents.island_clean.connect(_on_island_clean)


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


func refresh() -> void:
	for i in range(_slot_meshes.size()):
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
	_slot_meshes[slot].material_override = VerdictStyle.material(kind)
	_slot_marks[slot].visible = kind == "wrong"


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
		refresh()


func _on_completed(cid: String) -> void:
	if cid != container_id:
		return
	is_complete = true
	label.text = VerdictStyle.MARK_COMPLETE + " " + tr(def.name_key)
	label.modulate = VerdictStyle.COLOR_COMPLETE
	refresh()
	_pulse_all_slots()
	sfx_complete.play()


func _on_island_clean() -> void:
	if _received_last_item:
		sfx_clean.play()


# --- Feedback helpers -----------------------------------------------------------

func _flash_slot(slot: int, good: bool) -> void:
	if slot < 0 or slot >= _slot_meshes.size():
		return
	var m := _slot_meshes[slot]
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
	tween.chain().tween_callback(func(): if is_instance_valid(m): _apply_resting_material(slot))


func _pulse_all_slots() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	for m in _slot_meshes:
		m.scale = Vector3.ONE * 1.4
		tween.tween_property(m, "scale", Vector3.ONE, COMPLETE_PULSE_SECONDS).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
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
