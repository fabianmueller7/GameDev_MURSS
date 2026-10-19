extends Area3D
## A barrel the player can hide in.
## Walk up to it and press F (interact) to climb in, press F again to climb out.

@export var glow_light: OmniLight3D
@export var glow_energy := 0.8
@export var pulse_speed := 2.0    # How fast the blue glow pulses
@export var pulse_amount := 0.25  # How strong the pulse is (0 = steady light)

var occupant: Player = null
var _time := 0.0


func _process(delta: float) -> void:
	if glow_light == null:
		return
	_time += delta
	glow_light.light_energy = glow_energy * (1.0 + sin(_time * pulse_speed) * pulse_amount)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.add_nearby_interactable(self)
		if not body.is_hidden:
			GameManager.show_message.emit("Press F to hide in the barrel.")


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.remove_nearby_interactable(self)


# Called by the player when pressing the interact key near this barrel (or while hiding in it)
func interact(player: Player) -> void:
	if occupant == player:
		occupant = null
		player.leave_hiding_spot()
	elif occupant == null:
		occupant = player
		player.enter_hiding_spot(self)
		GameManager.show_message.emit("You are hiding. Press F to climb out.")
