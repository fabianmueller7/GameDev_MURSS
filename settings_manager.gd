extends Node
## Volumes (0-100) for everything (Master), the music and the sound effects. They are saved in
## user://settings.cfg and applied at startup.
##
## Buses: Master <- Music (music_manager.gd), Master <- SFX (all sound effects).
## Every sound player that is still on the Master bus when it enters the tree is moved to the SFX bus,
## so new sound effects are covered by the "Sound Effects" slider without extra code.

const SETTINGS_FILE := "user://settings.cfg"

var master_volume: float = 80.0:
	set(value):
		master_volume = value
		_apply("Master", value)
var music_volume: float = 100.0:
	set(value):
		music_volume = value
		_apply("Music", value)
var sfx_volume: float = 100.0:
	set(value):
		sfx_volume = value
		_apply("SFX", value)


func _ready() -> void:
	if AudioServer.get_bus_index("SFX") < 0:   # (in case the bus layout does not have it)
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "SFX")
		AudioServer.set_bus_send(index, "Master")
	get_tree().node_added.connect(_on_node_added)
	_load_settings()


func _on_node_added(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D) \
			and node.get("bus") == &"Master":
		node.set("bus", &"SFX")


# Convert the 0-100 scale to decibels: 0 is mute, 1-100 maps to -30 dB .. 0 dB (standard for games)
func _apply(bus_name: String, volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	if volume <= 0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
		AudioServer.set_bus_mute(bus_index, true)
	else:
		AudioServer.set_bus_mute(bus_index, false)
		AudioServer.set_bus_volume_db(bus_index, remap(volume, 1.0, 100.0, -30.0, 0.0))


func save_settings() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "master", master_volume)
	file.set_value("audio", "music", music_volume)
	file.set_value("audio", "sfx", sfx_volume)
	var err := file.save(SETTINGS_FILE)
	if err != OK:
		push_error("Could not save the settings to %s (%s)" % [SETTINGS_FILE, error_string(err)])


func _load_settings() -> void:
	var file := ConfigFile.new()
	file.load(SETTINGS_FILE)   # missing file (first start): the defaults below are used
	master_volume = file.get_value("audio", "master", master_volume)
	music_volume = file.get_value("audio", "music", music_volume)
	sfx_volume = file.get_value("audio", "sfx", sfx_volume)
