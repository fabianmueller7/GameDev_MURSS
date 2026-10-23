# game_container.gd
extends Node3D

@onready var level_container: Node3D = $LevelContainer

func _ready() -> void:
	load_selected_level()

func load_selected_level() -> void:
	# Check if a valid level path is set
	if GameManager.current_level_path.is_empty():
		return
		
	# Load the level scene resource
	var level_resource = load(GameManager.current_level_path)
	if level_resource:
		# Instantiate it and add it as a child of the container
		var level_instance = level_resource.instantiate()
		level_container.add_child(level_instance)
