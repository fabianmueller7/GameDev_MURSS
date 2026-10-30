class_name MusicManagerClass
extends Node
## Dynamic music with three synchronized versions of the same track:
##   Exploration - subtle undertone while nobody is around
##   Tension     - fades in the closer the player gets to an enemy
##   Combat      - takes over while at least one enemy is chasing
## All three play at the same time and stay in sync; only their volumes change,
## so the music never restarts, it just gets more nervous at the same spot.

@export_group("Tracks")
@export var exploration_track: AudioStream = preload("res://Assets/Music/Reflections/Reflections_EXPLORATION_loop.ogg")
@export var tension_track: AudioStream = preload("res://Assets/Music/Reflections/Reflections_TENSION_loop.ogg")
@export var combat_track: AudioStream = preload("res://Assets/Music/Reflections/Reflections_COMBAT_loop.ogg")

@export_group("Mix")
@export var music_volume_db := -4.0
# Per-track offsets so the three versions sound equally loud (combat is mastered much louder)
@export var exploration_offset_db := 0.0
@export var tension_offset_db := 1.5
@export var combat_offset_db := -3.0

@export_group("Tension")
@export var tension_far := 14.0   # Enemy further away than this: no tension at all
@export var tension_near := 5.0   # Enemy this close or closer: full tension
@export var tension_rise_speed := 1.0  # How fast it gets nervous (per second)
@export var tension_fall_speed := 0.3  # How slowly it calms down again
@export var combat_fade_in := 0.4      # Seconds to switch into combat
@export var combat_fade_out := 2.5     # Seconds to fade back after a chase

@export_group("Hiding")
@export var hidden_cutoff := 1200.0  # Music sounds muffled while hiding in a barrel
@export var open_cutoff := 20000.0

@export_group("Detected")
# Played once when the player gets detected (no enemy was chasing before)
@export var detected_sound: AudioStream = preload("res://Assets/Sounds/detected.mp3")
@export var detected_volume_db := -3.0

var active_chase_count := 0
var tension := 0.0  # 0 = calm, 1 = enemy right next to the player (smoothed)
var combat := 0.0   # 0 = no chase, 1 = full combat music (smoothed)

var exploration_player: AudioStreamPlayer
var tension_player: AudioStreamPlayer
var combat_player: AudioStreamPlayer
var detected_player: AudioStreamPlayer
var filter_effect: AudioEffectLowPassFilter
var player: Player


func _ready() -> void:
	var music_bus_idx := AudioServer.get_bus_index("Music")
	filter_effect = AudioServer.get_bus_effect(music_bus_idx, 0) as AudioEffectLowPassFilter
	filter_effect.cutoff_hz = open_cutoff

	exploration_player = _create_track_player(exploration_track)
	tension_player = _create_track_player(tension_track)
	combat_player = _create_track_player(combat_track)
	_apply_volumes()
	# Started in the same frame, so the three versions stay in sync
	exploration_player.play()
	tension_player.play()
	combat_player.play()

	# Sound effects go to the Master bus so the music filter does not muffle them
	detected_player = AudioStreamPlayer.new()
	detected_player.stream = detected_sound
	detected_player.volume_db = detected_volume_db
	detected_player.bus = "Master"
	add_child(detected_player)


func _create_track_player(track: AudioStream) -> AudioStreamPlayer:
	if "loop" in track:
		track.loop = true
	var track_player := AudioStreamPlayer.new()
	track_player.stream = track
	track_player.bus = "Music"
	add_child(track_player)
	return track_player


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player

	# Tension rises quickly when an enemy comes close and calms down slowly
	var target_tension := _tension_from_nearest_enemy()
	var speed := tension_rise_speed if target_tension > tension else tension_fall_speed
	tension = move_toward(tension, target_tension, speed * delta)

	var target_combat := 1.0 if active_chase_count > 0 else 0.0
	var fade_time := combat_fade_in if target_combat > combat else combat_fade_out
	combat = move_toward(combat, target_combat, delta / fade_time)

	_apply_volumes()

	# Muffle the music while hiding
	var target_cutoff := hidden_cutoff if is_instance_valid(player) and player.is_hidden else open_cutoff
	filter_effect.cutoff_hz = lerpf(filter_effect.cutoff_hz, target_cutoff, minf(delta * 4.0, 1.0))


# 0 when no enemy is within tension_far, 1 when one is within tension_near
func _tension_from_nearest_enemy() -> float:
	if not is_instance_valid(player):
		return 0.0
	var nearest := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		nearest = minf(nearest, player.global_position.distance_to(enemy.global_position))
	return clampf(inverse_lerp(tension_far, tension_near, nearest), 0.0, 1.0)


# Equal-power crossfade: exploration -> tension by proximity, everything -> combat during a chase
func _apply_volumes() -> void:
	var calm := 1.0 - combat
	exploration_player.volume_db = _weight_to_db((1.0 - tension) * calm) + exploration_offset_db
	tension_player.volume_db = _weight_to_db(tension * calm) + tension_offset_db
	combat_player.volume_db = _weight_to_db(combat) + combat_offset_db


func _weight_to_db(weight: float) -> float:
	return linear_to_db(maxf(sqrt(weight), 0.0001)) + music_volume_db


# Called by enemies when they start or stop chasing
func update_chase_state(is_chasing: bool) -> void:
	if is_chasing:
		active_chase_count += 1
		if active_chase_count == 1:
			detected_player.play()
	else:
		active_chase_count = max(active_chase_count - 1, 0)
