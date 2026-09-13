extends Node
## Global event bus (autoload "GameEvents").
##
## The presentation layer subscribes here instead of reaching into other
## scenes. [GameSession] re-emits every core event it applies, so audio, HUD,
## VFX and networking can each live in their own folder and never import each
## other. Keep signals coarse and data-only (ids, not Nodes).

## A core event Dictionary as produced by [CommandProcessor] (see its docs for shapes).
signal core_event(event: Dictionary)

## Convenience fan-out of the most used core events.
signal item_picked_up(item_id: String, player_id: int)
signal item_dropped(item_id: String, player_id: int, position: Vector3)
signal item_placed(item_id: String, player_id: int, container_id: String, slot: int, verdict: int)
signal item_taken_out(item_id: String, player_id: int, container_id: String)
signal container_completed(container_id: String)
signal island_clean()

## Presentation-only signals.
signal level_loaded(level_id: String)
signal local_player_spawned(player: Node3D)
signal command_rejected(command: Dictionary, error: String)
signal progress_changed(progress: Dictionary)


func publish(event: Dictionary) -> void:
	core_event.emit(event)
	match String(event.get("type", "")):
		"item_picked_up":
			item_picked_up.emit(event["item_id"], event["player_id"])
		"item_dropped":
			item_dropped.emit(event["item_id"], event["player_id"], event["position"])
		"item_placed":
			item_placed.emit(event["item_id"], event["player_id"], event["container_id"], event["slot"], event["verdict"])
		"item_taken_out":
			item_taken_out.emit(event["item_id"], event["player_id"], event["container_id"])
		"container_completed":
			container_completed.emit(event["container_id"])
		"island_clean":
			island_clean.emit()
