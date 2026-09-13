class_name SlotNode
extends StaticBody3D
## One aimable slot in a [ContainerNode]: its own collider so the player can
## target a specific position instead of letting the game pick one.
##
## Owns the slot's visual cube and its ✕ marker; [ContainerNode] drives the
## look and this node only knows where it is and what it holds.
##
## Built entirely in code (see [method create]) so container scenes stay thin.
## A StaticBody3D rather than an Area3D so the interaction ray hits it with
## plain body collision, and it sits ABOVE the container lid — inside the
## container's own collision box the ray would hit the box first.

const CUBE_SIZE := Vector3(0.18, 0.18, 0.18)
## The collider is bigger than the cube so slots are comfortable to hit from 2-3 m.
const HITBOX_SIZE := Vector3(0.24, 0.30, 0.30)

var container_id: String
var slot_index: int = -1

var mesh: MeshInstance3D
var mark: Label3D


static func create(p_container_id: String, p_slot_index: int) -> SlotNode:
	var node := SlotNode.new()
	node.container_id = p_container_id
	node.slot_index = p_slot_index
	node.name = "Slot_%d" % p_slot_index
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HITBOX_SIZE
	shape.shape = box
	node.add_child(shape)

	node.mesh = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = CUBE_SIZE
	node.mesh.mesh = cube
	node.add_child(node.mesh)

	node.mark = Label3D.new()
	node.mark.text = VerdictStyle.MARK_WRONG
	node.mark.modulate = VerdictStyle.COLOR_MARK
	node.mark.outline_size = 10
	node.mark.pixel_size = 0.0035
	node.mark.font_size = 72
	node.mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.mark.position = Vector3(0, 0.22, 0)
	node.mark.visible = false
	node.add_child(node.mark)
	return node


## The item currently in this slot, or "" when empty.
func item_id() -> String:
	return GameSession.state.item_in_slot(container_id, slot_index)


func is_empty() -> bool:
	return item_id().is_empty()
