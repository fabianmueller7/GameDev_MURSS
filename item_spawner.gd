extends Node3D

@export var collectible_scene: PackedScene = preload("res://Assets/collectible.tscn")

@export var key_spawn_points: Array[Marker3D] = []
@export var bomb_spawn_points: Array[Marker3D] = []

func _ready() -> void:
	# Wait one frame to ensure the scene tree and world transforms are fully ready
	await get_tree().process_frame
	spawn_items()

func spawn_items() -> void:
	spawn_item(Collectible.ItemType.KEY, key_spawn_points)
	spawn_item(Collectible.ItemType.BOMB, bomb_spawn_points)

# Spawns one item of the given type at a random one of the spawn points
func spawn_item(item_type: Collectible.ItemType, spawn_points: Array[Marker3D]) -> void:
	var valid_spots = spawn_points.filter(func(spot): return spot != null)
	if valid_spots.is_empty():
		return

	var random_spot = valid_spots.pick_random()
	var instance = collectible_scene.instantiate()

	# Add as child of this Spawner node
	add_child(instance)

	# Set global position safely now that it's in the tree
	instance.global_position = random_spot.global_position
	instance.item_type = item_type

	print(Collectible.item_name(item_type), " successfully spawned at: ", instance.global_position)
