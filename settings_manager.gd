extends Node

var master_volume: float = 80.0:
	set(value):
		master_volume = value
		apply_volume()

func apply_volume() -> void:
	# Convert 0-100 scale to an audio bus decibel value
	# AudioServer uses dB. 0 is mute (-80 dB), 100 is max (0 dB).
	var bus_index := AudioServer.get_bus_index("Master")
	
	if master_volume <= 0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
		AudioServer.set_bus_mute(bus_index, true)
	else:
		AudioServer.set_bus_mute(bus_index, false)
		# Map 1-100 to a logarithmic decibel scale (-30 dB to 0 dB is standard for games)
		var db := remap(master_volume, 1.0, 100.0, -30.0, 0.0)
		AudioServer.set_bus_volume_db(bus_index, db)
