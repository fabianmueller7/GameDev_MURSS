extends Control

@onready var volume_slider: HSlider = $VBoxContainer/HBoxContainer/VolumeSlider
@onready var value_label: Label = $VBoxContainer/HBoxContainer/ValueLabel

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Set slider to current global setting
	volume_slider.value = SettingsManager.master_volume
	value_label.text = str(int(volume_slider.value))
	
	# Connect signals
	volume_slider.value_changed.connect(_on_volume_changed)
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)

func _on_volume_changed(value: float) -> void:
	SettingsManager.master_volume = value
	value_label.text = str(int(value))

func _on_back_pressed() -> void:
	# Return to whichever scene requested the options menu
	get_tree().change_scene_to_file("res://Menues/main_menu.tscn")
