class_name BaseTile
extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Loop through all child nodes inside this tile
	for child in get_children():
		# Check if the node's name begins with "House"
		if child.name.begins_with("House"):
			# Choose randomly between 0 and 90 degrees
			var possible_rotations = [0.0, 90.0]
			var random_angle = possible_rotations[randi() % possible_rotations.size()]
			
			# Apply the rotation to the Y-axis
			child.rotation_degrees.y = random_angle
