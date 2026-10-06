extends Area3D

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if GameManager.has_bomb:
			# Player arrived with the bomb -> WIN!
			GameManager.show_message.emit("You won! You successfully used the bomb to finish the game!")
		else:
			# Player arrived without the bomb -> Missing item message
			GameManager.show_message.emit("You reached the end, but you are missing the Bomb!")
