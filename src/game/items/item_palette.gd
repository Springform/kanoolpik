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
}


static func color_for(category: String) -> Color:
	return CATEGORY_COLOURS.get(category, Color.WHITE)


static func box_size(def: ItemDef) -> Vector3:
	var s := 0.18 + 0.08 * def.size
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
