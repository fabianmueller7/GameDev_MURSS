extends Control

@export_file("*.tscn") var level_select_path: String = "res://Menues/level_select.tscn"
@export_file("*.tscn") var options_scene_path: String = "res://Menues/options_menu.tscn"

func _ready() -> void:
	# Ensure the mouse is visible on the main menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Connect button signals (or use the Node dock in the editor)
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_play_pressed() -> void:
	# Change to your main 3D game scene
	get_tree().change_scene_to_file(level_select_path)

func _on_options_pressed() -> void:
	# Change to your main 3D game scene
	get_tree().change_scene_to_file(options_scene_path)

func _on_quit_pressed() -> void:
	get_tree().quit()
