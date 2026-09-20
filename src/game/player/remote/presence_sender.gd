class_name PresenceSender
extends Node
## Tells the room where the local player is standing (WP-4.5).
##
## [b]This node owns the number that decides whether multiplayer stays free.[/b]
## ADR 0011 does the arithmetic and WP-4.5 hands it here: transforms are the
## only traffic that matters, everything else is a handful of commands a minute.
## Read [constant RATE_HZ] before changing it.

## Transform sends per second.
##
## [b]The sum, from ADR 0011.[/b] Cloudflare's free plan allows 100,000
## requests a day and bills incoming WebSocket messages at 20:1 (outgoing are
## free). Six players at 20 Hz is 120 incoming messages a second — 432,000 an
## hour, 21,600 billable — which is about [b]4.6 hours[/b] of six-player play a
## day. At 10 Hz it is about nine, and that is before the two savings below.
##
## Ten is chosen rather than twenty because [RemoteAvatar] interpolates: the gap
## between frames is hidden by walking towards the last known position, so the
## second ten cost half the daily budget and buy a smoothness nobody can see.
## Two boys on a lake have an evening either way; six for a whole Sunday only
## fits at this number.
##
## The two savings that make it comfortable rather than tight:
## [br]1. Nothing is sent while nobody moves ([method Presence.differs]).
## [br]2. The host merges the room into one fan-out rather than forwarding five
##    frames, so a tick costs six incoming messages and not eleven — see
##    [method WebSocketTransport.send_presence].
const RATE_HZ := 10.0

## The player we are reporting. Set by whoever installs this; when it is null
## (the title screen, the lobby, a torn-down level) there is nothing to report
## and nothing is sent.
var player: Player

var _since_last := 0.0
## The last transform actually put on the wire, to compare the next one against.
## Against what was SENT, not against last frame: comparing frame to frame lets
## a slow drift accumulate below the threshold forever and never report.
var _last_sent: Dictionary = {}


static func install(parent: Node, p_player: Player) -> PresenceSender:
	var sender := PresenceSender.new()
	sender.name = "PresenceSender"
	sender.player = p_player
	parent.add_child(sender)
	return sender


func _process(delta: float) -> void:
	_since_last += delta
	if _since_last < 1.0 / RATE_HZ:
		return
	_since_last = 0.0
	send_now()


## One rate tick's worth of reporting. Public so a test can drive the decision
## without waiting a tenth of a second per assertion.
##
## An unchanged transform still calls through to the transport with an empty
## dictionary rather than returning early. That is not a wasted call: on the
## host it is the tick on which everybody else's transforms go out, and a host
## standing still while five people walk around must not stop forwarding them.
func send_now() -> void:
	var transport := GameSession.transport
	if transport == null:
		return
	if not is_instance_valid(player):
		transport.send_presence({})
		return
	var position := player.global_position
	var yaw := player.rotation.y
	if not Presence.differs(position, yaw, _last_sent):
		transport.send_presence({})
		return
	transport.send_presence(Presence.to_wire(position, yaw))
	_last_sent = {"position": position, "yaw": yaw}
