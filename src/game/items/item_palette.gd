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


static func make_mesh(def: ItemDef, no_depth_test: bool = false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size(def)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for(def.category)
	if no_depth_test:
		mat.no_depth_test = true
		mat.render_priority = 10
	m.material_override = mat
	return m
