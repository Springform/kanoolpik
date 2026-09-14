class_name PickupItem
extends StaticBody3D
## Presentation of one catalog item lying on the island.
##
## Placeholder visual: a coloured box (see [ItemPalette]) with the item name
## floating above it. Phase 2 swaps the box for real models via ItemDef.model.
## Reacts to core events on the bus; never mutates state itself.

## Item names are only drawn within this distance of the camera (metres).
## Tuned by looking at the island, not by theory — at 6 m the 150 names still
## read as a wall of text. Worth re-tuning once you have played a full round.
const LABEL_VISIBLE_METRES := 2.5
## Only name what the player is actually facing. Distance alone is not enough:
## measured on screen at the spawn point, 3.5 m in every direction put 31 names
## up at once — a wall of text again, which is the thing the radius was added to
## prevent. A name behind your shoulder was never readable anyway.
## 0.45 is a little wider than the camera's own view, so a label does not blink
## out at the edge of the screen as you turn.
const LABEL_FACING_DOT := 0.45
## Only one item in this many frames re-checks its distance, staggered by
## instance id so the work is spread rather than spiking on one frame. 162 items
## doing a camera lookup and a distance test every frame buys nothing — a label
## cannot appear and disappear again within a tenth of a second of walking.
const LABEL_CHECK_FRAMES := 6

var item_id: String
var def: ItemDef

@onready var label: Label3D = $Label

## The model, or the generated placeholder when there is no model.
var visual: Node3D


func setup(p_def: ItemDef) -> void:
	def = p_def
	item_id = p_def.id


func _ready() -> void:
	var budget := ItemPalette.box_size(def)
	visual = ItemVisual.build(def.model, budget, ItemPalette.visual_color(def),
		def.model_scale, def.model_rotation)
	add_child(visual)
	# Collision follows whatever we ended up drawing, model or box, and stays a
	# simple box — the interaction ray only needs something to hit.
	var drawn := ItemVisual.visual_size(visual, budget)
	# Its OWN shape: a sub-resource declared in the .tscn is shared by every
	# instance of that scene, so all 150 items were writing to one BoxShape3D and
	# the last one to spawn decided the collision size for all of them.
	var shape := BoxShape3D.new()
	shape.size = drawn
	$Collision.shape = shape
	$Collision.position.y = drawn.y * 0.5
	label.text = tr(def.name_key)
	label.position.y = drawn.y + 0.15
	# With ~150 items the names became a wall of text across the whole island.
	# Only show them close up: the HUD prompt names whatever the crosshair is on,
	# so a label is just for the things right around you.
	#
	# Done in _process rather than with GeometryInstance3D.visibility_range_end,
	# which Label3D does not honour under the GL Compatibility renderer (the
	# property sets fine and changes nothing on screen — checked in the browser).
	label.visible = false
	GameEvents.item_picked_up.connect(_on_picked_up)
	GameEvents.item_dropped.connect(_on_dropped)
	GameEvents.item_placed.connect(_on_placed)
	GameEvents.item_taken_out.connect(_on_taken_out)
	# A level built from a save starts with items already carried or packed.
	set_in_world(GameSession.state.kind_of(item_id) == WorldState.Kind.GROUND)


func _process(_delta: float) -> void:
	if not visible:
		return
	# Staggered by instance id so the 162 checks are spread across frames rather
	# than all landing on the same one.
	if (Engine.get_process_frames() + get_instance_id()) % LABEL_CHECK_FRAMES != 0:
		return
	refresh_label()


## Show the name only when the camera is close. Public because the stagger above
## makes "call _process and look" an unreliable thing for a test to do — and
## because an item that has just appeared should be right immediately, not in
## six frames' time.
func refresh_label() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		label.visible = false
		return
	var offset := global_position - camera.global_position
	if offset.length_squared() > LABEL_VISIBLE_METRES * LABEL_VISIBLE_METRES:
		label.visible = false
		return
	# -Z is forward for a Godot camera.
	var forward := -camera.global_transform.basis.z
	label.visible = offset.normalized().dot(forward) >= LABEL_FACING_DOT


func _on_picked_up(id: String, _player_id: int) -> void:
	if id == item_id:
		set_in_world(false)


func _on_dropped(id: String, _player_id: int, position: Vector3) -> void:
	if id == item_id:
		global_position = position
		set_in_world(true)


func _on_placed(id: String, _player_id: int, _container_id: String, _slot: int, _verdict: int) -> void:
	if id == item_id:
		set_in_world(false) # ContainerNode renders placed items itself.


func _on_taken_out(id: String, _player_id: int, _container_id: String) -> void:
	if id == item_id:
		set_in_world(false)


## Visible and pickable, or tucked away because it is carried or packed.
func set_in_world(in_world: bool) -> void:
	visible = in_world
	$Collision.disabled = not in_world
