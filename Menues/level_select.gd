# level_select.gd
extends Control

const COMPLETED_COLOR := Color(0.45, 0.9, 0.45)

# Button -> level it starts (Level4Button has no level yet)
@onready var level_buttons := {
	$VBoxContainer/GridContainer/Level1Button: "res://Levels/level_1.tscn",
	$VBoxContainer/GridContainer/Level2Button: "res://Levels/Generated/generated_level_2.tscn",
	$VBoxContainer/GridContainer/Level3Button: "res://Levels/Generated/generated_level_421275.tscn",
}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for button: Button in level_buttons:
		var level_path: String = level_buttons[button]
		button.pressed.connect(_on_level_selected.bind(level_path))
		if GameManager.is_level_completed(level_path):
			_mark_completed(button)
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	$GeneratorButton.pressed.connect(_on_generator_pressed)

# Finished levels get a green label and a tooltip, so they stand out at a glance
func _mark_completed(button: Button) -> void:
	button.tooltip_text = "You have already finished this level"
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, COMPLETED_COLOR)

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
