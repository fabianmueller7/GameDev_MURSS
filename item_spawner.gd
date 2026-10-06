extends Node3D

@export var collectible_scene: PackedScene = preload("res://Assets/collectible.tscn")

@export var key_spawn_points: Array[Marker3D] = []
@export var bomb_spawn_points: Array[Marker3D] = []

func _ready() -> void:
	# Wait one frame to ensure the scene tree and world transforms are fully ready
	await get_tree().process_frame
	spawn_items()

func spawn_items() -> void:
	# 1. Spawn Key
	var valid_key_spots = key_spawn_points.filter(func(spot): return spot != null)
	if valid_key_spots.size() > 0:
		var random_key_spot = valid_key_spots.pick_random()
		var key_instance = collectible_scene.instantiate()
		
		# Add as child of this Spawner node
		add_child(key_instance)
		
		# Set global position safely now that it's in the tree
		key_instance.global_position = random_key_spot.global_position
		key_instance.item_type = 0 # KEY
		
		print("Key successfully spawned at: ", key_instance.global_position)

	# 2. Spawn Bomb
	var valid_bomb_spots = bomb_spawn_points.filter(func(spot): return spot != null)
	if valid_bomb_spots.size() > 0:
		var random_bomb_spot = valid_bomb_spots.pick_random()
		var bomb_instance = collectible_scene.instantiate()
		
		# Add as child of this Spawner node
		add_child(bomb_instance)
		
		# Set global position safely now that it's in the tree
		bomb_instance.global_position = random_bomb_spot.global_position
		bomb_instance.item_type = 1 # BOMB
		
		print("Bomb successfully spawned at: ", bomb_instance.global_position)
