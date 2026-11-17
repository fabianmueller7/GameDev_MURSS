extends Control

var is_dead: bool = false:
	set(value):
		is_dead = value
		visible = is_dead
		get_tree().paused = is_dead

		
		# Toggle mouse visibility for UI interaction
		if is_dead:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Adjust if your game uses a different mode
			

func _ready() -> void:
	# Hide the death menu on start
	visible = false
	
	# Connect buttons
	GameManager.player_died.connect(_on_player_died)
	$VBoxContainer/RetryButton.pressed.connect(_on_retry_pressed)
	$VBoxContainer/MenuButton.pressed.connect(_on_main_menu_pressed)

func _unhandled_input(event: InputEvent) -> void:
	# prevent pausing the game
	if is_dead and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled() # Prevent input bleeding
	
func _on_player_died() -> void:
	print("received player died event")
	is_dead = true

func _on_retry_pressed() -> void:
	is_dead = false
	GameManager.reset_game()

func _on_main_menu_pressed() -> void:
	# Always unpause before changing scenes, otherwise the new scene will start frozen!
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Menues/main_menu.tscn")
