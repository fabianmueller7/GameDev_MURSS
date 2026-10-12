extends Area3D
class_name Collectible

enum ItemType { KEY, BOMB, KNIFE }

const ITEM_NAMES := { ItemType.KEY: "Key", ItemType.BOMB: "Bomb", ItemType.KNIFE: "Knife" }
const ITEM_COLORS := { ItemType.KEY: Color(1, 0.8, 0.1), ItemType.BOMB: Color(0.15, 0.15, 0.15), ItemType.KNIFE: Color(0.75, 0.8, 0.85) }
const MAX_USES := { ItemType.KEY: 1, ItemType.BOMB: 1, ItemType.KNIFE: 3 }

@export var item_type: ItemType = ItemType.KEY:
	set(value):
		item_type = value
		if is_node_ready():
			_apply_look()

# Uses left on this item; -1 means it is unused (e.g. freshly spawned)
var uses: int = -1

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $SpotLight3D

static func item_name(type: ItemType) -> String:
	return ITEM_NAMES[type]

func remaining_uses() -> int:
	return uses if uses > 0 else MAX_USES[item_type]

func _ready() -> void:
	_apply_look()

func _apply_look() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = ITEM_COLORS[item_type]
	mesh.material_override = material
	match item_type:
		ItemType.KEY:
			light.light_color = Color(1, 1, 0)
		ItemType.BOMB:
			light.light_color = Color(1, 0.3, 0.1)
		ItemType.KNIFE:
			light.light_color = Color(0.6, 0.8, 1)

# The player picks items up with the "pickup" action, so we only tell it what is in reach
# (Make sure your player node is added to a group named "player")
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.add_nearby_item(self)
		GameManager.show_message.emit("Press E to pick up the %s" % item_name(item_type))

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.remove_nearby_item(self)
