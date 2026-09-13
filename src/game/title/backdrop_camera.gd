class_name BackdropCamera
extends Camera3D
## Slow orbit over the island behind the title screen.
##
## Built in code by [Main] when it shows the title, and freed when a game
## starts. Purely decorative: it never touches game state, and it keeps moving
## even when the tree is paused so the title never looks frozen.

@export var orbit_radius := 24.0
@export var height := 11.0
@export var degrees_per_second := 3.5
@export var look_at_height := 1.0

var _angle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fov = 60.0
	current = true
	_place()


func _process(delta: float) -> void:
	_angle = fmod(_angle + deg_to_rad(degrees_per_second) * delta, TAU)
	_place()


func _place() -> void:
	global_position = Vector3(cos(_angle) * orbit_radius, height, sin(_angle) * orbit_radius)
	look_at(Vector3(0, look_at_height, 0), Vector3.UP)
