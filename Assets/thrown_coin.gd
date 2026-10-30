extends Node3D
## A coin thrown by the player: flies in an arc, lands, and lures nearby enemies to where it landed.

@export var arc_height := 2.0
@export var spin_speed := 20.0
# Placeholder until there is a proper coin sound
@export var land_sound: AudioStream = preload("res://Assets/Sounds/drop_item.wav")
@export var land_volume_db := 6.0

var sound_player: AudioStreamPlayer3D


func _ready() -> void:
	sound_player = AudioStreamPlayer3D.new()
	sound_player.stream = land_sound
	sound_player.volume_db = land_volume_db
	sound_player.unit_size = 12.0  # The camera is ~14 m above the player, keep it audible
	add_child(sound_player)


func throw_to(target: Vector3, flight_time: float, distract_radius: float) -> void:
	var start := global_position
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		# Straight line plus a parabola on top
		global_position = start.lerp(target, t) + Vector3.UP * arc_height * 4.0 * t * (1.0 - t)
		rotation.x = t * flight_time * spin_speed
	, 0.0, 1.0, flight_time)
	tween.tween_callback(_land.bind(distract_radius))


func _land(distract_radius: float) -> void:
	rotation = Vector3(0, randf() * TAU, 0)
	sound_player.play()
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if global_position.distance_to(enemy.global_position) <= distract_radius and enemy.has_method("distract"):
			enemy.distract(global_position)
