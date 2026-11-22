extends Control
## Shown when the player finishes the level (GameManager.level_won). The game stays paused until
## the player restarts the level or goes back to the main menu.

var has_won: bool = false:
	set(value):
		has_won = value
		visible = has_won
		get_tree().paused = has_won
		# Toggle mouse visibility for UI interaction
		if has_won:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # Adjust if your game uses a different mode


func _ready() -> void:
	visible = false
	GameManager.level_won.connect(_on_level_won)
	$VBoxContainer/RestartButton.pressed.connect(_on_restart_pressed)
	$VBoxContainer/MenuButton.pressed.connect(_on_main_menu_pressed)


func _unhandled_input(event: InputEvent) -> void:
	# The pause menu must not open on top of the victory screen
	if has_won and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()


func _on_level_won() -> void:
	has_won = true


func _on_restart_pressed() -> void:
	has_won = false
	GameManager.reset_game()


func _on_main_menu_pressed() -> void:
	# Always unpause before changing scenes, otherwise the new scene will start frozen!
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Menues/main_menu.tscn")
