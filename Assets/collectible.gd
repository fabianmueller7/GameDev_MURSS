extends Area3D

enum ItemType { KEY, BOMB }
@export var item_type: ItemType = ItemType.KEY

func _on_body_entered(body: Node3D) -> void:
	# Check if the entering body is the player 
	# (Make sure your player node is added to a group named "Player")
	if body.is_in_group("player"):
		if item_type == ItemType.KEY:
			GameManager.has_key = true
			GameManager.show_message.emit("You collected the Key!")
		elif item_type == ItemType.BOMB:
			GameManager.has_bomb = true
			GameManager.show_message.emit("You collected the Bomb!")
		
		# Remove the item from the game world
		queue_free()
