extends Control
## Options from the main menu. The volume sliders are Menues/volume_settings.tscn
## (the same ones as in the pause menu).

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	SettingsManager.save_settings()
	# Return to whichever scene requested the options menu
	SceneFader.change_scene("res://Menues/main_menu.tscn")
