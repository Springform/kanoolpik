class_name SimNetwork
extends RefCounted
## N peers, one authority, one process, no sockets (WP-4.3).
##
## [b]Why this exists.[/b] The core has been built for a year on one promise:
## the same command list produces the same [WorldState] everywhere (ADR 0003,
## ADR 0010). Until now nothing has checked that across *peers* — only that two
## states in the same process agree. This is the thing that can falsify the
## promise, and it does so before a single byte goes over a wire.
##
## [b]How a command travels.[/b] The authority is asked, decides, and tells
## everyone to apply it:
## [codeblock]
##   client.submit_command(cmd)  →  authority validates against ITS state
##                               →  accepted: every peer applies cmd itself
##                               →  refused:  only the sender hears about it
## [/codeblock]
##
## The authority broadcasts the [b]command[/b], not the resulting events. That is
## a deliberate departure from the sketch in [Transport]'s docstring, and the
## reason is worth keeping: applying events on a client needs a second piece of
## code that knows the rules, and two implementations of one rule set is exactly
## how desyncs are born. Broadcasting the command means every peer runs the same
## [CommandProcessor] over the same state, and the authority only ever decides
## [i]whether[/i] and [i]in what order[/i].
##
## The risk that trade makes is that a client whose state has already drifted
## applies the command and drifts further, quietly. So the authority stamps each
## broadcast with its own state hash, and a peer that lands on a different number
## knows immediately. A desync becomes an event with a timestamp instead of a
## rumour about "something weird last Friday".
##
## [b]Usage[/b]
## [codeblock]
##   var net := SimNetwork.new(6, catalog, func(): return make_a_world())
##   net.submit(3, Commands.pick_up(3, "can_tuborg_1"))
##   net.flush()
##   assert(net.states_agree(), net.divergence())
## [/codeblock]

const AUTHORITY_ID := 1
const E_DISCONNECTED := "peer_disconnected"
const E_NOT_AUTHORITY := "not_authority"

## Peers, by id. Peer [constant AUTHORITY_ID] is the authority.
var peers: Dictionary = {}
## Ticks of one-way delay applied to everything. 0 delivers on the next flush.
var latency_ticks := 0
## Delivery is FIFO per link by default. Set > 1 to let the queue shuffle within
## that window, which is how you find out whether ordering was load-bearing.
var reorder_window := 1

var _catalog: Catalog
## Queued as { at_tick, seq, to, payload }. `seq` keeps the sort stable so a
## reordering run is reproducible rather than merely random.
var _in_flight: Array[Dictionary] = []
var _tick := 0
var _seq := 0
var _drop_next := 0
var _rng := RandomNumberGenerator.new()
## Every command the authority accepted, in order. The log a late joiner could
## be replayed from, and a useful thing to print when a test fails.
var _accepted_log: Array[Dictionary] = []


## [param make_state] must return a fresh [WorldState] identical for every peer —
## in the real game that is [MessGenerator] run from the shared seed, which is
## why nobody ships item positions at level start.
func _init(peer_count: int, catalog: Catalog, make_state: Callable, rng_seed := 12345) -> void:
	_catalog = catalog
	_rng.seed = rng_seed
	for id in range(AUTHORITY_ID, AUTHORITY_ID + peer_count):
		var state: WorldState = make_state.call()
		for other in range(AUTHORITY_ID, AUTHORITY_ID + peer_count):
			if not state.has_player(other):
				state.add_player(other, Progression.BASE_CAPACITY)
		var processor := CommandProcessor.new(catalog)
		processor.allow_debug_commands = true # tests drive points directly
		peers[id] = SimTransport.new(self, id, state, processor)


func peer(id: int) -> SimTransport:
	return peers.get(id)


func peer_ids() -> Array[int]:
	var out: Array[int] = []
	for k in peers.keys():
		out.append(int(k))
	out.sort()
	return out


func authority() -> SimTransport:
	return peers[AUTHORITY_ID]


# --- Driving it ----------------------------------------------------------------

## Convenience: submit as [param from_peer] without reaching into the transport.
func submit(from_peer: int, command: Dictionary) -> void:
	peer(from_peer).submit_command(command)


## A client's command arriving at the authority — after the wire, so it is queued
## like anything else.
func send_to_authority(from_peer: int, command: Dictionary) -> void:
	_queue({"kind": "request", "from": from_peer, "command": command}, AUTHORITY_ID)


## Advance the simulated clock by [param ticks] and deliver whatever is due.
func deliver(ticks := 1) -> void:
	for i in range(ticks):
		_tick += 1
		_deliver_due()


## Run until nothing is in flight. Latency still costs ticks; this just does not
## make the caller count them.
func flush(max_ticks := 1000) -> void:
	var spins := 0
	while not _in_flight.is_empty() and spins < max_ticks:
		deliver(1)
		spins += 1


## Drop the next [param count] messages that would be delivered — requests and
## broadcasts alike, whichever comes next. A request delivered in the same tick
## is queued ahead of the broadcasts it causes, so to lose a *broadcast* you
## deliver one tick first and then drop. Dropping the request instead means the
## command simply never happened, which every peer agrees about.
func drop_next(count: int) -> void:
	_drop_next += count


func disconnect_peer(id: int) -> void:
	peer(id).connected = false
	# Anything already on the wire for them is gone with them.
	var kept: Array[Dictionary] = []
	for message in _in_flight:
		if int(message["to"]) != id:
			kept.append(message)
	_in_flight = kept


## Reconnect and resynchronise from the authority's snapshot — the same
## [method WorldState.to_dict] a save writes and a late joiner receives, which is
## why ADR 0010 put progression inside the state.
func reconnect_peer(id: int) -> void:
	peer(id).connected = true
	peer(id).replace_state(authority().state.to_dict())


# --- Agreement -----------------------------------------------------------------

func states_agree() -> bool:
	return divergence().is_empty()


## "" when every connected peer matches the authority, otherwise the first
## concrete difference found. Naming the key matters: a test that fails with
## "states diverged" and nothing else costs the next person an evening.
func divergence() -> String:
	var truth := authority().state.to_dict()
	for id in peer_ids():
		if id == AUTHORITY_ID or not peer(id).connected:
			continue
		var theirs := peer(id).state.to_dict()
		var where := _first_difference(truth, theirs, "")
		if not where.is_empty():
			return "peer %d differs from the authority at %s" % [id, where]
	return ""


## The authority's fingerprint, for an at-a-glance comparison.
static func hash_state(state: WorldState) -> int:
	return JSON.stringify(state.to_dict()).hash()


## Every command the authority accepted, oldest first.
func accepted_log() -> Array[Dictionary]:
	return _accepted_log.duplicate()


# --- Internals -----------------------------------------------------------------

func _queue(payload: Dictionary, to: int) -> void:
	if not peer(to).connected:
		return
	_seq += 1
	_in_flight.append({
		"at_tick": _tick + latency_ticks, "seq": _seq, "to": to, "payload": payload,
	})


func _deliver_due() -> void:
	var due: Array[Dictionary] = []
	var later: Array[Dictionary] = []
	for message in _in_flight:
		if int(message["at_tick"]) <= _tick:
			due.append(message)
		else:
			later.append(message)
	_in_flight = later
	if due.is_empty():
		return
	due.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	if reorder_window > 1:
		due = _shuffle_within_window(due)
	for message in due:
		if _drop_next > 0:
			_drop_next -= 1
			continue
		_receive(int(message["to"]), message["payload"])


## Reorder [b]per destination[/b], which is the only kind of reordering that
## means anything: a link either delivers in order or it does not, and swapping
## two messages headed for different peers changes nothing about what either of
## them sees.
##
## The first version of this shuffled the whole due-list in windows of N. With
## five peers receiving a broadcast each, a window of four almost never held two
## messages for the same peer — so the reordering test passed without ever
## reordering anything one peer could notice. A test that cannot fail.
func _shuffle_within_window(messages: Array[Dictionary]) -> Array[Dictionary]:
	var by_peer: Dictionary = {}
	var order: Array[int] = []
	for message in messages:
		var to := int(message["to"])
		if not by_peer.has(to):
			by_peer[to] = []
			order.append(to)
		(by_peer[to] as Array).append(message)
	for to in order:
		var queue: Array = by_peer[to]
		var shuffled: Array = []
		var i := 0
		while i < queue.size():
			var window: Array = queue.slice(i, mini(i + reorder_window, queue.size()))
			while not window.is_empty():
				shuffled.append(window.pop_at(_rng.randi_range(0, window.size() - 1)))
			i += reorder_window
		by_peer[to] = shuffled
	# Rebuild one list, keeping each peer's (now shuffled) queue intact.
	var out: Array[Dictionary] = []
	for to in order:
		for message in by_peer[to]:
			out.append(message)
	return out


func _receive(to: int, payload: Dictionary) -> void:
	var target := peer(to)
	if target == null or not target.connected:
		return
	match String(payload.get("kind", "")):
		"request":
			_authority_decides(int(payload["from"]), payload["command"])
		"apply":
			var result := target.apply_accepted(payload["command"])
			# The authority's fingerprint travels with the command. A peer that
			# lands somewhere else has diverged, and says so now rather than
			# letting the difference compound in silence.
			if result["ok"] and target.state_hash() != int(payload["hash"]):
				push_error("peer %d diverged applying %s" % [to, payload["command"].get("type", "?")])
		"reject":
			target.reject(payload["command"], String(payload["error"]))
		"snapshot":
			target.replace_state(payload["state"])


## The only place a command is judged. Everyone else obeys.
func _authority_decides(from_peer: int, command: Dictionary) -> void:
	var host := authority()
	var result := host.processor.apply(host.state, command)
	if not result["ok"]:
		_queue({"kind": "reject", "command": command, "error": result["error"]}, from_peer)
		return
	_accepted_log.append(command)
	host.command_applied.emit(command, result)
	var stamp := hash_state(host.state)
	for id in peer_ids():
		if id != AUTHORITY_ID:
			_queue({"kind": "apply", "command": command, "hash": stamp}, id)


## Walks two snapshots and names the first place they differ.
func _first_difference(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s (types differ: %s vs %s)" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		var keys := (a as Dictionary).keys()
		keys.sort()
		for key in keys:
			if not (b as Dictionary).has(key):
				return "%s/%s (missing on the other side)" % [path, key]
			var deeper := _first_difference(a[key], b[key], "%s/%s" % [path, key])
			if not deeper.is_empty():
				return deeper
		for key in (b as Dictionary).keys():
			if not (a as Dictionary).has(key):
				return "%s/%s (only on the other side)" % [path, key]
		return ""
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return "%s (%d vs %d entries)" % [path, (a as Array).size(), (b as Array).size()]
		for i in range((a as Array).size()):
			var deeper := _first_difference(a[i], b[i], "%s[%d]" % [path, i])
			if not deeper.is_empty():
				return deeper
		return ""
	return "" if a == b else "%s (%s vs %s)" % [path, str(a), str(b)]
