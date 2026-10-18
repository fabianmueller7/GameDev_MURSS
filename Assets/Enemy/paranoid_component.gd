class_name ParanoidComponent
extends Node

@export var look_back_interval := 3.0
@export var look_back_duration := 1.0

var look_back_timer := 0.0
var is_looking_back := false
var look_back_hold_timer := 0.0

func process_behavior(enemy: CharacterBody3D, delta: float) -> bool:
	if is_looking_back:
		look_back_hold_timer -= delta
		if look_back_hold_timer <= 0.0:
			is_looking_back = false
			look_back_timer = 0.0
		return true
	else:
		look_back_timer += delta
		if look_back_timer >= look_back_interval:
			is_looking_back = true
			look_back_hold_timer = look_back_duration
		return false
