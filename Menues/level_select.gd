# level_select.gd
extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	$VBoxContainer/GridContainer/Level1Button.pressed.connect(_on_level_selected.bind("res://Levels/level_1.tscn"))
	$VBoxContainer/GridContainer/Level2Button.pressed.connect(_on_level_selected.bind("res://Levels/Generated/generated_level_2.tscn"))
	$VBoxContainer/GridContainer/Level3Button.pressed.connect(_on_level_selected.bind("res://Levels/Generated/generated_level_421275.tscn"))
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	$GeneratorButton.pressed.connect(_on_generator_pressed)

func _on_level_selected(level_path: String) -> void:
	# 1. Save the chosen path in GameManager
	GameManager.current_level_path = level_path
	
	# 2. Switch to the master container scene
	get_tree().change_scene_to_file("res://game_container.tscn")
	GameManager.reset_game()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Menues/main_menu.tscn")


func _on_generator_pressed() -> void:
	get_tree().change_scene_to_file("res://Menues/level_generator.tscn")
