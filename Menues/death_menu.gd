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
	
# Caught: the world freezes at once, the HUD flashes red and fades to dark (hud.gd) and the camera
# shakes (follow_camera.gd). The menu itself fades in a moment later.
const MENU_DELAY := 0.75
const MENU_FADE := 0.35

func _on_player_died() -> void:
	print("received player died event")
	if is_dead:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(MENU_DELAY).timeout   # timers keep running while paused
	modulate.a = 0.0
	is_dead = true
	create_tween().tween_property(self, "modulate:a", 1.0, MENU_FADE)

func _on_retry_pressed() -> void:
	is_dead = false
	GameManager.reset_game()   # SceneFader keeps the world frozen while it fades out

func _on_main_menu_pressed() -> void:
	# Always unpause before changing scenes, otherwise the new scene will start frozen!
	get_tree().paused = false
	SceneFader.change_scene("res://Menues/main_menu.tscn")
