extends Area3D

@export var door_body: StaticBody3D

var is_open: bool = false

func _on_body_entered(body: Node3D) -> void:
	if is_open:
		return # Already open, let them through!

	if body.is_in_group("player"):
		body.add_nearby_target(self)
		if GameManager.has_item(Collectible.ItemType.KEY):
			GameManager.show_message.emit("The door is locked. Select the Key and press W to unlock it.")
		else:
			# Player does not have the key
			GameManager.show_message.emit("The door is locked! You need a Key.")

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.remove_nearby_target(self)

# Called by the player when they use an item here. Returns true if the item was used up.
func try_use_item(item_type: Collectible.ItemType) -> bool:
	if is_open or item_type != Collectible.ItemType.KEY:
		return false
	is_open = true
	GameManager.show_message.emit("You unlocked the door with the Key!")
	open_door()
	return true

func open_door() -> void:
	# Disable the collision so the player can walk through
	if door_body:
		var collision = door_body.get_node_or_null("CollisionShape3D")
		if collision:
			collision.disabled = true
			
	# Simple visual swing open effect (rotates the door body over time)
	var tween = create_tween()
	tween.tween_property(door_body, "rotation:y", door_body.rotation.y + 1.57, 1.0) # Rotates ~90 degrees (1.57 radians)
