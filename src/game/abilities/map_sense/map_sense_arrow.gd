class_name MapSenseArrow
extends Control
## The Stedsans arrow (WP-3.3): one small triangle on a ring around the crosshair,
## turned toward the container the held item belongs in.
##
## It is drawn, not glyphed, on purpose. Godot's default font has no Geometric
## Shapes block, so a "▲" renders as nothing at all while every string assertion
## still passes (CLAUDE.md). [method _draw] owes the font nothing.
##
## The node knows only "which way, and how strongly" — [method aim] takes a unit
## vector in screen space and an alpha. Where the container *is* is
## [MapSenseAbility]'s problem; this is only the part you can see.
##
## Lives in [method HUD.ability_layer], the extension point the HUD exposes so no
## ability has to edit the HUD or its scene.

## Side of the (square) control, in pixels. Big enough to read at the edge of
## vision, small enough not to be the thing you look at.
const ARROW_SIZE := Vector2(34, 34)
## Ring radius as a fraction of the shorter screen side. Out at the edge of
## vision, where WP-3.3 wants it and where it is not competing with the
## crosshair — but short of the actual screen edge, so the whole triangle stays
## on screen in a window of any shape.
const RING_FRACTION := 0.40
## Warm gold, the HUD's "this is yours" colour family (see [InsightHighlight]).
const ARROW_COLOR := Color(1.0, 0.82, 0.25, 0.9)
## A thin dark outline so the arrow survives being drawn over sand or sky.
const OUTLINE_COLOR := Color(0.1, 0.09, 0.07, 0.75)
const OUTLINE_WIDTH := 2.0

## Unit vector, screen space (x right, y down), as last handed to [method aim].
var direction := Vector2.RIGHT

## Screen size to use when this node is not inside a sized parent — headless
## viewports and tests, where `get_parent_area_size()` can be zero.
var fallback_area := Vector2(1152, 648)


## An arrow ready to be added to [method HUD.ability_layer].
static func create() -> MapSenseArrow:
	var node := MapSenseArrow.new()
	node.name = "MapSenseArrow"
	return node


func _ready() -> void:
	# The HUD's ability layer ignores the mouse; so does anything hung on it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = ARROW_SIZE
	size = ARROW_SIZE
	pivot_offset = ARROW_SIZE * 0.5
	visible = false


func _draw() -> void:
	# Drawn pointing +X (screen right) at rotation 0, so `rotation` is simply the
	# angle of the direction vector and the test can state one number.
	var half := ARROW_SIZE * 0.5
	var points := PackedVector2Array([
		Vector2(half.x, half.y),                    # tip, to the right
		Vector2(-half.x * 0.6, -half.y * 0.75),     # back top
		Vector2(-half.x * 0.15, half.y * 0.0),      # tail notch
		Vector2(-half.x * 0.6, half.y * 0.75),      # back bottom
	])
	for i in range(points.size()):
		points[i] = points[i] + half
	draw_colored_polygon(points, ARROW_COLOR)
	draw_polyline(points + PackedVector2Array([points[0]]), OUTLINE_COLOR, OUTLINE_WIDTH)


# --- Public ----------------------------------------------------------------------

## Point at [param unit_direction] (screen space, x right, y down) with opacity
## [param alpha]. An alpha of 0 hides the node outright rather than drawing a
## fully transparent triangle every frame.
func aim(unit_direction: Vector2, alpha: float) -> void:
	direction = unit_direction if unit_direction.length() > 0.0001 else Vector2.RIGHT
	direction = direction.normalized()
	var area := screen_area()
	var radius: float = minf(area.x, area.y) * RING_FRACTION
	rotation = direction.angle()
	position = area * 0.5 + direction * radius - ARROW_SIZE * 0.5
	modulate.a = clampf(alpha, 0.0, 1.0)
	visible = modulate.a > 0.0


## Take the arrow off the screen without destroying it — the ability is on, but
## there is nothing to point at right now.
func stand_down() -> void:
	visible = false
	modulate.a = 0.0


## True when the player can actually see it.
func is_showing() -> bool:
	return visible and modulate.a > 0.0


## Where the centre of the arrow sits on screen. The node's own `position` is its
## top-left corner, and every assertion about aim is about the centre.
func centre() -> Vector2:
	return position + ARROW_SIZE * 0.5


## The rectangle the ring is drawn inside. Falls back to [member fallback_area]
## when the parent has no size yet: a zero-sized ring would stack every arrow in
## the top-left corner, which no test would notice and every player would.
func screen_area() -> Vector2:
	var area := get_parent_area_size()
	if area.x < 1.0 or area.y < 1.0:
		area = get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	if area.x < 1.0 or area.y < 1.0:
		area = fallback_area
	return area
