class_name GuardDogComponent
extends Node

@export var hearing_radius := 6.0

# Barking while hunting the player
@export var bark_sounds: Array[AudioStream] = [
	preload("res://Assets/Sounds/dog_bark/dog_bark_01.wav"),
	preload("res://Assets/Sounds/dog_bark/dog_bark_02.wav"),
	preload("res://Assets/Sounds/dog_bark/dog_bark_03.wav"),
]
@export var bark_interval_min := 1.0
@export var bark_interval_max := 2.5

var enemy: Enemy
var bark_player: AudioStreamPlayer3D
var bark_timer := 0.0


func _ready() -> void:
	enemy = get_parent() as Enemy
	bark_player = AudioStreamPlayer3D.new()
	bark_player.unit_size = 12.0  # The camera is ~14 m above the player, keep it audible
	# Attach to the dog itself so the bark comes from where the dog is
	get_parent().add_child.call_deferred(bark_player)


func _process(delta: float) -> void:
	if enemy == null or not enemy.chasing:
		bark_timer = 0.0  # Bark right away when the next hunt starts
		return

	bark_timer -= delta
	if bark_timer <= 0.0:
		bark_player.stream = bark_sounds.pick_random()
		bark_player.pitch_scale = randf_range(0.9, 1.1)
		bark_player.play()
		bark_timer = randf_range(bark_interval_min, bark_interval_max)


# radius_scale shrinks the hearing radius (e.g. while distracted by a coin)
func check_hearing(player: Player, distance: float, radius_scale := 1.0) -> bool:
	if distance < hearing_radius * radius_scale:
		var player_is_moving: bool = player.velocity.length() > 0.1
		var player_is_crouching: bool = ("is_crouching" in player and player.is_crouching)
		
		# Detects a moving player within hearing radius unless they are crouching
		if player_is_moving and not player_is_crouching:
			return true
	return false
