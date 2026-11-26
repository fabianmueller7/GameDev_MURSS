extends Area3D

## true: the player has to use the Bomb here to win (level_1).
## false: just reaching this spot wins, e.g. behind the city gate of a generated level.
@export var needs_bomb := true

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if not needs_bomb:
			GameManager.show_message.emit("You escaped through the gate!")
			GameManager.win_level()
			return
		body.add_nearby_target(self)  # the hint is shown above the object (Menues/interaction_prompt.gd)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.remove_nearby_target(self)

# Called by the player when they use an item here. Returns true if the item was used up.
func try_use_item(item_type: Collectible.ItemType) -> bool:
	if not needs_bomb or item_type != Collectible.ItemType.BOMB:
		return false
	# Player used the bomb at the end -> WIN!
	GameManager.show_message.emit("You won! You successfully used the bomb to finish the game!")
	GameManager.win_level()
	return true


# Shown above the target spot (Menues/interaction_prompt.gd)
func get_prompt(_player: Node) -> String:
	if not needs_bomb:
		return ""
	if GameManager.get_selected_item() == Collectible.ItemType.BOMB:
		return "[E] Use the Bomb"
	if GameManager.has_item(Collectible.ItemType.BOMB):
		return "Select the Bomb, then [E]"
	return "Needs the Bomb"
