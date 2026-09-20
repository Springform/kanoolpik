class_name RemoteAvatar
extends Node3D
## One other person on the island (WP-4.5).
##
## [b]Not the player scene.[/b] [Player] is a [CharacterBody3D] that simulates
## itself from input, and a remote player is the opposite of that: their
## position is a fact that arrives on the wire, and re-simulating it here would
## mean two answers to where somebody is standing. So this is a body, a name and
## an armful — no physics, no camera, no ray.
##
## [b]Built in code, not in a `.tscn`.[/b] Two reasons, both learned the hard
## way (see `CLAUDE.md`): a `Shape3D` or mesh declared in a scene is a
## sub-resource shared by every instance of it, and six avatars sharing one
## capsule is the 150-items bug again; and a `.tscn` is the one file two agents
## cannot merge.
##
## What it is carrying is [b]not[/b] sent. `pick_up` is a command, so every peer
## has already applied it — the armful is read out of [WorldState], which costs
## nothing and cannot disagree with the world.

## Stand-in until somebody models a boy in a life vest. A capsule of a person's
## size reads as a person at the distances people stand at, which is all this
## has to do until then.
##
## [b]The same numbers as the local player's capsule[/b] (`player.tscn`), and
## drawn the same way round: [Player] is a [CharacterBody3D] whose collision
## capsule is [i]centred[/i] on the node origin, so the position that travels is
## a chest, not a pair of feet. Standing the capsule on top of it instead — the
## obvious way to build it — put every remote player a metre in the air. The
## screenshot pass caught it; nothing in a test would have.
const BODY_HEIGHT := 1.8
const BODY_RADIUS := 0.35
## Clear of the top of the head, which is [constant BODY_HEIGHT] / 2 up.
const TAG_HEIGHT := 1.15

## Sized to read from the far side of the island, which is about 30 m — the
## whole distance range this has to work over. Verified by looking at it
## (`tools/shots.gd --only=remote`), not by asserting on a number, because
## "legible" is not a property a test can check.
##
## [b]There is no [code]visibility_range_end[/code] here on purpose.[/b] Under
## GL Compatibility [Label3D] ignores it: the property sets without complaint
## and changes nothing (see `CLAUDE.md`). Culling by distance would have to be
## done by hand, and on an island this small there is no distance worth culling.
## Drawn at a constant size on screen ([member Label3D.fixed_size]) rather than
## shrinking with distance. The first attempt scaled like the item labels do and
## the screenshot settled it: at eight metres "Spiller 4" was a smudge, and
## eight metres is not far — it is the other side of a tent. A name tag exists
## to answer "who is that over there", so it has to stay readable at exactly the
## distance where you cannot tell who it is.
const TAG_FONT_SIZE := 64
const TAG_PIXEL_SIZE := 0.0006

## The armful, drawn as one small block per item held in front of the chest. Not
## the real models: six avatars each rendering a paddle is a lot of triangles to
## say something a block says, and at this distance nobody can tell them apart
## anyway. The count is what people read.
const CARRY_BLOCK := 0.16

## How far in front of the body axis the blocks sit.
##
## [b]This is the same mistake as the floating capsule, from the other end.[/b]
## The first version stacked the armful straight up the node origin at y 0.55 —
## and the capsule is [i]centred[/i] on that origin with radius
## [constant BODY_RADIUS], so the blocks were inside the body. The stack only
## cleared the top of the shoulder at the third block, which is exactly what a
## playtest reported: "things are inside the player, and you cannot see an
## armful until it is more than three items". A feature that works only for a
## big armful does not work.
##
## So the offset is an arithmetic rather than a number somebody liked the look
## of: a block's centre has to be a body radius plus half a block away from the
## axis before any of it is outside, and the last term is the gap that keeps it
## from z-fighting the capsule's silhouette.
const CARRY_CLEARANCE := BODY_RADIUS + CARRY_BLOCK * 0.5 + 0.06

## Just below the body centre, so a full armful still ends well under the name
## tag. The x and z of this are zero on purpose: the sides are where the blocks
## go, and [method block_position] puts them there.
const CARRY_ORIGIN := Vector3(0.0, -0.10, 0.0)

## Metres per second the avatar closes the gap to the last position it was told
## about. Transforms arrive [constant PresenceSender.RATE_HZ] times a second and
## the gaps between them are longer than a frame, so moving straight to each one
## makes a walking friend a slideshow. Interpolating makes it walking.
##
## [b]Deliberately not prediction.[/b] Nothing here extrapolates past the last
## known position: a guess that turns out wrong has to be taken back, and an
## avatar that slides backwards out of a wall reads worse than one that is a
## tenth of a second behind.
const CATCH_UP := 12.0
## Above this, snap instead of sliding. A respawn after a swim moves somebody
## twenty metres, and sliding that is a person skating across the lake.
const TELEPORT_DISTANCE := 3.0

var peer_id := 0

var _target := Vector3.ZERO
var _target_yaw := 0.0
var _body: MeshInstance3D
var _tag: Label3D
var _armful: Node3D


func _init(p_peer_id: int = 0) -> void:
	peer_id = p_peer_id
	name = "RemoteAvatar_%d" % peer_id


func _ready() -> void:
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = BODY_HEIGHT
	capsule.radius = BODY_RADIUS
	_body.mesh = capsule
	# Centred, not standing on the origin. See the note on BODY_HEIGHT.
	_body.position = Vector3.ZERO
	var material := StandardMaterial3D.new()
	material.albedo_color = colour_for(peer_id)
	_body.material_override = material
	add_child(_body)

	_tag = Label3D.new()
	_tag.text = tr("ui.remote.player") % peer_id
	_tag.position = Vector3(0.0, TAG_HEIGHT, 0.0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = TAG_FONT_SIZE
	_tag.pixel_size = TAG_PIXEL_SIZE
	_tag.fixed_size = true
	_tag.outline_size = 12
	_tag.modulate = colour_for(peer_id)
	# Through the island, so somebody behind a hill is still somewhere rather
	# than nowhere. A name tag is a wayfinding aid; hiding it when it is most
	# needed is the wrong way round.
	_tag.no_depth_test = true
	add_child(_tag)

	_armful = Node3D.new()
	_armful.name = "Armful"
	add_child(_armful)
	# The firehose rather than the four convenience signals: picking up,
	# dropping, placing and taking out all change an armful, they have four
	# different signatures, and one connection cannot get out of step with
	# itself. Disconnected in _exit_tree — a node that outlives its avatar and
	# keeps answering GameEvents is the wave-1 lesson, and this one would rebuild
	# the arms of somebody who has gone home.
	GameEvents.core_event.connect(_on_core_event)
	_refresh_armful()

	_target = position
	_target_yaw = rotation.y


func _exit_tree() -> void:
	if GameEvents.core_event.is_connected(_on_core_event):
		GameEvents.core_event.disconnect(_on_core_event)


func _process(delta: float) -> void:
	if position.distance_to(_target) > TELEPORT_DISTANCE:
		position = _target
	else:
		position = position.move_toward(_target, CATCH_UP * delta)
	rotation.y = rotate_toward(rotation.y, _target_yaw, CATCH_UP * delta)


## A frame arrived. Decoded by [Presence]; an unreadable one leaves the avatar
## where it was, which looks like a dropped packet because that is what it is.
func apply_presence(presence: Dictionary) -> void:
	if presence.is_empty():
		return
	_target = presence["position"]
	_target_yaw = float(presence["yaw"])


## Put the avatar exactly there, with no catching up. Used when it is first
## created: sliding in from the origin would send a new arrival walking across
## the lake in front of everybody.
func place_at(presence: Dictionary) -> void:
	apply_presence(presence)
	position = _target
	rotation.y = _target_yaw


func _on_core_event(event: Dictionary) -> void:
	if int(event.get("player_id", 0)) == peer_id:
		_refresh_armful()


## What this player is holding, straight out of the world every peer shares.
func carried() -> Array[String]:
	if GameSession.state == null:
		return []
	return GameSession.state.carried_by(peer_id)


## One block per carried item, stacked. Rebuilt rather than diffed: an armful is
## at most a handful of blocks and this happens when somebody picks something
## up, not every frame.
func _refresh_armful() -> void:
	if _armful == null:
		return
	for block: Node in _armful.get_children():
		_armful.remove_child(block)
		block.free()
	var held := carried()
	for i in held.size():
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		# Per instance, not a shared sub-resource: 150 items all writing to one
		# BoxShape3D is how this was learned the first time.
		box.size = Vector3.ONE * CARRY_BLOCK
		block.mesh = box
		var material := StandardMaterial3D.new()
		var def := GameSession.catalog.get_item(held[i]) if GameSession.catalog != null else null
		material.albedo_color = ItemPalette.color_for(def.category) if def != null else Color.WHITE
		block.material_override = material
		block.position = block_position(i)
		_armful.add_child(block)


## Where the [param index]th block of an armful sits, in the avatar's own space.
##
## Static and pure so the one thing that went wrong here — a block ending up
## inside the body — can be checked by arithmetic instead of by a screenshot.
##
## [b]Blocks alternate left and right, and stack in pairs.[/b] A single offset
## in one direction only solves half the problem: an armful held in front is
## hidden by the body from behind, and one held on the left is hidden from the
## right. Hugged against both sides it is outside the silhouette from in front
## and from behind, and from the side the near column is. Stacking in pairs also
## keeps a full armful — capacity is by size, so eight small things is legal —
## from becoming a 1.4 m mast through the name tag.
static func block_position(index: int) -> Vector3:
	var step := CARRY_BLOCK * 1.15
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := index / 2
	return CARRY_ORIGIN + Vector3(side * CARRY_CLEARANCE, step * float(row), 0.0)


## True when a block at [param index] is clear of the body capsule — the rule
## the playtest found broken. Horizontal distance only: the capsule is a
## vertical cylinder over the height an armful occupies, so height does not
## enter into it.
static func block_is_outside_body(index: int) -> bool:
	var at := block_position(index)
	return Vector2(at.x, at.z).length() >= BODY_RADIUS + CARRY_BLOCK * 0.5


## A stable colour per peer, so "the green one keeps putting bottles in the
## kitchen box" is a thing six people can say to each other. Peer ids are 1-6
## and handed out by the relay, so the spread is fixed rather than random.
static func colour_for(id: int) -> Color:
	# Saturated, because the island is already full of pastel placeholder boxes
	# and a washed-out capsule among them is scenery. A person has to read as a
	# person from across the camp.
	return Color.from_hsv(fposmod(float(id) * 0.16, 1.0), 0.8, 0.9)
