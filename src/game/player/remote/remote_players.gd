class_name RemotePlayers
extends Node
## The other people on the island: one [RemoteAvatar] per peer, created when
## they first move and taken away when they leave (WP-4.5).
##
## [b]Created on first transform, not on join.[/b] A peer that has joined the
## room is not yet standing anywhere — the join arrives before their first
## presence frame, and an avatar built at that moment would appear at the origin
## and then slide across the island to wherever they actually are. So the roster
## is [Transport]'s business and this is only about who is visible.
##
## [b]Removed on leave, by freeing.[/b] Not `queue_free`: an avatar subscribes to
## [signal GameEvents.core_event], and a queued node is still subscribed. That is
## the wave-1 lesson and it is why this node exists at all rather than avatars
## managing themselves.

## Where the avatars are parented. The island, not the player: an avatar is part
## of the world, and hanging one off a first-person camera would take it along
## when the local player turns their head.
var world: Node3D

var _avatars: Dictionary = {} # peer_id -> RemoteAvatar


static func install(parent: Node, p_world: Node3D) -> RemotePlayers:
	var remote := RemotePlayers.new()
	remote.name = "RemotePlayers"
	remote.world = p_world
	parent.add_child(remote)
	return remote


func _ready() -> void:
	var transport := GameSession.transport
	if transport == null:
		return
	transport.presence_received.connect(_on_presence)
	transport.peer_left.connect(remove_peer)


func _exit_tree() -> void:
	var transport := GameSession.transport
	if transport != null:
		if transport.presence_received.is_connected(_on_presence):
			transport.presence_received.disconnect(_on_presence)
		if transport.peer_left.is_connected(remove_peer):
			transport.peer_left.disconnect(remove_peer)
	for peer_id: int in _avatars.keys():
		remove_peer(peer_id)


## Who is currently drawn. The test reads this; so does anything later that
## wants to point at somebody (WP-4.7's "who did what" toasts).
func visible_peers() -> Array[int]:
	var ids: Array[int] = []
	for peer_id: int in _avatars:
		ids.append(peer_id)
	ids.sort()
	return ids


func avatar_for(peer_id: int) -> RemoteAvatar:
	return _avatars.get(peer_id)


func remove_peer(peer_id: int) -> void:
	var avatar: RemoteAvatar = _avatars.get(peer_id)
	if avatar == null:
		return
	_avatars.erase(peer_id)
	if is_instance_valid(avatar):
		if avatar.get_parent() != null:
			avatar.get_parent().remove_child(avatar)
		avatar.free()


func _on_presence(peer_id: int, raw: Dictionary) -> void:
	# Never us: the host's fan-out carries the whole room, our own row included
	# on the way back, and an avatar standing inside the local camera is a grey
	# wall for whoever is unlucky enough to be peer 1.
	if peer_id <= 0 or peer_id == GameSession.local_player_id():
		return
	var presence := Presence.from_wire(raw)
	if presence.is_empty():
		return
	# The session keeps the latest so a leaver's armful falls where they were
	# standing rather than at the spawn point. This node is the only thing that
	# decodes a transform, so it is the only thing that can tell it.
	GameSession.remember_peer_position(peer_id, presence["position"])
	var avatar: RemoteAvatar = _avatars.get(peer_id)
	if avatar == null:
		if world == null:
			return
		avatar = RemoteAvatar.new(peer_id)
		_avatars[peer_id] = avatar
		world.add_child(avatar)
		avatar.place_at(presence)
		return
	avatar.apply_presence(presence)
