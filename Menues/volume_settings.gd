extends VBoxContainer
## Volume sliders for Master, Music and Sound Effects (SettingsManager). Used in the options menu
## (main menu) and in the pause menu. Changes are applied right away and saved when a slider is let go.

const TEST_SOUND := preload("res://Assets/Sounds/collect_item.wav")
const SLIDERS := {
	"MasterRow": "master_volume",
	"MusicRow": "music_volume",
	"SfxRow": "sfx_volume",
}

var test_sound: AudioStreamPlayer


func _ready() -> void:
	for row in SLIDERS:
		var slider := get_node("%s/Slider" % row) as HSlider
		var value_label := get_node("%s/Value" % row) as Label
		var setting: String = SLIDERS[row]
		slider.value_changed.connect(func(value: float) -> void:
			SettingsManager.set(setting, value)
			value_label.text = str(int(value)))
		slider.drag_ended.connect(func(_changed: bool) -> void: SettingsManager.save_settings())
	refresh()

	# A short sound when the sound effects slider is let go, to hear the new volume
	# (the music keeps playing in the menus, so that one can be heard directly)
	test_sound = AudioStreamPlayer.new()
	test_sound.stream = TEST_SOUND
	test_sound.bus = "SFX"
	add_child(test_sound)
	($SfxRow/Slider as HSlider).drag_ended.connect(func(_changed: bool) -> void: test_sound.play())

	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())


# Shows the current settings (without changing them)
func refresh() -> void:
	for row in SLIDERS:
		var value: float = SettingsManager.get(SLIDERS[row])
		(get_node("%s/Slider" % row) as HSlider).set_value_no_signal(value)
		(get_node("%s/Value" % row) as Label).text = str(int(value))


func _exit_tree() -> void:
	SettingsManager.save_settings()   # (also covers changes made with the keyboard)
