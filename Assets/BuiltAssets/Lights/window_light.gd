extends Node3D
## Light from inside a house: makes the glass of the window at this spot glow and lets warm light
## fall out onto the street. Place it with the same transform as the window (+Z = outside).

@export var glow_color := Color(1.0, 0.72, 0.4)
@export_range(0.0, 8.0, 0.1) var glow_energy := 1.6
## Glass meshes closer than this to the node are lit up
@export var search_radius := 0.4

static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = glow_color.darkened(0.4)
		_material.emission_enabled = true
		_material.emission = glow_color
		_material.emission_energy_multiplier = glow_energy
	# The windows belong to the house next to us; search the whole tile we are part of
	var tile := owner if owner else get_parent()
	for node in tile.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.global_position.distance_to(global_position) > search_radius:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i)
			if material and "Glass" in material.resource_name:
				mesh_instance.set_surface_override_material(i, _material)
