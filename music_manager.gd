class_name MusicManagerClass
extends AudioStreamPlayer

@export var stealth_cutoff := 800.0   # Muffled sound when hidden
@export var action_cutoff := 20000.0  # Fully open, punchy sound during chase

var music_bus_idx: int
var filter_effect: AudioEffectLowPassFilter
var active_chase_count := 0

func _ready() -> void:
	# Point to our custom music bus and filter effect
	music_bus_idx = AudioServer.get_bus_index("Music")
	filter_effect = AudioServer.get_bus_effect(music_bus_idx, 0) as AudioEffectLowPassFilter
	
	# Ensure this player uses the Music bus
	bus = "Music"
	
	# Instantly set to muffled stealth state at start
	filter_effect.cutoff_hz = stealth_cutoff
	
	# Start playing the music automatically if assigned
	if stream:
		play()

# Called by enemies when they start or stop chasing
func update_chase_state(is_chasing: bool) -> void:
	if is_chasing:
		active_chase_count += 1
	else:
		active_chase_count = max(active_chase_count - 1, 0)
	
	# If at least one guard is chasing, switch to action music!
	var target_cutoff = action_cutoff if active_chase_count > 0 else stealth_cutoff
	
	# Smoothly tween the filter frequency over 0.6 seconds for a cinematic feel
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(filter_effect, "cutoff_hz", target_cutoff, 0.6)
