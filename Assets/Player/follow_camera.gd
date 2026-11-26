extends Camera3D
## The player's camera: follows smoothly instead of being glued to the player and shakes when the
## player gets caught. Sits as a child of the player in the scene
## (where you set its height and angle) and moves on its own while the game runs.

@export var follow_speed := 6.0     # higher = follows more tightly
@export var snap_distance := 8.0    # the player teleported (respawn): jump there instead of gliding
@export var death_shake := 0.35     # strength of the shake when caught
@export var death_shake_time := 0.45

var _target: Node3D
var _offset: Vector3
var _shake_time := 0.0
var _shake_strength := 0.0
var _shake_total := 0.0


func _ready() -> void:
	_target = get_parent() as Node3D
	_offset = position
	# Keeps running while paused: the shake happens while the game freezes on death
	process_mode = Node.PROCESS_MODE_ALWAYS
	var start := global_transform
	top_level = true
	global_transform = start
	GameManager.player_died.connect(func() -> void: shake(death_shake, death_shake_time))


func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = duration
	_shake_total = duration


func _physics_process(delta: float) -> void:
	if is_instance_valid(_target) and not get_tree().paused:
		var goal := _target.global_position + _offset
		if global_position.distance_to(goal) > snap_distance:
			global_position = goal
		else:
			global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))

	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var s := _shake_strength * (_shake_time / _shake_total)
		h_offset = randf_range(-s, s)
		v_offset = randf_range(-s, s)
	elif h_offset != 0.0 or v_offset != 0.0:
		h_offset = 0.0
		v_offset = 0.0
