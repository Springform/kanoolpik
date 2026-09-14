class_name InsightHighlight
extends MeshInstance3D
## The glow Klarsyn puts on one item (WP-3.2): a swollen, unshaded, depth-test-free
## box drawn *around* the item, never on it.
##
## It is a separate node with its own mesh and its own material on purpose.
## Tinting the item's own material multiplies the imported glTF's albedo, which
## darkens as much as it colours (CLAUDE.md) — a "glow" drawn that way reads as a
## smudge. Drawing a second, additive-looking shell leaves [ItemVisual] alone.
##
## Everything is built in [method _ready] with `.new()`, so each highlight owns
## its mesh and material: a resource declared once and shared is the bug that
## made 150 items agree on one collision box.

## How much bigger than the item the shell is drawn, as a factor plus a flat
## margin. The flat part matters: a 13 cm beer can scaled by 1.5 is still a 13 cm
## beer can at 20 m, and the point of the ability is seeing it from across the island.
const SWELL_FACTOR := 1.45
const SWELL_MARGIN := 0.10
## Warm gold — the same family as the HUD's "you have this" colour, and it reads
## against grass, sand and water alike.
const GLOW_COLOR := Color(1.0, 0.82, 0.25, 0.5)
## Above the world, below the in-hand item ([ItemPalette] uses 10): the thing you
## are holding must never be hidden behind a hint about where its siblings are.
const RENDER_PRIORITY := 9

## Size of the item this shell wraps, in metres. Set before the node enters the tree.
var item_size := Vector3.ONE * 0.2


## A highlight shaped for an item of [param size]. Not added to anything — the
## caller parents it to the item it belongs to.
static func create(size: Vector3) -> InsightHighlight:
	var node := InsightHighlight.new()
	node.name = "InsightHighlight"
	node.item_size = size
	return node


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = item_size * SWELL_FACTOR + Vector3.ONE * SWELL_MARGIN
	mesh = box
	material_override = build_material()
	# Items stand on the ground with their base at y = 0 (see PickupItem), so the
	# shell has to be lifted by half its own height to wrap rather than sink.
	position.y = item_size.y * 0.5
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The look, as its own resource every time. Public so a test can state what
## "visible through terrain" actually means in material terms.
static func build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GLOW_COLOR
	# The whole point of the ability: the fourth tent pole is behind a hill.
	mat.no_depth_test = true
	mat.render_priority = RENDER_PRIORITY
	mat.disable_receive_shadows = true
	return mat
