class_name LocalTransport
extends Transport
## Single-player transport: applies commands synchronously to the local state.

var _processor: CommandProcessor
var _state: WorldState


func _init(processor: CommandProcessor, state: WorldState) -> void:
	_processor = processor
	_state = state


func submit_command(command: Dictionary) -> void:
	var result := _processor.apply(_state, command)
	if result["ok"]:
		command_applied.emit(command, result)
	else:
		command_rejected.emit(command, result["error"])


func tick(_delta: float) -> void:
	_processor.apply(_state, Commands.tick(1))
