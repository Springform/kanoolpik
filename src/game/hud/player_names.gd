class_name PlayerNames
extends RefCounted
## Who to call the other people in the room, and when to mention them at all
## (WP-4.7).
##
## [b]The rule that shapes everything here: single player must read exactly as
## it did before.[/b] A game nobody else is in has no "Spiller 1" in it — the
## toast that used to say "Flaskekassen er pakket" still says that. Naming the
## actor is for the case where there is an actor other than you.
##
## Names are peer ids for now. When somebody types a name in the lobby, this is
## the one place that changes.

## Is there anybody else here?
##
## [b]Not "are we in a room".[/b] A host alone in a lobby is in a room, and
## telling them "Spiller 1 pakkede flaskekassen" about themselves would be
## worse than saying nothing. The question the HUD actually has is whether
## there is somebody whose name is worth printing.
static func others_present() -> bool:
	var transport := GameSession.transport
	return transport != null and transport.known_peers().size() > 1


## What to call [param player_id] out loud. Empty when there is nobody else
## here, so callers can use it as the test as well as the answer.
static func of(player_id: int) -> String:
	if not others_present() or player_id <= 0:
		return ""
	return label(player_id)


## What [param player_id] is called, unconditionally.
##
## The arrival and departure toasts need this: somebody leaving a room of two
## makes [method others_present] false in the same breath, and "kom til" with a
## blank where the name goes is worse than not saying it at all.
static func label(player_id: int) -> String:
	# TranslationServer rather than tr(): this is a RefCounted, and tr() is a
	# Node method. Same lookup, no node needed.
	return TranslationServer.translate("ui.remote.player") % player_id


static func is_me(player_id: int) -> bool:
	return player_id == GameSession.local_player_id()


## How many are in the canoe, us included. 1 when there is no room.
static func party_size() -> int:
	var transport := GameSession.transport
	return transport.known_peers().size() if transport != null else 1
