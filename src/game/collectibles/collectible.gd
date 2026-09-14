class_name Collectible
extends Node3D
## One hidden thing lying on the island (WP-3.7): a trolley, a pair of
## sunglasses, a headlamp, a whistle.
##
## It is **not** a [PickupItem] and deliberately shares no code with one. A
## collectible is not in the catalog, cannot be carried, cannot be placed, and
## never counts toward completion, accuracy or the island-clean check — see
## [CollectibleSpawner]. Everything it does is presentation: the find itself
## goes through [member Commands.collect] like every other state change.
##
## No collider, for the reason [Dressing] has none: a prop the player can bump
## into can pin him against a container or hide a sock behind something that
## cannot be moved. Finding one is a proximity test in the spawner, not a
## physics event.
##
## No name label either, unlike [PickupItem]. A label floating over a hidden
## thing is a sign saying "here", and it would give away the trolley from across
## the camp.

## How far the thing floats above the ground it was placed on. Enough that it
## reads as lying on the grass rather than sunk into the hillside.
const LIFT := 0.08
## The slow bob and turn that catches the eye. Small on purpose: this is what
## makes a collectible findable in long grass at dusk without making it a beacon.
const BOB_HEIGHT := 0.05
const BOB_SECONDS := 2.6
const SPIN_DEGREES_PER_SECOND := 22.0

## How much bigger than life each one is drawn. Tuned by looking at them on a
## patch of grass, not by measuring: a real pair of sunglasses is 14 cm wide,
## and at that size it is a dark smudge you walk past forever. The trolley is
## already furniture-sized and stays honest.
const DISPLAY_SCALE := {
	"trolley": 1.0,
	"sunglasses": 1.8,
	"headlamp": 1.5,
	"whistle": 2.4,
}

## Key into [constant Progression.COLLECTIBLES].
var collectible_id: String

var _base_y := 0.0
## Offset into the bob cycle, so four of them do not pulse in unison.
var _phase := 0.0
var _elapsed := 0.0


## Must be called before the node enters the tree. [param phase] staggers the bob.
func setup(p_collectible_id: String, phase: float = 0.0) -> void:
	collectible_id = p_collectible_id
	_phase = phase


func _ready() -> void:
	_base_y = position.y
	add_child(_build_visual())


func _process(delta: float) -> void:
	_elapsed += delta
	rotate_y(deg_to_rad(SPIN_DEGREES_PER_SECOND) * delta)
	position.y = _base_y + LIFT + sin((_elapsed + _phase) * TAU / BOB_SECONDS) * BOB_HEIGHT


## Found things are off the island. Called by [CollectibleSpawner] both when the
## find happens and when a resumed save says it happened in an earlier session.
func set_found(found: bool) -> void:
	visible = not found
	set_process(not found)


# --- The four shapes ---------------------------------------------------------------
#
# Primitives rather than models: the four are small, seen from a couple of
# metres, and a box-and-cylinder language matches the placeholder items around
# them. Every mesh and material is built with .new() per instance — a resource
# declared once and shared is the bug that made 150 items share one collision
# box (see CLAUDE.md).

func _build_visual() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Visual"
	match collectible_id:
		"trolley":
			_build_trolley(holder)
		"sunglasses":
			_build_sunglasses(holder)
		"headlamp":
			_build_headlamp(holder)
		"whistle":
			_build_whistle(holder)
		_:
			_add_box(holder, "Body", Vector3(0.2, 0.2, 0.2), Vector3(0, 0.1, 0), Color(0.8, 0.2, 0.6))
	holder.scale = Vector3.ONE * float(DISPLAY_SCALE.get(collectible_id, 1.0))
	return holder


## A sack truck, folded and leaning: two uprights, a toe plate, two wheels.
func _build_trolley(holder: Node3D) -> void:
	const METAL := Color(0.52, 0.54, 0.58)
	const RUBBER := Color(0.14, 0.14, 0.16)
	_add_box(holder, "FrameLeft", Vector3(0.05, 0.62, 0.05), Vector3(-0.13, 0.34, 0.0), METAL)
	_add_box(holder, "FrameRight", Vector3(0.05, 0.62, 0.05), Vector3(0.13, 0.34, 0.0), METAL)
	_add_box(holder, "Handle", Vector3(0.31, 0.05, 0.05), Vector3(0.0, 0.63, 0.0), METAL)
	_add_box(holder, "Toe", Vector3(0.34, 0.03, 0.20), Vector3(0.0, 0.05, 0.11), METAL)
	_add_wheel(holder, "WheelLeft", Vector3(-0.19, 0.10, 0.0), RUBBER)
	_add_wheel(holder, "WheelRight", Vector3(0.19, 0.10, 0.0), RUBBER)
	holder.rotation.x = deg_to_rad(-16.0) # leaning back on its wheels, as one does


## Lenses, bridge, arms. The smallest of the four, so it gets the strongest
## glint: dark plastic against grass is otherwise nearly invisible.
func _build_sunglasses(holder: Node3D) -> void:
	const LENS := Color(0.10, 0.11, 0.14)
	const FRAME := Color(0.86, 0.72, 0.28)
	_add_box(holder, "LensLeft", Vector3(0.12, 0.07, 0.02), Vector3(-0.07, 0.07, 0.0), LENS, 0.7)
	_add_box(holder, "LensRight", Vector3(0.12, 0.07, 0.02), Vector3(0.07, 0.07, 0.0), LENS, 0.7)
	_add_box(holder, "Bridge", Vector3(0.04, 0.02, 0.02), Vector3(0.0, 0.08, 0.0), FRAME, 0.7)
	_add_box(holder, "ArmLeft", Vector3(0.02, 0.02, 0.13), Vector3(-0.12, 0.07, -0.07), FRAME, 0.7)
	_add_box(holder, "ArmRight", Vector3(0.02, 0.02, 0.13), Vector3(0.12, 0.07, -0.07), FRAME, 0.7)


## A head torch: an elastic band with a lamp on the front, and the lamp is lit.
func _build_headlamp(holder: Node3D) -> void:
	const STRAP := Color(0.22, 0.26, 0.34)
	const SHELL := Color(0.82, 0.80, 0.76)
	var band := MeshInstance3D.new()
	band.name = "Strap"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.10
	torus.outer_radius = 0.13
	band.mesh = torus
	band.material_override = _matte(STRAP, 0.0)
	band.rotation.x = deg_to_rad(90.0) # lying flat, the way a strap falls
	band.position.y = 0.03
	holder.add_child(band)
	_add_box(holder, "Lamp", Vector3(0.10, 0.07, 0.06), Vector3(0.0, 0.05, 0.12), SHELL)
	_add_box(holder, "Lens", Vector3(0.07, 0.05, 0.01), Vector3(0.0, 0.05, 0.155), Color(1.0, 0.96, 0.78), 1.4)


## A referee's whistle on its cord: a barrel, a mouthpiece, a bright finish.
func _build_whistle(holder: Node3D) -> void:
	const CHROME := Color(0.88, 0.86, 0.72)
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = 0.09
	barrel.mesh = cylinder
	barrel.material_override = _matte(CHROME, 0.9)
	barrel.rotation.z = deg_to_rad(90.0)
	barrel.position = Vector3(0.0, 0.04, 0.0)
	holder.add_child(barrel)
	_add_box(holder, "Mouthpiece", Vector3(0.07, 0.025, 0.02), Vector3(0.075, 0.04, 0.0), CHROME, 0.9)
	_add_box(holder, "Ring", Vector3(0.015, 0.03, 0.015), Vector3(-0.05, 0.075, 0.0), CHROME, 0.9)


func _add_box(holder: Node3D, node_name: String, size: Vector3, at: Vector3,
		color: Color, glint: float = 0.4) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = _matte(color, glint)
	mesh_node.position = at
	holder.add_child(mesh_node)


func _add_wheel(holder: Node3D, node_name: String, at: Vector3, color: Color) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.10
	cylinder.bottom_radius = 0.10
	cylinder.height = 0.05
	mesh_node.mesh = cylinder
	mesh_node.material_override = _matte(color, 0.0)
	mesh_node.rotation.z = deg_to_rad(90.0)
	mesh_node.position = at
	holder.add_child(mesh_node)


## Its own material every time, never a shared one — and a little emission, so
## the thing is still legible in the shade under a bush rather than a black
## silhouette on dark grass.
func _matte(color: Color, glint: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if glint > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glint * 0.4
	return mat
