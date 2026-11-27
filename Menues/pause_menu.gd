extends Control

var is_paused: bool = false:
	set(value):
		is_paused = value
		get_tree().paused = is_paused
		visible = is_paused
		_show_options(false)   # always opens on the main list
		
		# Toggle mouse visibility for UI interaction
		if is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_update_seed_label()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Adjust if your game uses a different mode

var seed_label: Label

func _ready() -> void:
	# Hide the pause menu on start
	visible = false
	
	# Map seed of generated levels, under the title (so a good map can be shared)
	seed_label = Label.new()
	seed_label.add_theme_font_size_override("font_size", 24)
	seed_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	$VBoxContainer.add_child(seed_label)
	$VBoxContainer.move_child(seed_label, $VBoxContainer/Label.get_index() + 1)
	seed_label.visible = false

	# Connect buttons
	$VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$VBoxContainer/RespawnButton.pressed.connect(_on_respawn_pressed)
	$VBoxContainer/MenuButton.pressed.connect(_on_main_menu_pressed)
	$VBoxContainer/OptionsButton.pressed.connect(_show_options.bind(true))
	$OptionsPanel/BackButton.pressed.connect(_show_options.bind(false))

func _unhandled_input(event: InputEvent) -> void:
	# Check for the pause input action (default ESC / ui_cancel)
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
		if is_paused and $OptionsPanel.visible:
			_show_options(false)   # ESC in the options: back to the pause menu
		else:
			is_paused = not is_paused
		get_viewport().set_input_as_handled() # Prevent input bleeding

# Options (volume sliders, Menues/volume_settings.tscn) in place of the pause menu buttons
func _show_options(open: bool) -> void:
	if not is_node_ready():
		return
	if not open and $OptionsPanel.visible:
		SettingsManager.save_settings()
	$OptionsPanel.visible = open
	$VBoxContainer.visible = not open

func _on_resume_pressed() -> void:
	is_paused = false

# In case the player got stuck: back to the start of the level without reloading it.
# Inventory, items and enemies stay as they are; chasing enemies give up.
func _on_respawn_pressed() -> void:
	is_paused = false
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.respawn()
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("on_player_respawned"):
			enemy.on_player_respawned()
	GameManager.show_message.emit("You respawned at the start.")

func _on_main_menu_pressed() -> void:
	# Always unpause before changing scenes, otherwise the new scene will start frozen!
	get_tree().paused = false
	SceneFader.change_scene("res://Menues/main_menu.tscn")


# Generated levels are called GeneratedLevel<seed> (by the map generator, saved or built on the fly)
func _update_seed_label() -> void:
	if seed_label == null:
		return
	var scene := get_tree().current_scene
	var level: Node = scene.find_child("GeneratedLevel*", true, false) if scene else null
	seed_label.visible = level != null
	if level:
		seed_label.text = "Map seed: " + str(level.name).trim_prefix("GeneratedLevel")
