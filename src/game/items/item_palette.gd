class_name ItemPalette
extends RefCounted
## Placeholder look for items until real models arrive (phase 2): one colour
## per category and a box size derived from ItemDef.size. Shared by
## [PickupItem] (on the ground) and [HeldItems] (in hand) so they match.

const CATEGORY_COLOURS := {
	"can": Color(0.85, 0.75, 0.2), "bottle_plastic": Color(0.6, 0.3, 0.2), "bottle_glass": Color(0.3, 0.6, 0.35),
	"trash": Color(0.55, 0.55, 0.55), "food": Color(0.9, 0.5, 0.5), "tent_pole": Color(0.2, 0.4, 0.8),
	"tent_peg": Color(0.3, 0.3, 0.6), "tent_canvas": Color(0.15, 0.3, 0.6), "clothing": Color(0.8, 0.4, 0.8),
	"paddle": Color(0.6, 0.4, 0.2), "life_vest": Color(1.0, 0.5, 0.0), "firewood": Color(0.4, 0.25, 0.1),
	# Still cold, still closed: the one category you are saving rather than clearing.
	"can_sealed": Color(0.95, 0.9, 0.75),
}


static func color_for(category: String) -> Color:
	return CATEGORY_COLOURS.get(category, Color.WHITE)


## How long the real thing is, in metres, along its longest axis — the size
## budget a model is fitted into and the size of the placeholder box.
##
## [member ItemDef.size] is *carry slots*, a gameplay number, and deriving
## metres from it made a paddle 34 cm long. Containers hit the same wall and
## answered it the same way (`ContainerDef.model_height`): what a thing measures
## in real life is something a person knows without opening the mesh.
const CATEGORY_LENGTHS := {
	"can": 0.13, "can_sealed": 0.13, "bottle_plastic": 0.26, "bottle_glass": 0.28,
	"trash": 0.22, "food": 0.2, "cookware": 0.26, "misc": 0.2, "clothing": 0.32,
	"tent_pole": 0.65, "tent_peg": 0.18, "tent_canvas": 0.8,
	"paddle": 1.4, "life_vest": 0.6, "sleeping_bag": 0.55, "firewood": 0.42,
}
## For a category nobody has measured yet: the old slot-derived guess.
static func fallback_length(def: ItemDef) -> float:
	return 0.18 + 0.08 * def.size


static func box_size(def: ItemDef) -> Vector3:
	var s: float = CATEGORY_LENGTHS.get(def.category, fallback_length(def))
	return Vector3(s, s * 0.8, s)


## The colour to hand the loader.
##
## A generated box wants the category colour — that is the only thing telling
## a can from a bottle. A model already looks like itself, so it keeps its own
## colours unless the item explicitly asks for a tint: tinting multiplies
## albedo, which on a textured model darkens as much as it colours.
static func visual_color(def: ItemDef) -> Color:
	return def.tint_color(color_for(def.category) if def.model.is_empty() else Color.WHITE)


## The in-hand visual: the item's model if it has one, otherwise the coloured
## box, with depth testing off so held things never clip into a wall.
static func make_held_visual(def: ItemDef) -> Node3D:
	var node := ItemVisual.build(def.model, box_size(def),
		visual_color(def), def.model_scale, def.model_rotation)
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		# material_override takes precedence over per-surface overrides, so the
		# no-depth-test copy has to replace whichever one is actually in force.
		if mesh.material_override != null:
			mesh.material_override = _no_depth_copy(mesh.material_override)
		else:
			for surface in range(mesh.mesh.get_surface_count() if mesh.mesh != null else 0):
				mesh.set_surface_override_material(surface, _no_depth_copy(mesh.get_active_material(surface)))
	return node


static func _no_depth_copy(source: Material) -> StandardMaterial3D:
	var mat := source.duplicate() if source is StandardMaterial3D else StandardMaterial3D.new()
	mat.no_depth_test = true
	mat.render_priority = 10
	return mat
