extends Area3D

## true: the player has to use the Bomb here to win (level_1).
## false: just reaching this spot wins, e.g. behind the city gate of a generated level.
@export var needs_bomb := true
## Optional: played when the bomb is used here (e.g. the landslide of the final tile). It wins the
## level itself when it is done. Without it the level is won right away.
@export var finale: Node
## Shown in the objectives (top left) once the player needs to use the bomb
@export var objective := "Use the Bomb at the target"

var bomb_used := false

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
	bomb_used = true
	if finale and finale.has_method("play"):
		finale.call("play")
		return true
	# Player used the bomb at the end -> WIN!
	GameManager.show_message.emit("You won! You successfully used the bomb to finish the game!")
	GameManager.win_level()
	return true


# Shown above the target spot (Menues/interaction_prompt.gd)
func get_prompt(_player: Node) -> String:
	if not needs_bomb or bomb_used:
		return ""
	if GameManager.get_selected_item() == Collectible.ItemType.BOMB:
		return "[E] Use the Bomb"
	if GameManager.has_item(Collectible.ItemType.BOMB):
		return "Select the Bomb, then [E]"
	return "Needs the Bomb"
