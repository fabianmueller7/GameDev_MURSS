class_name GuardDogComponent
extends Node

@export var hearing_radius := 6.0

func check_hearing(player: Player, distance: float) -> bool:
	if distance < hearing_radius:
		var player_is_moving: bool = player.velocity.length() > 0.1
		var player_is_crouching: bool = ("is_crouching" in player and player.is_crouching)
		
		# Detects a moving player within hearing radius unless they are crouching
		if player_is_moving and not player_is_crouching:
			return true
	return false
