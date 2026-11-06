extends Area3D
class_name Collectible

enum ItemType { KEY, BOMB, KNIFE, COIN }

const ITEM_NAMES := { 
	ItemType.KEY: "Key", 
	ItemType.BOMB: "Bomb", 
	ItemType.KNIFE: "Knife", 
	ItemType.COIN: "Coin" 
}

const MAX_USES := { 
	ItemType.KEY: 1, 
	ItemType.BOMB: 1, 
	ItemType.KNIFE: 3, 
	ItemType.COIN: 1 
}

const ITEM_COLORS := { 
	ItemType.KEY: Color(1, 0.8, 0.1), 
	ItemType.BOMB: Color(0.15, 0.15, 0.15), 
	ItemType.KNIFE: Color(0.75, 0.8, 0.85), 
	ItemType.COIN: Color(0.85, 0.55, 0.15) 
}

const ITEM_SCENES := {
	ItemType.KEY: preload("res://Assets/Fantasy Town Assets/key.glb"),
	ItemType.BOMB: preload("res://Assets/Fantasy Town Assets/simple_bomb.glb"),
	ItemType.KNIFE: preload("res://Assets/Fantasy Town Assets/knife.glb"),
	ItemType.COIN: preload("res://Assets/Medival Props/MegaKit/Exports/glTF/Coin.gltf")
}

const ITEM_SCALES := {
	ItemType.KEY: Vector3(0.02, 0.02, 0.02),
	ItemType.BOMB: Vector3(0.2, 0.2, 0.2),
	ItemType.KNIFE: Vector3(0.1, 0.1, 0.1),
	ItemType.COIN: Vector3(6, 6, 6)
}

# Define base rotation offsets (in radians, or use deg_to_rad() for degrees)
const ITEM_ROTATIONS := {
	ItemType.KEY: Vector3(0, deg_to_rad(90), 0),   # Rotate key to show from side
	ItemType.BOMB: Vector3(0, 0, 0),
	ItemType.KNIFE: Vector3(0, 0, 0),
	ItemType.COIN: Vector3(deg_to_rad(90), 0, 0)   # Rotate coin to stand up on its edge
}

# Set to true if you want the items to slowly spin in place like classic game pickups
@export var enable_idle_spin: bool = true
@export var spin_speed: float = 1.5

@export var item_type: ItemType = ItemType.KEY:
	set(value):
		item_type = value
		if is_node_ready():
			_apply_look()

# Uses left on this item; -1 means it is unused (e.g. freshly spawned)
var uses: int = -1

@onready var light: OmniLight3D = $SpotLight3D
var current_skin: Node3D = null

static func item_name(type: ItemType) -> String:
	return ITEM_NAMES[type]

func remaining_uses() -> int:
	return uses if uses > 0 else MAX_USES[item_type]

func _ready() -> void:
	_apply_look()

func _process(delta: float) -> void:
	# Optional: Make the item slowly spin in place
	if enable_idle_spin and current_skin:
		current_skin.rotate_y(spin_speed * delta)

func _apply_look() -> void:
	# Remove old skin if it exists
	if current_skin:
		current_skin.queue_free()
	
	# Instantiate new skin based on item type
	var scene_to_load = ITEM_SCENES.get(item_type)
	if scene_to_load:
		current_skin = scene_to_load.instantiate()
		current_skin.scale = ITEM_SCALES.get(item_type, Vector3.ONE)
		
		# Apply the base rotation offset so it faces correctly
		current_skin.rotation = ITEM_ROTATIONS.get(item_type, Vector3.ZERO)
		
		add_child(current_skin)
	
	# Configure light color depending on item type
	match item_type:
		ItemType.KEY:
			light.light_color = Color(1, 1, 0)
		ItemType.BOMB:
			light.light_color = Color(1, 0.3, 0.1)
		ItemType.KNIFE:
			light.light_color = Color(0.6, 0.8, 1)
		ItemType.COIN:
			light.light_color = Color(1, 0.7, 0.3)

# The player picks items up with the "interact" action (F), so we only tell it what is in reach
# (Make sure your player node is added to a group named "player")
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.add_nearby_item(self)
		GameManager.show_message.emit("Press F to pick up the %s" % item_name(item_type))

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.remove_nearby_item(self)
