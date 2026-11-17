extends Control

var is_paused: bool = false:
	set(value):
		is_paused = value
		get_tree().paused = is_paused
		visible = is_paused
		
		# Toggle mouse visibility for UI interaction
		if is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Adjust if your game uses a different mode

func _ready() -> void:
	# Hide the pause menu on start
	visible = false
	
	# Connect buttons
	$VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$VBoxContainer/MenuButton.pressed.connect(_on_main_menu_pressed)

func _unhandled_input(event: InputEvent) -> void:
	# Check for the pause input action (default ESC / ui_cancel)
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
		is_paused = not is_paused
		get_viewport().set_input_as_handled() # Prevent input bleeding

func _on_resume_pressed() -> void:
	is_paused = false

func _on_main_menu_pressed() -> void:
	# Always unpause before changing scenes, otherwise the new scene will start frozen!
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Menues/main_menu.tscn")
