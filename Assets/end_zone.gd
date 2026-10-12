extends Area3D

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.add_nearby_target(self)
		if GameManager.has_item(Collectible.ItemType.BOMB):
			GameManager.show_message.emit("This is the spot! Select the Bomb and press W to use it.")
		else:
			# Player arrived without the bomb -> Missing item message
			GameManager.show_message.emit("You reached the end, but you are missing the Bomb!")

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.remove_nearby_target(self)

# Called by the player when they use an item here. Returns true if the item was used up.
func try_use_item(item_type: Collectible.ItemType) -> bool:
	if item_type != Collectible.ItemType.BOMB:
		return false
	# Player used the bomb at the end -> WIN!
	GameManager.show_message.emit("You won! You successfully used the bomb to finish the game!")
	return true
